# Barangay Health Information System

A Flutter mobile + web application for barangay health workers (BHW), doctors,
and the City Health Office (CHO) to record patient care and get AI-assisted
decision support. Built around two capstone features:

- **OCR-assisted data entry** — scan printed health forms (camera or gallery)
  and auto-fill patient, checkup, prenatal, immunization, and surveillance
  forms via ML Kit text recognition. Extracted values stay editable and never
  bypass normal form validation; low-confidence fields are left blank for
  manual entry rather than guessed.
- **AI symptom guidance** — a decision-support feature, not a diagnosis tool.
  Given staff-entered symptoms, the backend returns self-care and
  emergency-referral guidance sourced from Firestore, clearly labeled as
  guidance for a health worker to review, not an automated diagnosis.

## Architecture

- **Mobile app** — `lib/app` (Flutter, Android/iOS). Patient records,
  checkups, prenatal, immunization, referrals, and camera/gallery-based OCR
  capture for BHWs in the field.
- **Web dashboard** — `lib/web` (Flutter web). Role-based views for BHW,
  doctor, and CHO staff: patients, checkups, prenatal, immunization,
  surveillance (communicable, non-communicable, mortality, morbidity),
  referrals, dashboard, and analytics.
- **Shared** — `lib/shared` — code used by both mobile and web targets.
- **Backend** — `backend/` (Python, FastAPI). Serves authenticated symptom
  guidance from Firestore-authored content, plus the supporting offline model
  evaluation/training pipeline. The Random Forest is not an active diagnosis
  endpoint. See
  [backend/README.md](backend/README.md) for the full pipeline, API, and
  deployment details.
- **Firebase** — Authentication, Firestore, App Check, and Hosting. Every
  `/guidance` request requires a valid Firebase ID token and App Check
  token.

### Backend API

| Method | Path        | Purpose                                      |
|--------|-------------|-----------------------------------------------|
| GET    | `/`         | API and model status                          |
| GET    | `/health`   | Health and dependency readiness               |
| GET    | `/symptoms` | List every valid model symptom                |
| POST   | `/guidance` | Authenticated symptom guidance (decision support) |

The legacy `POST /predict` disease-prediction route is intentionally not
registered and returns `404` — guidance, not diagnosis, is the supported
AI feature.

## Getting started

### Mobile / web app

```bash
flutter pub get
flutter analyze
flutter test
flutter run                 # mobile (connected device/emulator)
flutter run -d chrome        # web
```

### Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate   # already set up in .venv/
pip install -r requirements.txt
cp ../.env.example ../.env   # fill in local Firebase credentials, never commit .env
pytest -q
uvicorn app.api:app --reload
```

Full setup (environment variables, Firestore seeding, App Check
configuration, troubleshooting) is documented in
[backend/README.md](backend/README.md).

## Documentation

- [docs/CAPSTONE_COMPLETION_PLAN.md](docs/CAPSTONE_COMPLETION_PLAN.md) — phased
  checklist tracking the remaining capstone work.
- [docs/DEMO_WORKFLOW.md](docs/DEMO_WORKFLOW.md) — demo script.
- [docs/DATASET_PROVENANCE.md](docs/DATASET_PROVENANCE.md) — training data
  sources and lineage.
- [docs/AI_REQUIREMENTS_STATUS.md](docs/AI_REQUIREMENTS_STATUS.md) /
  [docs/AI_ACCURACY_GAP_ANALYSIS.md](docs/AI_ACCURACY_GAP_ANALYSIS.md) — model
  accuracy status and known gaps.

## Scope note

AI guidance is decision support for a health worker, not an automated
diagnosis: it never returns medication or prescription advice, always labels
low-confidence results as such, and the app remains fully usable for
record-keeping if the AI backend is unavailable. See the completion plan's
Phase 4 for validation status.
