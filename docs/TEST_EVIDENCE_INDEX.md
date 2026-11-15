# Test evidence index

Verification date: 2026-10-15.

| Evidence | Command or artifact | Result |
| --- | --- | --- |
| Backend unit/API tests | `backend/.venv/bin/pytest -q` | 109 passed |
| Flutter regression suite | `flutter test --no-pub` | 220 passed |
| Flutter static checks | `flutter analyze --no-pub` | 0 blocking errors; 311 warnings/info findings remain, including legacy unused code and debug prints |
| Web release build | `flutter build web --release --no-wasm-dry-run` | Succeeded |
| Android debug build | `flutter build apk --debug --no-pub` | Succeeded |
| Android emulator smoke | Install/launch on `emulator-5554`, Android 14 | Succeeded |
| Firestore security rules | `npm run test:firestore-rules` | 33 passing |
| Storage security rules | `npm run test:storage-rules` | 6 passing |
| Functions callable suites | BHW, doctor, RBAC, access, routing, account emulator suites | Passed locally |
| Referral attachment authorization | `npx mocha tests/referral_attachment_access.unit.test.cjs` | 5 passing |
| Guidance seed schema | `backend/firebase/seed_symptom_guidance.py` | 7 documents validated in dry run |
| AI validation | `docs/AI_VALIDATION_REPORT.md` | Dataset/model limitations and metrics documented |
| RAG/LLM safety tests | `backend/tests/test_rag_orchestration.py` | 4 passed with mocked provider; live provider not configured |
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
