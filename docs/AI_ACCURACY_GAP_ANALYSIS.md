# AI accuracy-gap analysis

Generated from the current repository artifacts by
`backend/scripts/analyze_accuracy_gaps.py` on **2026-08-11**. The machine-
readable output is `backend/reports/accuracy_gap_analysis.json`. This analysis
does not change records, labels, features, routes, or model behavior.

The current offline model is `disease_model_v3`: held-out top-1 accuracy is
89.3138%, five-fold training-only CV mean accuracy is 89.2025% (standard
deviation 0.1136 percentage points), and train/test exact-vector overlap is
0 groups. Held-out top-2 is 96.4043% and top-3 is 98.3936%. The prior v2
result, 89.2713%, is retained in the model registry.

## Current measured limit

| Measure | Actual result |
|---|---:|
| Raw source rows | 96,088 |
| Valid processed rows | 93,993 |
| Records removed by preprocessing | 2,095 exact duplicate rows |
| Classifier inputs | 229 binary symptom variables |
| Target | `diseases` |
| Classes | 100 |
| Unique exact symptom vectors | 88,894 |
| Conflicting exact-vector groups | 4,127 groups / 9,226 rows |
| Exact-vector majority-label upper bound | 94.5751% |

The upper bound is computed by assigning each identical input vector its
most frequent observed label. It is an empirical ceiling for this dataset and
feature representation, not a clinical performance claim. It is below the
95% target, so 95% cannot be reached honestly on this exact dataset using only
these 229 binary inputs. Additional paired clinical variables or a cleaner,
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

2. The weakest held-out recalls are COPD (61.96%), skin polyp (63.98%), acute
   bronchospasm (64.41%), skin pigmentation disorder (64.60%), and
   noninfectious gastroenteritis (66.80%). These are not removed or merged merely to
   improve the aggregate score.

3. The largest held-out prediction confusions are noninfectious → infectious
   gastroenteritis (61), cystitis → temporary/benign blood in urine (49),
   infectious → noninfectious gastroenteritis (47), cholecystitis → gallstone
   (41), and personality disorder → schizophrenia (38).

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
| `symptoms` | Yes | Yes | Checkup/prenatal text plus 229 normalized source columns | **Yes** |
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
readable report. The current RF remains a 229-feature symptom-only model.

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
