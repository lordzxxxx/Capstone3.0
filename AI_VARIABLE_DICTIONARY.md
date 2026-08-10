# AI-DSUHIS — AI/ML Variable Dictionary

Every variable below was read from the actual live artifacts and source
files in this repository (`backend/models/disease_model.pkl`,
`backend/models/disease_model_features.json`,
`backend/dataset/processed/merged_dataset.csv`,
`assets/models/health_classifier_weights.json`,
`lib/app/core/services/health_ai_classifier.dart`) — no variable name or
value set below is invented.

This system has **two trained models** with formal `X`/`y` structure, plus
two rule-based components that consume derived inputs rather than a
fixed feature vector. All four are documented below.

---

## Model 1 — Random Forest disease classifier (`backend/models/disease_model.pkl`)

`/predict` is disabled in production (see `AI_ALGORITHM_QA.md` §18); this
model is trained and evaluated but not currently reachable by any active
route.

### Independent Variables — `X` (229 features)

| Property | Value |
|---|---|
| Count | **229** (`model.n_features_in_ == 229`) |
| Data type | `uint8`, values restricted to `{0, 1}` (verified: `pd.unique()` over every feature cell returns exactly `[0, 1]`) |
| Encoding | Binary presence/absence indicator — no one-hot, no scaling |
| Possible values | `1` = symptom present in this record; `0` = symptom absent or not reported |
| Unit | Not applicable (categorical presence flag, not a measured quantity) |
| Source | `backend/dataset/processed/merged_dataset.csv`, produced by `backend/scripts/merge_datasets.py` from `backend/dataset/raw/Diseases_and_Symptoms_dataset.csv` |
| Missing-value rule | Any missing/non-numeric cell is coerced to `0` (absent) during preprocessing — `pd.to_numeric(...).fillna(0)` in `pipeline_utils.prepare_wide_dataset()` |
| Component using it | `backend/app/train.py` (training), `backend/app/predict.py` (inference, currently unreachable via `/predict`) |
| Role | Predictor — each column is one symptom name; the full 229-length vector for one patient/record is the model's input row |

Every feature is a distinct named symptom (e.g. `fever`, `headache`,
`back pain`, `nosebleed`, `difficulty in swallowing`). All 229 share this
same type/encoding/role, so they are documented once here as a class
rather than repeated 229 times. The complete, ordered list of all 229
names is the source of truth at
[`backend/models/disease_model_features.json`](backend/models/disease_model_features.json)
(also mirrored at `backend/models/feature_columns.json`, verified
byte-identical). A representative sample, grouped by theme for
readability (grouping is descriptive only — the model treats all 229
as an unordered flat vector, with no theme metadata):

**Symptoms — general/constitutional:** `fever`, `chills`, `ache all over`,
`fatigue`, `sweating`, `weight loss`, `hot flashes`.

**Symptoms — respiratory:** `cough`, `shortness of breath`, `wheezing`,
`sore throat`, `nasal congestion`, `sneezing`, `abnormal breathing sounds`.

**Symptoms — gastrointestinal:** `vomiting`, `nausea`, `diarrhea`,
`burning abdominal pain`, `vomiting blood`, `mouth ulcer`.

**Symptoms — musculoskeletal:** `back pain`, `hip stiffness or tightness`,
`arm pain`, `ankle pain`, `abnormal involuntary movements`.

**Symptoms — dermatologic:** `abnormal appearing skin`, `itchy scalp`,
`acne or pimples`.

**Symptoms — genitourinary/reproductive:** `vaginal pain`,
`unusual color or odor to urine`, `uterine contractions`.

**Symptoms — ENT/neurological:** `headache`, `nosebleed`, `hemoptysis`,
`pus draining from ear`, `symptoms of the face`.

**Behavioral/social:** `abusing alcohol`, `antisocial behavior`.

There is no explicit demographic, vital-sign, or lab-result feature in
this model — see the "Only symptoms" limitation in `AI_ALGORITHM_QA.md`
§17.

### Target Variable — `y`

| Property | Value |
|---|---|
| Exact column name | **`diseases`** (`TARGET = "diseases"` in `train.py`) |
| Data type | String / categorical (`pandas` `string` dtype at training time) |
| Number of classes | **100** (`model.n_classes_ == 100`) |
| Encoding | None — scikit-learn's `RandomForestClassifier` consumes and returns the raw string labels directly (`model.classes_` is an array of the original disease-name strings); there is no separate integer `LabelEncoder` step in `train.py` |
| Example values | `asthma`, `sepsis`, `heart failure`, `cystitis`, `spondylosis`, `hypertensive heart disease` (full list: 100 entries, in `model.classes_` / derivable from `merged_dataset.csv`'s `diseases` column) |
| Source | Same `merged_dataset.csv`, `diseases` column |
| Missing-value rule | Rows with an empty/`"nan"`/`"none"`/`"null"` label are dropped entirely before training (`pipeline_utils.remove_empty_labels()`) |
| Role | **Target/output** — the disease the 229-symptom vector is associated with |

`X = 229 binary symptom-presence features`. `y = "diseases"`, a 100-class
categorical column.

---

## Model 2 — On-device neural network (`assets/models/health_classifier_weights.json`)

Active — runs on-device inside `HealthAIClassifier`
(`lib/app/core/services/health_ai_classifier.dart`) when a BHW saves a
checkup or prenatal record. No network call is made for this
classification.

### Independent Variables — `X` (200-length vector)

| Index | Variable | Meaning | Type | Encoding | Source |
|---|---|---|---|---|---|
| 0 | `age (normalized)` | Patient age at time of record | float | `age / 100.0` | `healthData['age']` field on the checkup/prenatal record |
| 1–50 | `keyword hash buckets` | Presence of any of 129 configured medical keywords (see grouped list below), hashed via FNV-1a 32-bit into 50 fixed buckets | float (`0.0` or `1.0`) | `bucket = 1 + (fnv1a32(keyword) % 50)`; if a bucket's keyword is present in the record's combined `symptoms + details` text, that bucket is set to `1.0` — **buckets are shared across keywords, so two different keywords can collide into the same bucket** (a documented limitation, not a bug) | `healthData['symptoms']` + `healthData['details']` (free text) |
| 51 | `bp_systolic (normalized)` | Systolic blood pressure | float | regex-parsed from `details` (`BP:\s*(\d+)/(\d+)`), divided by 200.0 | `details` field |
| 52 | `bp_diastolic (normalized)` | Diastolic blood pressure | float | same regex, divided by 150.0 | `details` field |
| 53 | `temperature (normalized)` | Body temperature (°C) | float | regex `Temp:\s*(\d+\.?\d*)`, divided by 42.0 | `details` field |
| 54 | `heart_rate (normalized)` | Heart rate (bpm) | float | regex `HR:\s*(\d+)`, divided by 200.0 | `details` field |
| 55–199 | unused | Reserved capacity in the fixed 200-length input; not populated by the current 129-keyword/4-vital layout | float (always `0.0`) | — | — |

**The 129 source keywords** (before hashing), grouped exactly as defined
in `train_model/train_health_classifier.py`'s `KEYWORDS` dict:

- **Communicable** (43): fever, cough, flu, cold, infection, tuberculosis,
  dengue, covid, measles, chickenpox, pneumonia, sore throat, runny nose,
  body pain, headache, chills, rash, vomiting, diarrhea, malaria,
  hepatitis, typhoid, pertussis, mumps, rubella, meningitis, bronchitis,
  viral infection, bacterial infection, respiratory infection, skin
  infection, ear infection, pink eye, conjunctivitis, hand foot and mouth
  disease, hfmd, scabies, lice, parasite, worm infection,
  gastroenteritis, uti, urinary tract infection.
- **Emergency** (36): chest pain, difficulty breathing, severe bleeding,
  unconscious, seizure, stroke, heart attack, fainting, loss of
  consciousness, shortness of breath, severe headache, confusion,
  slurred speech, numbness, paralysis, high fever, convulsion, severe
  burn, broken bone, fracture, deep wound, vomiting blood, blood in
  stool, severe dehydration, allergic reaction, anaphylaxis, poisoning,
  snake bite, dog bite, road accident, trauma, collapse, labor pain,
  heavy vaginal bleeding, unresponsive, bluish lips, rapid heartbeat.
- **Non-communicable** (37): diabetes, hypertension, asthma, arthritis,
  cancer, thyroid, cholesterol, obesity, heart disease, kidney disease,
  chronic kidney disease, ckd, copd, chronic obstructive pulmonary
  disease, osteoporosis, gout, epilepsy, migraine, allergy, eczema,
  psoriasis, anemia, liver disease, fatty liver, ulcer, gastritis, acid
  reflux, gerd, depression, anxiety, mental illness, bronchial asthma,
  high blood pressure, coronary artery disease, stroke history, heart
  failure, arrhythmia, insomnia, constipation.
- **Prenatal** (5): pregnant, pregnancy, prenatal, antenatal, maternal.
- **Pediatric** (5): infant, child, baby, newborn, toddler.

(Sums to 131 raw entries; `_build_feature_keywords()` de-duplicates by
normalized lowercase text, yielding the 129 unique keywords confirmed in
the loaded `health_classifier_weights.json`.)

### Target Variables — `y` (two outputs, multi-task)

| Output | Classes | Values |
|---|---|---|
| `category_output` (6-way softmax) | 6 | `Communicable Disease`, `Non-Communicable Disease`, `Emergency`, `Routine Checkup`, `Prenatal Care`, `Pediatric Care` |
| `severity_output` (4-way softmax) | 4 | `Low`, `Medium`, `High`, `Critical` |

Both heads share the same `Dense(128)→Dense(64)→Dense(32)` trunk and are
trained jointly (`train_model/train_health_classifier.py: build_model()`).

---

## Rule-based component inputs (not trained-model variables)

These are not `X`/`y` pairs of a statistical model — they are the inputs
a deterministic function reads. Included here because the task requires
every variable actually used in classification to be documented.

### `backend/app/health_category_service.py: suggest_health_category()`

| Variable | Type | Source | Role |
|---|---|---|---|
| `recognized_conditions` | `list[str]` | Explicit condition names a BHW typed, matched against the RF's 100-class disease vocabulary (`predict.recognize_diseases()`) | Primary classification input |
| `recognized_symptoms` | `list[str]` | Symptom names matched against the RF's 229-feature vocabulary (`predict.recognize_symptoms()`) | Secondary classification input, used only if no condition matched |

### `HealthAIClassifier._determineSeverity()` (rule-based fallback path only)

Grouped by category, per the task's requested grouping:

**Vital signs:**

| Variable | Source field(s) | Effect |
|---|---|---|
| Systolic/diastolic blood pressure | `details` (regex `BP: sys/dia`) or direct `bp` field | +1 or +2 to severity score at defined thresholds (§20 of `AI_ALGORITHM_QA.md`) |
| Temperature | `details` (regex `Temp: x`) or direct `temp` field | +1 or +2 at defined thresholds |

**Demographics/risk factors:**

| Variable | Source field(s) | Effect |
|---|---|---|
| Prenatal risk level | `healthData['riskLevel']` | +1 (moderate) or +3 (high); only applied when category is "Prenatal Care" |
| Age | `healthData['age']` | Affects **category** scoring (boosts Non-Communicable for age > 40, Pediatric for age < 18) — not read by the severity function itself |

**Clinical observations:**

| Variable | Source field(s) | Effect |
|---|---|---|
| Previous complications / pre-existing conditions | `previousComplications`, `preExistingConditions` | +1 if either is non-empty (Prenatal Care only) |
| Severity keywords in free text | `symptoms`, `preExistingConditions`, `previousComplications` — checked for "severe", "acute", "intense", "unbearable", "extreme" | +1 per keyword found |

**AI-derived values:**

| Variable | Source | Effect |
|---|---|---|
| Assigned category | Output of this same classifier's category step | If `"Emergency"`, severity is forced directly to `"Critical"`, bypassing the point score |

Final mapping: score `≥4 → Critical`, `≥2 → High`, `≥1 → Medium`, else `Low`.

---

## Summary

| | Random Forest | On-device neural net | Rule engines |
|---|---|---|---|
| `X` | 229 binary symptom features | 200-length vector (age, 50 hashed keyword buckets, 4 vitals) | `recognized_conditions`/`recognized_symptoms` (guidance); vitals/riskLevel/keywords (severity) |
| `y` | `diseases` (100 classes) | `category` (6 classes) + `severity` (4 classes) | `suggestedHealthCategory` (4 values) / `severity` (4 values) — computed, not learned |
| Learned from data? | Yes | Yes | No — fixed rules |
