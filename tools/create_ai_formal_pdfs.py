from __future__ import annotations

from html import escape
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "formal_ai_documents"
OUT.mkdir(exist_ok=True)

CSS = r'''
@page { size: A4; margin: 25.4mm; }
* { box-sizing: border-box; }
body { font-family: "Times New Roman", Times, serif; color: #000; background: #fff; font-size: 12pt; line-height: 1.6; margin: 0; }
.cover { min-height: 245mm; page-break-after: always; display: flex; flex-direction: column; justify-content: center; }
.brand { color: #000; font-weight: 700; letter-spacing: 1.6px; font-size: 14pt; text-align: center; margin-bottom: 22px; }
h1 { color: #000; font-size: 22pt; line-height: 1.1; margin: 0 0 10px; text-align: center; }
.subtitle { color: #000; font-size: 12pt; text-align: center; margin: 0 auto 28px; max-width: 160mm; }
.doc-meta { border-collapse: collapse; width: 150mm; margin: 0 auto; font-size: 11pt; }
.doc-meta td { border: 1px solid #000; padding: 8px 10px; }
.doc-meta td:first-child { background: #fff; color: #000; font-weight: 700; width: 35mm; }
.cover-note { color: #000; font-size: 10pt; font-style: italic; text-align: center; margin: 25px auto 0; max-width: 160mm; }
h2 { color: #000; font-size: 15pt; line-height: 1.15; margin: 18px 0 7px; border-bottom: 1px solid #000; padding-bottom: 4px; page-break-after: avoid; }
h3 { color: #000; font-size: 12pt; margin: 12px 0 5px; page-break-after: avoid; }
p { margin: 0 0 10px; text-align: justify; }
ul { margin: 3px 0 12px 25px; padding: 0; }
li { margin: 0 0 5px; }
.callout { border: 1px solid #000; background: #fff; padding: 10px 12px; margin: 10px 0 12px; page-break-inside: avoid; }
.callout.warn, .callout.danger, .callout.good { background: #fff; border-color: #000; }
.callout strong { color: #000; }
table { border-collapse: collapse; width: 100%; margin: 8px 0 14px; page-break-inside: auto; }
thead { display: table-header-group; }
tr { page-break-inside: avoid; }
th { background: #000; color: #fff; font-weight: 700; text-align: left; padding: 7px 7px; font-size: 10pt; }
td { border: 1px solid #000; padding: 6px 7px; vertical-align: top; font-size: 10pt; }
tbody tr:nth-child(even) td { background: #fff; }
td.num, th.num { text-align: center; }
.formula { border: 1px solid #000; background: #fff; padding: 9px 11px; margin: 8px 0 12px; page-break-inside: avoid; }
.formula-title { color: #000; font-weight: 700; margin-bottom: 4px; }
pre { font-family: "Courier New", Courier, monospace; white-space: pre-wrap; font-size: 10pt; line-height: 1.35; margin: 0 0 4px; }
.note { color: #000; font-size: 10pt; font-style: italic; }
.small { font-size: 10pt; color: #000; }
.path { font-family: "Courier New", Courier, monospace; font-size: 10pt; color: #000; }
.footer-note { border-top: 1px solid #000; margin-top: 18px; padding-top: 7px; color: #000; font-size: 9pt; }
a { color: #000; text-decoration: underline; }
'''


def doc_html(title: str, subtitle: str, doc_id: str, body: str) -> str:
    return f'''<!doctype html>
<html><head><meta charset="utf-8"><title>{escape(title)}</title><style>{CSS}</style></head>
<body>
<section class="cover">
  <div class="brand">AI-DSUHIS</div>
  <h1>{escape(title)}</h1>
  <p class="subtitle">{escape(subtitle)}</p>
  <table class="doc-meta"><tbody>
    <tr><td>Document ID</td><td>{escape(doc_id)}</td></tr>
    <tr><td>Version</td><td>1.0</td></tr>
    <tr><td>Effective date</td><td>27 August 2026</td></tr>
    <tr><td>Status</td><td>Current repository implementation and verified evidence</td></tr>
  </tbody></table>
  <p class="cover-note">Prepared from the current source code, generated reports, model artifacts, and validation documentation in the shared repository.</p>
</section>
{body}
<div class="footer-note">AI-DSUHIS | {escape(doc_id)} | Version 1.0 | 27 August 2026</div>
</body></html>'''


def section(title: str, body: str) -> str:
    return f'<h2>{title}</h2>\n{body}'


def p(text: str) -> str:
    return f'<p>{text}</p>'


def bullets(items: list[str]) -> str:
    return '<ul>' + ''.join(f'<li>{item}</li>' for item in items) + '</ul>'


def callout(label: str, text: str, kind: str = '') -> str:
    return f'<div class="callout {kind}"><strong>{label}:</strong> {text}</div>'


def table(headers: list[str], rows: list[list[str]]) -> str:
    h = ''.join(f'<th>{x}</th>' for x in headers)
    r = ''.join('<tr>' + ''.join(f'<td>{x}</td>' for x in row) + '</tr>' for row in rows)
    return f'<table><thead><tr>{h}</tr></thead><tbody>{r}</tbody></table>'


def formula(title: str, expression: str, note: str = '') -> str:
    extra = f'<div class="note">{note}</div>' if note else ''
    return f'<div class="formula"><div class="formula-title">{title}</div><pre>{expression}</pre>{extra}</div>'


def data_analysis_body() -> str:
    body = section('Abstract', p('This report presents the data-analysis methodology used to evaluate the AI-DSUHIS health-classification components. It documents the verified dataset, variable encoding, preprocessing, leakage-safe evaluation design, statistical results, and operational limitations. The report distinguishes the active decision-support workflow from the offline Random Forest artifact so that evaluation metrics are not misrepresented as clinical accuracy.') + p('<strong>Keywords:</strong> data analysis; supervised classification; Random Forest; symptom features; group-safe evaluation; decision support.'))
    body += section('1. Purpose and scope', p('This document defines the data analysis performed for the AI-DSUHIS project and separates offline model evaluation from the live product workflow. It is based on the current repository artifacts as of 27 August 2026. The analysis describes what the data contains, how it is prepared, how the offline Random Forest is evaluated, and what the active application actually uses [R1, R2].') + callout('Accuracy statement', 'The verified offline model result is 89.3399% top-1 held-out agreement. The project accuracy target is 95%-98%; the minimum target was not achieved. This is dataset performance, not clinical diagnostic accuracy [R1, R6].', 'warn'))
    body += section('2. System paths covered by this analysis', table(['System component', 'Current role', 'Data-analysis status'], [
        ['FastAPI POST /guidance', 'Active remote product path; retrieves Firestore-authored symptom guidance and filters medication/prescription wording.', 'Does not call the Random Forest and does not return a disease label, probability, or Top-3 diagnosis list.'],
        ['Flutter HealthAIClassifier', 'Active local/offline decision-support path; deterministic keyword, structured-field, age, and vital-sign rules.', 'No verified held-out accuracy percentage is claimed for this rule-based path.'],
        ['backend/models/disease_model.pkl', 'Offline Random Forest artifact.', 'Trained and evaluated on the 93,993-record dataset; the /predict route is intentionally disabled.'],
        ['assets/models/health_classifier_weights.json', 'Portable neural-network artifact retained for experimentation/documentation.', 'Training provenance and held-out production metrics are not verified; not the default classifier.'],
    ]))
    body += section('3. Dataset description', table(['Item', 'Verified value', 'Interpretation'], [
        ['Raw source', '96,088 rows', 'Source file: <span class="path">backend/dataset/raw/Diseases_and_Symptoms_dataset.csv</span> [R3].'],
        ['Usable processed records', '93,993', 'Records retained after structural preprocessing and exact duplicate removal.'],
        ['Input features', '228', 'Binary symptom-presence variables.'],
        ['Target', '<span class="path">diseases</span>', 'Categorical disease label used as y.'],
        ['Disease classes', '100', 'All 100 classes remain after the pipeline quality gate.'],
        ['Feature-vector groups', '88,878', 'Unique 228-bit symptom vectors.'],
        ['Conflicting groups', '4,140 groups / 9,255 rows', 'The same symptom vector is associated with different disease labels.'],
        ['Project record target', '150,000-200,000', 'Not met; legitimate shortfall to the minimum is 56,007 records.'],
    ]))
    body += p('The source provenance sidecar is <span class="path">backend/dataset/processed/row_provenance.csv</span> [R4]. The current report records no synthetic padding, no fabricated records, and no relabeling to inflate performance [R6].')
    body += section('4. Variables and data encoding', p('The offline Random Forest uses the following supervised-learning structure:') + formula('Independent variables', 'X = [x1, x2, ..., x228], where xj in {0, 1}', 'Each xj indicates whether one normalized symptom is present (1) or absent/not reported (0).') + formula('Target variable', 'y = diseases, a categorical variable with 100 disease classes', 'The original disease-name strings are used as the class labels; no clinical measurement is implied by the label.') + table(['Variable group', 'Type / encoding', 'Used by'], [
        ['Normalized symptoms', '228 uint8 binary columns; values only 0 or 1.', 'Offline Random Forest.'],
        ['Age', 'Available in application workflows; not present in the offline RF training dataset.', 'Local/on-device classifier only.'],
        ['Temperature, blood pressure, heart rate', 'Available in application workflows; not present in the offline RF training dataset.', 'Local/on-device classifier and rule logic only.'],
        ['Pregnancy/history fields', 'Available in application workflows; no paired RF labels in the training source.', 'Local rule-based decision support only.'],
        ['diseases', 'String categorical target; 100 classes.', 'Offline Random Forest target y.'],
    ]))
    body += section('5. Data preprocessing and quality analysis', bullets([
        'Validate that a disease target exists, feature names are unique, and feature values are binary.',
        'Remove empty or invalid disease labels before training.',
        'Normalize configured symptom aliases and disease aliases.',
        'Remove exact duplicate rows; 2,095 were removed from the raw source before the current processed count.',
        'Collapse the literal duplicate raw symptom columns regurgitation and regurgitation.1 into one logical feature, producing 228 inputs.',
        'Preserve row-level provenance for every retained processed row.',
        'Measure identical-vector conflicts and near-neighbor patterns diagnostically; do not silently delete them.',
    ]) + table(['Quality check', 'Result', 'Meaning'], [
        ['Missing cells', '0', 'No missing feature/target cells in the verified processed dataset.'],
        ['Blank targets', '0', 'No blank disease labels remain.'],
        ['Exact duplicate rows', '0 remaining', 'Duplicate removal completed before model evaluation.'],
        ['Constant features', '0', 'No feature is constant across all retained rows.'],
        ['Near-zero-variance features', '0', 'No configured feature-quality removal was triggered.'],
        ['All feature values binary', 'True', 'Every input value is 0 or 1.'],
        ['Train/test exact-vector overlap', '0 groups', 'Identical input vectors were kept on one side of the evaluation boundary.'],
    ]))
    body += p('<span class="small">Preprocessing, quality gates, duplicate handling, and provenance are implemented and documented in [R5, R6].</span>')
    body += section('6. Exploratory and diagnostic analysis', p('The class distribution is mildly to moderately imbalanced. Class sizes range from 567 to 1,219 records, approximately a 2.15:1 ratio. The Random Forest therefore uses class_weight=balanced_subsample. No class was removed to improve the aggregate score [R1, R6].') + p('The most important measured limitation is label ambiguity. There are 4,140 exact 228-symptom vectors that map to multiple disease labels. The majority-label upper bound is computed by selecting the most frequent label within each identical vector group [R7]:') + formula('Empirical feature-representation ceiling', 'Ceiling = sum_g max_c count(y=c | vector=g) / n\n        = 88,878 / 93,993\n        = 94.5581%', 'This is an upper bound for this exact feature representation and dataset; it is not a clinical performance guarantee [R7].') + p('The largest observed confusion patterns include infectious versus noninfectious gastroenteritis, cystitis versus temporary or benign blood in urine, cholecystitis versus gallstone, personality disorder versus schizophrenia, and COPD versus asthma/acute bronchitis. These findings indicate missing discriminating clinical information rather than a simple removable software defect [R7].'))
    body += section('7. Model-training and evaluation design', p('The offline model is a RandomForestClassifier with the following current configuration:') + table(['Parameter', 'Current value'], [
        ['n_estimators', '200'], ['criterion', 'entropy'], ['max_depth', '28'], ['min_samples_split', '4'], ['min_samples_leaf', '2'], ['max_features', 'log2'], ['class_weight', 'balanced_subsample'], ['bootstrap', 'True'], ['random_state', '42'],
    ]) + p('Evaluation uses the first fold of StratifiedGroupKFold(n_splits=5), with groups defined by identical feature-vector identity. This prevents the same exact symptom presentation from appearing in both training and test sets. The held-out test set is not used for model selection.') + p('A five-fold group-safe cross-validation run is performed only within the training partition as a robustness check. It does not replace the locked held-out test result.'))
    body += section('8. Verified evaluation results', table(['Metric', 'Formula basis', 'Current result'], [
        ['Top-1 accuracy', 'Correct top-1 predictions / 18,799 test records', '16,795 / 18,799 = 89.3399%'],
        ['Top-2 coverage', 'True label in two highest-ranked classes / n', '18,149 / 18,799 = 96.5424%'],
        ['Top-3 coverage', 'True label in three highest-ranked classes / n', '18,518 / 18,799 = 98.5052%'],
        ['Weighted precision', 'Support-weighted mean of per-class precision', '89.8701%'],
        ['Weighted recall', 'Support-weighted mean of per-class recall', '89.3399%'],
        ['Weighted F1', 'Support-weighted mean of per-class F1', '89.3328%'],
        ['Macro precision', 'Unweighted mean of 100 class precisions', '89.1112%'],
        ['Macro recall / balanced accuracy', 'Unweighted mean of 100 class recalls', '89.6946%'],
        ['Macro F1', 'Unweighted mean of 100 class F1 values', '89.1264%'],
        ['Training-only CV mean accuracy', 'Mean of five training-partition fold accuracies', '89.1082%'],
    ]) + callout('Interpretation', 'Top-2 and Top-3 are coverage measures, not proof that the system has identified a single correct diagnosis. The model probability score is not a calibrated medical likelihood [R7].', 'danger'))
    body += section('9. Limitations and release interpretation', bullets([
        'The 150,000-record minimum is not met; only 93,993 legitimate training records are verified.',
        'The 95% minimum accuracy target is not met; the current held-out top-1 result is 89.3399%.',
        'The Random Forest uses symptoms only. Age, vital signs, laboratory findings, duration, examination findings, and history are not paired with the offline disease labels.',
        'The dataset publisher, collection method, geographic representativeness, and clinical labeling process are not independently verified in this repository.',
        'No component in the repository is clinically validated or a substitute for a licensed healthcare professional.',
        'The active /guidance path provides decision support and guidance, not automated diagnosis or prescription advice.',
    ]))
    body += section('10. Reproducibility and evidence locations', p('The analysis is reproducible from the checked-in pipeline and artifacts. The following files are the evidence sources for this report [R1, R5, R6]:') + bullets([
        '<span class="path">backend/dataset/processed/merged_dataset.csv</span> - generated training table.',
        '<span class="path">backend/dataset/processed/row_provenance.csv</span> - row-level source mapping.',
        '<span class="path">backend/app/train.py</span> - model construction, group-safe split, training, and metrics.',
        '<span class="path">backend/scripts/verify_ai_requirements.py</span> - current verification procedure.',
        '<span class="path">backend/reports/ai_requirements_verification.json</span> - authoritative current counts and metrics.',
        '<span class="path">docs/AI_VALIDATION_REPORT.md</span> - canonical safety and validation summary.',
        '<span class="path">docs/AI_ACCURACY_GAP_ANALYSIS.md</span> - ambiguity, error, and ceiling analysis.',
        '<span class="path">docs/AI_WORKFLOW.md</span> and <span class="path">backend/README.md</span> - active product-path behavior.',
    ]) + p('<span class="small">This report should be updated whenever the dataset, model artifact, feature contract, or active AI workflow changes.</span>'))
    body += section('11. References', p('[R1] <span class="path">backend/reports/ai_requirements_verification.json</span>. Current machine-readable counts, split, metrics, and status.') + p('[R2] <span class="path">docs/AI_WORKFLOW.md</span>; <span class="path">backend/README.md</span>. Active product workflow and endpoint behavior.') + p('[R3] <span class="path">backend/dataset/raw/Diseases_and_Symptoms_dataset.csv</span>. Raw dataset artifact.') + p('[R4] <span class="path">backend/dataset/processed/row_provenance.csv</span>. Row-level provenance artifact.') + p('[R5] <span class="path">backend/app/train.py</span>; <span class="path">backend/scripts/merge_datasets.py</span>. Preprocessing, model training, and evaluation implementation.') + p('[R6] <span class="path">docs/DATASET_PROVENANCE.md</span>; <span class="path">DATASET_QUALITY_REPORT.md</span>. Dataset provenance and quality analysis.') + p('[R7] <span class="path">docs/AI_VALIDATION_REPORT.md</span>; <span class="path">docs/AI_ACCURACY_GAP_ANALYSIS.md</span>; <span class="path">backend/app/evaluation_metrics.py</span>. Canonical validation, diagnostic analysis, and metric definitions.') + p('[E1] <a href="https://www.kaggle.com/datasets/behzadhassan/sympscan-symptomps-to-disease">Kaggle: SympScan - Symptomps to Disease</a>. Public dataset page identified by the repository provenance review.'))
    return body


def formula_body() -> str:
    body = section('Abstract', p('This specification defines the mathematical and deterministic formulas used or evaluated in AI-DSUHIS. It records the active Flutter rule-based category and severity formulas, the backend guidance-routing logic, the offline Random Forest equations, the experimental portable neural-network equations, and the evaluation metrics. Each formula is explicitly tied to the current implementation and is bounded by the system safety statement that outputs are decision support rather than diagnosis.') + p('<strong>Keywords:</strong> rule-based classification; Random Forest; neural network; confidence; severity scoring; evaluation metrics.'))
    body += section('1. Purpose and implementation status', p('This document records the formulas and decision rules implemented or evaluated in AI-DSUHIS. It distinguishes the active rule-based classifier and guidance rules from the offline Random Forest evaluation model and the experimental portable neural network. The formulas below are written to match the current source code and generated reports [R1, R2, R3].') + callout('Active-path statement', 'The Flutter classify() method currently uses the deterministic rule-based classifier by default. The FastAPI /guidance endpoint uses recognition and Firestore guidance lookup; it does not call the Random Forest. The offline Random Forest and portable neural network must not be described as the active clinical diagnosis engine [R2, R3].', 'good'))
    body += section('2. Notation', table(['Symbol', 'Meaning'], [
        ['x', 'One input record.'], ['Kc', 'Number of distinct matched, non-negated keywords for category c.'], ['Sc', 'Rule-based score for category c.'], ['I(condition)', 'Indicator: 1 when condition is true, otherwise 0.'], ['T', 'Sum of all six category scores.'], ['Q', 'Rule-based severity score.'], ['B', 'Number of Random Forest trees; B = 200.'], ['pc', 'Model probability assigned to class c.'], ['n', 'Number of evaluated records.'],
    ]))
    body += section('3. Active Flutter rule-based category formulas', p('Before scoring, the classifier lowercases text, normalizes hyphens and whitespace, applies a fixed spelling/abbreviation dictionary, matches whole words or phrases, allows a simple plural s, and ignores a match when a narrow negation cue appears immediately before it. Each distinct matched keyword contributes 1.5 points [R3].') + formula('Keyword score', 'KeywordScore_c = 1.5 * K_c', 'Examples of negation cues include no, denies, without, not, negative for, and ruled out [R3].') + formula('Emergency category', 'S_E = 1.5*K_E + 5*V_E\nV_E = 3*I(BP emergency)\n    + 2*I(temperature emergency)\n    + 2*I(heart-rate emergency)', 'BP emergency: systolic >180 or <90, or diastolic >120 or <60. Temperature emergency: >40 C or <35 C. Heart-rate emergency: >120 bpm or <50 bpm [R3]. These thresholds are implementation rules, not a diagnosis.') + formula('Communicable Disease', 'S_C = 1.5*K_C') + formula('Non-Communicable Disease', 'S_N = (1.5*K_N + V_N) * A\nV_N = 3.0 if BP >=140/90 range\n      1.5 if BP >=130/80 range\n      0 otherwise\nA = 1.3 if age >40, otherwise 1.0', 'The implementation applies the chronic blood-pressure signal before the age multiplier. The BP signal is below the emergency threshold and is intended as a chronic-risk signal [R3, E2].') + formula('Prenatal Care', 'S_P = 1.5*K_P + 2*F_P\n      + 3*I(riskLevel is low/moderate/high risk)', 'F_P is the count of populated structured prenatal fields among gravida, para, lmp, edd, gestationalAge, aog, fh, dhb, and tcb [R3].') + formula('Pediatric Care', 'S_child = 1.5*K_child + 2*I(age <18)') + formula('Routine Checkup', 'S_R = 0.5', 'This is the fixed fallback floor when no stronger category signal is present.'))
    body += section('4. Category selection and safety rules', formula('Winning category', 'category = argmax_c S_c') + bullets([
        'If scores are exactly tied, Emergency wins the tie.',
        'If Emergency has a positive score but another category leads by less than 1.0 point, the result is overridden to Emergency as a safety-margin rule.',
        'The matched keywords and observable input fields are returned as decision-support evidence for human review.',
    ]))
    body += section('5. Rule-based confidence formula', formula('Total category score', 'T = S_E + S_C + S_N + S_P + S_child + S_R') + formula('Normal confidence', 'confidence(c) = S_c / T, when T > 0.501') + formula('No-evidence confidence', 'confidence(c) = 0.1 * (S_c / T), when T <= 0.501 and T > 0\nconfidence(c) = 0, when T <= 0', 'The 0.5 Routine Checkup floor is not clinical evidence. The low-confidence branch prevents the fallback category from appearing artificially certain.') + callout('Meaning of confidence', 'This is a score share or dominance measure for the rule engine. It is not a calibrated probability, diagnosis certainty, or treatment recommendation.', 'warn'))
    body += section('6. Active rule-based severity formula', p('Emergency category results are immediately assigned Critical severity. Otherwise, the classifier accumulates Q from the available details and structured fields [R3].') + formula('Blood-pressure contribution from details', 'Q_BP = 2 if systolic >160 or <90\n       1 if systolic >140 or <100\n       0 otherwise') + formula('Blood-pressure contribution from direct prenatal bp field', 'Q_bp_direct = 2 if systolic >160 or <90 or diastolic >100\n              1 if systolic >140 or <100 or diastolic >90\n              0 otherwise') + formula('Temperature contribution', 'Q_temp = 2 if temperature >39.5 C\n         1 if temperature >38.0 C\n         0 otherwise') + formula('Prenatal contribution', 'Q_prenatal = 3*I(high risk) + 1*I(moderate risk)\n              + 1*I(previous complications or pre-existing conditions present)\n              + 3*I(prenatal danger sign present)', 'Danger-sign examples include vaginal bleeding, convulsions, reduced/decreased/no fetal movement, and corresponding baby-movement wording [R3, E3].') + formula('Text caution contribution', 'Q_text = number of matched severe/acute/intense/unbearable/extreme terms\n         + 2*I(chest discomfort or chest tightness)') + formula('Severity decision', 'Q = Q_BP + Q_bp_direct + Q_temp + Q_prenatal + Q_text\nCritical if Q >=4; High if Q >=2; Medium if Q >=1; Low if Q =0', 'If category = Emergency, severity = Critical before the score thresholds are applied.'))
    body += section('7. Backend /guidance category rule formula', p('The active FastAPI guidance service is a conservative administrative routing rule, not a disease-prediction formula. It first normalizes explicit conditions and symptoms, then applies this precedence [R4]:') + table(['Condition', 'Output', 'Basis / review behavior'], [
        ['Unmapped explicit condition exists', 'Needs Clinical Review', 'Highest caution; categoryRequiresReview = true.'],
        ['Communicable and non-communicable explicit conditions both exist', 'Mixed', 'Mixed explicit conditions; review required.'],
        ['Communicable explicit condition exists', 'Communicable', 'Explicit condition mapping; no category review flag for this basis.'],
        ['Non-communicable explicit condition exists', 'Non-Communicable', 'Explicit condition mapping; no category review flag for this basis.'],
        ['Both symptom groups match', 'Mixed', 'Mixed symptom keyword mapping; review required.'],
        ['Communicable symptom matches', 'Communicable', 'Symptom keyword mapping; review required.'],
        ['Non-communicable symptom matches', 'Non-Communicable', 'Symptom keyword mapping; review required.'],
        ['No classifiable input', 'Needs Clinical Review', 'No classifiable input; review required.'],
    ]) + p('After this routing, the service retrieves supportive guidance from Firestore. It does not return a disease label, Random Forest probability, or Top-3 prediction.'))
    body += section('8. Offline Random Forest prediction formula', p('The offline disease model receives x in {0,1}^228 and produces class probabilities from 200 decision trees [R5, R6].') + formula('Random Forest class probability', 'P(y=c | x) = (1/B) * sum from b=1 to B I(h_b(x) = c), with B=200') + formula('Random Forest prediction', 'predicted_disease = argmax_c P(y=c | x)') + p('The current configuration is RandomForestClassifier(criterion=entropy, max_depth=28, min_samples_split=4, min_samples_leaf=2, max_features=log2, class_weight=balanced_subsample, bootstrap=True, random_state=42, n_estimators=200). This model is trained and evaluated but /predict is not registered in the active API [R2, R5].'))
    body += section('9. Experimental portable neural-network formula', p('The portable model is retained as a loadable artifact but is not the default path in classify(). Its 200-element input vector is constructed as follows [R7]:') + table(['Feature positions', 'Construction'], [
        ['0', 'age / 100.0'],
        ['1-50', 'Hashed keyword-presence buckets using FNV-1a 32-bit: index = 1 + (hash(keyword) mod 50). Collisions are possible.'],
        ['51', 'BP systolic / 200.0'], ['52', 'BP diastolic / 150.0'], ['53', 'Temperature in C / 42.0'], ['54', 'Heart rate / 200.0'], ['55-199', 'Reserved zeros in the current layout.'],
    ]) + formula('Shared neural-network trunk', 'h1 = ReLU(xW1 + b1)\nh2 = ReLU(h1W2 + b2)\nh3 = ReLU(h2W3 + b3)', 'Layer sizes are Dense(128), Dense(64), and Dense(32), with dropout during training between the first three dense layers.') + formula('Two output heads', 'p_category = softmax(h3W_category + b_category)\np_severity = softmax(h3W_severity + b_severity)\ncategory = argmax(p_category); severity = argmax(p_severity)', 'Category output has 6 classes; severity output has 4 classes.') + formula('Training loss', 'L = mean[-log p_category(correct_category) - log p_severity(correct_severity)]', 'The Keras model compiles two sparse-categorical-cross-entropy losses with equal default weighting. The checked-in artifact has no traceable production training manifest or verified held-out metrics.'))
    body += section('10. Evaluation formulas', p('The following definitions are implemented in the offline evaluation pipeline and statistical audit [R5, R8].') + formula('Top-1 accuracy', 'Accuracy = (1/n) * sum_i I(predicted_label_i = true_label_i)') + formula('Per-class precision and recall', 'Precision_c = TP_c / (TP_c + FP_c)\nRecall_c = TP_c / (TP_c + FN_c)') + formula('F1-score', 'F1_c = 2 * Precision_c * Recall_c / (Precision_c + Recall_c)') + formula('Weighted and macro averages', 'WeightedMetric = sum_c (support_c/n) * Metric_c\nMacroMetric = (1/C) * sum_c Metric_c, with C=100') + formula('Balanced accuracy', 'BalancedAccuracy = (1/C) * sum_c Recall_c') + formula('Top-k coverage', 'TopK = (1/n) * sum_i I(true_label_i is among the k highest-ranked probabilities_i)') + formula('Wilson 95% interval', 'p = x/n\ncentre = (p + z^2/(2n)) / (1 + z^2/n)\nmargin = z*sqrt(p(1-p)/n + z^2/(4n^2)) / (1 + z^2/n), z=1.96', 'Used for uncertainty around observed top-k proportions; it does not establish clinical validity.') + formula('Identical-vector ceiling', 'Ceiling = sum_g max_c count(label=c | exact input vector=g) / n') + formula('Calibration metrics', 'LogLoss = -mean(log p_true)\nBrier = mean(sum_c (p_c - one_hot_c)^2)\nECE = sum_bins (n_bin/n) * |bin_accuracy - bin_mean_confidence|', 'Lower log loss, Brier score, and ECE are better. Calibration is a probability-reliability measure, not a diagnosis-safety measure.'))
    body += section('11. Current verified results and correct interpretation', table(['Evaluation result', 'Value', 'Correct interpretation'], [
        ['Offline Random Forest top-1', '89.3399%', 'Agreement with held-out dataset labels.'],
        ['Offline Random Forest top-2', '96.5424%', 'True label appeared in the two highest-ranked classes; coverage, not ordinary accuracy.'],
        ['Offline Random Forest top-3', '98.5052%', 'True label appeared in the three highest-ranked classes; coverage, not a single diagnosis.'],
        ['Rule-based active Flutter path', 'No verified accuracy claim', 'Deterministic rules are active for offline decision support.'],
        ['Clinical validation', 'Not established', 'Qualified professional review and authenticated field testing remain open.'],
    ]) + callout('Safety boundary', 'AI output is decision support. Healthcare professionals remain responsible for final assessment, referral, treatment, and emergency decisions. The system does not prescribe medication.', 'danger'))
    body += section('12. Source-of-truth files', bullets([
        '<span class="path">lib/app/core/services/health_ai_classifier.dart</span> - active Flutter rule scoring, severity rules, confidence, and portable-model inference implementation.',
        '<span class="path">backend/app/health_category_service.py</span> - active backend category-routing rules.',
        '<span class="path">backend/app/train.py</span> - offline Random Forest training and evaluation.',
        '<span class="path">backend/app/evaluation_metrics.py</span> - metric definitions and statistical formulas.',
        '<span class="path">train_model/train_health_classifier.py</span> - portable neural-network feature extraction, architecture, and training loss.',
        '<span class="path">backend/reports/ai_requirements_verification.json</span> - authoritative current evaluation values.',
        '<span class="path">docs/AI_VALIDATION_REPORT.md</span> - validation, safety, and limitations.',
        '<span class="path">docs/AI_WORKFLOW.md</span> - active system workflow and path selection.',
    ]) + p('<span class="small">This formula specification should be revised whenever the source implementation changes. If a future trained model replaces the rule-based default, its training provenance, held-out evaluation, and production route must be documented before its metrics are presented as current.</span>'))
    body += section('13. References', p('[R1] <span class="path">backend/reports/ai_requirements_verification.json</span>. Current machine-readable evaluation evidence.') + p('[R2] <span class="path">docs/AI_WORKFLOW.md</span>; <span class="path">backend/README.md</span>. Active system paths and API behavior.') + p('[R3] <span class="path">lib/app/core/services/health_ai_classifier.dart</span>. Active Flutter classifier, category scores, confidence, and severity formulas.') + p('[R4] <span class="path">backend/app/health_category_service.py</span>. Active backend category-routing rules.') + p('[R5] <span class="path">backend/app/train.py</span>. Random Forest configuration, group-safe split, training, and evaluation.') + p('[R6] <span class="path">backend/app/evaluation_metrics.py</span>. Metric and statistical definitions.') + p('[R7] <span class="path">train_model/train_health_classifier.py</span>; <span class="path">AI_VARIABLE_DICTIONARY.md</span>. Portable model features, architecture, and variable encoding.') + p('[R8] <span class="path">docs/AI_VALIDATION_REPORT.md</span>; <span class="path">docs/AI_ACCURACY_GAP_ANALYSIS.md</span>. Canonical validation and interpretation.') + p('[E2] <a href="https://www.who.int/news-room/fact-sheets/detail/hypertension">World Health Organization. Hypertension fact sheet.</a> Accessed 27 August 2026. Supports the clinical context for blood-pressure categories; the application thresholds remain implementation rules.') + p('[E3] <a href="https://www.who.int/publications/i/item/WHO-MCA-19.02">World Health Organization. Exploratory meeting to review new evidence for IMCI danger signs.</a> Accessed 27 August 2026. Supports the documented pediatric danger-sign context.') + p('[E4] <a href="https://www.who.int/tools/your-life-your-health/life-phase/pregnancy--birth-and-after-childbirth/getting-the-health-services-you-need-during-pregnancy">World Health Organization. Getting the health services you need during pregnancy.</a> Accessed 27 August 2026. Supports the documented pregnancy danger-sign context.'))
    return body


def main() -> None:
    (OUT / 'AI_Data_Analysis_Report.html').write_text(doc_html('AI Data Analysis Report', 'Dataset, variables, preprocessing, evaluation design, results, and limitations', 'DA-001', data_analysis_body()), encoding='utf-8')
    (OUT / 'AI_Formula_Specification.html').write_text(doc_html('AI Formula Specification', 'Current decision-support rules, model equations, confidence calculation, and evaluation formulas', 'AF-001', formula_body()), encoding='utf-8')
    print(OUT / 'AI_Data_Analysis_Report.html')
    print(OUT / 'AI_Formula_Specification.html')


if __name__ == '__main__':
    main()
