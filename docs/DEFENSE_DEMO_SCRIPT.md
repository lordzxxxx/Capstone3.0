# Defense demo script

This script is designed to demonstrate implemented behavior without relying
on unverified accuracy or clinical-review claims. Use a seeded evaluation
project and test accounts; never use real patient data in a public defense.

## 1. Introduce the scope (30 seconds)

> “AI-DSUHIS is a Flutter mobile and web health-record system for BHWs,
> doctors, and the CHO. The two capstone features are OCR-assisted data entry
> and non-prescriptive symptom guidance. The AI is decision support, not a
> diagnosis or prescription system.”

## 2. Show OCR-assisted entry (2 minutes)

1. Sign in as a BHW on the Android test device.
2. Open patient registration or check-up and choose **Create with OCR**.
3. Capture a prepared, synthetic printed form.
4. Point out the permission rationale and the editable review screen.
5. Show a low-confidence field and correct it manually.
6. Continue to the normal form and save.
7. Point out that OCR values remain subject to ordinary required-field and
   format validation.

Say: “OCR assists data entry; it does not decide a clinical value or bypass
validation.”

## 3. Show offline record continuity (1 minute)

1. Use the prepared test environment's offline mode or disable network on the
   test device.
2. Create a synthetic check-up record and save it.
3. Show that the record remains in the local workflow.
4. Restore connectivity and show the sync result.

This step is a release gate until it has been run on the team's target
handset and documented in `docs/E2E_TEST_LOG.md`.

## 4. Show AI guidance safely (2 minutes)

1. With a configured staging API and test account, enter a benign symptom
   example such as “fever and cough”.
2. Show the supportive guidance, precautions, emergency warning section, and
   human-review disclaimer.
3. Enter an emergency example and show referral/escalation wording.
4. Enter a medication/prescription prompt and show that medication advice is
   not returned.
5. Stop the backend or remove the local API URL and save another record to
   demonstrate that record keeping remains usable.

Do not show a disease probability, call `/predict`, or claim the response is a
diagnosis. If production API/App Check credentials are not configured, show the
safe unavailable state and identify the deployment gate honestly.

## 5. Show role workflow (1 minute)

1. BHW creates a synthetic referral.
2. CHO reviews it and assigns a doctor.
3. Doctor records a consultation note.
4. BHW reads the continuity-of-care result.

The Firestore emulator evidence for this sequence is recorded as one passing
workflow test in `docs/E2E_TEST_LOG.md`.
