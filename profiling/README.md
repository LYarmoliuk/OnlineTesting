# Lab 9 profiling artifacts

`scripts/run-lab9.ps1` creates `results/` with the same attempt fixture used for both modes, k6 summaries, SQL `EXPLAIN ANALYZE` plans, and Docker CPU/memory samples. It starts Jaeger at [http://localhost:16686](http://localhost:16686); filter services `onlinetesting-api-a`, `-b`, or `-c` and spans `lab9.attempt.read`.

The default run is a short smoke run. For reportable numbers, run at least three 60-second iterations at the same VU count and use medians. See `docs/profiling/report-template.md`. Never commit `.env` or secrets. Result JSON/CSV/trace exports are evidence and may be committed selectively after review.
