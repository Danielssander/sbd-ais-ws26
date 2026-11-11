# Exercise 5 - Stages A and B

Daniel Sander-Gassner

## Stage A - Today's system

### Test setup

For these tests, I used the supplied Python files without changing them. The tests ran remotely on Linux with Python 3.12 and PostgreSQL 16.2. PostgreSQL ran directly, without Docker. This is different from the supplied Docker setup, which uses PostgreSQL 18.1. My new PC's Ubuntu VM setup is still to be done.

I started the detector first in both tests:

- **20 machines:** I ran the plant for 90 seconds, then waited another 10 seconds for the detector to catch up. Its backlog reached zero before I stopped it.
- **60 machines:** I ran the plant for 60 seconds and stopped the detector just after the plant finished.

I cleared the database tables between tests. These are the commands, with the detector and plant in separate terminals:

```bash
# First test: start the detector, then the plant
python3 baseline_detector.py --quiet
python3 plant.py --sink postgres --machines 20 --duration 90

# Second test: start a new detector, then the plant
python3 baseline_detector.py --quiet
python3 plant.py --sink postgres --duration 60
```

I compared the detector's count with the number of rows in the database:

```sql
SELECT count(*) FROM readings
WHERE run = (SELECT max(run) FROM readings);
```

The `--quiet` option only hides individual anomaly messages. The detector still processes the readings and counts anomalies.

### A1 - 20 machines

| Result | Value |
|---|---:|
| Readings sent | 18,000 |
| Readings stored in PostgreSQL | 18,000 |
| Readings processed by the detector | 14,962 |
| Readings skipped | 3,038 |
| Model's missing counter | 3,038 |
| Final reported backlog | 0 |
| Delay shown while running | 0.1-0.3 seconds |

The detector was fast enough, but it still missed **3,038 readings**. These readings were in the database, because all 18,000 readings were stored.

The problem is how the detector remembers its position. It saves the highest ID it has read and only asks for larger IDs next time. However, a reading gets its ID before its transaction is committed. COMMIT is the point when other connections can see the reading.

Using the example from the assignment:

1. Gateway 1 inserts rows with IDs 100-114 but waits before committing.
2. Gateway 2 inserts rows with IDs 115-129 and commits first.
3. The detector sees IDs 115-129 and saves 129 as its last ID.
4. Gateway 1 commits later. The detector skips IDs 100-114 because it now only asks for IDs above 129.

So the order of the IDs is not always the order in which rows become visible. This explains why the detector can miss readings even when it keeps up.

The displayed backlog was zero at the end, but that did not mean everything had been processed. The program calculates backlog as `max(id) - last_id`, so it does not include rows it already skipped.

### A2 - 60 machines

| Result | Value |
|---|---:|
| Readings sent and stored | 36,000 |
| Readings processed before stopping | 18,588 |
| Model's missing counter | 37 |
| Delay shown while running | Increased from 2.1 to 27.5 seconds |
| Backlog shown while running | Increased from 1,200 to 16,460 |

At the full rate, the plant sends **60 x 10 = 600 readings per second**. Each model calculation takes 3 ms, so one detector can process at most about **1 / 0.003 = 333 readings per second**, even before other work is included.

More readings arrive than the detector can process. The queue grows, and the detector works on older and older readings. This explains the increasing backlog and delay. The delay went above 5 seconds. These printed values are individual delay measurements; I did not calculate p95, which is the delay that 95% of results must stay below.

There were **36,000 - 18,588 = 17,412** readings left unprocessed when I stopped the detector. I cannot call all of them lost, because many were still waiting to be processed.

The missing counter only reached 37. This does not mean the ID problem was fixed. Because the detector was behind, the gateways usually had time to commit before it reached their rows. Also, the counter only detects gaps between readings it has seen, not readings before the first one or after the last one.

No anomalies were detected before I stopped the test. The detector was still working on readings from before the fault started at 40 seconds. I checked the delay while the plant was running, because stopping the plant gives the detector time to catch up and hides the overload problem.

## Stage B - My decision

I would send the sensor readings to **Kafka** and keep **PostgreSQL for the machine registry**.

| Requirement | Improve PostgreSQL polling | Use Kafka |
|---|---|---|
| R1: Handle 600, later 100,000 readings/s | I could split machines between several detectors. The database would still handle all inserts and polling queries. I would need to test the larger rate. | I could split the stream into partitions and add detectors. I would still need to test whether the Kafka servers and detectors can handle the larger rate. |
| R2: Process every reading in order | I would need to track each machine's sequence and retry gaps. Adding more detectors alone does not fix the ID problem. | I would use machine_id as the key so one machine's readings stay in one partition. One detector in the group processes that partition in order. Retries must not cause a reading to be scored twice. |
| R3: Keep p95 delay at most 5 seconds | This could work at a low rate, but polling and database load add delay. Enough detectors would still be needed. | Enough detectors could keep the delay low, but I would need to measure it under full load. Kafka alone does not make the model faster. |
| R4: Independent archive and dashboard | Each extra reader would query PostgreSQL and add database load, so this does not meet R4. | I would give the detector, archive and dashboard separate consumer groups. Each group reads at its own position without querying PostgreSQL for sensor readings. Kafka still needs enough capacity for all three. |

### Number of detectors

One detector needs **0.003 seconds per reading**:

| Rate | Calculation | Minimum based on model time |
|---|---|---|
| 600 readings/s | 600 x 0.003 = 1.8 seconds of work per second | 2 detectors |
| 100,000 readings/s | 100,000 x 0.003 = 300 seconds of work per second | 300 detectors, fully busy |

At 100,000 readings/s, 300 detectors would have no spare time at all. Even under ideal conditions, I would need at least 301 to stay below full capacity, and more in practice for database calls, Kafka communication and uneven workloads.

As a starting estimate, I would aim for around **70% usage**. Rounding up `rate x 0.003 / 0.7` gives **3 detectors for 600 readings/s** and **429 for 100,000 readings/s**. These are planning estimates, not tested guarantees. I would create at least as many partitions as active detectors and check that work is spread evenly.

The model remembers information about each machine. If a partition moves to another detector, that detector must restore the saved model state or replay enough readings to rebuild it. Saving the Kafka reading position alone is not enough.

I would also keep readings in Kafka for replay, wait for confirmation that writes succeeded, and enable the producer's duplicate protection when retrying. Anomalies would go to their own topic.

### When is Kafka worth using?

For an office sending one temperature reading per minute, I would keep PostgreSQL with correct polling. It is simpler and the workload is small.

There is no single rate where every system must switch to Kafka. For this model, one detector gets close to its limit around 300 readings/s, and 600 already needs several detectors. I choose Kafka here because I need ordered readings, replay and several independent readers, especially the archive and dashboard. The decision is about these requirements together, not just how many rows PostgreSQL can insert.

## Test logs

The original logs are below. I reset the database tables between tests. The database results show the row count, lowest sequence, highest sequence and number of machines. I did not change the protected Python files or use `ground_truth.jsonl` in solution code.

<details>
<summary>database_20.txt</summary>

```text
count, min_seq, max_seq, machines: (18000, 0, 899, 20)
```

</details>

<details>
<summary>database_60.txt</summary>

```text
count, min_seq, max_seq, machines: (36000, 0, 599, 60)
```

</details>

<details>
<summary>detector_20.txt</summary>

```text
[baseline] polling table readings for id > 0 (Ctrl+C to stop)
[baseline] read      680  backlog      30 rows  delay   0.2 s  missing    125  anomalies 0
[baseline] read    1,520  backlog      40 rows  delay   0.3 s  missing    280  anomalies 0
[baseline] read    2,363  backlog      20 rows  delay   0.2 s  missing    477  anomalies 0
[baseline] read    3,192  backlog      40 rows  delay   0.3 s  missing    603  anomalies 0
[baseline] read    4,053  backlog      40 rows  delay   0.3 s  missing    767  anomalies 0
[baseline] read    4,847  backlog      25 rows  delay   0.2 s  missing    963  anomalies 0
[baseline] read    5,681  backlog      14 rows  delay   0.1 s  missing  1,109  anomalies 0
[baseline] read    6,498  backlog      25 rows  delay   0.2 s  missing  1,307  anomalies 0
[baseline] read    7,344  backlog      40 rows  delay   0.2 s  missing  1,456  anomalies 0
[baseline] read    8,193  backlog      20 rows  delay   0.1 s  missing  1,602  anomalies 5
[baseline] read    9,005  backlog      35 rows  delay   0.2 s  missing  1,815  anomalies 45
[baseline] read    9,842  backlog      24 rows  delay   0.2 s  missing  1,988  anomalies 88
[baseline] read   10,682  backlog      15 rows  delay   0.2 s  missing  2,128  anomalies 130
[baseline] read   11,503  backlog      20 rows  delay   0.2 s  missing  2,312  anomalies 171
[baseline] read   12,397  backlog      15 rows  delay   0.2 s  missing  2,438  anomalies 217
[baseline] read   13,162  backlog      24 rows  delay   0.2 s  missing  2,643  anomalies 251
[baseline] read   13,980  backlog       0 rows  delay   0.1 s  missing  2,815  anomalies 292
[baseline] read   14,792  backlog      20 rows  delay   0.2 s  missing  2,998  anomalies 330
[baseline] read   14,962  backlog       0 rows  delay   0.0 s  missing  3,038  anomalies 337
[baseline] read   14,962  backlog       0 rows  delay   0.0 s  missing  3,038  anomalies 337
[baseline] stopped: read 14,962 readings, last id 18,000, 3,038 readings missing, 337 anomalies
```

</details>

<details>
<summary>detector_60.txt</summary>

```text
[baseline] polling table readings for id > 0 (Ctrl+C to stop)
[baseline] read    1,388  backlog   1,200 rows  delay   2.1 s  missing     22  anomalies 0
[baseline] read    4,588  backlog   4,060 rows  delay   6.8 s  missing     37  anomalies 0
[baseline] read    6,588  backlog   5,855 rows  delay   9.9 s  missing     37  anomalies 0
[baseline] read    8,588  backlog   7,665 rows  delay  12.9 s  missing     37  anomalies 0
[baseline] read   10,588  backlog   9,453 rows  delay  15.8 s  missing     37  anomalies 0
[baseline] read   12,588  backlog  11,210 rows  delay  18.7 s  missing     37  anomalies 0
[baseline] read   14,588  backlog  12,960 rows  delay  21.7 s  missing     37  anomalies 0
[baseline] read   16,588  backlog  14,708 rows  delay  24.6 s  missing     37  anomalies 0
[baseline] read   18,588  backlog  16,460 rows  delay  27.5 s  missing     37  anomalies 0
[baseline] stopped: read 18,588 readings, last id 19,257, 37 readings missing, 0 anomalies
```

</details>

<details>
<summary>plant_20.txt</summary>

```text
run 1794413408: 20 machines x 10 Hz = 200 readings/s -> postgres (Ctrl+C to stop)
  t=    5s      1,020 readings sent (204/s)
  t=   10s      2,020 readings sent (202/s)
  t=   15s      3,020 readings sent (201/s)
  t=   20s      4,020 readings sent (201/s)
  t=   25s      5,020 readings sent (201/s)
  t=   30s      6,020 readings sent (201/s)
  t=   35s      7,020 readings sent (201/s)
  t=   40s  fault starts on M-006 (repaired in 45 s)
  t=   40s      8,020 readings sent (200/s)  faulty: M-006
  t=   45s      9,020 readings sent (200/s)  faulty: M-006
  t=   50s     10,020 readings sent (200/s)  faulty: M-006
  t=   55s     11,020 readings sent (200/s)  faulty: M-006
  t=   60s     12,020 readings sent (200/s)  faulty: M-006
  t=   65s     13,020 readings sent (200/s)  faulty: M-006
  t=   70s     14,020 readings sent (200/s)  faulty: M-006
  t=   75s     15,020 readings sent (200/s)  faulty: M-006
  t=   80s     16,020 readings sent (200/s)  faulty: M-006
  t=   85s     17,020 readings sent (200/s)
run 1794413408: sent 18,000 readings in 91 s
```

</details>

<details>
<summary>plant_60.txt</summary>

```text
run 1794413510: 60 machines x 10 Hz = 600 readings/s -> postgres (Ctrl+C to stop)
  t=    5s      3,060 readings sent (612/s)
  t=   10s      6,060 readings sent (606/s)
  t=   15s      9,060 readings sent (604/s)
  t=   20s     12,060 readings sent (603/s)
  t=   25s     15,060 readings sent (602/s)
  t=   30s     18,060 readings sent (602/s)
  t=   35s     21,060 readings sent (602/s)
  t=   40s  fault starts on M-029 (repaired in 45 s)
  t=   40s     24,060 readings sent (601/s)  faulty: M-029
  t=   45s     27,060 readings sent (601/s)  faulty: M-029
  t=   50s     30,060 readings sent (601/s)  faulty: M-029
  t=   55s     33,060 readings sent (601/s)  faulty: M-029
run 1794413510: sent 36,000 readings in 61 s
```

</details>
