# AI-DSUHIS — AI/ML Algorithm Verification & Q&A (historical baseline)

> Current status is maintained in `docs/AI_REQUIREMENTS_STATUS.md` and the
> generated `backend/reports/ai_requirements_verification.json`. This file
> preserves the earlier algorithm review for traceability; its old plain-split
> 84.96% production metrics and 300-tree settings are historical and must not
> be used as the current model result. The current saved artifact uses the
> group-safe evaluation implemented in `backend/app/train.py`.

This document explains, from the actual source code, datasets, and saved
model artifacts in this repository, exactly what AI/ML is implemented, how
it works, and what is and is not active in production. It is written for
system defense (thesis panel, code review, audit) — every claim below is
tied to a specific file, and every number is read directly from a live
artifact, not estimated.

Verification was performed by loading `backend/models/disease_model.pkl`
with the project's own `joblib`/scikit-learn environment
(`backend/.venv`), reading `backend/models/training_metrics.json`, reading
`backend/dataset/processed/merged_dataset.csv` with `pandas`, and reading
the relevant Python/Dart source files directly.

**Important correction to a common assumption:** this system has **two
independent classifiers**, not one:

| | Backend Random Forest | Backend rule engine | On-device neural net |
|---|---|---|---|
| File | `backend/app/train.py`, `predict.py` | `backend/app/health_category_service.py` | `lib/app/core/services/health_ai_classifier.dart` |
| Type | Supervised, multi-class, 100 diseases | Deterministic keyword/lookup rules | Supervised, small dense neural network (2 outputs) |
| Where it runs | Backend (FastAPI), if called | Backend (FastAPI), inside `/guidance` | **On the Flutter device**, no network call |
| Status | Trained, evaluated, **not called by any active route** | Active, powers `/guidance`'s `suggestedHealthCategory` | Active, powers checkup/prenatal record classification |
| Categories | 100 disease names | Communicable / Non-Communicable / Mixed / Needs Clinical Review | Communicable Disease / Non-Communicable Disease / Emergency / Routine Checkup / Prenatal Care / Pediatric Care |

The Random Forest is real, trained, and evaluated — but `/predict` is
disabled, so it is currently dormant. The category/severity labels a BHW
actually sees when saving a checkup or prenatal record ("Emergency",
"Critical", etc.) come from the **on-device neural network** in
`health_ai_classifier.dart`, not from the Random Forest and not from the
Python rule engine. Sections 1–17 below cover the Random Forest; Section
18 confirms it is disabled; Sections 19–20 cover the two systems that are
actually active.

---

## 1. Exact Random Forest implementation — file map

| Responsibility | File | Function/class |
|---|---|---|
| Dataset loading | `backend/app/train.py` | `load_training_data()` |
| Preprocessing (merge, normalize, dedupe) | `backend/scripts/merge_datasets.py`, `pipeline_utils.py`, `remove_duplicates.py` | `build_master_dataset()`, `prepare_wide_dataset()`, `remove_duplicates()` |
| Feature selection | `backend/scripts/pipeline_utils.py` | `prepare_wide_dataset()` (all normalized symptom columns become features) |
| Target selection | `backend/app/train.py` | `TARGET = "diseases"` (module constant) |
| Train/test splitting | `backend/app/train.py` | `train_test_split(...)` inside `train_model()` |
| `RandomForestClassifier` creation | `backend/app/train.py` | `train_model()`, line ~78 |
| Model training | `backend/app/train.py` | `model.fit(x_train, y_train)` |
| Model evaluation | `backend/app/train.py` | `accuracy_score`, `precision_recall_fscore_support`, `confusion_matrix`, `classification_report` inside `train_model()` |
| Saving `disease_model.pkl` | `backend/app/train.py` | `joblib.dump(model, MODEL_PATH, compress=3)` |
| Loading `disease_model.pkl` | `backend/app/predict.py` | `_load_artifacts_cached()` / `load_artifacts()` (via `joblib.load`) |
| `predict()` | not called directly — the API only uses `predict_proba()` | — |
| `predict_proba()` | `backend/app/predict.py` | `predict_top_diseases()`, calls `model.predict_proba(sample)` |

An alternate/experimental trainer, `backend/app/train_baseline.py`, exists
for comparison and writes to `backend/models/experiments/raw_baseline.pkl`.
It is **not** the production model and is not loaded by the API.

## 2. Machine learning type — verified from code

From `backend/app/train.py`:

- **Supervised** — `model.fit(x_train, y_train)` is trained against a
  labeled target column (`diseases`), read from
  `backend/dataset/processed/merged_dataset.csv`.
- **Classification**, not regression — `sklearn.ensemble.RandomForestClassifier`,
  and the target (`diseases`) is a categorical string, not a continuous number.
- **Multi-class**, not binary — the loaded model reports
  `model.n_classes_ == 100` and `len(model.classes_) == 100` (verified by
  loading the actual `.pkl`). It is not one-vs-rest or binary.

## 3. Why Random Forest was used

The repository does **not** contain an explicit written rationale for
choosing `RandomForestClassifier` (no design doc, comment, or README
section states "we chose Random Forest because..."). The closest thing is
`backend/README.md`, which documents *what* the model does, not *why* the
algorithm was picked.

The following is therefore a **technical interpretation**, based only on
properties that genuinely apply to this implementation:

- The dataset is tabular/structured: 229 binary symptom columns and one
  categorical target — exactly the shape Random Forest is designed for.
- There are many input features (229) and many classes (100); Random
  Forest handles high-dimensional, multi-class tabular problems without
  manual feature scaling.
- The features are binary presence/absence indicators with likely
  non-linear, combinatorial relationships to disease labels (e.g., "fever"
  alone means little, but "fever + rash + joint pain" together shifts the
  prediction); tree ensembles capture that without hand-engineered
  interaction terms.
- Averaging across `n_estimators=300` trees reduces the variance/overfitting
  risk that a single decision tree would have on a 93,993-row, 100-class
  dataset.
- The API needs calibrated-looking class probabilities
  (`predict_proba()`, used for the Top-3 ranked list) — Random Forest
  exposes this natively by averaging per-tree class votes.

This is **not** a claim that Random Forest is medically superior to any
other algorithm — no such comparison exists in this repository.

## 4. How the implemented Random Forest works

Actual flow, from `backend/app/predict.py` and `train.py`:

```
Symptom names (strings, e.g. "fever", "sore throat")
  → normalize_symptom() + symptom_aliases.json  (build_feature_vector)
  → 229-length binary feature vector (1 = present, 0 = absent)
  → RandomForestClassifier (300 trees, each trained on a bootstrap sample)
  → each tree casts a class-probability vote
  → probabilities averaged across all 300 trees (model.predict_proba)
  → np.argsort by probability, top 3 kept (predict_top_diseases)
  → {"disease": ..., "confidence": ..., "rank": ...} × 3
```

**Decision Tree.** Each individual tree in the forest receives one
bootstrap-resampled copy of the 75,194 training rows. At every node it
picks, from a random subset of the 229 features (see §9,
`max_features="sqrt"` → ~15 features considered per split), the single
feature/threshold (here, effectively "is this symptom present?") that
most reduces Gini impurity (§15) among the 100 disease labels. It repeats
this recursively — up to `max_depth=24` — until a leaf is reached.

**Random Forest.** 300 such trees are built independently (`n_estimators=300`,
§14), each seeing a different bootstrap sample and a different random
subset of features at each split. This decorrelates the trees so their
errors don't all point the same way.

**Bootstrap sampling / bagging.** Enabled — `bootstrap=True` is the
loaded model's actual attribute value. Each tree is trained on a random
sample of the 75,194 training rows, drawn **with replacement**, the same
size as the training set (some rows repeated, some omitted — standard
bagging).

**Random feature selection.** At each split, scikit-learn considers
`max_features="sqrt"` of the 229 features — √229 ≈ 15 features — chosen
randomly per split, not the same 15 every time. This is what makes it a
*random* forest rather than a plain bagged-tree ensemble.

**Tree splitting.** `criterion="gini"` (the loaded model's actual
attribute) — see §15.

**Voting / probability.** The API never calls the plain `predict()`
method. It calls `model.predict_proba(sample)` (`predict.py`, inside
`predict_top_diseases()`), which returns, for each of the 100 classes,
the fraction of the 300 trees that voted for that class at their leaf
(averaged, not majority-only). `np.argsort(...)[::-1]` sorts these 100
probabilities descending and keeps the top 3, each converted to a
percentage (`round(probability * 100.0, 2)`).

## 5. Model variables — Independent variables / Features (`X`)

Verified by loading `backend/dataset/processed/merged_dataset.csv` (93,993
rows × 230 columns) and `backend/models/disease_model_features.json`:

- **Exact number of features: 229** (`model.n_features_in_ == 229`,
  matches `len(disease_model_features.json) == 229`).
- **Column names**: symptom phrases, normalized to lowercase with spaces
  (e.g. `"abnormal appearing skin"`, `"abnormal breathing sounds"`,
  `"ache all over"`, `"headache"`, `"nosebleed"`, `"back pain"` — full
  list in `backend/models/disease_model_features.json`).
- **Data type**: every feature column is `uint8` (pandas), holding only
  the integers **0 or 1** — verified directly:
  `pd.unique(df[feature_columns].values.ravel())` returns exactly `[0, 1]`.
- **Meaning**: each column is one symptom; `1` = the symptom is present
  for that record, `0` = absent.
- **Encoding**: binary presence/absence indicator (multi-hot vector across
  229 symptoms per record) — not one-hot, not scaled/normalized.

## 6. Target variable

- **Exact column name: `diseases`** (`TARGET = "diseases"` in `train.py`,
  confirmed present in the CSV header).
- **Number of unique classes: 100** (`df['diseases'].nunique() == 100`,
  matches `model.classes_` length).
- **Example classes** (from the live dataset's class-count table):
  `asthma`, `hypertensive heart disease`, `acute bronchospasm`,
  `heart failure`, `sepsis`, `cystitis`, `vulvodynia`, `nose disorder`,
  `complex regional pain syndrome`, `spondylosis`.
- **Meaning**: the disease/condition label a training row's symptom
  pattern is associated with.
- **Multi-class**: yes — 100 distinct string labels, not binary.

## 7. Input representation

Confirmed from the dataset and from `backend/app/predict.py`:

- Symptom columns use `1 = present`, `0 = absent` — verified as the only
  two values present anywhere in the 229 feature columns.
- At inference time, `build_feature_vector()` starts from an
  all-zero dict over the 229 canonical feature names, then for every
  symptom string a user/BHW enters: normalizes it
  (`normalize_symptom()` — lowercase, trims, collapses whitespace,
  replaces `_`/`-` with spaces), resolves it through
  `symptom_aliases.json` if it's a known synonym, and — only if it
  exactly matches one of the 229 trained feature names — sets that
  position to `1`. Anything that doesn't match a known feature is
  returned separately as `ignoredSymptoms` and never silently guessed.
  The result is a single-row `pandas.DataFrame` with the exact 229
  columns, in the exact order, the model was trained on.

## 8. Preprocessing — verified pipeline steps only

Everything below is implemented in
`backend/scripts/merge_datasets.py` + `pipeline_utils.py` +
`remove_duplicates.py`, run **before** `train.py` (train.py itself does no
further preprocessing beyond loading the already-processed CSV):

| Step | Present? | Where | What it does / why |
|---|---|---|---|
| Duplicate removal | Yes | `remove_duplicates.py: remove_duplicates()` | `frame.drop_duplicates()` on the merged frame; the script prints rows-before/after. |
| Missing-value handling | Yes | `merge_datasets.py` (`.fillna(0)`), `pipeline_utils.prepare_wide_dataset` (`pd.to_numeric(...).fillna(0)`) | Any missing symptom cell is treated as "absent" (0), not dropped. |
| Symptom normalization | Yes | `pipeline_utils.normalize_symptom()` / `basic_normalize()` | Lowercases, trims, replaces underscores with spaces, strips a leading `"symptom "` prefix and `UMLS:C####` prefixes, collapses whitespace. |
| Alias normalization | Yes | `pipeline_utils.load_mapping()` + `dataset/mappings/symptom_mapping.json` / `disease_mapping.json` | Maps known synonyms (raw column/label text) to one canonical name before merging. |
| Column merging | Yes | `pipeline_utils.collapse_duplicate_columns()` | If two columns normalize to the same symptom name, they're combined with logical OR (`max`), not summed or overwritten. |
| Feature selection/removal | Yes | `pipeline_utils.NON_FEATURE_COLUMNS` set, `merge_datasets.is_binary_feature_dataset()` | Drops known non-symptom columns (`code`, `frequency`, `index`, `treatment`, etc.) and rejects any source file whose feature columns aren't strictly numeric binary. |
| Encoding | Yes | `pipeline_utils.prepare_wide_dataset()` | `pd.to_numeric(...).ne(0).astype("uint8")` — any nonzero value becomes `1`. |
| Label cleanup | Yes | `pipeline_utils.remove_empty_labels()` | Drops rows whose disease label is empty/`"nan"`/`"none"`/`"null"`. |
| Class normalization | Yes | `pipeline_utils.normalize_disease()` + disease alias map | Same lowercase/whitespace/synonym normalization applied to the target column. |
| Minimum-class-size filtering | Yes | `merge_datasets.build_master_dataset()` (`MIN_DISEASE_SAMPLES = 20`) | Diseases with fewer than 20 rows are dropped from the merged dataset entirely. |
| Data balancing (SMOTE/undersampling) | **No** | — | Not present anywhere in the pipeline. Classes are left at their natural counts (see §17). |
| Scaling/normalization of feature values | **No** (not applicable) | — | Features are binary 0/1 already; no `StandardScaler`/`MinMaxScaler` is used, and Random Forest does not require it. |
| Train/test splitting | Yes | `train.py: train_model()` | `train_test_split(test_size=0.20, random_state=42, stratify=labels)` (see §10). |

## 9. Random Forest hyperparameters — read from the loaded `.pkl`

These were read directly off the live model object
(`joblib.load('backend/models/disease_model.pkl')`), not from source
code alone, so they reflect exactly what was actually trained:

| Parameter | Actual value | Explicitly set in `train.py`? |
|---|---|---|
| `n_estimators` | **300** | Yes |
| `criterion` | **gini** | No — scikit-learn default |
| `max_depth` | **24** | Yes |
| `min_samples_split` | **2** | No — scikit-learn default |
| `min_samples_leaf` | **2** | Yes |
| `max_features` | **sqrt** | No — scikit-learn default (as of the installed version) |
| `max_leaf_nodes` | **4096** | Yes |
| `bootstrap` | **True** | No — scikit-learn default |
| `random_state` | **42** | Yes |
| `class_weight` | **None** | No — scikit-learn default (see §17, class imbalance is *not* compensated) |
| `n_jobs` | **-1** (use all CPU cores) | Yes |

Installed scikit-learn version in `backend/.venv`: **1.9.0**.

In simple terms:
- **`n_estimators=300`** — the forest is 300 trees; more trees generally
  means steadier probability estimates, at the cost of memory/CPU.
- **`max_depth=24`** and **`max_leaf_nodes=4096`** — caps on how large
  each tree can grow, which limits memorizing noise in the training data.
- **`min_samples_leaf=2`** — a leaf must represent at least 2 training
  rows, a mild guard against single-row overfitting.
- **`max_features="sqrt"`** — each split only considers a random ~15 of
  the 229 symptoms, which is what decorrelates the trees (§4).
- **`class_weight=None`** — every training row counts equally regardless
  of how common its disease label is; the model does not upweight rare
  diseases.

## 10. Train/test split — verified from `training_metrics.json`

Read directly from `backend/models/training_metrics.json` (written by
`train.py` at training time) and cross-checked against the live CSV:

| | Value |
|---|---|
| Total usable records | **93,993** (`merged_dataset.csv` shape) |
| Training records | **75,194** |
| Test records | **18,799** |
| Training percentage | **80.0%** |
| Testing percentage | **20.0%** |
| `random_state` | **42** |
| Stratified? | **Yes** — `stratify=labels` in `train_test_split(...)` |

This **is** an 80/20 split, confirmed both by the recorded counts and by
the `test_size=0.20` argument in `train.py`.

## 11. Training pipeline — actual steps

```
Raw source CSVs (backend/dataset/raw/*.csv)
  → merge_datasets.load_compatible_datasets()      # filters to binary-symptom files only
  → pipeline_utils.prepare_wide_dataset()           # normalize symptom/disease names, encode 0/1
  → merge_datasets.build_master_dataset()           # align all files to one shared symptom-column list
  → remove_duplicates.remove_duplicates()           # drop exact duplicate rows
  → drop diseases with < 20 rows
  → dataset/processed/merged_dataset.csv            # 93,993 rows × 230 columns (229 features + target)

train.py: load_training_data()
  → dtype-cast every feature column to uint8, target to string
  → split into features (X) / labels (y)
train.py: train_model()
  → train_test_split(X, y, test_size=0.20, random_state=42, stratify=y)
  → RandomForestClassifier(n_estimators=300, max_depth=24, max_leaf_nodes=4096,
                            min_samples_leaf=2, random_state=42, n_jobs=-1)
  → model.fit(x_train, y_train)
  → predictions = model.predict(x_test)
  → accuracy_score / precision_recall_fscore_support / confusion_matrix / classification_report
  → joblib.dump(model, 'backend/models/disease_model.pkl', compress=3)
  → write backend/models/disease_model_features.json (ordered feature-column list)
  → write backend/models/training_metrics.json (accuracy, precision, recall, f1, record/feature/class counts)
```

## 12. Model evaluation — actual numbers, read from the saved artifact

Read directly from `backend/models/training_metrics.json`:

| Metric | Value |
|---|---|
| Accuracy | **84.96%** (0.849566...) |
| Precision (weighted) | **88.39%** (0.883854...) |
| Recall (weighted) | **84.96%** (0.849566...; recall equals accuracy for weighted multi-class here) |
| F1-score (weighted) | **85.60%** (0.855988...) |
| Test samples | **18,799** |

These match the figures previously reported (84.96% / 88.39% / 85.60%) —
**confirmed against the live artifact**, not copied blind.

- **Confusion matrix / per-class results**: `train.py` computes and
  prints a full 100×100 confusion matrix and a per-class
  `classification_report` at training time, but neither is written to a
  file — only the four summary numbers above are persisted to
  `training_metrics.json`. Re-running `train.py` would reproduce them on
  stdout, but no committed confusion-matrix artifact exists in the repo
  to quote numbers from.
- **Cross-validation**: **not used**. `train.py` performs a single
  `train_test_split`; there is no `cross_val_score`, `StratifiedKFold`, or
  similar anywhere in `backend/app` or `backend/scripts`.

**Model test accuracy is not clinical validation.** 84.96% measures how
often the model's top guess matches the label on a held-out 20% slice of
the *same* merged public/synthetic symptom datasets it was trained on. It
says nothing about performance on real Malaybalay patients, does not
account for comorbidities, lab results, or clinician exam findings, and
has not been reviewed or validated by a licensed clinician against real
cases. It is a measure of pattern-matching consistency on this dataset,
not of diagnostic correctness.

## 13. One real prediction example (live model output)

Run against the actual loaded model via `backend/app/predict.py:predict_top_diseases()`,
input symptoms `["fever", "cough", "sore throat"]`:

```
recognizedSymptoms: ["fever", "cough", "sore throat"]
ignoredSymptoms: []

topPredictions:
  1. spinal stenosis     — 1.56%
  2. acute bronchitis    — 1.45%
  3. anxiety             — 1.42%
```

Flow: `"fever", "cough", "sore throat"` → normalized (already lowercase,
no aliasing needed) → 229-length vector with exactly those 3 positions
set to `1`, the other 226 set to `0` → 300 trees each vote a probability
distribution over 100 classes → `predict_proba()` averages the 300 votes
→ sorted descending → top 3 returned.

These are the model's **real, unedited output percentages** — not
invented. They are intentionally low (under 2%) because only 3 of 229
possible symptoms are set, and the model is spreading probability across
100 classes; this is expected behavior for a sparse, generic symptom set
and is exactly why the API layer (`confidence_threshold`, default 0.50 in
`config.py`) exists to flag low-confidence predictions — though that
threshold currently only matters to the disabled `/predict` code path.

## 14. Number of trees

**300 decision trees** (`model.n_estimators == 300`, confirmed on the
loaded artifact; also explicitly set as `n_estimators=300` in `train.py`).
This means every prediction is the *average* of 300 independently-trained
trees' class-probability outputs, not a single tree's guess — the
mechanism that makes the ensemble more stable than any one tree.

## 15. Split criterion

**Gini impurity** (`model.criterion == "gini"`, scikit-learn's default —
`train.py` does not override it). In plain terms: at each branching point,
the tree tries the available symptom-presence splits and picks whichever
one produces the two resulting groups that are *most "pure"* — i.e., each
group is dominated by as few disease labels as possible. It repeats this
at every node until it hits the depth/leaf-count limits from §9.

## 16. Feature importance

The saved model exposes `feature_importances_`, and the feature order in
`backend/models/disease_model_features.json` is written by the same
`train.py` run (`list(features.columns)`, straight from the `X` DataFrame
used to `fit()`), so the mapping between importance values and feature
names is reliable. Top 20, read directly from the loaded model:

| Rank | Feature | Importance |
|---|---|---|
| 1 | nosebleed | 0.01520 |
| 2 | hemoptysis | 0.01338 |
| 3 | difficulty in swallowing | 0.01336 |
| 4 | vaginal pain | 0.01273 |
| 5 | symptoms of the face | 0.01270 |
| 6 | headache | 0.01183 |
| 7 | unusual color or odor to urine | 0.01175 |
| 8 | pus draining from ear | 0.01159 |
| 9 | ache all over | 0.01139 |
| 10 | hip stiffness or tightness | 0.01117 |
| 11 | hot flashes | 0.01115 |
| 12 | mouth ulcer | 0.01092 |
| 13 | back pain | 0.01090 |
| 14 | abusing alcohol | 0.01088 |
| 15 | uterine contractions | 0.01027 |
| 16 | burning abdominal pain | 0.01013 |
| 17 | jaundice | 0.01008 |
| 18 | itchy scalp | 0.01005 |
| 19 | sneezing | 0.00960 |
| 20 | vomiting blood | 0.00955 |

With 229 features and a flat-ish importance curve (top feature is only
1.5% of total importance), no single symptom dominates the model — this
is expected for a 100-class problem with many overlapping symptoms.
**This ranking reflects influence on this trained classifier's split
decisions only — it is not evidence of medical causation.** A high-ranked
feature is one the trees found statistically useful for separating
classes in this dataset, not a claim that it *causes* or *diagnoses*
anything.

## 17. Random Forest limitations — specific to this implementation

- **Dataset provenance**: the merged training data comes from public
  Kaggle-style symptom/disease CSVs plus a text-narrative dataset
  (`backend/dataset/raw/`), not from actual Malaybalay/local patient
  records. It has not been validated as representative of the local
  population.
- **Class imbalance, not corrected**: class sizes range from 567 rows
  (`sepsis`) to 1,219 rows (`cystitis`) — about a 2.1× spread — and
  `class_weight=None`, so no reweighting compensates for this.
- **Overlapping symptoms**: many diseases share common symptoms (fever,
  headache, cough), which is reflected in the low per-class confidence
  seen in §13 and is an inherent limitation of symptom-only tabular data.
- **Binary symptom representation**: severity, duration, and intensity of
  a symptom are not captured — a mild ache and a severe one are both just
  `1`.
- **No lab/exam data**: the model only ever sees symptom presence/absence
  — no vitals, lab results, imaging, or physical exam findings are part
  of its 229 features.
- **Input quality**: predictions depend entirely on symptoms being
  correctly recognized against the 229-name vocabulary; anything
  unmatched is silently ignored (`ignoredSymptoms`), which can starve the
  model of relevant signal for oddly-phrased input.
- **No clinical validation**: as stated in §12, the 84.96% figure is a
  held-out test-set score on the training dataset's own distribution, not
  a clinical trial or expert-reviewed validation.
- **Not currently in production use**: see §18 — this model is trained
  and evaluated, but no active route calls it.

## 18. Current production status — `/predict` is disabled

Confirmed directly in `backend/app/api.py`:

- The function that would call the Random Forest and build a disease
  prediction response, `_disabled_legacy_prediction_endpoint(...)`
  (lines ~449–554), is defined but **has no `@application.post("/predict")`
  decorator** — the comment directly above it states: *"Kept temporarily
  as an unregistered function for response-contract history. There is
  intentionally no route decorator: POST /predict now returns 404."*
- `backend/README.md` confirms the same: *"The legacy `POST /predict`
  route is no longer registered and returns HTTP 404."*
- On the Flutter side, `lib/app/core/services/disease_prediction_api_service.dart`'s
  `predictFromText()` immediately throws
  `DiseasePredictionApiException('Disease prediction has been disabled.
  Use AI Symptom Guidance instead.')` before it would ever reach the
  network — the actual HTTP call to `/predict` exists only inside a
  `/* ... */` comment block below the `throw`, so it is unreachable dead
  code, not a live call path.

**Therefore: the trained `RandomForestClassifier` artifact exists, is
correctly loadable, and evaluates as described above — but it is not the
primary active user-facing prediction path.** The only currently-active
backend AI route is `POST /guidance`.

## 19. The active classification algorithms (Random Forest is disabled)

There are two separate active classification systems — see the table at
the top of this document.

### 19a. Backend `/guidance` health-category suggestion (rule-based)

File: `backend/app/health_category_service.py`, function
`suggest_health_category(recognized_conditions, recognized_symptoms)`,
`RULE_VERSION = "condition-category-rules-v2"`.

- **Input variables**: `recognized_conditions` (explicit condition names
  the BHW typed, matched against the model's disease vocabulary) and
  `recognized_symptoms` (symptom names matched against the 229-feature
  vocabulary) — both already validated upstream in `api.py` before this
  function runs.
- **Keywords/rules**: four fixed Python sets — `COMMUNICABLE_CONDITIONS`
  (17 named diseases, e.g. influenza, tuberculosis, dengue fever),
  `NON_COMMUNICABLE_CONDITIONS` (16 named diseases, e.g. hypertension,
  diabetes, asthma), `COMMUNICABLE_SYMPTOMS` (10 symptom keywords, e.g.
  fever, cough, skin rash), `NON_COMMUNICABLE_SYMPTOMS` (7 symptom
  keywords, e.g. frequent urination, chronic joint pain).
- **Scoring logic**: no numeric score — pure set-membership matching.
  Each recognized condition/symptom is bucketed into "communicable,"
  "non-communicable," or "unmapped" by direct lookup against the sets
  above.
- **Category-selection logic** (checked in this exact priority order):
  1. Any unmapped explicit condition → `"Needs Clinical Review"`
  2. Both communicable and non-communicable conditions present → `"Mixed"`
  3. Only communicable conditions → `"Communicable"`
  4. Only non-communicable conditions → `"Non-Communicable"`
  5. (no explicit conditions) both symptom types present → `"Mixed"`
  6. Only communicable symptoms → `"Communicable"`
  7. Only non-communicable symptoms → `"Non-Communicable"`
  8. Nothing classifiable → `"Needs Clinical Review"`
- **Fallback behavior**: anything not on the fixed keyword/condition lists
  routes to `"Needs Clinical Review"` rather than guessing — the function
  never invents a category for unrecognized input.
- **Output**: `suggestedHealthCategory`, `categoryBasis` (an audit string
  like `"explicit_condition_mapping"` or `"symptom_only"`),
  `categoryRequiresReview` (`true` unless the basis was an explicit,
  unambiguous condition match).

This is a deterministic lookup table, not a statistical or trained model
— there is no probability, confidence, or learned weight anywhere in this
function.

### 19b. On-device checkup/prenatal record classification (hybrid: neural net + rule-based fallback)

File: `lib/app/core/services/health_ai_classifier.dart`, class
`HealthAIClassifier`. Called live from `checkup.dart` and `prenatal.dart`
(both `lib/app/features/...` and `lib/web/roles/bhw/...`) when a BHW
saves a checkup or prenatal record — **this runs entirely on the Flutter
device; it makes no network call.**

- **Primary path — trained neural network**: `assets/models/health_classifier_weights.json`
  (bundled in `pubspec.yaml`, confirmed present, 791 KB) is loaded at
  startup. It is a real trained **feedforward neural network** (Keras
  `Dense(128, relu) → Dense(64, relu) → Dense(32, relu)` shared trunk,
  then two separate `softmax` output heads — one for category (6
  classes), one for severity (4 classes)) — exported to portable JSON and
  re-implemented by hand in Dart (`_PortableMLModel` class) so it can run
  without a native TFLite runtime on Flutter Web. This is a **different
  algorithm from Random Forest** — a small dense neural network, trained
  by `train_model/train_health_classifier.py`.
  - Input: a 200-length feature vector — index 0 is normalized age
    (`age / 100.0`); indices 1–50 are FNV-1a hashed keyword-presence
    buckets over 129 medical keywords; indices 51–54 are normalized blood
    pressure (systolic/diastolic), temperature, and heart rate, parsed
    out of the record's free-text `details` field with regex
    (`BP:\s*(\d+)/(\d+)`, `Temp:\s*(\d+\.?\d*)`, `HR:\s*(\d+)`).
  - Output: 6-way category softmax + 4-way severity softmax; the highest
    probability in each determines the final label.
  - Training data for the checked-in weights: the training script
    defaults to **synthetic data** generated by deterministic rules
    (`create_synthetic_training_data()`, 2,000 samples by default) unless
    explicitly run with `--data-file <real Firebase export>.json`. The
    repository contains no committed real-data export and no training
    log alongside the checked-in `health_classifier_weights.json`, so
    which data source produced the exact checked-in weights cannot be
    verified from the repo alone — treat it as most likely synthetic
    unless the team confirms otherwise. **No accuracy/precision/recall
    figures for this model are committed anywhere in the repo** (unlike
    the Random Forest's `training_metrics.json`) — the training script
    prints category/severity accuracy to the console but does not save it.
- **Fallback path — rule-based keyword scoring**: only used if the
  neural-network path throws an exception (`_ruleBasedClassify()`). Scores
  each of the 6 categories by counting keyword matches from
  `keywordDatabase` (with a +5 boost to "Emergency" for abnormal vitals
  detected via regex, and a +1.3× multiplier to "Non-Communicable" for
  patients over 40, and prenatal-field/risk-level boosts for "Prenatal
  Care"); the category with the highest score wins. "Routine Checkup" has
  a flat baseline score of 0.5 so it wins only when nothing else matches.
- **Categories** (verified `categories` constant, both in Dart and in the
  Python trainer): `Communicable Disease`, `Non-Communicable Disease`,
  `Emergency`, `Routine Checkup`, `Prenatal Care`, `Pediatric Care`.

## 20. Severity classification — verified variables

Two severity computations exist, matching the two systems above. The one
a BHW actually sees on a checkup/prenatal record is the neural-net/
rule-based one in `health_ai_classifier.dart` (`/guidance` does not
compute a numeric severity at all — it only returns
`emergencyWarningSigns` text pulled from Firestore).

**Severity levels** (verified constant): `Low`, `Medium`, `High`, `Critical`.

When the neural-net path is used, severity comes straight from the
model's `severity_output` softmax head (trained end-to-end alongside
category, same feature vector as §19b). When the rule-based fallback
runs, `_determineSeverity()` computes it explicitly:

| Variable | Source | How it affects severity |
|---|---|---|
| Category = "Emergency" | Computed category (this same classifier) | Immediately forces `Critical`, no further scoring. |
| Blood pressure (systolic/diastolic) | Regex-parsed from `details` string (`BP: sys/dia`) or a direct `bp` field (prenatal records) | +2 to severity score if systolic >160/<90 (or diastolic >100 for the direct-field path); +1 if systolic >140/<100 (or diastolic >90). |
| Temperature | Regex-parsed from `details` (`Temp: x`) or a direct `temp` field | +2 if >39.5°C; +1 if >38.0°C. |
| Prenatal risk level | `healthData['riskLevel']` field | +3 if it contains "high"; +1 if it contains "moderate" (only applied when category is "Prenatal Care"). |
| Prenatal complications/pre-existing conditions | `previousComplications` / `preExistingConditions` fields | +1 if either is non-empty (only applied when category is "Prenatal Care"). |
| Symptom text severity keywords | `symptoms`, `preExistingConditions`, `previousComplications` text, checked for "severe", "acute", "intense", "unbearable", "extreme" | +1 per matching keyword found. |
| Age | `healthData['age']` | Not used by `_determineSeverity()` directly (age affects *category* scoring in §19b, not severity). |

Final mapping from the accumulated integer score: `≥4 → Critical`,
`≥2 → High`, `≥1 → Medium`, else `Low`. Only variables that are actually
read by the code are listed — no vitals or fields beyond the ones above
factor into the rule-based severity score.

---

## Q&A

**What type of AI/ML does this system use?**
Two supervised machine-learning models (a Random Forest and a small
feedforward neural network) plus deterministic rule-based/keyword logic.
No unsupervised learning, no clustering, and no generative AI (no LLM,
no text generation, no chatbot) is used anywhere in the codebase.

**Does the system use generative AI (e.g. an LLM/chatbot)?**
No. There is no generative-AI API integration, prompt template, or
text-generation model anywhere in `backend/` or `lib/`. All AI output is
either a classification label + probability (Random Forest, neural net)
or fixed reference text retrieved from Firestore/local constants.

**Is this supervised learning? Classification?**
Yes to both, for both trained models. The Random Forest is trained on
labeled `(symptoms → disease)` pairs (`train.py`, `model.fit(x_train,
y_train)`); the on-device neural network is trained on labeled
`(record → category, severity)` pairs (`train_health_classifier.py`,
`model.fit(X_train, {category, severity})`). Both are multi-class
classification, not regression.

**What is Random Forest, as implemented here?**
An ensemble of 300 independently-trained decision trees (§4, §14), each
built on a bootstrap sample of the training rows (§4 bagging) and a
random ~15-of-229 feature subset per split (§9 `max_features="sqrt"`).
Final predictions average all 300 trees' class-probability votes
(`predict_proba`).

**Why was Random Forest selected?**
Not documented in the repository — §3 gives a technical interpretation
only (tabular binary features, many classes, non-linear symptom
combinations, need for probability output), explicitly not a claim of
medical superiority.

**How does the model predict?**
Symptom names → normalized → 229-length binary vector → 300 trees vote →
probabilities averaged → sorted → top result(s) returned. See §4 and §13
for the exact flow and a real example.

**How many trees does the Random Forest use?**
300 (`n_estimators=300`, confirmed on the loaded model object). See §14.

**What are the input and target variables?**
Input (`X`): 229 binary symptom-presence columns. Target (`y`): `diseases`
— a 100-class categorical column. See §5–§6.

**How many features and classes does the Random Forest have?**
229 features, 100 classes — both confirmed on the loaded model
(`model.n_features_in_`, `model.n_classes_`) and the source CSV.

**How are symptoms represented as input?**
Binary: `1` if present, `0` if absent, across a fixed 229-name vocabulary.
Free-text symptom entries are normalized and alias-matched before being
placed into this fixed vector; unmatched text is ignored, not guessed.
See §7.

**What preprocessing is actually done?**
Duplicate removal, missing-value fill, symptom/disease text normalization,
alias mapping, duplicate-column merging, non-feature-column removal,
binary encoding, label cleanup, minimum-class-size filtering, and an
80/20 stratified train/test split. No scaling (features are already
binary) and no class-balancing (SMOTE/undersampling) are used. See §8.

**What is the train/test split?**
80% / 20%, stratified by disease label, `random_state=42` — 75,194
training rows / 18,799 test rows out of 93,993 total. See §10.

**What are the Random Forest's hyperparameters?**
`n_estimators=300`, `max_depth=24`, `max_leaf_nodes=4096`,
`min_samples_leaf=2`, `random_state=42`, `n_jobs=-1` explicitly set;
`criterion="gini"`, `min_samples_split=2`, `max_features="sqrt"`,
`bootstrap=True`, `class_weight=None` are scikit-learn defaults, left
unset. See §9.

**What is the model's accuracy, precision, recall, and F1?**
Accuracy 84.96%, weighted precision 88.39%, weighted recall 84.96%,
weighted F1 85.60%, measured on 18,799 held-out test rows. Read directly
from `backend/models/training_metrics.json`. See §12.

**Why isn't model accuracy the same as clinical validation?**
The 84.96% figure only measures agreement with labels on a held-out slice
of the *same* merged training datasets (mostly public/Kaggle-style
symptom data) — it has not been checked against real patients by a
licensed clinician, does not account for information the model never
sees (vitals, labs, exam findings, patient history), and is not a
substitute for medical diagnosis. See §12, §17.

**Is `/predict` currently active?**
No. It is intentionally unregistered in `backend/app/api.py` and returns
HTTP 404; the Flutter client's equivalent method throws before making any
network call. See §18.

**If Random Forest is disabled, what actually classifies records today?**
Two systems: (1) a deterministic rule engine in
`health_category_service.py` that powers `/guidance`'s
`suggestedHealthCategory` (Communicable / Non-Communicable / Mixed /
Needs Clinical Review), and (2) an on-device neural network (with a
rule-based fallback) in `health_ai_classifier.dart` that classifies saved
checkup/prenatal records into 6 categories with 4 severity levels. See
§19.

**How is severity calculated?**
Either directly from the on-device neural network's severity output head,
or — if that model fails to load — from an explicit point-scoring rule
over blood pressure, temperature, prenatal risk level/complications, and
severity keywords in the symptom text. See §20.

**Where does home-care guidance come from?**
From reviewed Firestore content only — the `symptom_guidance` collection
(`SymptomGuidanceService`) merged with matching `diseases` collection
documents' `selfCareGuidance` field (`DiseaseService` +
`build_prediction_response`/`guidance_endpoint` in `api.py`). For the
on-device classifier, a local static `treatmentDatabase` /
`categoryFallbackTreatment` map in `health_ai_classifier.dart` supplies
home-care text when no Firestore call is involved. None of this text is
generated by a model — it is retrieved/looked up.

**Who is responsible for medication decisions?**
**Doctor-controlled only. The AI does not prescribe medication.** Both
active systems explicitly strip medication-related wording at their
output boundary: `backend/app/api.py`'s `_safe_guidance_strings()` filters
any string matching `medications?|medicines?|dosage|prescription|
prescribed|antibiotics?|inhaler` (case-insensitive) out of every
`/guidance` field before it's returned; `health_ai_classifier.dart`'s
`_safeGuidanceItems()`/`_isMedicationInstruction()` applies the identical
pattern to on-device recovery-plan text. Notably, the neural network's
own training metadata (`category_recovery_guidance` in
`health_classifier_weights.json`) *does* contain a `medications` field
per category, but the Dart code that reads this JSON
(`_generateRecoveryPlan()`) never accesses that key — it is present in
the artifact but structurally unreachable in the app.

**What happens when input is uncertain or unrecognized?**
The Random Forest path (`predict.py`) raises `NoRecognizedSymptomsError`
if zero symptoms match the vocabulary, rather than guessing. `/guidance`
returns HTTP 422 with the unrecognized text listed as `ignoredKeywords`
if neither symptoms nor conditions are recognized. The rule-based health
category (§19a) explicitly falls back to `"Needs Clinical Review"` rather
than forcing an answer. The on-device neural classifier falls back to
rule-based scoring if the ML model throws.

**What are this system's AI limitations?**
See §17 in full — dataset provenance (public/synthetic, not local
patient data), mild class imbalance with no correction, overlapping
symptoms across diseases, binary-only symptom representation (no
severity/duration signal), no lab or exam data, dependence on exact
vocabulary matching, no clinical validation, and the Random Forest
specifically being disabled in production.

**What's the difference between the Random Forest and the active
rule-based/neural system?**
The Random Forest predicts one of 100 specific *diseases* from symptoms
and is currently unreachable (§18). The active systems predict a much
coarser *category* (4 or 6 possible values, not 100) plus, for the
on-device system, a *severity* level — and both are reachable today, one
server-side (`/guidance`) and one entirely on-device. See the comparison
table at the top of this document and §19.

**What data is sent to `/guidance`?**
Only a JSON body of `{"symptoms": [<strings>]}` — confirmed in both
`backend/app/schemas.py`'s `PredictionRequest` (which accepts nothing
else) and the Flutter caller `disease_prediction_api_service.dart`
(`jsonEncode({'symptoms': symptoms})`). No patient name, ID, date of
birth, or other record fields are included in the request body.

**Are full patient records sent to the AI backend?**
No. Only the symptom-name strings a BHW typed/selected are sent. Patient
identity, demographics, and the rest of the checkup/prenatal record never
leave the device for this call — they stay in Firestore, accessed
separately and only after authentication.

**How is the AI API secured?**
`backend/app/security.py`'s `require_ai_access()` dependency, applied to
`/guidance`, requires: (1) a valid Firebase ID token as a `Bearer`
header, verified via `firebase_admin.auth.verify_id_token(...)` with
revocation checking; (2) a valid Firebase App Check token in the
`X-Firebase-AppCheck` header, verified via `firebase_admin.app_check`;
and (3) a per-user sliding-window rate limit (`AI_RATE_LIMIT_REQUESTS` /
`AI_RATE_LIMIT_WINDOW_SECONDS`, default 30 requests / 60 seconds),
returning HTTP 429 with `Retry-After` when exceeded. CORS in
`create_app()` further restricts allowed origins to the deployed Firebase
Hosting domains plus `localhost`/`127.0.0.1` for local development, and
only `GET`/`POST`/`OPTIONS` methods with a small allow-listed header set.

---

## Final Algorithm Summary

**AI TYPE:** Supervised machine learning (two trained models: a Random
Forest classifier and a small feedforward neural network) plus
deterministic rule-based/keyword logic. No generative AI.

**ACTIVE ALGORITHM:** (a) Deterministic rule engine
(`health_category_service.py`, `condition-category-rules-v2`) inside the
active `/guidance` endpoint; (b) an on-device trained feedforward neural
network (`Dense 128→64→32`, dual softmax heads) with a rule-based
fallback, inside `HealthAIClassifier` (`health_ai_classifier.dart`).

**ACTIVE PURPOSE:** (a) Suggests a coarse Communicable/Non-Communicable/
Mixed/Needs-Review category alongside retrieved Firestore self-care
guidance for symptom lookups; (b) classifies saved checkup/prenatal
records into a care category and severity level on-device.

**RANDOM FOREST TYPE:** Supervised, multi-class classification
(100 disease classes).

**RANDOM FOREST STATUS:** Trained and evaluated; **not called by any
active route** — `POST /predict` is unregistered and returns HTTP 404.

**INPUT VARIABLES:** 229 binary symptom-presence features (1 = present,
0 = absent).

**TARGET VARIABLE:** `diseases` — 100-class categorical disease label.

**NUMBER OF FEATURES:** 229.

**NUMBER OF CLASSES:** 100.

**NUMBER OF TREES:** 300 (`n_estimators=300`).

**SPLIT CRITERION:** Gini impurity (`criterion="gini"`, scikit-learn
default, not overridden).

**TRAIN/TEST SPLIT:** 80% / 20%, stratified, `random_state=42`
(75,194 train / 18,799 test of 93,993 total records).

**ACCURACY:** 84.96%.

**PRECISION:** 88.39% (weighted).

**RECALL:** 84.96% (weighted).

**F1-SCORE:** 85.60% (weighted).

**SEVERITY VARIABLES:** Category (Emergency forces Critical), blood
pressure, temperature, prenatal risk level, prenatal complications/
pre-existing conditions, and severity-keyword matches in symptom text
(see §20 table). Computed by the on-device neural network's severity
output head, or by explicit point-scoring rules as a fallback.

**HOME-CARE SOURCE:** Reviewed Firestore content (`symptom_guidance` and
`diseases` collections) for the backend path; a local static guidance map
in `health_ai_classifier.dart` for the on-device path. Retrieved/looked
up text only — never model-generated.

**MEDICATION:** Doctor-controlled only. AI does not prescribe medication.
