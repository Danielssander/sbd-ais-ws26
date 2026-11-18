# Exercise 6 - Card Sentinel

## My decision

I would use log-based CDC with Debezium because I cannot change the certified payment path. It reads committed changes from PostgreSQL's WAL instead of repeatedly querying the payments table. Polling adds query load and can miss payments that commit out of ID order. Dual writes change the application and can lose an event if it crashes between the database commit and the Kafka send. Each model has its own consumer group, so both receive the stream independently. The main operational risk is that the replication slot retains unread WAL while Debezium is down; I would monitor connector status, replication lag, retained WAL size and free disk space, with alerts before storage fills up. If my team owned the payment path, I would choose a transactional outbox, writing the payment and its event in the same database transaction.

## Three runs

**Measurement status:** The runs have not been executed yet. The statements below are predictions based on the exercise instructions, not measured results. The required velocity scoreboard lines must be added after running the experiments.

### Run 1 - one partition, payment ID as key

**Prediction:** Only one velocity instance gets partition 0; the other two stay idle, so R4 should fail. One instance processes about 400-500 payments/s against 1,000 incoming payments/s, so the backlog grows and some frauds have not been processed when the scoreboard runs.

**Measured velocity R3 (caught / false alerts) and R4:** Not measured yet.

### Run 2 - six partitions, payment ID as key

**Prediction:** All three velocity instances can work, so R4 should pass, but fraud recall (R3) should fail. Payments from one cardholder are split between instances because the key is still the payment ID, so each instance sees only part of the 12-payment attack and may never reach the threshold of eight payments within 60 seconds.

**Measured velocity R3 (caught / false alerts) and R4:** Not measured yet.

### Run 3 - six partitions, cardholder ID as key

**Prediction:** The key payload becomes `{"user_id": ...}`, and R3 and R4 should pass if the machine sustains the full rate. All payments from one cardholder now reach the same partition and instance in order, keeping the model's history together while distributing different cardholders across the three instances.

**Measured velocity R3 (caught / false alerts) and R4:** Not measured yet.

## What unchecked defaults would cause

One partition would leave two velocity instances idle and delay alerts; using payment IDs with multiple partitions would silently split each cardholder's history and miss fraud. I would check partition assignments, consumer lag, p95 alert latency and fraud recall against confirmed cases, and test detection with multiple instances before deployment. The final connector therefore uses six partitions and `user_id` as the key; the replication factor is one because this lab has one broker.
