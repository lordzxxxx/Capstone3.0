# Medical dataset pipeline

Compatible binary training CSV files live in `dataset/raw` and are never
modified by the pipeline. Text datasets, knowledge-base files, and excluded
sources are kept in their respective sibling directories. Add future compatible
binary datasets to `dataset/raw`, then run these commands from the project root:

```powershell
.\venv\Scripts\python.exe backend\scripts\inspect_dataset.py
.\venv\Scripts\python.exe backend\scripts\merge_datasets.py
.\venv\Scripts\python.exe backend\scripts\train_model.py
python backend/scripts/verify_ai_requirements.py
python backend/scripts/accuracy_audit.py
```

The verification command writes `reports/ai_requirements_verification.json`
with actual source counts, feature/target definitions, quality checks, and a
group-safe held-out evaluation. It does not generate or duplicate data.
The accuracy audit writes `reports/accuracy_statistics_audit.json` with exact
held-out hit counts, Wilson 95% intervals, top-k coverage definitions, the
identical-vector ambiguity ceiling, and (when `MODEL_PATH` is available)
multiclass log loss, Brier score, and top-label calibration error. It does not
retrain or rewrite the model.

To compare the original, recovered 100,000-row Kaggle source, union merge, and
common-feature merge without replacing the production baseline, run:

```powershell
.\venv\Scripts\python.exe backend\scripts\compare_datasets.py
```

This writes detailed comparison reports to `reports` and isolated experimental
models to `models/experiments`.

## Firestore disease knowledge

The trained model remains responsible only for symptom-to-disease prediction.
Draft educational and self-care content is maintained separately in Firestore.
Generate, validate, and preview the 100-label knowledge seed with:

```powershell
.\venv\Scripts\python.exe backend\firebase\generate_disease_seed.py
.\venv\Scripts\python.exe backend\firebase\validate_disease_seed.py
.\venv\Scripts\python.exe backend\firebase\seed_firestore.py --dry-run
```

See [firebase/README.md](firebase/README.md) for schema, clinical-review,
credentials, security, API integration, apply, and rollback guidance. No seed
command writes to Firestore unless `--apply` is explicitly supplied.

The merge command normalizes disease and symptom names, aligns all compatible
schemas, removes exact duplicates, removes diseases with fewer than 20 records,
and writes `dataset/processed/merged_dataset.csv`. The training command uses only
that master CSV and writes the model plus its ordered feature schema and metrics
to `models`.

Synonyms can be extended without changing Python code by editing:

- `dataset/mappings/disease_mapping.json`
- `dataset/mappings/symptom_mapping.json`

Files with no recognizable disease target and corrupted CSVs are logged and
skipped. `Name` is treated as a disease only when the same dataset contains a
symptom-list column; this avoids misclassifying catalog/remedy tables.

## Production symptom-guidance API

> The check-up workflow uses the authenticated `POST /guidance` endpoint for
> recognition-only symptom guidance. The legacy `POST /predict` route is no
> longer registered and returns HTTP 404.

### Symptom guidance workflow

`POST /guidance` normalizes submitted symptom keywords, validates them against
the 228-feature vocabulary, and retrieves self-care and emergency guidance from
the Firestore `symptom_guidance` collection. It never calls the Random Forest
prediction method and never returns a disease label, confidence, or Top-3 list.
An exact or aliased condition explicitly entered by staff (for example `UTI`,
`BPH`, or `COPD`) is matched against the known condition vocabulary and uses the
existing Firestore `diseases` guidance. Such values are returned separately as
`recognizedConditions` and are never described as AI predictions.

Validate the local guidance seed without writing to Firestore:

```powershell
.\backend\venv\Scripts\python.exe backend\firebase\seed_symptom_guidance.py
```

After clinical review and explicit approval, apply the documents once:

```powershell
.\backend\venv\Scripts\python.exe backend\firebase\seed_symptom_guidance.py --apply
```

Every guidance request must include a current Firebase Authentication ID token
and Firebase App Check token. The Flutter client attaches both automatically.
For an authorized diagnostic request in PowerShell:

```powershell
$body = @{ symptoms = @('fever', 'cough') } | ConvertTo-Json
$headers = @{
  Authorization = "Bearer $firebaseIdToken"
  'X-Firebase-AppCheck' = $firebaseAppCheckToken
}
Invoke-RestMethod -Method Post `
  -Uri 'http://127.0.0.1:8000/guidance' `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body $body
```

The active FastAPI guidance path does not load or call the Random Forest. It
recognizes submitted symptom/condition terms, retrieves reviewed Firestore
content, applies the medication/prescription safety filter, and returns
supportive care, precautions, referral prompts, emergency warning signs, and a
human-review disclaimer. The Random Forest and ordered feature columns remain
available for offline evaluation only; the disabled `/predict` route never
returns its Top-3 probabilities.

### Install and configure

```powershell
.\venv\Scripts\python.exe -m pip install -r backend\requirements.txt

$env:MODEL_PATH = (Resolve-Path 'backend\models\disease_model.pkl').Path
$env:FEATURE_COLUMNS_PATH = (Resolve-Path 'backend\models\feature_columns.json').Path
$env:CONFIDENCE_THRESHOLD = '0.50'
$env:MODEL_VERSION = '1.0.0'
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\capstone-service-account.json'
$env:FIRESTORE_DATABASE_ID = 'capstone-c98f9'
$env:FIRESTORE_TIMEOUT_SECONDS = '5'
$env:AI_REQUIRE_FIREBASE_AUTH = 'true'
$env:AI_REQUIRE_APP_CHECK = 'true'
$env:AI_CHECK_REVOKED_TOKENS = 'true'
$env:AI_RATE_LIMIT_REQUESTS = '30'
$env:AI_RATE_LIMIT_WINDOW_SECONDS = '60'
```

`MODEL_PATH`, `FEATURE_COLUMNS_PATH`, and `CONFIDENCE_THRESHOLD` have safe local
defaults. Firebase credentials must never be committed. The service-account key
should be stored outside the repository.

### Run and open Swagger

From the repository root:

```powershell
.\venv\Scripts\python.exe -m uvicorn backend.app.api:app --reload
```

Or from `backend`:

```powershell
Set-Location backend
..\venv\Scripts\python.exe -m uvicorn app.api:app --reload
```

Open `http://127.0.0.1:8000/docs`. Status endpoints are `GET /` and
`GET /health`.

### Run the protected Flutter web client

Register a reCAPTCHA v3 web provider in Firebase App Check, add `localhost` and
the deployed Hosting domains to its allowed domains, then run locally:

```powershell
.\flutter\bin\flutter.bat run -d chrome `
  --web-port 8081 `
  --dart-define=AI_API_BASE_URL=http://127.0.0.1:8000 `
  --dart-define=FIREBASE_APP_CHECK_WEB_KEY=YOUR_RECAPTCHA_V3_SITE_KEY `
```

Production web and mobile builds must provide the deployed HTTPS FastAPI host;
never ship the development localhost fallback:

```bash
flutter build web --release \
  --dart-define=AI_API_BASE_URL=https://YOUR_DEPLOYED_AI_API_HOST \
  --dart-define=FIREBASE_APP_CHECK_WEB_KEY=YOUR_RECAPTCHA_V3_SITE_KEY \
```

The repository does not contain a deployed AI API host yet. Until one is
provisioned, `AI-08` remains an operational deployment task rather than an
invented configuration value. Release builds fail closed for the guidance
request and still allow check-up records to be saved when the define is absent.

Release web builds fail at startup if the App Check site key is missing.
Android release builds use Play Integrity; Apple release builds use App Attest
with DeviceCheck fallback. Debug attestation providers are selected only in
Flutter debug builds.

### Tests

```powershell
.\venv\Scripts\python.exe -m pytest backend\tests -q
```

Tests use mocked Firestore for API/service behavior and do not require live
Firebase credentials.

Firestore authorization tests run against the Firebase emulator. Install
Node.js LTS first, then run once:

```powershell
npm install
npm run test:firestore-rules
```

The rules tests verify that users cannot promote their own role, approve their
own account, change barangay scope, or read patient data while pending.

### Troubleshooting

- `401`: sign in again so the Flutter client can refresh its Firebase ID token.
- `403`: configure App Check and register the current debug or production app.
- `429`: wait for the `Retry-After` interval before requesting more guidance.
- `contentAvailable: false`: verify credentials, `FIRESTORE_DATABASE_ID`, and
  the normalized disease document in the `diseases` collection.
- `422`: submit a non-empty JSON array of non-empty symptom strings.
- Low confidence is not an API failure; it indicates that the result must be
  displayed only as educational information about possible conditions.
