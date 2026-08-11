# AI-DSUHIS — Dataset Quality Report

Dataset version documented here: **`merged_dataset_v2`**. The row values and
229-feature schema are unchanged after the reproducibility rerun, but the
pipeline now emits a source-row provenance sidecar and the verifier records
near-duplicate diagnostics. Generated
`2026-08-11`. All figures were computed directly against the files in
this repository, not estimated.

---

## 1. Authoritative dataset inventory

Every dataset file present in `backend/dataset/` is listed below, with
its **actual** role verified by tracing the pipeline code
(`backend/scripts/merge_datasets.py`, `pipeline_utils.py`), not assumed
from its filename or folder.

### 1.1 `Diseases_and_Symptoms_dataset.csv` — TRAINING (the only training source)

| Field | Value |
|---|---|
| Local path | `backend/dataset/raw/Diseases_and_Symptoms_dataset.csv` |
| Source/provider | **Strongly corroborated candidate identified (update, follow-up review):** [Kaggle — "SympScan - Symptomps to Disease"](https://www.kaggle.com/datasets/behzadhassan/sympscan-symptomps-to-disease), uploaded by Kaggle user `behzadhassan`. Evidence: (1) the exact filename `Diseases_and_Symptoms_dataset.csv` is present in that dataset's file list; (2) the same GitHub user (`BehzadHassan/SympScan`, matching Kaggle username — first-party project showcase, not a third party) documents this dataset as "~96,000 patient records," "200+ binary-encoded symptoms," and "~100 disease classes" — all three figures match this repository's file exactly (96,088 rows, 230 raw symptom columns, 100 disease classes); (3) two independent public GitHub repos (`sandeep-panchal-fl/AI-Medical-Assistant-Hackathon`, `BehzadHassan/SympScan`) cite this same Kaggle URL as the source of a file with this exact name. **License terms could not be retrieved** — Kaggle's dataset page is JavaScript-rendered and returned no license metadata to either `WebFetch` or a direct `curl` request during this review. **Before formal citation (thesis, publication, external audit), the project team should open the Kaggle URL directly in a browser and record the stated license.** No checksum match was possible (Kaggle does not expose one without downloading via authenticated API, which this review does not have credentials for), so this remains corroborated-but-not-cryptographically-verified. |
| Country/geographic coverage | Unknown / unverifiable from the file itself. No demographic or geographic column exists. Should **not** be described as Philippine-sourced. |
| Original record count | **96,088 data rows** (96,089 lines including header), 231 columns (`diseases` + 230 raw symptom columns) |
| Usable record count after pipeline | **93,993 rows**, 229 features, 100 disease classes (2,095 exact-duplicate rows removed; 2 raw columns dropped as non-numeric or reduced during normalization/collapsing — see §5) |
| Column count | 231 raw → 230 after preprocessing (229 features + `diseases`) |
| Target column | `diseases` |
| Target classes | 100 (after dropping any disease with fewer than 20 rows — none were dropped at this threshold; see `merge_datasets.py` output) |
| Provenance sidecar | `backend/dataset/processed/row_provenance.csv`, 93,993 rows, source file and original source CSV row number for every retained row |
| Data type | All feature values numeric, coerced to binary `uint8` |
| Data format | CSV, wide binary-matrix format (one column per symptom) |
| Purpose | **Sole source of the Random Forest's training data** |
| Preprocessing applied | Full pipeline — see §5 |
| How the system uses it | Input to `backend/scripts/merge_datasets.py` → `dataset/processed/merged_dataset.csv` → `backend/app/train.py` → `disease_model.pkl` |
| Philippine-specific | **NO** |
| Status | **Training** |
| Known limitations | Unverified provenance/license; 9,226 rows (9.8%) share an identical 229-symptom vector with a different disease label elsewhere in the dataset (§4); no patient demographics, vitals, or lab data |

### 1.2 `main.csv` — CORRECTLY EXCLUDED (not usable)

| Field | Value |
|---|---|
| Local path | `backend/dataset/excluded/main.csv` |
| Source/provider | **Verified academic source (update, follow-up review):** the `UMLS:Cxxxxxxx_<name>` column pattern (e.g. `UMLS:C0457096_yellow sputum`) was traced via GitHub code search to the **Columbia University Disease-Symptom Knowledge Database** — Wang X, Chused A, Elhadad N, Friedman C, Markatou M, *"Automated knowledge acquisition from clinical reports,"* AMIA Annu Symp Proc. 2008:783-7, PMCID: [PMC2656103](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2656103/). Source page: `people.dbmi.columbia.edu/~friedma/Projects/DiseaseSymptomKB/` (confirmed reachable and matching during this review). Built via MedLEE NLP extraction of UMLS-coded disease/symptom mentions from New York-Presbyterian Hospital discharge summaries, covering the 150 most frequent diseases from 2004 admissions. **No explicit license is stated on the source page** — usage requires contacting the corresponding author (`friedman@dbmi.columbia.edu`) per the page itself. This does not change the file's exclusion status (still correctly excluded, see below) but resolves what was previously an open provenance question. |
| Original record count | 134 rows, 409 columns (`label` target + `frequency` + 407 UMLS-coded binary symptom columns) |
| Usable record count | **0** |
| Reason excluded | Every one of the 134 disease labels has **exactly 1 row** (`value_counts()` confirms `min == max == 1.0`). The pipeline's own quality gate, `merge_datasets.has_enough_class_samples()`, requires a **median of ≥20 rows per class** before a source file is accepted — this file's median is 1, so it fails outright and cannot be used for supervised training (a class with one example cannot be split into train/test, let alone learned robustly). |
| Status | **Legacy / Excluded** — correctly kept out of `dataset/raw/` (outside the pipeline's scan path) by a previous contributor. This review confirms the exclusion was justified, not an oversight. |

### 1.3 `Symptom2Disease.csv` — REFERENCE / LEGACY (investigated for expansion, rejected)

| Field | Value |
|---|---|
| Local path | `backend/dataset/text_datasets/Symptom2Disease.csv` |
| Source/provider | Structurally consistent with the public Kaggle dataset `niyarrbarman/symptom2disease` (candidate match found via web search; **not cryptographically verified** — SOURCE REQUIRES VERIFICATION for a definitive citation) |
| Original record count | 1,200 rows, 3 columns (`Unnamed: 0`, `label`, `text`) |
| Format | **Free-text narrative** ("I have been experiencing a skin rash on my arms...") with a disease label — not a binary symptom matrix |
| Target classes | 24 unique disease labels; only 6 (`allergy`, `common cold`, `drug reaction`, `pneumonia`, `psoriasis`, `urinary tract infection`) match an existing RF class after normalization — the other 18 (`diabetes`, `hypertension`, `dengue`, `malaria`, `typhoid`, etc.) are not present in the RF's current 100-class vocabulary at all |
| How the system uses it today | **Not used for RF training.** `merge_datasets.py` explicitly skips it (`detect_text_symptom_column()` flags it as text-based and logs: *"text-based symptoms are not compatible with the production binary Random Forest model"*) |
| Expansion investigated | Yes — `pipeline_utils.py` already contains an unused `prepare_text_dataset()` function built exactly to convert narrative text into binary features by matching known symptom phrases. It was run experimentally against this file during this review. Result: **522 of 1,200 rows (43.5%) matched zero known symptom phrases**, and another 281 (23.4%) matched only one. Integrating it would inject ~67% near-empty/single-feature rows into an otherwise well-populated dataset — a quality regression, not an improvement. **Rejected — not integrated.** |
| Philippine-specific | NO |
| Status | **Reference / Legacy** (kept in the repo, not deleted, but confirmed not training-eligible) |

### 1.4 `AI_DSUHIS_Disease_Self_Care_Knowledge_Base.csv` — REFERENCE (Firestore content source)

| Field | Value |
|---|---|
| Local path | `backend/dataset/knowledge_base/AI_DSUHIS_Disease_Self_Care_Knowledge_Base.csv` |
| Source/provider | **Project-authored.** This is not an external dataset — it is the reviewed content draft the project team wrote, one row per RF disease class (100 rows), consumed by `backend/firebase/generate_disease_seed.py` ("Transform the reviewed source draft into one seed per production model class") to produce `disease_seed.json` for Firestore. Columns include `disease_id`, `disease_key`, `disease_name`, `category`, `training_records`, `dataset_top_symptoms`, `self_care_level`, `safe_self_care_draft` — the presence of `training_records`/`dataset_top_symptoms` columns indicates this file was authored *with reference to* the RF's training data, not as an independent dataset. |
| Record count | 100 rows (one per RF disease class) |
| How the system uses it | Source for Firestore `diseases` collection content — self-care guidance shown by `/guidance` (§ `AI_ALGORITHM_QA.md`) |
| Philippine-specific | Not applicable (authored content, not epidemiological data) |
| Status | **Reference** — feeds the knowledge base, never used to train or evaluate the RF |

### 1.5 `Diseases_Symptoms.csv` — REFERENCE (unused catalog)

| Field | Value |
|---|---|
| Local path | `backend/dataset/knowledge_base/Diseases_Symptoms.csv` |
| Record count | 400 rows, 4 columns (`Code`, `Name`, `Symptoms`, `Treatments`) |
| Format | Free-text `Symptoms`/`Treatments` columns, not binary |
| How the system uses it | Not referenced by any Python file in `backend/app` or `backend/scripts` (confirmed by repo-wide search) — present in the repo but not wired into any pipeline |
| Philippine-specific | NO |
| Status | **Legacy / unused catalog.** Not training-eligible in its current text format. |

### 1.6 `Home Remedies.csv` — REFERENCE (unused catalog)

| Field | Value |
|---|---|
| Local path | `backend/dataset/knowledge_base/Home Remedies.csv` |
| Record count | 115 rows, 4 columns (`Name of Item`, `Health Issue`, `Home Remedy`, `Yogasan`) |
| How the system uses it | Not referenced by any Python file in the backend (confirmed by repo-wide search) |
| Philippine-specific | NO |
| Status | **Legacy / unused catalog** |

### 1.7 `merged_dataset.csv` — GENERATED ARTIFACT (not a source; the actual training file)

| Field | Value |
|---|---|
| Local path | `backend/dataset/processed/merged_dataset.csv` |
| Generated by | `backend/scripts/merge_datasets.py`, from §1.1 only |
| Reproducibility | **Verified during this review**: regenerating this file from `Diseases_and_Symptoms_dataset.csv` via `merge_datasets.py` produces the same 93,993-row result. The current SHA-256 is persisted in `backend/models/training_metrics.json`; the pipeline is deterministic and reproducible. |
| Record count | 93,993 |
| Feature count | 229 |
| Target classes | 100 |

---

## 2. Philippine data source investigation

Investigated (network access confirmed working during this review):
DOH Epidemiology Bureau / PIDSR, EDCS weekly surveillance data, and
related open datasets.

**Finding:** the DOH's actual published symptom/disease-relevant data —
PIDSR (Philippine Integrated Disease Surveillance and Response) and EDCS
(Epidemiology and Disease Control Surveillance) — is **aggregate weekly
case-count surveillance data** (confirmed directly: a representative
public republication, "Philippine Disease Cases Data (2017–2021)" on
Mendeley Data, CC BY 4.0, contains "260 weekly case observations" across
17 diseases nationwide — i.e., *how many confirmed cases of dengue
occurred that week*, not *what symptoms an individual patient had*).

This is a **structurally different schema** from what the Random Forest
needs (one row per patient/case, 229 binary symptom-presence columns,
one disease label). Converting aggregate weekly counts into per-patient
symptom vectors is not mechanically possible without inventing
per-patient symptom data — which the integrity constraints of this task
explicitly prohibit ("never fabricate... never through unrelated
datasets, label manipulation").

**Conclusion:** legitimate Philippine government sources found during
this review are valuable as **epidemiological/surveillance reference
data** (e.g., for a future outbreak-trend or reporting feature) but are
**not usable to expand this Random Forest's training set** without
fabrication. No Philippine-sourced, patient-level, symptom-to-diagnosis
training-ready dataset was found within this review's search budget.
None is currently integrated, and none is claimed to be.

---

## 3. Dataset expansion — result

| | |
|---|---|
| Target | 150,000–200,000 valid usable records |
| Current legitimate usable record count | **93,993** |
| Local unused files investigated | `Symptom2Disease.csv` (rejected — see §1.3, would degrade quality), `main.csv` (correctly excluded — see §1.2), `Diseases_Symptoms.csv` / `Home Remedies.csv` (not compatible binary-symptom format) |
| External sources investigated | Philippine PhilHealth NHDR, PSA OpenSTAT/PSADA, DOH/WHO reference sources, and public text/mixed Hugging Face candidates; all were rejected as aggregate, restricted, text-only, synthetic, mixed-provenance, or otherwise incompatible — details in `docs/DATASET_PROVENANCE.md` |
| New records added | **0**; no reviewed source met the compatible, traceable, license/provenance and patient-level quality gates |
| **STATUS** | **TARGET NOT ACHIEVED.** The dataset remains at 93,993 legitimate records. |

**Technical reason:** every additional dataset available inside this
repository is either (a) already proven incompatible/insufficient by the
pipeline's own quality gates (`main.csv`), (b) structurally incompatible
without a quality-destroying conversion (`Symptom2Disease.csv` — verified
by actually running the conversion, not assumed), or (c) not a
symptom-training dataset at all (the three knowledge-base CSVs). No
externally reachable, schema-compatible, license-clear, downloadable
dataset was identified within this review's scope. Reaching 150k–200k
would currently require either (a) locating and legitimately licensing a
new large symptom-checker dataset with a compatible schema, or (b)
collecting new real (properly consented, de-identified) BHW/CHO
encounter data over time — both are legitimate paths but outside what
this review could complete now. **No duplication, synthetic padding, or
relabeling was used to approach the target**, per the integrity
constraints of this task.

---

## 4. Duplicate and leakage statistics

Full detail and raw counts: `backend/reports/leakage_report.json`
(generated by `backend/scripts/optimize_random_forest.py` during this
review).

| Check | Result |
|---|---|
| Exact full-row duplicates remaining in `merged_dataset.csv` | **0** (2,095 were already removed by `merge_datasets.py`'s `remove_duplicates()` step) |
| Unique 229-feature symptom-vector groups | 88,894 (out of 93,993 rows) |
| Rows sharing an identical feature vector with ≥1 other row | 9,226 (9.8%) |
| Feature-vector groups where the *same* vector maps to *different* disease labels | **4,127 groups, 9,226 rows** |
| Train/test feature-vector overlap under the current **group-safe** split (`StratifiedGroupKFold` keyed on feature-vector identity) | **0 groups** (verified; this is the only current model evaluation split) |
| Missing values across all cells | 0 |
| Constant (zero-variance) features | 0 |
| Extremely rare features (<0.05% prevalence) | 0 |
| Extremely common features (>99.95% prevalence) | 0 |
| Unique vectors with an exact Hamming-distance-one neighbor | **88,356** |
| Rows in Hamming-distance-one neighborhoods | **93,454** |

**Interpretation.** The label-conflict groups are not a data-entry bug —
spot-checking the pairs (`backend/reports/leakage_report.json` →
`labelConflictExamples`) shows clinically plausible overlaps: *acute
bronchitis* vs. *asthma*, *cholecystitis* vs. *esophagitis*,
*diverticulitis* vs. *rectal disorder*, *appendicitis* vs.
*diverticulitis*. These are diseases that genuinely can present with
identical symptom checklists when no vitals, labs, or exam findings are
available — a real, inherent ceiling on any classifier using only this
229-symptom feature set, independent of algorithm choice or tuning (see
`MODEL_EVALUATION_REPORT.md` for how this bounds achievable accuracy).

The production train/test leakage (1,485 rows) does not mean the
checked-in `training_metrics.json` numbers were fabricated — they are
real numbers from a real `train_test_split` — but it does mean part of
that evaluation's apparent performance reflects the model having seen an
identical symptom pattern during training that then reappeared in its
test set. The group-safe re-evaluation in `MODEL_EVALUATION_REPORT.md`
gives a cleaner, leakage-free comparison point.

---

## 5. Preprocessing applied (verified against `pipeline_utils.py` / `merge_datasets.py`)

| Step | Applied | Detail |
|---|---|---|
| Schema validation | Yes | `detect_disease_column()`, `is_binary_feature_dataset()` reject files without a valid target or non-binary features |
| Column-name normalization | Yes | `basic_normalize()` — lowercase, underscore→space, strip `"symptom "` prefix, collapse whitespace |
| Symptom alias resolution | Yes | `dataset/mappings/symptom_mapping.json` (11 entries) |
| Disease label normalization/aliasing | Yes | `dataset/mappings/disease_mapping.json` (15 entries) |
| Missing-value handling | Yes | `pd.to_numeric(...).fillna(0)` — missing = absent |
| Invalid-record removal | Yes | `remove_empty_labels()` drops `""`/`"nan"`/`"none"`/`"null"` labels |
| Exact-duplicate removal | Yes | `remove_duplicates()` — 2,095 rows removed |
| Near-duplicate/label-conflict detection | Yes | `verify_ai_requirements.py` reports exact vector groups, label conflicts, and Hamming-distance-one neighborhoods; near duplicates are analyzed, not silently removed |
| Column merging (aliased duplicates) | Yes | `collapse_duplicate_columns()` — logical OR via `.max()` |
| Unusable-column removal | Yes | `NON_FEATURE_COLUMNS` set drops `code`, `frequency`, `index`, `treatment(s)`, `remedy` |
| Provenance preservation | Yes | `merge_datasets.py` writes `processed/row_provenance.csv` with processed index, normalized target, source filename and original source CSV row number |
| Class-count filtering | Yes | Any disease with fewer than 20 rows is dropped (`MIN_DISEASE_SAMPLES = 20`); none were dropped at this threshold in the current data |
| Encoding | Yes | `pd.to_numeric(...).ne(0).astype("uint8")` |
| Scaling/normalization of feature values | Not applicable | Features are already binary; Random Forest does not require scaling |
| Data balancing (SMOTE/undersampling) | **No** | Not implemented; class counts left at natural distribution (see §6) |
| Train/test split | Yes | `StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)` first fold; exact feature-vector groups cannot cross the boundary |

---

## 6. Class distribution

100 classes total. Full per-class counts are derivable from
`merged_dataset.csv`'s `diseases` column; the extremes:

**Largest classes:**

| Class | Record Count | Percentage |
|---|---:|---:|
| cystitis | 1,219 | 1.30% |
| vulvodynia | 1,218 | 1.30% |
| nose disorder | 1,218 | 1.30% |
| complex regional pain syndrome | 1,217 | 1.29% |
| spondylosis | 1,216 | 1.29% |

**Smallest classes:**

| Class | Record Count | Percentage |
|---|---:|---:|
| sepsis | 567 | 0.60% |
| heart failure | 590 | 0.63% |
| acute bronchospasm | 591 | 0.63% |
| hypertensive heart disease | 592 | 0.63% |
| asthma | 604 | 0.64% |

**Imbalance assessment:** the ratio between the largest and smallest
class is **≈2.15×** (1,219 vs. 567). This is a **mild-to-moderate**
imbalance — not severe (no class is a rare edge case with a handful of
rows; every class has hundreds). `class_weight=None` in the production
model, meaning this mild imbalance is currently uncorrected. No class was
removed to inflate accuracy; all 100 classes present in the source file
after the ≥20-row filter remain in the dataset.

---

## 7. Variable definitions and encoding

See `AI_VARIABLE_DICTIONARY.md` for the complete `X`/`y` definitions
across all four classification components in this system. Summary for
the Random Forest specifically: 229 independent binary symptom-presence
features (`X`), one categorical target column `diseases` with 100 classes
(`y`).

---

## 8. Provenance status summary

| Dataset | Provenance status |
|---|---|
| `Diseases_and_Symptoms_dataset.csv` | **Strongly corroborated** — Kaggle `behzadhassan/sympscan-symptomps-to-disease` (exact filename, exact 100-class count, exact ~96k row count, corroborated by the dataset author's own GitHub repo and one independent third-party repo). **License terms not yet retrieved** — Kaggle's page would not render its metadata to this review's tools. |
| `main.csv` | **Verified** — Columbia University Disease-Symptom Knowledge Database (Wang, Chused, Elhadad, Friedman, Markatou; AMIA 2008; PMCID PMC2656103). Correctly unused regardless (1 record/class). |
| `Symptom2Disease.csv` | Structurally consistent with a named public Kaggle dataset (`niyarrbarman/symptom2disease`, candidate identified), not cryptographically confirmed |
| `AI_DSUHIS_Disease_Self_Care_Knowledge_Base.csv` | **Verified** — project-authored, traced to `generate_disease_seed.py` |
| `Diseases_Symptoms.csv`, `Home Remedies.csv` | Unused; provenance not investigated further as they do not affect training |

**Recommendation for the project team:** open
`kaggle.com/datasets/behzadhassan/sympscan-symptomps-to-disease`
directly in a browser (this review's tools could not render Kaggle's
JavaScript-based metadata panel) and record the exact license shown
there before citing it formally in a thesis, publication, or external
audit. Everything else needed to identify the dataset — filename, class
count, row count, and two independent corroborating citations — is
already documented above.

---

## 9. Known limitations (dataset-level)

- Provenance of the sole training source is strongly corroborated but not
  cryptographically confirmed, and its license terms are not yet on
  record (§1.1, §8).
- 9.8% of records share a symptom presentation with a different disease
  label elsewhere in the dataset — an inherent ambiguity ceiling, not a
  bug (§4).
- No Philippine-specific training data is present; the model's symptom
  vocabulary and disease taxonomy were not validated against local
  clinical presentation patterns (§2).
- No demographic, vital-sign, or lab-result features exist in the
  training data — see `AI_VARIABLE_DICTIONARY.md`.
- Mild class imbalance (2.15×) is present and uncorrected
  (`class_weight=None`).
- Dataset scale (93,993 records) is well short of the 150k–200k target;
  no legitimate path to close that gap was found within this review.
