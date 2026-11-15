# Staging load and performance test plan

Run only against local, preview, or a dedicated staging API. Never run a
stress test against the live website or production API. The repository helper
`tools/load_test_api.py` refuses remote targets unless both
`--allow-remote --confirm-remote` are supplied and caps them at 100 requests.

## Baseline probe

Start the FastAPI service locally with non-production test settings, then run:

```bash
python3 tools/load_test_api.py \
  --base-url http://127.0.0.1:8000 \
  --path /health \
  --requests 50 \
  --concurrency 5
```

The output reports p50/p95/max/mean latency, throughput, success/error count,
and status counts. It never prints bodies or auth headers.

## Staging matrix

Run small steps such as 10, 25, 50, and 100 requests with concurrency 1, 5,
and 10. Stop if errors, timeouts, memory growth, or database contention
appears. Capture API and provider metrics for each step.

- `GET /health` and `/ready` liveness/readiness.
- `GET /symptoms` vocabulary retrieval.
- Authenticated `POST /guidance` with a synthetic symptom set.
- Authenticated OCR single and batch with synthetic non-clinical images.
- Login/logout and protected dashboard load in a preview browser.
- Patient/referral search, filters, pagination, one create/update, and refresh.
- Storage upload/download/delete using the Storage runbook matrix.
- Referral assignment, doctor action, notes, and BHW history synchronization.
- Invalid payloads, missing auth, missing App Check, 401/403/404/422/429/503,
  network interruption, and timeout recovery.

## Record

For every run record target revision, date, request count, concurrency, p50/p95,
error rate, status counts, Cloud Run CPU/memory/instance count, Firestore
latency/reads, Storage failures, Functions failures, and whether any data was
left behind. Do not record patient payloads, access tokens, or uploaded content.

The current practical Cloud Run starting point is 2 CPU, 4 GiB memory,
concurrency 1, and max 3 instances. These are safe staging hypotheses, not
performance claims; change them only after evidence, especially for TrOCR.
