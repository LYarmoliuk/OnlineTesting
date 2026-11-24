# Lab 9 — Performance profiling report

## Environment and reproducibility

- Git commit:
- Docker/OS:
- API replicas and DB configuration:
- Fixture size: 30 questions × 4 options, 30 saved answers (one attempt)
- VUs / duration:
- Date and time:
- Runs used for the reported values (use medians of at least 3 runs):

## Hypotheses

1. The single EF Core query joining the attempt, questions, answer options, and answers duplicates rows because two child collections are joined. `AsSplitQuery()` should reduce transferred/processed duplicate rows and improve tail latency for large attempts.
2. The response materialization and allocations may drive API CPU and memory under concurrency; runtime metrics and process/container samples will show whether this is material.
3. Database execution may be dominated by joins or scans; `EXPLAIN (ANALYZE, BUFFERS)` and Npgsql spans will confirm or reject this.

## Baseline evidence and root cause

Attach `single-explain.json`, `single.json`, `single-docker-stats.csv`, and Jaeger trace screenshots/links. Explain which hypothesis the evidence confirms. Do not state a root cause before the evidence supports it.

## Optimization

The `splitQuery` mode applies EF Core `AsSplitQuery()` to the read of one attempt. The response contract stays the same. Tradeoff: more SQL round trips, which may be slower for small attempts or high network latency.

## A/B results

| Mode | RPS | p95 (ms) | p99 (ms) | errors (%) | CPU (Docker) | memory (Docker) |
|---|---:|---:|---:|---:|---:|---:|
| Single query baseline | | | | | | |
| Split query optimized | | | | | | |

Compare medians from at least three runs with identical VUs, duration, fixture, environment, and warm-up. Attach JSON/CSV artifacts. The script produces a smoke run by default; use `-DurationSeconds 60 -Vus 25 -Runs 3` for a reportable experiment.

## Database and distributed tracing

Attach `single-explain.json`, `split-explain.json`, and trace screenshots from Jaeger filtered by `lab9.attempt.read`. Include the relevant SQL/span timings and explain the root cause.

## Tradeoffs and conclusion

Describe latency/throughput, CPU/memory, query count, and any regression. State whether the change should be retained for this workload and what workload limits that conclusion.
