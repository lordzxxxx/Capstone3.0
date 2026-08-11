# AI accuracy-gap analysis

Generated from the current repository artifacts by
`backend/scripts/analyze_accuracy_gaps.py` on **2026-08-11**, re-run later
the same day after a verified preprocessing fix (see
`DATASET_QUALITY_REPORT.md` §1.1a). The machine-readable output is
`backend/reports/accuracy_gap_analysis.json`. This analysis does not
change records, labels, features, routes, or model behavior.

The current offline model is `disease_model_v4`: held-out top-1 accuracy is
89.3399%, five-fold training-only CV mean accuracy is 89.1082% (standard
deviation 0.2373 percentage points), and train/test exact-vector overlap is
0 groups. Held-out top-2 is 96.5424% and top-3 is 98.5052%. The prior v3
result, 89.3138% (229 features), and v2 result, 89.2713%, are retained in
the model registry.

## Current measured limit

| Measure | Actual result |
|---|---:|
| Raw source rows | 96,088 |
| Valid processed rows | 93,993 |
| Records removed by preprocessing | 2,095 exact duplicate rows, plus one duplicate raw column (`regurgitation.1`) collapsed into `regurgitation` |
| Classifier inputs | 228 binary symptom variables |
| Target | `diseases` |
| Classes | 100 |
| Unique exact symptom vectors | 88,878 |
| Conflicting exact-vector groups | 4,140 groups / 9,255 rows |
| Exact-vector majority-label upper bound | 94.5581% |

The upper bound is computed by assigning each identical input vector its
most frequent observed label. It is an empirical ceiling for this dataset and
feature representation, not a clinical performance claim. It is below the
95% target, so 95% cannot be reached honestly on this exact dataset using only
these 228 binary inputs. Additional paired clinical variables or a cleaner,
less ambiguous labeled dataset are required.

## Main causes of error

1. The same symptom vector is assigned to multiple medically distinct
   conditions. The most common conflicting pairs by exact-vector groups are:

   | Labels | Conflicting vector groups | Rows in those groups |
   |---|---:|---:|
| Infectious gastroenteritis / noninfectious gastroenteritis | 268 | 571 |
   | Acute bronchitis / COPD | 198 | 519 |
   | Skin pigmentation disorder / skin polyp | 167 | 400 |
   | Personality disorder / schizophrenia | 167 | 362 |
   | Acute bronchospasm / pneumonia | 148 | 449 |
   | Cystitis / temporary or benign blood in urine | 135 | 282 |
   | Asthma / COPD | 119 | 343 |
   | Degenerative disc disease / spinal stenosis | 113 | 294 |

2. The weakest held-out recalls are COPD (54.32%), skin pigmentation disorder
   (60.87%), personality disorder (64.42%), noninfectious gastroenteritis
   (67.22%), and skin polyp (68.32%). These are not removed or merged merely to
   improve the aggregate score.

3. The largest held-out prediction confusions are noninfectious → infectious
   gastroenteritis (59), cystitis → temporary/benign blood in urine (57),
   infectious → noninfectious gastroenteritis (47), cholecystitis → gallstone
   (34), and personality disorder → schizophrenia (34).

4. Hamming-distance-one analysis found 88,356 unique vectors with a one-bit
   neighbor, covering 93,454 rows. This is a diagnostic of very similar
   presentations, not a reason to delete records or alter medical meaning.

5. There are no constant or near-zero-variance features under the repository's
   configured checks. The limiting issue is therefore missing discriminating
   information and conflicting labels for identical presentations, rather
   than a removable dead feature.

## Label audit

The configured disease mapping is in
`backend/dataset/mappings/disease_mapping.json`. It records genuine
abbreviation/synonym forms such as `copd`, `htn`, `uti`, and `type ii
diabetes`. The current raw source contains 100 labels and already uses the
canonical forms: **0 records were changed by the mapping in this run**.

No medically different classes were merged because their symptoms overlap.
The complete reviewed mapping list and the zero-change result are preserved
in `backend/reports/accuracy_gap_analysis.json`.

## Candidate variables

The application collects more fields than the Random Forest source contains.
They are not added to the RF until real labeled training records include the
same field and the `diseases` target.

| Variable | Available in system | Available in training data | Source | Can be used for RF training now? |
|---|---|---|---|---|
| `symptoms` | Yes | Yes | Checkup/prenatal text plus 228 normalized source columns | **Yes** |
| `age` | Yes | No | Checkup/prenatal records and on-device classifier | No |
| Symptom duration | Form/reference concept, not a paired RF field | No | DOH/RITM case-form templates; no local RF column | No |
| Symptom severity | Workflow/details text | No | Application severity workflow; no labeled RF column | No |
| Temperature | Yes | No | Checkup details / on-device classifier | No |
| Blood pressure | Yes | No | Checkup and prenatal details | No |
| Heart rate | Yes | No | Checkup details / on-device classifier | No |
| Respiratory rate | Yes | No | Checkup details | No |
| Oxygen saturation | Yes | No | Checkup details | No |
| Medical history | Yes in prenatal fields | No | `preExistingConditions`, `previousComplications` | No |
| Pregnancy context | Yes in prenatal fields | No | `gestationalAge`, `gravida`, `para`, `riskLevel` | No |
| `diseases` | Diagnosis/category fields exist in workflows | Yes | RF source target column | Target `y`, not an input |

The detailed source paths, encoding status, and reasons are in the machine-
readable report. The current RF remains a 228-feature symptom-only model.
This inventory was re-checked on 2026-08-11 against the current FastAPI
schemas and Firestore checkup/prenatal fields; the conclusion is unchanged.

## Legitimate data-source investigation

No new training records were integrated. The following official Philippine
sources were investigated and retained as reference/acquisition evidence:

| Source | Finding | Training status |
|---|---|---|
| [DOH standardized clinical/exposure assessment form](https://doh.gov.ph/wp-content/uploads/2023/08/dm2020-0512.pdf) | Includes useful fields such as onset, comorbidities, age, and risk context, but is a form template rather than released patient-level records | Reference; 0 records added |
| [RITM COVID case investigation form](https://ritm.gov.ph/wp-content/uploads/2023/02/eCIF_version_8_Fillable_-_Molecular_Diagnostics_Laboratory_04192021.pdf) | Structured disease-specific case form with symptoms and clinical context, but not a public 100-class compatible training table | Reference; 0 records added |
| [RITM surveillance data](https://ritm.gov.ph/data/surveillance/) | Surveillance information and reports, not a downloadable symptom-to-disease patient table | Reference; 0 records added |
| [PSA Data Archive](https://psada.psa.gov.ph/home) and [access guidance](https://psada.psa.gov.ph/helpcenter) | Official microdata catalog; access can be public, licensed, or restricted, and no compatible release was obtained | Acquisition candidate; 0 records added |
| [DOH Telemedicine 2024 report](https://ro4a.doh.gov.ph/wp-content/uploads/2025/01/HAE-Website-Content_Telemedicine-2024-FINAL.pdf) | Aggregate consultation/chief-complaint statistics, not patient-level symptom vectors | Reference; 0 records added |
| [PhilHealth National Health Data Repository](https://www.philhealth.gov.ph/nhdr/) | Health reporting/repository reference; no compatible public symptom-level export was obtained | Reference; 0 records added |

Aggregate counts and form templates were not converted into patient records.
The 150,000–200,000 target remains unmet at 93,993 valid records; the
shortfall is 56,007 records to the minimum. This is an acquisition limitation,
not a justification for duplication or synthetic padding.

## Required path to improve beyond the current ceiling

Collect or obtain properly consented/de-identified records containing the
existing symptom vector plus at least some of: duration, severity, age,
vital signs, relevant history, examination findings, laboratory results, or
other disease-discriminating observations. Each source needs a verified
provider, version, license/access basis, schema, label definition, record
count, and row-level provenance before integration.

The current classifier remains offline/evaluation-only; `/predict` remains
disabled and low-confidence results must not be presented as medical
certainty.

## Further legitimate improvement attempts (2026-08-11, this session)

Per this task's requirement not to stop after one negative result, three
further avenues were tried on the Random Forest before accepting the 89%
plateau, plus one bug found and fixed in the separate active AI system:

1. **Preprocessing fix, adopted.** The raw source's own header contains a
   literal duplicate column (`regurgitation` and `regurgitation.1`).
   Mapping them together (228 features instead of 229) improved held-out
   Top-1 from 89.3138% to 89.3399% with identical hyperparameters and the
   same leakage-safe split. Small but real. See
   `DATASET_QUALITY_REPORT.md` §1.1a.
2. **Further RF hyperparameter search, not adopted.** A bounded
   `RandomizedSearchCV` re-run on the corrected dataset selected
   `min_samples_leaf=1` by training-only CV, but that candidate scored
   89.13% on the real held-out test — below the existing 89.34%
   production config. The existing hyperparameters remain best. See
   `MODEL_EVALUATION_REPORT.md` §2a.
3. **Hierarchical (category → disease) classification, tested and
   rejected.** Using the project's own 12-category disease taxonomy: a
   perfect-category-oracle ceiling is only 95.02% (+0.46 points over the
   flat model's 94.56%), and a real trained pipeline scored 88.96% —
   *below* the flat model, because stage-1 category errors compound into
   stage-2. See `DATASET_QUALITY_REPORT.md` §11.
4. **Active AI system bug found and fixed (separate from this Random
   Forest).** The system's actual user-facing classifier
   (`HealthAIClassifier` in `lib/app/core/services/health_ai_classifier.dart`
   — an on-device neural net with a rule-based fallback, distinct from
   this offline 100-disease RF) was tested with representative cases. Its
   ML path's fixed input vector has no feature slot for structured
   prenatal fields (`gravida`, `para`, `gestationalAge`, `riskLevel`,
   etc.), so a high-risk record with preeclampsia-pattern symptoms
   ("severe headache, vision changes" plus those fields) was classified
   as "Communicable Disease" at "Medium" severity — silently dropping the
   risk signal. Fixed by making `classify()` defer to the rule-based path
   (which reads those fields explicitly) whenever they are present;
   verified with new regression tests in
   `test/app/health_ai_classifier_test.dart`. Other lower-stakes
   miscalibrations observed in the same ML model (e.g., a plain adult
   fever/cough case classified as "Pediatric Care") were **not** fixed —
   they trace to that model being trained only on synthetic data
   (`train_model/train_health_classifier.py`), which the project's own
   `train_model/README.md` already states must not be treated as
   production evidence. Fixing that would require real Firebase-exported
   labeled records, which are not available in this environment.
