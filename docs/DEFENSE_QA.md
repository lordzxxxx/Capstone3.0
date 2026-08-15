# Defense questions and safe answers

## What is the AI feature?

It is symptom guidance and triage-oriented decision support. The supported
backend endpoint is `/guidance`; it retrieves reviewed guidance content and
does not return a diagnosis or prescription.

## Is the Random Forest the production diagnosis model?

No. Its group-safe held-out metrics are documented as offline evaluation only.
The `/predict` route is disabled. The product uses Firestore-backed guidance
and a local rule-based fallback for availability and explainability.

## What do the 89.34% and 98.51% numbers mean?

They are the offline model's group-safe held-out top-1 and top-3 agreement with
dataset labels: 89.3399% and 98.5052%. They are not clinical accuracy and not
diagnostic certainty. Top-2 is 96.5424%.

## Why is the dataset limitation important?

There are 93,993 usable records, below the 150,000 project target, and the
external provenance and clinical labeling process are not independently
verified in this repository. The project reports that limitation instead of
padding the dataset or overstating the result.

## Can the system prescribe medicine?

No. Medication and prescription advice is filtered from guidance, and staff
remain responsible for treatment and prescriptions.

## What happens when the backend is unavailable?

The record can still be saved. Mobile retains its local decision-support path,
and a release without a configured API URL fails closed with a clear
unavailable message rather than calling localhost.

## How is access protected?

The guidance API requires Firebase Authentication and App Check, applies rate
limiting and input validation, and Firestore rules enforce approved role and
barangay scope. Emulator-backed rules and workflow tests are included.

## Is OCR clinically intelligent?

No. Google ML Kit recognizes text and the app maps conservative labeled values
into an editable form. Workers must review every value; OCR accuracy on real
printed forms still needs a manually labeled field study.

## What has not been validated yet?

Qualified health-professional review, live production Firebase/App Check
requests, production API hosting, target-handset offline synchronization, and
the real-form OCR accuracy study remain open gates.

## What is the main safety principle?

The system supports a trained worker but never replaces clinical judgment. It
surfaces uncertainty and emergency referral prompts while keeping assessment,
treatment, and referral responsibility with qualified staff.
