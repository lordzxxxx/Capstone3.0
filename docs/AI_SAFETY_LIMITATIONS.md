# AI safety and limitations

## Intended use

AI-DSUHIS provides non-prescriptive decision support for trained health
workers. It can organize symptom guidance, surface emergency warning signs,
and encourage referral or human review. It must not be used as a stand-alone
diagnosis, treatment, medication, or prescription tool.

## Controls implemented

- Firebase Authentication and App Check are required for `/guidance`.
- Requests are rate-limited and malformed/unknown input is rejected safely.
- Medication and prescription wording is filtered from guidance responses.
- Emergency warnings are retained and shown as referral/escalation prompts.
- Low-confidence and human-review messaging is shown to the user.
- The disabled `/predict` route prevents accidental exposure of disease
  probabilities.
- Record saving does not depend on the AI backend being available.
- Security rules enforce approved role and barangay access boundaries.

## Limitations that must be stated in the defense

- The dataset's external publisher, geographic representativeness, collection
  method, and clinical labeling process are not independently verified here.
- The current source size and 95% accuracy target gates are not met.
- Held-out dataset agreement is not clinical validation.
- The manually labeled local safety set is pending qualified professional
  review.
- Real authenticated production requests, live Firestore guidance reads, and
  field-device/offline testing remain release gates.
- OCR parser tests do not establish photographed-form OCR accuracy.
- Unknown, ambiguous, incomplete, or contradictory input can produce an
  uncertain result; staff must review the complete record.

## Human responsibility

The attending health professional remains responsible for assessment,
referral, treatment, emergency action, and prescriptions. Emergency prompts do
not replace local emergency protocols. The system should be withdrawn from
use if its guidance content, credentials, security controls, or clinical
review status cannot be maintained.
