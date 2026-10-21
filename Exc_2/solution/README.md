# Exercise 2 - PostgreSQL

## Files and setup

I used the provided generators with seed 42 and loaded one million rows into each table.

- [00_setup.sql](00_setup.sql): table definitions and CSV imports.
- [01_ecommerce.sql](01_ecommerce.sql): queries for A-D and the customer-name check.
- [02_self_join.sql](02_self_join.sql): self-join measurements, index test and rewrite.
- [results/](results/): saved results, timings and execution plans.

The measurements were taken with PostgreSQL 18.1 directly on Windows because Docker was unavailable. For the self-join tests, parallel workers and JIT were off, with `work_mem = 4MB` and `shared_buffers = 128MB`. These are single-run timings, so they can vary on another machine. This setup does not reproduce Docker's CPU limit exactly.

To rerun with Docker, first generate both CSVs and start the container as explained in the [exercise instructions](../README.md). Then run these commands from `Exc_2`:

```bash
docker cp solution/. pg-bigdata:/solution
docker exec pg-bigdata psql -X -U postgres -f /solution/00_setup.sql
docker exec pg-bigdata psql -X -U postgres -f /solution/01_ecommerce.sql
docker exec pg-bigdata psql -X -U postgres -f /solution/02_self_join.sql
```

The setup script replaces the exercise tables.

## Activity 2.1 - E-commerce

I created the `orders` table in [00_setup.sql](00_setup.sql). I used `TEXT` for names, categories and countries, `INTEGER` for quantity, `DATE` for the order date and `NUMERIC(10, 2)` for prices to keep exact decimal values. I also added a serial primary key.

The queries are in [01_ecommerce.sql](01_ecommerce.sql).

### A - Highest price per unit

I compared each price with `MAX(price_per_unit)`. The result was:

| Order ID | Customer | Category | Quantity | Unit price | Date | Country |
|---|---|---|---:|---:|---|---|
| 841292 | Emma Brown | Automotive | 3 | 2000.00 | 2024-10-11 | Italy |

### B - Top three categories by quantity

I grouped by category and sorted `SUM(quantity)` from highest to lowest.

| Category | Total quantity |
|---|---:|
| Health & Beauty | 300,842 |
| Electronics | 300,804 |
| Toys | 300,598 |

### C - Revenue per category

I calculated revenue as `SUM(price_per_unit * quantity)` for each category.

| Category | Total revenue |
|---|---:|
| Automotive | 306,589,798.86 |
| Electronics | 241,525,009.45 |
| Home & Garden | 78,023,780.09 |
| Sports | 61,848,990.83 |
| Health & Beauty | 46,599,817.89 |
| Office Supplies | 38,276,061.64 |
| Fashion | 31,566,368.22 |
| Toys | 23,271,039.02 |
| Grocery | 15,268,355.66 |
| Books | 12,731,976.04 |

### D - Top five customers by spending

I grouped by customer name and added up each name's spending.

| Customer name | Orders | Total spending |
|---|---:|---:|
| Carol Taylor | 1,028 | 991,179.18 |
| Nina Lopez | 980 | 975,444.95 |
| Daniel Jackson | 1,033 | 959,344.48 |
| Carol Lewis | 943 | 947,708.57 |
| Daniel Young | 973 | 946,030.14 |

### E - Why are these totals so high?

I noticed that each name has around 1,000 orders. The generator randomly combines 32 first names with 33 last names, giving only **1,056 possible names** for a million orders. My check found all 1,056 names, averaging **946.97 orders per name**.

Grouping by name combines these repeated names, which explains the high spending. The generator also chooses the country independently, so these totals do not represent realistic individual customers. In a real database, I would use customer IDs.

## Activity 2.2 - Self-join

### Step 1 - Measurements and prediction

I ran the country self-join on the three smaller tables:

| Rows | Matching pairs | Time |
|---:|---:|---:|
| 50,000 | 27,501,822 | 3.08 s |
| 100,000 | 109,946,508 | 12.63 s |
| 200,000 | 439,395,606 | 48.38 s |

Doubling the input gives about **four times as many pairs**. The runtime increased by **4.10 times** and then **3.83 times**, which is close to quadratic growth.

For one million rows, I predicted:

- Pairs: `439,395,606 * 25 = 10,984,890,150`.
- Time: `48.384155 * 25 = 1209.60 seconds`, or about **20.16 minutes**.

I used 25 because one million is five times 200k, and `5 * 5 = 25`. This assumes similar conditions and country proportions. I did not run the full million-row join.

### Step 2 - Index test

I added an index on `people_100k(country)`, ran `ANALYZE` and repeated the query. It improved from **12.63 s to 5.38 s**, about **2.35 times faster**.

The saved `EXPLAIN ANALYZE` plans show a **Hash Join** before the index and a **Nested Loop with Memoize and an Index Only Scan** afterwards. Memoize reused matches for each country, with 92 cache misses and 99,908 hits. The index-only scan still needed 100,000 heap fetches to check row visibility.

The index helped, but both plans still processed **109,946,508 matching pairs**. That large number of combinations is the main problem. The full plans are in [02_self_join.txt](results/02_self_join.txt).

### Step 3 - Rewrite

Instead of joining every matching person, I counted people per country. A country with `k` people contributes `k * k` pairs, including self-pairs and both directions.

```sql
SELECT SUM(k * k) AS matching_pairs
FROM (
    SELECT country, COUNT(*) AS k
    FROM people_big
    WHERE country IS NOT NULL
    GROUP BY country
) country_counts;
```

I excluded null countries because they would not match in the original join.

| Rows | Rewrite result | Time |
|---:|---:|---:|
| 100,000 | 109,946,508 | 0.024 s |
| 1,000,000 | 10,983,941,260 | 0.247 s |

My equality check on 100k returned **true**. On one million rows, the rewrite took about **0.25 seconds**, compared with my predicted **20.16 minutes** for the join. It scans the table and combines only 92 country counts, so the work grows roughly in proportion to the input.

### Step 4 - Discussion

**Query and hardware:** I would start with the rewrite because it removes most of the work. An index or more hardware can help, but the original join still grows about four times when the input doubles. Ideally, four times the processing capacity could offset one doubling; real speedups would usually be smaller. For a frequently requested count, I could maintain a country summary instead of scanning everything again.

**If the pairs are needed:** I would first check whether the business can narrow the query. If all pairs are required, the roughly 11 billion output rows cannot be avoided. A bigger machine or a cluster could share the work. Ideally, `P` equally loaded workers could approach a `P`-fold speedup, but uneven country sizes, network transfers and writing the results would limit this. I would process the output in batches.

**OLTP and cloud limits:** These large joins compete with normal transactions for CPU, memory and disk access. A larger cloud instance costs more and still has limits. For regular analytical work, I would consider a read replica or a separate analytical database, accepting some delay in data updates. Distributed processing can help, but transferring and storing billions of pairs would still take time and money.

## References

PostgreSQL documentation: [EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html), [parallel queries](https://www.postgresql.org/docs/18/parallel-query.html), [index-only scans](https://www.postgresql.org/docs/18/indexes-index-only-scans.html).
