from __future__ import annotations

from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "formal_ai_documents"
OUT.mkdir(exist_ok=True)

NAVY = "183B56"
BLUE = "2F6690"
LIGHT_BLUE = "EAF2F8"
PALE = "F5F8FA"
GRAY = "5B6570"
GREEN = "EAF6EF"
AMBER = "FFF5D6"
RED = "FDECEC"


def set_cell_shading(cell, fill: str):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=90, start=110, bottom=90, end=110):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for margin, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{margin}"))
        if node is None:
            node = OxmlElement(f"w:{margin}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_cell_border(cell, color="D5DDE5", size="6"):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    borders = tc_pr.first_child_found_in("w:tcBorders")
    if borders is None:
        borders = OxmlElement("w:tcBorders")
        tc_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        tag = f"w:{edge}"
        element = borders.find(qn(tag))
        if element is None:
            element = OxmlElement(tag)
            borders.append(element)
        element.set(qn("w:val"), "single")
        element.set(qn("w:sz"), size)
        element.set(qn("w:space"), "0")
        element.set(qn("w:color"), color)


def keep_with_next(paragraph):
    paragraph.paragraph_format.keep_with_next = True


def set_repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)


def set_font(run, name="Aptos", size=10.5, color=None, bold=False, italic=False):
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), name)
    run.font.size = Pt(size)
    run.bold = bold
    run.italic = italic
    if color:
        run.font.color.rgb = RGBColor.from_string(color)


def add_text(paragraph, text, *, bold=False, italic=False, color=None, size=10.5, name="Aptos"):
    run = paragraph.add_run(text)
    set_font(run, name=name, size=size, color=color, bold=bold, italic=italic)
    return run


def style_document(doc: Document, short_title: str, doc_id: str):
    section = doc.sections[0]
    section.top_margin = Inches(0.72)
    section.bottom_margin = Inches(0.68)
    section.left_margin = Inches(0.78)
    section.right_margin = Inches(0.78)
    section.header_distance = Inches(0.32)
    section.footer_distance = Inches(0.32)

    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = "Aptos"
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Aptos")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Aptos")
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = RGBColor.from_string("263238")
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.08

    for name, size, color in (("Title", 25, NAVY), ("Heading 1", 15, NAVY), ("Heading 2", 12, BLUE), ("Heading 3", 10.5, BLUE)):
        style = styles[name]
        style.font.name = "Aptos Display" if name in ("Title", "Heading 1") else "Aptos"
        style._element.rPr.rFonts.set(qn("w:ascii"), style.font.name)
        style._element.rPr.rFonts.set(qn("w:hAnsi"), style.font.name)
        style.font.size = Pt(size)
        style.font.color.rgb = RGBColor.from_string(color)
        style.font.bold = True
        style.paragraph_format.space_before = Pt(13 if name == "Heading 1" else 8)
        style.paragraph_format.space_after = Pt(5)
        style.paragraph_format.keep_with_next = True

    header = section.header
    hp = header.paragraphs[0]
    hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    add_text(hp, short_title, bold=True, color=BLUE, size=8.5)
    footer = section.footer
    fp = footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_text(fp, f"AI-DSUHIS | {doc_id} | Version 1.0 | 27 August 2026", color=GRAY, size=8)

    props = doc.core_properties
    props.author = "AI-DSUHIS Project Documentation"
    props.title = short_title
    props.subject = "Current AI system data analysis and formula documentation"
    props.comments = "Prepared from the current repository implementation and verified artifacts."


def add_cover(doc: Document, title: str, subtitle: str, doc_id: str, status: str):
    for _ in range(2):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_text(p, "AI-DSUHIS", bold=True, color=BLUE, size=13)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_text(p, title, bold=True, color=NAVY, size=26)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_text(p, subtitle, color=GRAY, size=12)
    doc.add_paragraph()
    table = doc.add_table(rows=4, cols=2)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    widths = [Inches(1.45), Inches(4.7)]
    rows = [
        ("Document ID", doc_id),
        ("Version", "1.0"),
        ("Effective date", "27 August 2026"),
        ("Status", status),
    ]
    for row, (label, value) in zip(table.rows, rows):
        for i, width in enumerate(widths):
            row.cells[i].width = width
            row.cells[i].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            set_cell_margins(row.cells[i])
            set_cell_border(row.cells[i])
        set_cell_shading(row.cells[0], LIGHT_BLUE)
        p0 = row.cells[0].paragraphs[0]
        add_text(p0, label, bold=True, color=NAVY, size=9.5)
        p1 = row.cells[1].paragraphs[0]
        add_text(p1, value, color=GRAY, size=9.5)
    doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_text(p, "Prepared from the current source code, generated reports, model artifacts, and validation documentation in the shared repository.", italic=True, color=GRAY, size=9)
    doc.add_page_break()


def add_heading(doc, text, level=1):
    p = doc.add_heading(text, level=level)
    keep_with_next(p)
    return p


def add_para(doc, text="", *, bold_lead=None, italic=False, color=None):
    p = doc.add_paragraph()
    if bold_lead and text.startswith(bold_lead):
        add_text(p, bold_lead, bold=True, color=NAVY)
        add_text(p, text[len(bold_lead):], italic=italic, color=color)
    else:
        add_text(p, text, italic=italic, color=color)
    return p


def add_bullets(doc, items, level=0):
    for item in items:
        p = doc.add_paragraph(style="List Bullet")
        p.paragraph_format.left_indent = Inches(0.25 + level * 0.2)
        p.paragraph_format.space_after = Pt(3)
        add_text(p, item, size=10.2)


def add_callout(doc, label, text, fill=LIGHT_BLUE):
    table = doc.add_table(rows=1, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = table.cell(0, 0)
    set_cell_shading(cell, fill)
    set_cell_border(cell, color="B7C8D5", size="8")
    set_cell_margins(cell, top=130, start=150, bottom=130, end=150)
    p = cell.paragraphs[0]
    add_text(p, f"{label}: ", bold=True, color=NAVY, size=10)
    add_text(p, text, size=10)
    doc.add_paragraph().paragraph_format.space_after = Pt(1)


def add_table(doc, headers, rows, widths=None, font_size=8.8, header_fill=NAVY):
    table = doc.add_table(rows=1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    header = table.rows[0]
    set_repeat_table_header(header)
    for i, text in enumerate(headers):
        cell = header.cells[i]
        if widths:
            cell.width = widths[i]
        set_cell_shading(cell, header_fill)
        set_cell_border(cell, color=header_fill, size="8")
        set_cell_margins(cell, top=100, start=100, bottom=100, end=100)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        add_text(p, text, bold=True, color="FFFFFF", size=font_size)
    for r_index, row_data in enumerate(rows):
        row = table.add_row()
        for i, value in enumerate(row_data):
            cell = row.cells[i]
            if widths:
                cell.width = widths[i]
            set_cell_shading(cell, "FFFFFF" if r_index % 2 == 0 else PALE)
            set_cell_border(cell)
            set_cell_margins(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = cell.paragraphs[0]
            if i == 0 and len(headers) > 2:
                p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            else:
                p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            add_text(p, str(value), size=font_size)
    doc.add_paragraph().paragraph_format.space_after = Pt(1)
    return table


def add_formula_box(doc, title, formula, note=None):
    table = doc.add_table(rows=1, cols=1)
    cell = table.cell(0, 0)
    set_cell_shading(cell, "F7FAFC")
    set_cell_border(cell, color="9FB7C7", size="8")
    set_cell_margins(cell, top=140, start=160, bottom=140, end=160)
    p = cell.paragraphs[0]
    add_text(p, title, bold=True, color=NAVY, size=10)
    p = cell.add_paragraph()
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after = Pt(2)
    add_text(p, formula, name="Courier New", size=9.4, color="1F2933")
    if note:
        p = cell.add_paragraph()
        add_text(p, note, italic=True, color=GRAY, size=8.8)
    doc.add_paragraph().paragraph_format.space_after = Pt(1)


def make_data_analysis():
    doc = Document()
    style_document(doc, "DATA ANALYSIS REPORT", "DA-001")
    add_cover(
        doc,
        "AI Data Analysis Report",
        "Dataset, variables, preprocessing, evaluation design, results, and limitations",
        "DA-001",
        "Current repository evidence; suitable for capstone documentation",
    )

    add_heading(doc, "1. Purpose and scope")
    add_para(doc, "This document defines the data analysis performed for the AI-DSUHIS project and separates offline model evaluation from the live product workflow. It is based on the current repository artifacts as of 27 August 2026. The analysis describes what the data contains, how it is prepared, how the offline Random Forest is evaluated, and what the active application actually uses.")
    add_callout(doc, "Accuracy statement", "The verified offline model result is 89.3399% top-1 held-out agreement. The project accuracy target is 95%-98%; the minimum target was not achieved. This is dataset performance, not clinical diagnostic accuracy.", AMBER)

    add_heading(doc, "2. System paths covered by this analysis")
    add_table(doc, ["System component", "Current role", "Data-analysis status"], [
        ("FastAPI POST /guidance", "Active remote product path; retrieves Firestore-authored symptom guidance and filters medication/prescription wording.", "Does not call the Random Forest and does not return a disease label, probability, or Top-3 diagnosis list."),
        ("Flutter HealthAIClassifier", "Active local/offline decision-support path; deterministic keyword, structured-field, age, and vital-sign rules.", "No verified held-out accuracy percentage is claimed for this rule-based path."),
        ("backend/models/disease_model.pkl", "Offline Random Forest artifact.", "Trained and evaluated on the 93,993-record dataset; the /predict route is intentionally disabled."),
        ("assets/models/health_classifier_weights.json", "Portable neural-network artifact retained for experimentation/documentation.", "Training provenance and held-out production metrics are not verified; not the default classifier."),
    ], [Inches(1.45), Inches(2.25), Inches(3.0)], 8.5)

    add_heading(doc, "3. Dataset description")
    add_table(doc, ["Item", "Verified value", "Interpretation"], [
        ("Raw source", "96,088 rows", "Source file: backend/dataset/raw/Diseases_and_Symptoms_dataset.csv."),
        ("Usable processed records", "93,993", "Records retained after structural preprocessing and exact duplicate removal."),
        ("Input features", "228", "Binary symptom-presence variables."),
        ("Target", "diseases", "Categorical disease label used as y."),
        ("Disease classes", "100", "All 100 classes remain after the pipeline quality gate."),
        ("Feature-vector groups", "88,878", "Unique 228-bit symptom vectors."),
        ("Conflicting groups", "4,140 groups / 9,255 rows", "The same symptom vector is associated with different disease labels."),
        ("Project record target", "150,000-200,000", "Not met; the legitimate shortfall to the minimum is 56,007 records."),
    ], [Inches(1.65), Inches(1.35), Inches(3.7)], 8.7)
    add_para(doc, "The source provenance sidecar is backend/dataset/processed/row_provenance.csv. The current report records no synthetic padding, no fabricated records, and no relabeling to inflate performance.")

    add_heading(doc, "4. Variables and data encoding")
    add_para(doc, "The offline Random Forest uses the following supervised-learning structure:")
    add_formula_box(doc, "Independent variables", "X = [x1, x2, ..., x228], where xj in {0, 1}", "Each xj indicates whether one normalized symptom is present (1) or absent/not reported (0).")
    add_formula_box(doc, "Target variable", "y = diseases, a categorical variable with 100 disease classes", "The original disease-name strings are used as the class labels; no clinical measurement is implied by the label.")
    add_table(doc, ["Variable group", "Type / encoding", "Used by"], [
        ("Normalized symptoms", "228 uint8 binary columns; values only 0 or 1.", "Offline Random Forest."),
        ("Age", "Available in application workflows; not present in the offline RF training dataset.", "Local/on-device classifier only."),
        ("Temperature, blood pressure, heart rate", "Available in application workflows; not present in the offline RF training dataset.", "Local/on-device classifier and rule logic only."),
        ("Pregnancy/history fields", "Available in application workflows; no paired RF labels in the training source.", "Local rule-based decision support only."),
        ("diseases", "String categorical target; 100 classes.", "Offline Random Forest target y."),
    ], [Inches(1.65), Inches(3.15), Inches(1.9)], 8.5)

    add_heading(doc, "5. Data preprocessing and quality analysis")
    add_bullets(doc, [
        "Validate that a disease target exists, that feature names are unique, and that feature values are binary.",
        "Remove empty or invalid disease labels before training.",
        "Normalize configured symptom aliases and disease aliases.",
        "Remove exact duplicate rows; 2,095 were removed from the raw source before the current processed count.",
        "Collapse the literal duplicate raw symptom columns regurgitation and regurgitation.1 into one logical feature, producing 228 inputs.",
        "Preserve row-level provenance for every retained processed row.",
        "Measure identical-vector conflicts and near-neighbor patterns diagnostically; do not silently delete them.",
    ])
    add_table(doc, ["Quality check", "Result", "Meaning"], [
        ("Missing cells", "0", "No missing feature/target cells in the verified processed dataset."),
        ("Blank targets", "0", "No blank disease labels remain."),
        ("Exact duplicate rows", "0 remaining", "Duplicate removal completed before model evaluation."),
        ("Constant features", "0", "No feature is constant across all retained rows."),
        ("Near-zero-variance features", "0", "No configured feature-quality removal was triggered."),
        ("All feature values binary", "True", "Every input value is 0 or 1."),
        ("Train/test exact-vector overlap", "0 groups", "Identical input vectors were kept on one side of the evaluation boundary."),
    ], [Inches(1.75), Inches(1.35), Inches(3.6)], 8.5)

    add_heading(doc, "6. Exploratory and diagnostic analysis")
    add_para(doc, "The class distribution is mildly to moderately imbalanced. Class sizes range from 567 to 1,219 records, approximately a 2.15:1 ratio. The Random Forest therefore uses class_weight=balanced_subsample. No class was removed to improve the aggregate score.")
    add_para(doc, "The most important measured limitation is label ambiguity. There are 4,140 exact 228-symptom vectors that map to multiple disease labels. The majority-label upper bound is computed by selecting the most frequent label within each identical vector group:")
    add_formula_box(doc, "Empirical feature-representation ceiling", "Ceiling = sum_g max_c count(y=c | vector=g) / n = 88,878 / 93,993 = 94.5581%", "This is an upper bound for this exact feature representation and dataset; it is not a clinical performance guarantee.")
    add_para(doc, "The largest observed confusion patterns include infectious versus noninfectious gastroenteritis, cystitis versus temporary or benign blood in urine, cholecystitis versus gallstone, personality disorder versus schizophrenia, and COPD versus asthma/acute bronchitis. These findings indicate missing discriminating clinical information rather than a simple removable software defect.")

    add_heading(doc, "7. Model-training and evaluation design")
    add_para(doc, "The offline model is a RandomForestClassifier with the following current configuration:")
    add_table(doc, ["Parameter", "Current value"], [
        ("n_estimators", "200"),
        ("criterion", "entropy"),
        ("max_depth", "28"),
        ("min_samples_split", "4"),
        ("min_samples_leaf", "2"),
        ("max_features", "log2"),
        ("class_weight", "balanced_subsample"),
        ("bootstrap", "True"),
        ("random_state", "42"),
    ], [Inches(2.2), Inches(4.5)], 9.0)
    add_para(doc, "Evaluation uses the first fold of StratifiedGroupKFold(n_splits=5), with groups defined by identical feature-vector identity. This prevents the same exact symptom presentation from appearing in both training and test sets. The held-out test set is not used for model selection.")
    add_para(doc, "A five-fold group-safe cross-validation run is performed only within the training partition as a robustness check. It does not replace the locked held-out test result.")

    add_heading(doc, "8. Verified evaluation results")
    add_table(doc, ["Metric", "Formula basis", "Current result"], [
        ("Top-1 accuracy", "Correct top-1 predictions / 18,799 test records", "16,795 / 18,799 = 89.3399%"),
        ("Top-2 coverage", "True label in two highest-ranked classes / n", "18,149 / 18,799 = 96.5424%"),
        ("Top-3 coverage", "True label in three highest-ranked classes / n", "18,518 / 18,799 = 98.5052%"),
        ("Weighted precision", "Support-weighted mean of per-class precision", "89.8701%"),
        ("Weighted recall", "Support-weighted mean of per-class recall", "89.3399%"),
        ("Weighted F1", "Support-weighted mean of per-class F1", "89.3328%"),
        ("Macro precision", "Unweighted mean of 100 class precisions", "89.1112%"),
        ("Macro recall / balanced accuracy", "Unweighted mean of 100 class recalls", "89.6946%"),
        ("Macro F1", "Unweighted mean of 100 class F1 values", "89.1264%"),
        ("Training-only CV mean accuracy", "Mean of five training-partition fold accuracies", "89.1082%"),
    ], [Inches(1.8), Inches(3.35), Inches(1.55)], 8.3)
    add_callout(doc, "Interpretation", "Top-2 and Top-3 are coverage measures, not proof that the system has identified a single correct diagnosis. The model's probability score is not a calibrated medical likelihood.", RED)

    add_heading(doc, "9. Limitations and release interpretation")
    add_bullets(doc, [
        "The 150,000-record minimum is not met; only 93,993 legitimate training records are verified.",
        "The 95% minimum accuracy target is not met; the current held-out top-1 result is 89.3399%.",
        "The Random Forest uses symptoms only. Age, vital signs, laboratory findings, duration, examination findings, and history are not paired with the offline disease labels.",
        "The dataset publisher, collection method, geographic representativeness, and clinical labeling process are not independently verified in this repository.",
        "No component in the repository is clinically validated or a substitute for a licensed healthcare professional.",
        "The active /guidance path provides decision support and guidance, not automated diagnosis or prescription advice.",
    ])

    add_heading(doc, "10. Reproducibility and evidence locations")
    add_para(doc, "The analysis is reproducible from the checked-in pipeline and artifacts. The following files are the evidence sources for this report:")
    add_bullets(doc, [
        "backend/dataset/processed/merged_dataset.csv - generated training table.",
        "backend/dataset/processed/row_provenance.csv - row-level source mapping.",
        "backend/app/train.py - model construction, group-safe split, training, and metrics.",
        "backend/scripts/verify_ai_requirements.py - current verification procedure.",
        "backend/reports/ai_requirements_verification.json - authoritative current counts and metrics.",
        "docs/AI_VALIDATION_REPORT.md - canonical safety and validation summary.",
        "docs/AI_ACCURACY_GAP_ANALYSIS.md - ambiguity, error, and ceiling analysis.",
        "docs/AI_WORKFLOW.md and backend/README.md - active product-path behavior.",
    ])
    add_para(doc, "This report should be updated whenever the dataset, model artifact, feature contract, or active AI workflow changes.", italic=True, color=GRAY)
    path = OUT / "AI_Data_Analysis_Report.docx"
    doc.save(path)
    return path


def make_formula_document():
    doc = Document()
    style_document(doc, "AI FORMULA SPECIFICATION", "AF-001")
    add_cover(
        doc,
        "AI Formula Specification",
        "Current decision-support rules, model equations, confidence calculation, and evaluation formulas",
        "AF-001",
        "Current repository implementation; formula reference",
    )

    add_heading(doc, "1. Purpose and implementation status")
    add_para(doc, "This document records the formulas and decision rules implemented or evaluated in AI-DSUHIS. It distinguishes the active rule-based classifier and guidance rules from the offline Random Forest evaluation model and the experimental portable neural network. The formulas below are written to match the current source code and generated reports.")
    add_callout(doc, "Active-path statement", "The Flutter classify() method currently uses the deterministic rule-based classifier by default. The FastAPI /guidance endpoint uses recognition and Firestore guidance lookup; it does not call the Random Forest. The offline Random Forest and portable neural network must not be described as the active clinical diagnosis engine.", GREEN)

    add_heading(doc, "2. Notation")
    add_table(doc, ["Symbol", "Meaning"], [
        ("x", "One input record."),
        ("K_c", "Number of distinct matched, non-negated keywords for category c."),
        ("S_c", "Rule-based score for category c."),
        ("I(condition)", "Indicator: 1 when condition is true, otherwise 0."),
        ("T", "Sum of all six category scores."),
        ("Q", "Rule-based severity score."),
        ("B", "Number of Random Forest trees; B = 200."),
        ("p_c", "Model probability assigned to class c."),
        ("n", "Number of evaluated records."),
    ], [Inches(1.7), Inches(5.0)], 9.0)

    add_heading(doc, "3. Active Flutter rule-based category formulas")
    add_para(doc, "Before scoring, the classifier lowercases text, normalizes hyphens and whitespace, applies a fixed spelling/abbreviation dictionary, matches whole words or phrases, allows a simple plural s, and ignores a match when a narrow negation cue appears immediately before it. Each distinct matched keyword contributes 1.5 points.")
    add_formula_box(doc, "Keyword score", "KeywordScore_c = 1.5 * K_c", "Examples of negation cues include no, denies, without, not, negative for, and ruled out.")
    add_formula_box(doc, "Emergency category", "S_E = 1.5*K_E + 5*V_E\nV_E = 3*I(BP emergency) + 2*I(temperature emergency) + 2*I(heart-rate emergency)", "BP emergency: systolic >180 or <90, or diastolic >120 or <60. Temperature emergency: >40 C or <35 C. Heart-rate emergency: >120 bpm or <50 bpm.")
    add_formula_box(doc, "Communicable Disease", "S_C = 1.5*K_C")
    add_formula_box(doc, "Non-Communicable Disease", "S_N = (1.5*K_N + V_N) * A\nV_N = 3.0 if BP >=140/90 range; 1.5 if BP >=130/80 range; otherwise 0\nA = 1.3 if age >40, otherwise 1.0", "The implementation applies the chronic blood-pressure signal before the age multiplier. The BP signal is below the emergency threshold and is intended as a chronic-risk signal.")
    add_formula_box(doc, "Prenatal Care", "S_P = 1.5*K_P + 2*F_P + 3*I(riskLevel is low/moderate/high risk)", "F_P is the count of populated structured prenatal fields among gravida, para, lmp, edd, gestationalAge, aog, fh, dhb, and tcb.")
    add_formula_box(doc, "Pediatric Care", "S_child = 1.5*K_child + 2*I(age <18)")
    add_formula_box(doc, "Routine Checkup", "S_R = 0.5", "This is the fixed fallback floor when no stronger category signal is present.")

    add_heading(doc, "4. Category selection and safety rules")
    add_formula_box(doc, "Winning category", "category = argmax_c S_c")
    add_bullets(doc, [
        "If scores are exactly tied, Emergency wins the tie.",
        "If Emergency has a positive score but another category leads by less than 1.0 point, the result is overridden to Emergency as a safety-margin rule.",
        "The matched keywords and observable input fields are returned as decision-support evidence for human review.",
    ])

    add_heading(doc, "5. Rule-based confidence formula")
    add_formula_box(doc, "Total category score", "T = S_E + S_C + S_N + S_P + S_child + S_R")
    add_formula_box(doc, "Normal confidence", "confidence(c) = S_c / T, when T > 0.501")
    add_formula_box(doc, "No-evidence confidence", "confidence(c) = 0.1 * (S_c / T), when T <= 0.501 and T > 0;\nconfidence(c) = 0, when T <= 0", "The 0.5 Routine Checkup floor is not clinical evidence. The low-confidence branch prevents the fallback category from appearing artificially certain.")
    add_callout(doc, "Meaning of confidence", "This is a score share or dominance measure for the rule engine. It is not a calibrated probability, diagnosis certainty, or treatment recommendation.", AMBER)

    add_heading(doc, "6. Active rule-based severity formula")
    add_para(doc, "Emergency category results are immediately assigned Critical severity. Otherwise, the classifier accumulates Q from the available details and structured fields.")
    add_formula_box(doc, "Blood-pressure contribution from details", "Q_BP = 2 if systolic >160 or <90;\n       1 if systolic >140 or <100;\n       0 otherwise")
    add_formula_box(doc, "Blood-pressure contribution from direct prenatal bp field", "Q_bp_direct = 2 if systolic >160 or <90 or diastolic >100;\n               1 if systolic >140 or <100 or diastolic >90;\n               0 otherwise")
    add_formula_box(doc, "Temperature contribution", "Q_temp = 2 if temperature >39.5 C;\n         1 if temperature >38.0 C;\n         0 otherwise")
    add_formula_box(doc, "Prenatal contribution", "Q_prenatal = 3*I(high risk) + 1*I(moderate risk)\n              + 1*I(previous complications or pre-existing conditions present)\n              + 3*I(prenatal danger sign present)", "Danger-sign examples include vaginal bleeding, convulsions, reduced/decreased/no fetal movement, and corresponding baby-movement wording.")
    add_formula_box(doc, "Text caution contribution", "Q_text = number of matched severe/acute/intense/unbearable/extreme terms\n         + 2*I(chest discomfort or chest tightness)")
    add_formula_box(doc, "Severity decision", "Q = Q_BP + Q_bp_direct + Q_temp + Q_prenatal + Q_text\nCritical if Q >=4; High if Q >=2; Medium if Q >=1; Low if Q =0", "If category = Emergency, severity = Critical before the score thresholds are applied.")

    add_heading(doc, "7. Backend /guidance category rule formula")
    add_para(doc, "The active FastAPI guidance service is a conservative administrative routing rule, not a disease-prediction formula. It first normalizes explicit conditions and symptoms, then applies this precedence:")
    add_table(doc, ["Condition", "Output", "Basis / review behavior"], [
        ("Unmapped explicit condition exists", "Needs Clinical Review", "Highest caution; categoryRequiresReview = true."),
        ("Communicable and non-communicable explicit conditions both exist", "Mixed", "Mixed explicit conditions; review required."),
        ("Communicable explicit condition exists", "Communicable", "Explicit condition mapping; no category review flag for this basis."),
        ("Non-communicable explicit condition exists", "Non-Communicable", "Explicit condition mapping; no category review flag for this basis."),
        ("Both symptom groups match", "Mixed", "Mixed symptom keyword mapping; review required."),
        ("Communicable symptom matches", "Communicable", "Symptom keyword mapping; review required."),
        ("Non-communicable symptom matches", "Non-Communicable", "Symptom keyword mapping; review required."),
        ("No classifiable input", "Needs Clinical Review", "No classifiable input; review required."),
    ], [Inches(2.35), Inches(1.55), Inches(3.15)], 8.1)
    add_para(doc, "After this routing, the service retrieves supportive guidance from Firestore. It does not return a disease label, Random Forest probability, or Top-3 prediction.")

    add_heading(doc, "8. Offline Random Forest prediction formula")
    add_para(doc, "The offline disease model receives x in {0,1}^228 and produces class probabilities from 200 decision trees.")
    add_formula_box(doc, "Random Forest class probability", "P(y=c | x) = (1/B) * sum from b=1 to B I(h_b(x) = c), with B=200")
    add_formula_box(doc, "Random Forest prediction", "predicted_disease = argmax_c P(y=c | x)")
    add_para(doc, "The current configuration is RandomForestClassifier(criterion=entropy, max_depth=28, min_samples_split=4, min_samples_leaf=2, max_features=log2, class_weight=balanced_subsample, bootstrap=True, random_state=42, n_estimators=200). This model is trained and evaluated but /predict is not registered in the active API.")

    add_heading(doc, "9. Experimental portable neural-network formula")
    add_para(doc, "The portable model is retained as a loadable artifact but is not the default path in classify(). Its 200-element input vector is constructed as follows:")
    add_table(doc, ["Feature positions", "Construction"], [
        ("0", "age / 100.0"),
        ("1-50", "Hashed keyword-presence buckets using FNV-1a 32-bit: index = 1 + (hash(keyword) mod 50). Collisions are possible."),
        ("51", "BP systolic / 200.0"),
        ("52", "BP diastolic / 150.0"),
        ("53", "Temperature in C / 42.0"),
        ("54", "Heart rate / 200.0"),
        ("55-199", "Reserved zeros in the current layout."),
    ], [Inches(1.45), Inches(5.6)], 8.7)
    add_formula_box(doc, "Shared neural-network trunk", "h1 = ReLU(xW1 + b1)\nh2 = ReLU(h1W2 + b2)\nh3 = ReLU(h2W3 + b3)", "Layer sizes are Dense(128), Dense(64), and Dense(32), with dropout during training between the first three dense layers.")
    add_formula_box(doc, "Two output heads", "p_category = softmax(h3W_category + b_category)\np_severity = softmax(h3W_severity + b_severity)\ncategory = argmax(p_category); severity = argmax(p_severity)", "Category output has 6 classes; severity output has 4 classes.")
    add_formula_box(doc, "Training loss", "L = mean[-log p_category(correct_category) - log p_severity(correct_severity)]", "The Keras model compiles two sparse-categorical-cross-entropy losses with equal default weighting. The checked-in artifact has no traceable production training manifest or verified held-out metrics.")

    add_heading(doc, "10. Evaluation formulas")
    add_formula_box(doc, "Top-1 accuracy", "Accuracy = (1/n) * sum_i I(predicted_label_i = true_label_i)")
    add_formula_box(doc, "Per-class precision and recall", "Precision_c = TP_c / (TP_c + FP_c)\nRecall_c = TP_c / (TP_c + FN_c)")
    add_formula_box(doc, "F1-score", "F1_c = 2 * Precision_c * Recall_c / (Precision_c + Recall_c)")
    add_formula_box(doc, "Weighted and macro averages", "WeightedMetric = sum_c (support_c/n) * Metric_c\nMacroMetric = (1/C) * sum_c Metric_c, with C=100")
    add_formula_box(doc, "Balanced accuracy", "BalancedAccuracy = (1/C) * sum_c Recall_c")
    add_formula_box(doc, "Top-k coverage", "TopK = (1/n) * sum_i I(true_label_i is among the k highest-ranked probabilities_i)")
    add_formula_box(doc, "Wilson 95% interval", "p = x/n\ncentre = (p + z^2/(2n)) / (1 + z^2/n)\nmargin = z*sqrt(p(1-p)/n + z^2/(4n^2)) / (1 + z^2/n), z=1.96", "Used for uncertainty around observed top-k proportions; it does not establish clinical validity.")
    add_formula_box(doc, "Identical-vector ceiling", "Ceiling = sum_g max_c count(label=c | exact input vector=g) / n")
    add_formula_box(doc, "Calibration metrics", "LogLoss = -mean(log p_true)\nBrier = mean(sum_c (p_c - one_hot_c)^2)\nECE = sum_bins (n_bin/n) * |bin_accuracy - bin_mean_confidence|", "Lower log loss, Brier score, and ECE are better. Calibration is a probability-reliability measure, not a diagnosis-safety measure.")

    add_heading(doc, "11. Current verified results and correct interpretation")
    add_table(doc, ["Evaluation result", "Value", "Correct interpretation"], [
        ("Offline Random Forest top-1", "89.3399%", "Agreement with held-out dataset labels."),
        ("Offline Random Forest top-2", "96.5424%", "True label appeared in the two highest-ranked classes; coverage, not ordinary accuracy."),
        ("Offline Random Forest top-3", "98.5052%", "True label appeared in the three highest-ranked classes; coverage, not a single diagnosis."),
        ("Rule-based active Flutter path", "No verified accuracy claim", "Deterministic rules are active for offline decision support."),
        ("Clinical validation", "Not established", "Qualified professional review and authenticated field testing remain open."),
    ], [Inches(2.05), Inches(1.35), Inches(3.65)], 8.5)
    add_callout(doc, "Safety boundary", "AI output is decision support. Healthcare professionals remain responsible for final assessment, referral, treatment, and emergency decisions. The system does not prescribe medication.", RED)

    add_heading(doc, "12. Source-of-truth files")
    add_bullets(doc, [
        "lib/app/core/services/health_ai_classifier.dart - active Flutter rule scoring, severity rules, confidence, and portable-model inference implementation.",
        "backend/app/health_category_service.py - active backend category-routing rules.",
        "backend/app/train.py - offline Random Forest training and evaluation.",
        "backend/app/evaluation_metrics.py - metric definitions and statistical formulas.",
        "train_model/train_health_classifier.py - portable neural-network feature extraction, architecture, and training loss.",
        "backend/reports/ai_requirements_verification.json - authoritative current evaluation values.",
        "docs/AI_VALIDATION_REPORT.md - validation, safety, and limitations.",
        "docs/AI_WORKFLOW.md - active system workflow and path selection.",
    ])
    add_para(doc, "This formula specification should be revised whenever the source implementation changes. If a future trained model replaces the rule-based default, its training provenance, held-out evaluation, and production route must be documented before its metrics are presented as current.", italic=True, color=GRAY)
    path = OUT / "AI_Formula_Specification.docx"
    doc.save(path)
    return path


if __name__ == "__main__":
    print(make_data_analysis())
    print(make_formula_document())
