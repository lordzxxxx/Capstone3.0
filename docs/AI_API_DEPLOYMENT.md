# FastAPI AI/OCR deployment runbook

Recommended host: Google Cloud Run in `asia-east1`, close to the existing
Firestore database. Cloud Run provides a stable HTTPS service URL and supports
the repository's `backend/Dockerfile`. The deployment is not performed by this
document.

## What the service needs

The service exposes:

- `GET /health` — cheap liveness/model status check.
- `GET /ready` — model plus Firestore readiness check for deployment/uptime.
- `GET /symptoms` — bounded symptom vocabulary.
- `POST /guidance` — Firebase Auth + Firebase App Check protected supportive
  guidance backed by Firestore.
- `POST /api/v1/ocr/handwriting` and `/batch` — Firebase Auth + App Check
  protected TrOCR handwriting recognition.

The active `/guidance` path is guidance/decision support, not diagnosis. The
Random Forest `/predict` route is intentionally disabled. The model checksum
currently recorded by the repository is:

`4cc536ba3503283454f58c6f53d992350f1e6205317d3b3c50e7da3573cd370c`

The TrOCR model is loaded lazily from Hugging Face by the first OCR request.
Use at least 4 GiB memory and concurrency 1 for the initial staging test; keep
the service at one process until a measured load test proves more is safe.

## One-time Google Cloud setup

Use a project owner or Cloud administrator. Billing is required for Cloud Run,
Cloud Build, Artifact Registry, and production Firestore access.

```bash
gcloud auth login
gcloud config set project capstone-c98f9
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com firestore.googleapis.com
gcloud iam service-accounts create ai-dsuhis-api \
  --display-name="AI-DSUHIS FastAPI service"
gcloud projects add-iam-policy-binding capstone-c98f9 \
  --member="serviceAccount:ai-dsuhis-api@capstone-c98f9.iam.gserviceaccount.com" \
  --role="roles/datastore.user"
```

Do not create or upload a service-account JSON key. The container uses
Application Default Credentials from the attached service account. The
Datastore User role is required because the API reads guidance and atomically
writes hashed rate-limit windows; use a narrower custom role if the project
owner has one approved for those operations.

## Deploy from the repository

Run from the repository root after confirming the model files are present and
the code is in the reviewed local state:

```bash
gcloud run deploy ai-dsuhis-api \
  --source backend \
  --project capstone-c98f9 \
  --region asia-east1 \
  --service-account ai-dsuhis-api@capstone-c98f9.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --port 8080 \
  --memory 4Gi \
  --cpu 2 \
  --concurrency 1 \
  --timeout 300 \
  --min 0 \
  --max 3 \
  --set-env-vars "APP_ENV=production,FIRESTORE_DATABASE_ID=capstone-c98f9,MODEL_VERSION=1.0.0,MODEL_EXPECTED_SHA256=4cc536ba3503283454f58c6f53d992350f1e6205317d3b3c50e7da3573cd370c,WEB_ALLOWED_ORIGINS=https://www.ai-dsuhis.com\,https://ai-dsuhis.com,API_ALLOWED_HOSTS=localhost,AI_REQUIRE_FIREBASE_AUTH=true,AI_REQUIRE_APP_CHECK=true,AI_CHECK_REVOKED_TOKENS=true,RATE_LIMIT_BACKEND=firestore,LOG_LEVEL=INFO"
```

Production must use `RATE_LIMIT_BACKEND=firestore`. The API, OCR, and
authenticated guidance limits then update atomically in the shared
`api_rate_limits` collection, so a multi-instance Cloud Run service cannot
reset a caller's quota by moving the request to another instance. Configure a
Firestore TTL policy on `api_rate_limits.expiresAt` after the first deployment
so expired limiter documents are removed automatically. If the Firestore
limiter is unavailable, protected requests fail closed with a safe `503`.

The initial `API_ALLOWED_HOSTS=localhost` is only a bootstrap value so the
service can be created. Immediately read the service URL and replace it with
the exact host. Do not leave `localhost` in a production revision:

```bash
SERVICE_URL="$(gcloud run services describe ai-dsuhis-api \
  --project capstone-c98f9 --region asia-east1 --format='value(status.url)')"
SERVICE_HOST="${SERVICE_URL#https://}"
gcloud run services update ai-dsuhis-api \
  --project capstone-c98f9 --region asia-east1 \
  --update-env-vars "API_ALLOWED_HOSTS=${SERVICE_HOST}"
curl --fail "${SERVICE_URL}/health"
curl --fail "${SERVICE_URL}/ready"
```

For a cleaner public name, map `api.ai-dsuhis.com` to the service, complete
the DNS records Cloud Run provides, then update `API_ALLOWED_HOSTS` to include
`api.ai-dsuhis.com` and use that custom HTTPS name below. Keep the generated
`run.app` host during the first smoke test as a rollback path.

## Vercel configuration

`AI_API_BASE_URL` is a Flutter compile-time value. Setting the Vercel variable
does not change an already-built deployment; it requires a new Vercel build.

In Vercel Project Settings → Environment Variables:

- Production: `AI_API_BASE_URL=https://api.ai-dsuhis.com` (or the verified
  Cloud Run HTTPS URL, without a trailing slash).
- Preview/staging: a separate HTTPS staging API URL.
- Local development: `http://127.0.0.1:8000` only through a local Dart define.

Set `WEB_ALLOWED_ORIGINS` on Cloud Run to the exact deployed web origins and
keep Firebase Auth, App Check, and revoked-token checks enabled. After saving
the Vercel variable, trigger a new production deployment and verify the
compiled app version and an authenticated guidance request.

## Verification gate

Do not mark this blocker complete until all are true:

1. `/health` returns `200` and `/ready` returns `200` from the final HTTPS
   hostname.
2. An approved synthetic Firebase user plus a real browser App Check token can
   call `/guidance` and receive the expected response.
3. Invalid Firebase ID tokens and missing App Check return `401`/`403`.
4. Invalid, oversized, and mismatched OCR uploads return safe `4xx` responses;
   a valid test image returns a controlled result or safe `503`.
5. Vercel's compiled web artifact contains the verified HTTPS base and no
   localhost fallback.
6. Cloud Run logs contain request IDs, status, and latency but no tokens,
   request bodies, names, or symptom lists.
