\set ON_ERROR_STOP on
\pset pager off
\timing on

-- Use one query worker to make comparisons easier on a single CPU workload.
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET statement_timeout = '5min';

SELECT version();
SHOW max_parallel_workers_per_gather;
SHOW jit;
SHOW work_mem;
SHOW shared_buffers;

DROP TABLE IF EXISTS people_50k, people_100k, people_200k;
CREATE TABLE people_50k AS SELECT * FROM people_big WHERE id <= 50000;
CREATE TABLE people_100k AS SELECT * FROM people_big WHERE id <= 100000;
CREATE TABLE people_200k AS SELECT * FROM people_big WHERE id <= 200000;

-- Give the planner statistics both before and after adding an index.
ANALYZE people_50k;
ANALYZE people_100k;
ANALYZE people_200k;

\echo Step 1 - 50,000 rows
SELECT COUNT(*) AS matching_pairs
FROM people_50k p1 JOIN people_50k p2 ON p1.country = p2.country;

\echo Step 1 - 100,000 rows
SELECT COUNT(*) AS matching_pairs
FROM people_100k p1 JOIN people_100k p2 ON p1.country = p2.country;

\echo Step 1 - 200,000 rows
SELECT COUNT(*) AS matching_pairs
FROM people_200k p1 JOIN people_200k p2 ON p1.country = p2.country;

\echo Step 2 - Plan before the country index
-- TIMING OFF avoids measuring a clock for every row; total time is still shown.
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT COUNT(*)
FROM people_100k p1 JOIN people_100k p2 ON p1.country = p2.country;

CREATE INDEX people_100k_country_idx ON people_100k(country);
ANALYZE people_100k;

\echo Step 2 - Repeat after creating the index
SELECT COUNT(*) AS matching_pairs
FROM people_100k p1 JOIN people_100k p2 ON p1.country = p2.country;

EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT COUNT(*)
FROM people_100k p1 JOIN people_100k p2 ON p1.country = p2.country;

\echo Step 3 - Rewrite on 100,000 rows
SELECT SUM(k * k) AS matching_pairs
FROM (
    SELECT country, COUNT(*) AS k
    FROM people_100k
    WHERE country IS NOT NULL
    GROUP BY country
) country_counts;

\echo Step 3 - Check equality with the original join
SELECT
    (SELECT COUNT(*)
     FROM people_100k p1 JOIN people_100k p2 ON p1.country = p2.country)
    =
    (SELECT SUM(k * k)
     FROM (
         SELECT country, COUNT(*) AS k
         FROM people_100k
         WHERE country IS NOT NULL
         GROUP BY country
     ) country_counts) AS results_match;

\echo Step 3 - Rewrite on the full million rows (no full-size join)
SELECT SUM(k * k) AS matching_pairs
FROM (
    SELECT country, COUNT(*) AS k
    FROM people_big
    WHERE country IS NOT NULL
    GROUP BY country
) country_counts;

EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT SUM(k * k)
FROM (
    SELECT country, COUNT(*) AS k
    FROM people_big
    WHERE country IS NOT NULL
    GROUP BY country
) country_counts;
