# Dataset and health-reference provenance

This inventory is generated from the files currently committed in this
repository (10 August 2026). Counts below are non-empty data rows, not line
counts. No record in this inventory is asserted to be Philippine-specific
unless the publisher and geographic coverage are independently identified.

## Current classifier training data

| File | Raw rows | Usable rows | Fields | Current use | Provenance and limitation |
| --- | ---: | ---: | --- | --- | --- |
| `backend/dataset/processed/merged_dataset.csv` | 93,993 | 93,993 | `diseases` plus 229 symptom indicators used by the model | **Model training**; stratified 80/20 split | Local processed artifact. The original publisher/source is not verified in this repository. It is not labelled as Philippine data. Duplicate full rows: 0; rows with missing fields: 0. |
| `backend/dataset/raw/Diseases_and_Symptoms_dataset.csv` | 96,088 | 96,088 | `diseases` plus 230 source columns (229 validated model features) | Training source/audit comparison; not loaded directly by the API | Source provenance not verified. The comparison report explicitly records that the standalone Kaggle CSV was unavailable and that the recovered segment must not be treated as an independently verified Kaggle download. Duplicate full rows: 0; rows with missing fields: 0. |

The persisted training metrics in `backend/models/training_metrics.json` are
the actual metrics for the processed file: 75,194 training rows and 18,799
test rows (80/20, stratified, random state 42), 229 features, and 100 disease
classes. The estimator is a 300-tree scikit-learn `RandomForestClassifier`
(`max_depth=24`, `max_leaf_nodes=4096`, `min_samples_leaf=2`). Recorded
weighted metrics are accuracy 0.8495664663, precision 0.8838544897, recall
0.8495664663, and F1 0.8559878323. A confusion matrix/per-class report was
printed during training but is not persisted as a machine-readable artifact;
therefore no matrix values are claimed here.

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
