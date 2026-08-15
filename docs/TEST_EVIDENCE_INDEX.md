# Test evidence index

Verification date: 2026-08-15.

| Evidence | Command or artifact | Result |
| --- | --- | --- |
| Backend unit/API tests | `backend/.venv/bin/pytest -q` | 69 passed |
| Flutter regression suite | `flutter test --no-pub` | 91 passed |
| Flutter static checks | `flutter analyze --no-pub` | No blocking analyzer errors; existing warnings/infos remain documented by command output |
| Web release build | `flutter build web --release --no-tree-shake-icons` | Succeeded |
| Android debug build | `flutter build apk --debug --no-pub` | Succeeded |
| Android emulator smoke | Install/launch on `emulator-5554`, Android 14 | Succeeded |
| Firestore security rules | `npm run test:firestore-rules` | 17 passing |
| Firestore workflow persistence | `npm run test:workflow-persistence` | 1 passing |
| Guidance seed schema | `backend/firebase/seed_symptom_guidance.py` | 7 documents validated in dry run |
| AI validation | `docs/AI_VALIDATION_REPORT.md` | Dataset/model limitations and metrics documented |
| E2E gates | `docs/E2E_TEST_LOG.md` | External gates listed with owners/actions |

## Screenshot evidence

The repository currently contains no checked-in production screenshots. The
defense team should capture and attach, using synthetic data only:

1. narrow mobile landing/auth screen without overflow;
2. OCR permission, review, low-confidence correction, and saved form;
3. mobile offline save and later sync;
4. web BHW check-up guidance and disclaimer;
5. emergency warning and medication-filter behavior;
6. BHW → CHO → doctor referral continuity.

Screenshots are presentation evidence, not a substitute for the automated
tests or professional review.
