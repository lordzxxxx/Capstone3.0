# ISO-aligned AI quality and governance controls

This project uses the standards below as design and review references. This
is an implementation-alignment statement, not a conformity assessment and
not an ISO certification claim. Formal certification would require an
independent audit and an applicable certification process.

| Standard | Relevant control in this system | Evidence / limitation |
| --- | --- | --- |
| ISO/IEC 25010:2023 — product quality | Reproducible preprocessing, schema checks, exact feature ordering, model tests, held-out evaluation, persisted confusion/per-class metrics, and explicit uncertainty handling | `backend/scripts/merge_datasets.py`, `backend/app/train.py`, `backend/tests/`, and `backend/reports/ai_requirements_verification.json` |
| ISO/IEC 27001:2022 — information security management | Authenticated AI access, App Check configuration, rate limiting, server-side model loading, secret/config separation, Firestore security rules, and security tests | Security controls exist in the repository; deployment configuration, access reviews, retention, and incident exercises still require operational ownership |
| ISO/IEC 23894:2023 — AI risk management | Dataset provenance and quality gates, duplicate/leakage detection, group-safe evaluation, accuracy acceptance gate, low-confidence/clinical-review behavior, and no fabricated data | `docs/AI_REQUIREMENTS_STATUS.md`, `backend/scripts/verify_ai_requirements.py`, `backend/reports/leakage_report.json`; real clinical validation is not present |
| ISO/IEC 42001:2023 — AI management system | Documented model scope, human decision-maker responsibility, change-controlled training entry point, dataset manifest, evaluation artifacts, and explicit non-certification language | Governance documentation is present; a full organization-wide AI management system and independent audit are outside this repository |
| ISO/IEC TR 24027:2021 — bias in AI systems | Demographic features are not silently inferred, source populations are documented as unknown when unverified, and subgroup fairness is not claimed without subgroup labels | A fairness evaluation is blocked by the current dataset's lack of verified demographic variables; this is an open risk, not evidence of fairness |
| ISO/IEC 24028:2021 — trustworthiness overview | Model limitations, label ambiguity, confidence/uncertainty, traceability, and human oversight are documented | Trustworthiness is a design objective; it is not a clinical safety certification |

## Required operating controls before a production model release

- Attach a source/provider/reference/license or consent record to every
  training source and record the exact imported file hash.
- Pass the dataset quality gate: valid records, no exact duplicates, no
  missing labels, binary/typed features, normalized labels, and no
  train/test feature-vector overlap.
- Evaluate on a locked held-out set and report accuracy, balanced accuracy,
  macro/weighted precision, recall, F1, top-k accuracy, per-class results,
  confusion matrix, and subgroup results where data supports them.
- Require human review for low-confidence or out-of-distribution cases and
  keep the tool positioned as decision support, not diagnosis.
- Review changes to source data, labels, features, thresholds, and model
  artifacts before deployment; retain the prior artifact and evaluation.
- Never use synthetic padding, duplicated rows, label manipulation, or
  untraceable external data to satisfy a record-count or accuracy target.
