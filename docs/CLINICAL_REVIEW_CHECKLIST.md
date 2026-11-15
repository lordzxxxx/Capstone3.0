# Clinical review checklist

This is an external approval gate. Software tests, model metrics, and a
successful demo are not clinical validation.

## Review scope

The reviewer must inspect:

- FastAPI `POST /guidance` output and the Firestore `symptom_guidance` content.
- Rule-based health-category suggestions from
  `backend/app/health_category_service.py` and
  `lib/app/core/services/health_ai_classifier.dart`.
- Emergency warning signs, referral wording, uncertainty/disclaimer behavior,
  and the medication/prescription exclusion filter.
- OCR extraction as data-entry assistance only: editable fields, low-confidence
  review, normal form validation, and no automatic clinical record save.
- The disabled legacy disease-prediction route and the boundary that no active
  AI output is a diagnosis or treatment prescription.

## Reviewer questions

For each symptom/condition content item:

1. Is the source authoritative, current, and correctly cited?
2. Is the wording clinically accurate for the intended Philippine CHO/BHW use?
3. Are emergency signs complete, prominent, and appropriately urgent?
4. Could self-care wording be read as medication, dosage, or diagnosis advice?
5. Are age, pregnancy, comorbidity, and escalation limitations clear?
6. Does an unknown, low-confidence, conflicting, or missing-content case fail
   safely to human review/referral?
7. Are health-category suggestions clearly advisory and never automatically
   used as a diagnosis or treatment decision?
8. Does OCR remain editable and require the same validation as manual entry?

## Approval record

The clinical owner should record content/model version, reviewer name and
professional role, organization, license/credential confirmation, review date,
items reviewed, corrections required, decision (`approved`, `approved with
conditions`, or `rejected`), expiry/review date, and signature or approved
institutional record. Store only the minimum evidence needed by policy.

If any item is rejected or needs correction, keep the guidance unavailable or
marked pending review; do not change a status to approved merely to pass a
deployment check.
