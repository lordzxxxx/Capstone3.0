# Dataset and health-reference provenance

This inventory is generated from the files currently committed in this
repository (11 August 2026). Counts below are non-empty data rows, not line
counts. No record in this inventory is asserted to be Philippine-specific
unless the publisher and geographic coverage are independently identified.
The latest error-gap, label-normalization, and application-variable inventory
is in [`docs/AI_ACCURACY_GAP_ANALYSIS.md`](AI_ACCURACY_GAP_ANALYSIS.md), with
machine-readable evidence at `backend/reports/accuracy_gap_analysis.json`.

## Current classifier training data

| File | Raw rows | Usable rows | Fields | Current use | Provenance and limitation |
| --- | ---: | ---: | --- | --- | --- |
| `backend/dataset/processed/merged_dataset.csv` | 93,993 | 93,993 | `diseases` plus 229 symptom indicators used by the model | **Model training**; stratified 80/20 split | Local processed artifact. The original publisher/source is not verified in this repository. It is not labelled as Philippine data. Duplicate full rows: 0; rows with missing fields: 0. |
| `backend/dataset/raw/Diseases_and_Symptoms_dataset.csv` | 96,088 | 96,088 | `diseases` plus 230 source columns (229 validated model features) | Training source/audit comparison; not loaded directly by the API | Source provenance not verified. The comparison report explicitly records that the standalone Kaggle CSV was unavailable and that the recovered segment must not be treated as an independently verified Kaggle download. Duplicate full rows: 0; rows with missing fields: 0. |

The persisted training metrics in `backend/models/training_metrics.json` are
the actual metrics for the processed file: 75,193 training rows and 18,800
test rows, 229 features, and 100 disease classes. The split is
`StratifiedGroupKFold(n_splits=5)` with groups formed from identical symptom
vectors, so the held-out test set has zero exact feature-vector overlap with
training. The estimator is the tuned 200-tree scikit-learn
`RandomForestClassifier` (`criterion=entropy`, `max_depth=28`,
`max_features=log2`, `class_weight=balanced_subsample`). Held-out accuracy is
89.3138%, weighted precision 89.9042%, weighted recall 89.3138%, and weighted
F1 89.3197%. Top-2 accuracy is 96.4043% and Top-3 accuracy is 98.3936%.
Confusion and per-class reports are persisted under
`backend/reports/`; the complete source counts and acceptance status are in
`backend/reports/ai_requirements_verification.json`.

## Text and reference files

| File | Rows | Fields | Classification | Current use and limitations |
| --- | ---: | --- | --- | --- |
| `backend/dataset/text_datasets/Symptom2Disease.csv` | 1,200 | `label`, `text` (plus an empty index column) | Text symptom/disease reference; **not model training in the active trainer** | Original publisher and URL are not recorded; source provenance not verified. Not Philippine-specific. |
| `backend/dataset/knowledge_base/AI_DSUHIS_Disease_Self_Care_Knowledge_Base.csv` | 100 | Disease key/name, category, training-record reference, symptoms, self-care, cautions, warning signs, review metadata and lookup URLs | AI knowledge/reference, home-care and safety guidance | Used by the Firestore seed tooling and guidance service. It is not individual patient data and is not a training set. Publisher and original publication provenance are not independently verified in this repository. Medication wording is filtered from active guidance. |
| `backend/dataset/knowledge_base/Diseases_Symptoms.csv` | 400 | `Code`, `Name`, `Symptoms`, `Treatments` | Repository reference only | Contains treatment text and is not used by the active medication-safe guidance path. Source provenance not verified; one non-empty row has a missing field. |
| `backend/dataset/knowledge_base/Home Remedies.csv` | 115 | `Name of Item`, `Health Issue`, `Home Remedy`, `Yogasan` | Repository reference only | Contains 89 rows with at least one empty field and is not used as an active model-training set. Source provenance not verified. Do not treat its content as a clinical recommendation without professional review. |

Full-row duplicate counts for all six files are zero after ignoring blank
lines. The two knowledge-base files containing treatment/home-remedy text are
kept separate from the model-training data and are not evidence that the model
was trained on Philippine clinical records.

## Active AI relationship

The deployed `/predict` route is intentionally disabled. The web/mobile
guidance path performs symptom normalization/keyword recognition, optional
Firestore disease-reference lookup, rule-based health-category and
severity/risk guidance, then returns home-care, precautions, warning signs,
monitoring and referral-support text. Medication, dosage and prescription
language is filtered before responses are returned. The persisted RandomForest
artifact is available for offline training/evaluation and existing prediction
unit tests, but it is not an active public prediction endpoint.

## Philippine sources reviewed (reference-only; no rows imported)

The following official sources are suitable for epidemiological or validation
context, but their public material is aggregated/statistical or document-based
and does not match the current symptom-indicator training schema. No rows were
copied into the classifier and none are represented as patient-level training
records:

| Official source | Publisher / country | Data type and coverage | URL | Status |
| --- | --- | --- | --- | --- |
| National Health Data Repository | Philippine Health Insurance Corporation (PhilHealth), Philippines | Health-sector submissions and repository metadata; aggregate/reference context | <https://www.philhealth.gov.ph/nhdr/> | Reference-only; release/version and row count must be obtained from the selected release before integration |
| Health Statistics | Department of Health NCR, Philippines | Public-health statistics and reports for the Philippines/NCR | <https://ncroffice.doh.gov.ph/HealthStatistics> | Reference-only; no compatible symptom-level labelled export selected |
| Health database | Philippine Statistics Authority, Philippines | Official demographic, morbidity, mortality, utilization and health-service statistics | <https://openstat.psa.gov.ph/Database/Demographic-and-Social-Statistics/Health> | Reference-only; aggregate/statistical rather than patient-level symptom samples |
| National Objectives for Health 2023–2028 | Department of Health, Philippines | Policy and indicator reference document | <https://doh.gov.ph/wp-content/uploads/2024/01/National-Objectives-for-Health-2023-2028.pdf> | Reference/rule-support only; document, not training rows |
| 2022 National Demographic and Health Survey: Key Indicators | Philippine Statistics Authority, Philippines | Survey indicators for Philippine households/population | <https://www.psa.gov.ph/system/files/main-publication/2022%2520NDHS%2520Key%2520Indicators%2520Report.pdf> | Reference/validation-support only; survey aggregates, not symptom-level training rows |

The following additional Philippine sources were checked during the current
expansion review. They remain reference-only because no downloadable,
patient-level, symptom-to-disease table with a verified release and license
was identified for this repository:

| Official source | Publisher / country | Data type and coverage | URL | Status |
| --- | --- | --- | --- | --- |
| National Health Data Repository framework | PhilHealth / Philippine Department of Health, Philippines | Health-sector repository framework covering administrative, public-health, clinical and financing data | <https://www.philhealth.gov.ph/about_us/NationalHealthDataRepositoryFramework03282022.pdf> | Reference-only; framework and submission standard, not a released compatible row dataset |
| PSA Data Archive (PSADA) | Philippine Statistics Authority, Philippines | Catalog of Philippine microdata; access varies by public-use file, licensed file and data enclave | <https://psada.psa.gov.ph/helpcenter> | Candidate discovery source; no compatible release was downloaded or represented as training data; future access may require agreement/application |
| WHO Philippines NCD surveillance | World Health Organization, Philippines coverage | Surveillance summaries and links to NCD survey/microdata resources | <https://www.who.int/teams/noncommunicable-diseases/surveillance/data/philippines> | Reference-only; no compatible symptom/disease matrix was imported |
| Clinical and exposure assessment form | Philippine Department of Health, Philippines | Standardized form/template containing symptoms, age and clinical fields | <https://doh.gov.ph/wp-content/uploads/2023/08/dm2020-0512.pdf> | Reference/schema context only; a form is not patient-level records and was not converted into samples |

## External dataset compatibility review

The following public machine-readable candidates were reviewed but not merged.
The decision preserves the current 229-feature binary schema and prevents
synthetic, mixed-provenance or text-only records from being presented as
equivalent clinical observations:

| Dataset / provider | Official reference | Observed records / type | License or provenance | Decision |
| --- | --- | --- | --- | --- |
| `eng_dataset` / Technological Institute of the Philippines thesis authors | <https://huggingface.co/datasets/notlath/eng_dataset/blob/main/README.md> | 3,000 English symptom narratives across 6 infectious-disease classes; the dataset card describes the descriptions as synthetic | CC BY 4.0, but synthetic text and text-only labels are not compatible with the current wide binary feature matrix | Not integrated; reference only |
| `symptom-based-disease-prediction-v2` / Jainam-11 | <https://huggingface.co/datasets/Jainam-11/symptom-based-disease-prediction-v2> | 157,036 JSONL text/instruction records with multi-label/confidence-oriented fields | Apache-2.0 is stated on the dataset page, but the schema is an LLM-oriented text task rather than the current single-label 229-feature task | Not integrated; requires an independent schema/provenance/label study |
| `Diseases_Dataset` / kamruzzaman-asif | <https://huggingface.co/datasets/kamruzzaman-asif/Diseases_Dataset> | 267,614 records across multiple splits, mixed text `Disease`/`Symptoms`/optional treatment fields | Aggregated from other Hugging Face/Kaggle sources; upstream publisher, release and rights are not established by the aggregator page | **SOURCE REQUIRES VERIFICATION**; not integrated |
| `Disease-Symptom-Extensive-Clean` referenced by the mixed collection | <https://huggingface.co/datasets/kamruzzaman-asif/Diseases_Dataset> | Referenced as a 246,945-row source inside the mixed collection | Direct dataset-card provenance/license was not verified during this run | **SOURCE REQUIRES VERIFICATION**; not integrated |

A further check (2026-08-11) used Kaggle's unauthenticated public metadata
endpoint (`https://www.kaggle.com/api/v1/datasets/view/<owner>/<slug>`),
which returns dataset license, size, and description JSON even when the
dataset's own HTML page is JavaScript-rendered and unreadable to a plain
page fetch. This resolved the open license question for this repository's
actual training source (`behzadhassan/sympscan-symptomps-to-disease` is
`CC0: Public Domain` — see `DATASET_QUALITY_REPORT.md` §1.1) and was used
to screen five further candidate datasets surfaced by search:

| Dataset / provider | Reported size | License (Kaggle-tagged) | Decision |
| --- | --- | --- | --- |
| `diseases-and-symptoms-dataset` / `dhivyeshrk` | 773 diseases, 377 symptoms, ~246,000 rows | "World Bank Dataset Terms of Use" | **Rejected — self-disclosed synthetic data.** The publisher's own description states the rows "were artificially generated, preserving Symptom Severity and Disease Occurrence Possibility." Not real patient records regardless of size; likely the same lineage as the `kamruzzaman-asif` mixed collection already rejected above (near-identical ~246k row count). |
| `disease-and-symptoms-dataset` / `choongqianzheng` | 800+ diseases, 600 symptoms, ~5,000 rows | "Other (specified in description)" | Rejected — sparse `Symptom_1..Symptom_17` text-list schema, not a binary matrix; no stated collection methodology. |
| `disease-prediction-based-on-symptoms` / `noeyislearning` | 132 binary symptoms, 1 target | CC0: Public Domain | Rejected — small incompatible taxonomy (not this repo's 229-symptom/100-class schema); same lineage as the next row. |
| `disease-symptom-description-dataset` / `itachi9604` | 132 symptoms, 41 diseases, ~4,920 rows | CC BY-SA 4.0 | Rejected — publisher states "data...is for reference and training purposes only, and actual data may vary"; a student chatbot-course project, not real patient encounters; 41-class taxonomy incompatible with this repo's 100 classes. |
| `symptom2disease` / `niyarrbarman` | 24 diseases, 1,200 rows, free text | CC0: Public Domain | Already investigated as `text_datasets/Symptom2Disease.csv` above (43.5% of rows matched zero known symptom phrases when conversion was tested); license confirmed CC0 for completeness, decision unchanged. |

`data.gov.ph` (Philippine national open-data portal) was also checked
directly: it serves a JavaScript single-page application with no reachable
CKAN/REST API at the standard path, so it could not be queried
programmatically in this environment. PhysioNet's non-credentialed
disease/symptom resources found (e.g., a 34-patient endometriosis symptom
diary) are single-condition datasets, incompatible with this repository's
multi-disease 100-class task. Net result: 0 new training records from this
follow-up search.

The absence of a compatible imported source is an acquisition limitation, not
an assertion that no Philippine health data exists. Aggregate statistics,
surveys, forms and restricted microdata cannot be converted into fabricated
patient-level symptom vectors. The current training source therefore remains
the local file whose external publisher, country coverage, release and license
are still marked unverified.

For each source above, publication/update/version/license details must be
recorded from the exact release chosen for a future import. Because no release
was imported in this change, raw/usable record counts, feature counts,
cleaning, and mappings are **not applicable**, rather than guessed.

## Reliability boundary

The RandomForest metrics describe internal hold-out performance, not clinical
validity or Philippine population validity. The local training files have no
verified publisher, collection methodology, geographic coverage, license, or
independent clinical review in this repository. Class imbalance and label
quality therefore remain limitations. Official Philippine sources above have
strong publisher authority, but their aggregate/statistical nature prevents
direct use as patient-level classifier training data without an approved,
documented mapping and evaluation protocol.
