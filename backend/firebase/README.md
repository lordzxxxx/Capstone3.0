# Firestore disease knowledge base

## BHW Analytics demo data

`seed_bhw_analytics_demo.py` creates deterministic, barangay-scoped demo
records for the BHW Analytics graphs. It discovers registered BHW accounts,
writes under `barangays/{BARANGAY_CODE}/{collection}`, and marks every document
with `isDemoData: true` and `demoDataset: bhw-analytics-demo-v1`. Stable IDs and
merge writes make repeated runs idempotent; the command never deletes records.

From the repository root in PowerShell:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = (
  Resolve-Path 'backend\firebase\capstone-c98f9-firebase-adminsdk-fbsvc-cc42d687d2.json'
).Path
$env:FIRESTORE_DATABASE_ID = 'capstone-c98f9'

# Validate counts without writing
.\backend\venv\Scripts\python.exe backend\firebase\seed_bhw_analytics_demo.py

# Apply to every registered BHW barangay scope
.\backend\venv\Scripts\python.exe backend\firebase\seed_bhw_analytics_demo.py --apply

# Optionally limit the seed to one barangay
.\backend\venv\Scripts\python.exe backend\firebase\seed_bhw_analytics_demo.py `
  --apply --barangay-code AGLAYAN
```

The generated records cover patient demographics, BMI, blood-pressure trends,
check-ups, immunizations, morbidity, mortality, referrals, communicable cases,
and non-communicable cases. Keep the service-account file private and never
ship it with the Flutter web build.

## Purpose and safety boundary

The Scikit-learn model predicts a disease label from binary symptom inputs. The
Firestore `diseases` collection separately provides draft educational content
for that label. Knowledge content is not an ML feature and must never be merged
into the symptom-training CSV.

All generated records use `clinicalReview.status: needs_review`. They are for
education and decision support only, are not a diagnosis, and do not replace a
licensed healthcare professional. An authorized clinical reviewer must approve
content before it is treated as reviewed material.

## Inputs and generated files

The generator reads the exact 100 classes from `models/disease_model.pkl` and
maps them to
`dataset/knowledge_base/AI_DSUHIS_Disease_Self_Care_Knowledge_Base.csv`.
Model classes are authoritative; the CSV contributes draft content only.

- `disease_seed.json`: array form for review and validation
- `disease_seed_firestore.json`: map keyed by Firestore document ID
- `reports/disease_seed_validation.json`: detailed errors and warnings
- `reports/missing_disease_records.csv`: model labels without content
- `reports/unmatched_disease_labels.csv`: source rows outside model classes

`datasetSymptoms` contains ML-dataset associations with frequency annotations
removed. It must not be interpreted as proof of clinical causation.
`commonSymptoms` remains separate and empty until clinically reviewed content is
provided.

## Firestore schema

Documents are stored at `diseases/{diseaseKey}`. Keys are normalized lowercase
IDs such as `acute_kidney_injury`. Documents contain display/model labels,
aliases, category, separate dataset and clinical symptoms, care level, guidance,
cautions, prevention, risk factors, complications, escalation advice,
specialists, ICD-10 codes, references, clinical-review state, content version,
activity state, and server timestamps.

ICD-10 arrays are intentionally empty unless an approved source mapping is
available. Empty codes produce warnings, not invented codes.

## Generate and validate

From the repository root in PowerShell:

```powershell
.\venv\Scripts\python.exe backend\firebase\generate_disease_seed.py
.\venv\Scripts\python.exe backend\firebase\validate_disease_seed.py
.\venv\Scripts\python.exe backend\firebase\seed_firestore.py --dry-run
```

The validator exits non-zero for coverage, schema, safety, or model-label
errors. The seed command defaults to dry-run even when no mode is supplied.

## Firebase credentials and apply

Install dependencies and point Application Default Credentials at a service
account kept outside the repository:

```powershell
.\venv\Scripts\python.exe -m pip install -r backend\requirements.txt
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\firebase-service-account.json'
.\venv\Scripts\python.exe backend\firebase\seed_firestore.py --apply
```

Optional bounded or single-record operations:

```powershell
.\venv\Scripts\python.exe backend\firebase\seed_firestore.py --apply --batch-size 100
.\venv\Scripts\python.exe backend\firebase\seed_firestore.py --apply --only influenza
```

The apply mode uses server timestamps, preserves `createdAt` on updates, updates
`updatedAt`, skips unchanged content, never deletes documents, and prints
created/updated/unchanged/skipped/failed totals. Never commit credential JSON.

## Clinical-review workflow

1. Generate and validate the draft.
2. Have a licensed reviewer assess disease wording, escalation advice,
   specialists, references, and any future ICD-10 mapping.
3. Record reviewer identity/time and notes through an authorized admin workflow.
4. Change status to `approved` only after actual review.
5. Regenerate or apply updates with a new `contentVersion` when content changes.

## FastAPI and Flutter

`app/disease_service.py` performs read-only server lookups. `app/api.py` attaches
public disease content after prediction and still returns the prediction if
Firestore is unavailable. Low-confidence results are explicitly described as
possible-condition information.

A Flutter client should call FastAPI rather than use Admin credentials:

```dart
final response = await http.post(
  Uri.parse('$apiBaseUrl/predict'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'symptoms': ['fever', 'cough']}),
);
final payload = jsonDecode(response.body) as Map<String, dynamic>;
final available = payload['contentAvailable'] == true;
final diseaseInfo = payload['diseaseInfo'] as Map<String, dynamic>?;
```

Do not display content as a confirmed diagnosis, especially when
`reliablePrediction` is false.

## Security rules

`firestore.rules` allows authenticated users to read active disease documents
and restricts writes to existing super-admin roles. Firebase Admin bypasses
client rules, so service-account access must be tightly controlled.

## Rollback

Before the first apply or a large content update, export/backup the Firestore
`diseases` collection. To roll back, restore the prior reviewed seed/version with
the same guarded apply command. The script intentionally never performs
automatic deletes; retire a document by setting `isActive` to false through an
authorized workflow.
