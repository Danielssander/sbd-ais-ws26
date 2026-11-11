# Exercise 5 - Stages A and B

Daniel Sander-Gassner

## Stage A - Today's system

### How the tests were run

These are actual runs of the supplied `plant.py`, `baseline_detector.py`, `model.py` and `services.py`, without modifying those files. I used Python 3.12 and PostgreSQL 16.2 on Linux in a remote environment. PostgreSQL ran directly, rather than in the supplied PostgreSQL 18.1 Docker container. These results demonstrate the supplied algorithm's behaviour in this environment; they do not verify the Windows/Ubuntu VM setup or the Docker configuration.

I started the detector first, then ran the 20-machine plant for 90 seconds. After the plant finished, I allowed 10 seconds for the detector to drain and checked that its reported backlog was zero. I reset the database tables before the second test, started a fresh detector, and ran the default 60-machine plant for 60 seconds. I stopped that detector immediately after the plant finished.

Commands, each long-running program in its own terminal:

```bash
# Test 1: start detector first
python3 baseline_detector.py --quiet
python3 plant.py --sink postgres --machines 20 --duration 90

# After the plant ends, wait for backlog 0, then stop detector with Ctrl+C.
# Count rows for this run:
```

```sql
SELECT count(*) FROM readings
WHERE run = (SELECT max(run) FROM readings);
```

```bash
# Test 2: start a fresh detector first
python3 baseline_detector.py --quiet
python3 plant.py --sink postgres --duration 60
# Stop the detector immediately after the plant ends.
```

`--quiet` only suppresses printing each anomaly; the model still processes and counts them. Both tests kept the default inference cost of 3 ms per reading.

### A1 - Why readings go missing at 20 machines

| Measurement | 20-machine test |
|---|---:|
| Readings sent / rows stored | 18,000 / 18,000 |
| Readings processed | 14,962 |
| Stored but never processed after draining | 3,038 |
| Model's missing counter | 3,038 |
| Final reported backlog | 0 |
| Live reported delay | 0.1-0.3 s |


The skipped readings are in the database. The detector remembers the highest ID it has processed and queries only `WHERE id > last_id`. IDs are allocated during INSERT, but rows become visible to other connections only after COMMIT. The four gateways commit independently.

In the example from the assignment:

1. Gateway 1 inserts IDs 100-114 but does not commit yet.
2. Gateway 2 inserts IDs 115-129 and commits immediately.
3. The detector polls, sees 115-129 and advances `last_id` to 129.
4. Gateway 1 commits. Its rows now exist, but their IDs are below 129, so later polls never return them.

Therefore, ID allocation order is not commit order. The detector can keep up with the incoming rate and still miss rows. A zero backlog does not establish completeness: the displayed backlog is `max(id) - last_id`, not a count of all unprocessed readings. Comparing the table count with the detector's processed count exposes the loss.

### A2 - What changes at the full rate

The 60-machine run stored **36,000 readings**. When stopped, the detector had processed **18,588**, with a missing counter of **37**. During production, the printed delay rose from **2.1 s to 27.5 s**, and the reported backlog rose from **1,200 to 16,460**. These are live log samples, not the final SQL queue size or a p95 measurement.

The remaining 36,000 - 18,588 = **17,412** readings were unprocessed at shutdown; that number includes outstanding work and skipped readings, so it must not be called permanent loss. The missing counter only counts sequence gaps after a machine's first observed reading; it does not count an unseen initial prefix or a still-unread suffix. No anomalies had been detected by shutdown: the detector was still processing data from before the fault at plant time 40 s.


The full plant produces 60 x 10 = **600 readings/s**. With 3 ms per score, one sequential detector can handle at most about **333 readings/s**, before database and Python overhead. The incoming work exceeds its capacity, so backlog and reading age grow while the plant is running. Growing delay puts the 5-second freshness requirement at risk; the printed delay is a sample, not a measured p95 latency.

The commit-order bug still exists, but the missing counter need not grow at the same rate as in the small test. When the detector falls behind, previously uncommitted batches have more time to commit before it reaches their IDs. Therefore, a small missing counter in the overloaded test would not mean the polling algorithm is safe. Missing readings and overload are separate problems. Stopping the plant lets the backlog drain, so the important observations are those taken while it is still producing.

## Stage B - My decision record

I choose Kafka for sensor readings and keep PostgreSQL as the system of record for the machine registry.

| Requirement | PostgreSQL with improved polling | Kafka |
|---|---|---|
| R1: scale | Several pollers owning different machines can increase processing capacity. Inserts and polling still load the database; 100,000 readings/s needs benchmarking. | Partitions distribute readings across detectors. Broker capacity and partition balance still need testing at 100,000 readings/s. |
| R2: complete and ordered | Needs a correct protocol, e.g. per-machine sequence checkpoints and retrying gaps. More pollers do not fix the global-ID bug. | Key by machine_id, preserve producer order and process partitions sequentially within one detector group. Recover model state consistently with offsets and deduplicate retries. |
| R3: p95 delay <= 5 s | Possible at low load with sufficient workers; polling and database contention add delay. | Possible with enough workers and low lag; Kafka itself does not guarantee the target. Measure p95 at full load. |
| R4: independent consumers | Extra readers add PostgreSQL load, failing R4 as written. | Detector, archive and dashboard use separate groups and offsets without reading sensor data from PostgreSQL. Provision shared broker resources adequately. |

**Numbers:** one reading costs 0.003 s, giving an ideal ceiling of 333.3 readings/s per sequential detector. For 600 readings/s, ceil(600 x 0.003) = **2 detectors** is the theoretical minimum. For 100,000 readings/s, the arithmetic gives **300 detector-equivalents**, but that means 100% utilisation: at least **301** would be needed even under ideal balance to stay below saturation. Real workloads need more headroom. At a starting target of 70% utilisation, ceil(rate x 0.003 / 0.7) gives **3 and 429 detectors**, respectively; validate these budgets by measurement. Use at least as many partitions as active detectors and check key distribution.

I would use idempotent production with reliable acknowledgements, retained readings for replay, and a separate anomalies topic. Rebalances require model-state restoration or sufficient replay to rebuild the per-machine warm-up/window state; offsets alone cannot restore it.

There is no universal tipping point. One temperature reading per minute is easily served by correct database polling. This model approaches one worker's ceiling around 300 readings/s and needs parallelism at 600. Kafka is justified here by the combination of rate, ordered replay and independent readers, especially R4; this is not a claim that PostgreSQL cannot sustain a particular insert rate.

## Run evidence

The database tables were reset between tests. The count results below also record minimum sequence, maximum sequence and distinct machines. No protected source file was changed and no solution code read ground_truth.jsonl. Stage C was not attempted.

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
