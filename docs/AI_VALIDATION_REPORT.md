# AI data and safety validation report

Verification date: 2026-08-15.

This report is the canonical summary for Phase 4. It separates offline model
agreement with a dataset from clinical validation. The system must not present
either number as diagnostic certainty.

## Dataset provenance — VAL-01

- The active Random Forest evaluation uses 93,993 usable records from
  `backend/dataset/processed/merged_dataset.csv`.
- The raw source has 96,088 rows; preprocessing removed invalid/duplicate
  structural content without synthetic padding.
- The repository records row-level provenance in
  `backend/dataset/processed/row_provenance.csv`.
- The external publisher, collection method, geographic representativeness,
  and clinical labeling process are not independently verified here.
- The 150,000-record acceptance minimum is not met. No untraceable data was
  added to close that gap.

Evidence: `docs/DATASET_PROVENANCE.md` and
`backend/reports/ai_requirements_verification.json`.

## Offline model evaluation — VAL-02 to VAL-04

The locked group-safe held-out evaluation for the offline `disease_model_v4`
artifact reports:

| Metric | Result | Interpretation |
| --- | ---: | --- |
| Top-1 accuracy | 89.3399% | Agreement with held-out dataset labels, not clinical accuracy |
| Top-2 accuracy | 96.5424% | True label appeared in the two highest-ranked classes |
| Top-3 accuracy | 98.5052% | True label appeared in the three highest-ranked classes |
| Five-fold training-only CV mean | 89.1082% | Robustness estimate; not a replacement for held-out evaluation |
| Exact feature-vector overlap | 0 groups | Group-safe split prevented identical vectors crossing train/test |

Lowest-recall classes are COPD (54.32%), skin pigmentation disorder
(60.87%), personality disorder (64.42%), noninfectious gastroenteritis
(67.22%), and skin polyp (68.32%). The largest confusion pairs include
infectious/noninfectious gastroenteritis, cystitis/benign blood in urine,
cholecystitis/gallstone, personality disorder/schizophrenia, and COPD/asthma.

Evidence: `backend/reports/accuracy_gap_analysis.json`,
`backend/reports/disease_model_per_class_report.csv`, and
`docs/AI_ACCURACY_GAP_ANALYSIS.md`.

## Safety behavior checks — VAL-05 to VAL-08

The repository verifies:

- ambiguous or unsupported text is marked for review or rejected with HTTP
  422 rather than converted into a disease diagnosis;
- emergency-oriented cases preserve urgent warning signs;
- medication/prescription requests are not returned as AI instructions;
- all active guidance carries a decision-support and human-review disclaimer.

Evidence includes `backend/tests/test_symptom_guidance.py`,
`test/disease_prediction_api_service_test.dart`, and the classifier safety
tests under `test/app/`.

## Small manually labeled local set — VAL-10

`backend/validation/ai_manual_validation.json` contains 12 cases covering
ordinary symptoms, emergency symptoms, prenatal danger signs, ambiguous input,
unknown input, and medication-related prompts. The labels describe expected
administrative routing/escalation behavior only; they do not assert a disease
diagnosis. Its integrity and coverage are checked by
`backend/tests/test_manual_validation_set.py`.

The set is explicitly marked `pending_qualified_health_professional_review`.
It must not be reported as clinical validation until a qualified reviewer
signs off on the cases and response behavior.

## Clinical limitations and human oversight — VAL-09, VAL-11, VAL-12

- No model or rule set in this repository is clinically validated.
- Dataset agreement is not evidence of safety for a real patient population.
- The AI cannot prescribe, recommend medication, or replace a licensed
  clinician.
- BHW/doctor/CHO staff must review the complete record and remain responsible
  for referral, treatment, and emergency decisions.
- Emergency warning signs are escalation prompts, not a substitute for local
  emergency protocols.
- Qualified health-professional review and real authenticated field testing
  remain open release gates.
