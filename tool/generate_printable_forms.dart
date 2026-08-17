import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final outputDir = Directory('docs/forms');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  print('Generating 5 printable PDF clinical and intake forms with optimized label layouts...');

  // 1. Check-Up Form
  final checkupPdf = _buildCheckupFormPdf();
  final checkupFile = File('${outputDir.path}/checkup_form.pdf');
  await checkupFile.writeAsBytes(await checkupPdf.save());
  print('✅ Generated: ${checkupFile.path}');

  // 2. Prenatal Care Form
  final prenatalPdf = _buildPrenatalFormPdf();
  final prenatalFile = File('${outputDir.path}/prenatal_care_form.pdf');
  await prenatalFile.writeAsBytes(await prenatalPdf.save());
  print('✅ Generated: ${prenatalFile.path}');

  // 3. Immunization Form
  final immunizationPdf = _buildImmunizationFormPdf();
  final immunizationFile = File('${outputDir.path}/immunization_form.pdf');
  await immunizationFile.writeAsBytes(await immunizationPdf.save());
  print('✅ Generated: ${immunizationFile.path}');

  // 4. Mortality Form
  final mortalityPdf = _buildMortalityFormPdf();
  final mortalityFile = File('${outputDir.path}/mortality_form.pdf');
  await mortalityFile.writeAsBytes(await mortalityPdf.save());
  print('✅ Generated: ${mortalityFile.path}');

  // 5. Morbidity Form
  final morbidityPdf = _buildMorbidityFormPdf();
  final morbidityFile = File('${outputDir.path}/morbidity_form.pdf');
  await morbidityFile.writeAsBytes(await morbidityPdf.save());
  print('✅ Generated: ${morbidityFile.path}');

  print('\nAll 5 PDF forms generated successfully in ${outputDir.path}!');
}

// -------------------------------------------------------------
// COMMON PROFESSIONAL STYLING & COMPONENT HELPERS
// -------------------------------------------------------------

pw.Widget _buildHeader({
  required String formTitle,
  required String formCode,
  String subtitle = 'BARANGAY HEALTH STATION CLINICAL & SURVEILLANCE RECORD',
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        'REPUBLIC OF THE PHILIPPINES  •  PROVINCE OF BUKIDNON',
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.6),
      ),
      pw.SizedBox(height: 1),
      pw.Text(
        'CITY HEALTH OFFICE  •  $subtitle',
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
      ),
      pw.SizedBox(height: 4),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(color: PdfColors.black, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              formTitle.toUpperCase(),
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.3),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.black, width: 0.6),
              ),
              child: pw.Text(
                'FORM: $formCode',
                style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 3),
    ],
  );
}

pw.Widget _buildSectionHeader(String title) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.2),
    margin: const pw.EdgeInsets.only(top: 4, bottom: 3),
    decoration: const pw.BoxDecoration(
      color: PdfColors.grey300,
      border: pw.Border(
        left: pw.BorderSide(color: PdfColors.black, width: 2.5),
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
    ),
    child: pw.Text(
      title.toUpperCase(),
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 0.3),
    ),
  );
}

/// Stacked field: Label on top (with optional format hint), full-width underline below
pw.Widget _buildStackedField({
  required String label,
  String? hint,
  double height = 15,
  double labelFontSize = 7,
  bool isRequired = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: labelFontSize, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
            if (isRequired)
              pw.Text(
                ' *',
                style: pw.TextStyle(fontSize: labelFontSize, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
              ),
            if (hint != null && hint.isNotEmpty) ...[
              pw.SizedBox(width: 3),
              pw.Text(
                hint,
                style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 1),
        pw.Container(
          height: height,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Checkbox square with label
pw.Widget _buildCheckboxItem(String label, {double boxSize = 7.5, double fontSize = 7}) {
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(
        width: boxSize,
        height: boxSize,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.8),
          color: PdfColors.white,
        ),
      ),
      pw.SizedBox(width: 3),
      pw.Text(
        label,
        style: pw.TextStyle(fontSize: fontSize),
      ),
    ],
  );
}

/// Checkbox group with a top label and aligned choices below
pw.Widget _buildCheckboxGroup({
  required String label,
  required List<String> options,
  double labelFontSize = 7,
  double optionFontSize = 6.8,
  double itemSpacing = 6,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: labelFontSize, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Wrap(
          spacing: itemSpacing,
          runSpacing: 2,
          children: options.map((opt) => _buildCheckboxItem(opt, fontSize: optionFontSize)).toList(),
        ),
      ],
    ),
  );
}

/// Structured Table Grid for Measurements / Vitals / Obstetrical Data
pw.Widget _buildTableGrid({
  required List<String> headers,
  List<String>? subHeaders,
  double writeHeight = 17,
  double headerFontSize = 7,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 2),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: 0.6),
    ),
    child: pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
      ),
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers.asMap().entries.map((entry) {
            final idx = entry.key;
            final header = entry.value;
            final subHeader = (subHeaders != null && idx < subHeaders.length) ? subHeaders[idx] : null;
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 2),
              alignment: pw.Alignment.center,
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    header,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: headerFontSize, fontWeight: pw.FontWeight.bold),
                  ),
                  if (subHeader != null && subHeader.isNotEmpty)
                    pw.Text(
                      subHeader,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
        // Blank Handwriting Row
        pw.TableRow(
          children: headers.map((_) {
            return pw.Container(
              height: writeHeight,
              alignment: pw.Alignment.center,
            );
          }).toList(),
        ),
      ],
    ),
  );
}

/// Structured Box with Top Label and Ruled Writing Lines
pw.Widget _buildBoxField({
  required String label,
  String? hint,
  int lines = 2,
  double lineHeight = 14,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 2, bottom: 2),
    padding: const pw.EdgeInsets.all(3.5),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey700, width: 0.6),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold),
            ),
            if (hint != null && hint.isNotEmpty) ...[
              pw.SizedBox(width: 4),
              pw.Text(
                hint,
                style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 1),
        ...List.generate(
          lines,
          (i) => pw.Container(
            height: lineHeight,
            decoration: i == lines - 1
                ? null
                : const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: PdfColors.grey400,
                        width: 0.4,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}

/// Signatures Block
pw.Widget _buildSignatures({
  String leftTitle = 'Attending Health Worker / BHW',
  String rightTitle = 'Physician / Nurse-in-Charge',
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 6),
    padding: const pw.EdgeInsets.only(top: 4),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Container(
                height: 18,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.7)),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                leftTitle,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Signature over Printed Name  •  Date',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 5.8, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 30),
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Container(
                height: 18,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.7)),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                rightTitle,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Signature over Printed Name  •  License No. / Date',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 5.8, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// -------------------------------------------------------------
// 1. CHECK-UP CLINICAL INTAKE FORM (CHK-2026)
// -------------------------------------------------------------
pw.Document _buildCheckupFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(
              formTitle: 'Barangay Health Check-Up Intake Form',
              formCode: 'CHK-2026',
            ),

            _buildSectionHeader('1. Patient Demographic Information'),
            pw.Row(
              children: [
                pw.Expanded(flex: 7, child: _buildStackedField(label: 'Full Name', hint: '(Last Name, First Name, Middle Name)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Patient ID', hint: '(PAT-YYYY-XXXX)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Date of Birth', hint: '(YYYY-MM-DD)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 2, child: _buildStackedField(label: 'Age', hint: '(yrs/mos)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _buildCheckboxGroup(
                    label: 'Sex',
                    options: ['Male', 'Female'],
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 6,
                  child: _buildCheckboxGroup(
                    label: 'Civil Status',
                    options: ['Single', 'Married', 'Widowed', 'Separated'],
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 5,
                  child: _buildStackedField(label: 'Contact Number', hint: '(09XX-XXX-XXXX)'),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(flex: 8, child: _buildStackedField(label: 'Residential Address', hint: '(House / Street / Zone / Sitio)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Barangay', hint: '(e.g. Barangay 01)', isRequired: true)),
              ],
            ),

            _buildSectionHeader('2. Vital Signs & Clinical Measurements'),
            _buildTableGrid(
              headers: [
                'Blood Pressure (BP)',
                'Body Temp (T)',
                'Pulse Rate (HR)',
                'Resp. Rate (RR)',
                'Oxygen Sat (SpO2)',
                'Weight (WT)',
                'Height (HT)',
              ],
              subHeaders: [
                'mmHg (e.g. 120/80)',
                '°C (e.g. 36.5)',
                'bpm',
                'cpm',
                '% (e.g. 98)',
                'kg',
                'cm',
              ],
              writeHeight: 16,
            ),

            _buildSectionHeader('3. Chief Complaint & Subjective Symptoms'),
            _buildBoxField(
              label: 'Chief Complaint / Reason for Visit / Symptoms',
              hint: '(Describe onset, duration, severity, and associated symptoms)',
              lines: 3,
              lineHeight: 14,
            ),

            _buildSectionHeader('4. Clinical Assessment & Diagnosis (Dx)'),
            _buildBoxField(
              label: 'Clinical Diagnosis / Disease Condition (Dx)',
              hint: '(Primary diagnosis, ICD-10 or clinical impression)',
              lines: 2,
              lineHeight: 14,
            ),

            _buildSectionHeader('5. Treatment Plan, Medication (Rx) & Management'),
            _buildBoxField(
              label: 'Treatment Plan / Prescribed Medications (Rx) / Home Care Advice',
              hint: '(Drug name, dosage, frequency, duration, precautions)',
              lines: 3,
              lineHeight: 14,
            ),

            _buildSectionHeader('6. Encounter Metadata & Verification'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Date of Visit', hint: '(YYYY-MM-DD)', isRequired: true)),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 6,
                  child: _buildCheckboxGroup(
                    label: 'Encounter Status',
                    options: ['Completed', 'Follow-Up Needed', 'Referred to Hospital'],
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Next Visit Date', hint: '(YYYY-MM-DD)')),
              ],
            ),

            _buildSignatures(),
          ],
        );
      },
    ),
  );

  return pdf;
}

// -------------------------------------------------------------
// 2. PRENATAL CARE RECORD FORM (PNC-2026)
// -------------------------------------------------------------
pw.Document _buildPrenatalFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(
              formTitle: 'Barangay Maternal & Prenatal Care Record',
              formCode: 'PNC-2026',
            ),

            _buildSectionHeader('1. Patient & Maternal Information'),
            pw.Row(
              children: [
                pw.Expanded(flex: 7, child: _buildStackedField(label: 'Maternal Full Name', hint: '(Surname, Given Name, Middle Name)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Patient ID', hint: '(PAT-YYYY-XXXX)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 2, child: _buildStackedField(label: 'Age', hint: '(years)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Date of Birth', hint: '(YYYY-MM-DD)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 6,
                  child: _buildCheckboxGroup(
                    label: 'Civil Status',
                    options: ['Single', 'Married', 'Widowed', 'Separated'],
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Contact Number', hint: '(09XX-XXX-XXXX)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'PhilHealth ID / No.', hint: '(12-digit ID)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(flex: 8, child: _buildStackedField(label: 'Residence Address', hint: '(House / Street / Zone)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Barangay', hint: '(e.g. Barangay 02)', isRequired: true)),
              ],
            ),

            _buildSectionHeader('2. Obstetrical & Pregnancy History'),
            // Obstetric Formula Grid
            _buildTableGrid(
              headers: [
                'Gravida (G)',
                'Para (P)',
                'Full Term (FT)',
                'Premature (PT)',
                'Abortion (AB)',
                'Living Children (LC)',
              ],
              subHeaders: [
                'Total pregnancies',
                'Total deliveries',
                '>= 37 weeks',
                '< 37 weeks',
                'Miscarriages/Loss',
                'Currently living',
              ],
              writeHeight: 14,
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'LMP', hint: '(Last Menstrual Period: YYYY-MM-DD)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'EDD', hint: '(Expected Delivery Date: YYYY-MM-DD)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 2, child: _buildStackedField(label: 'AOG', hint: '(Gestation wks)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 2, child: _buildStackedField(label: 'Blood Type', hint: '(ABO/Rh: A+, O+, etc.)')),
              ],
            ),
            pw.SizedBox(height: 2),
            _buildCheckboxGroup(
              label: 'Pregnancy Risk Assessment Level',
              options: ['Low Risk', 'Moderate Risk (BHS Monitoring)', 'High Risk (Refer to OB/Hospital)'],
              itemSpacing: 10,
            ),

            _buildSectionHeader('3. Physical Examination & Maternal Vital Signs'),
            _buildTableGrid(
              headers: [
                'Blood Pressure',
                'Body Temp (T)',
                'Weight (WT)',
                'Height (HT)',
                'Fundal Height (FH)',
                'Fetal Heart Beat (FHB)',
                'Presentation',
                'Abdom. Tenderness',
              ],
              subHeaders: [
                'mmHg (BP)',
                '°C',
                'kg',
                'cm',
                'cm',
                'bpm',
                'Cephalic/Breech',
                'AT: Normal / Present',
              ],
              writeHeight: 15,
            ),

            _buildSectionHeader('4. Medical History, Allergies & Pre-existing Conditions'),
            _buildBoxField(
              label: 'Past Medical/Surgical History, Allergies & Chronic Conditions',
              hint: '(Hypertension, Diabetes, Asthma, Previous Cesarean, Allergies)',
              lines: 2,
              lineHeight: 13,
            ),

            _buildSectionHeader('5. Prenatal Care Plan, Immunization & Supplements'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: _buildCheckboxGroup(
                    label: 'Tetanus Toxoid (TT) Dose',
                    options: ['TT1', 'TT2', 'TT3', 'TT4', 'TT5'],
                    itemSpacing: 6,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 7,
                  child: _buildCheckboxGroup(
                    label: 'Micronutrient Supplementation Given',
                    options: ['Iron + Folic Acid', 'Calcium Carbonate', 'Iodine'],
                    itemSpacing: 6,
                  ),
                ),
              ],
            ),
            _buildBoxField(
              label: 'Prescribed Medications / Nutrition Advice / Danger Signs Discussed',
              hint: '(Vaginal bleeding, severe headache, epigastric pain, decreased fetal movement)',
              lines: 2,
              lineHeight: 13,
            ),

            _buildSectionHeader('6. Visit Schedule & Notes'),
            pw.Row(
              children: [
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Registration Date', hint: '(YYYY-MM-DD)', isRequired: true)),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Next Prenatal Visit Due Date', hint: '(YYYY-MM-DD)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Place of Delivery Planned', hint: '(RHU / BHS / Hospital)')),
              ],
            ),

            _buildSignatures(
              leftTitle: 'Attending Midwife / BHW',
              rightTitle: 'Attending Physician / MHO',
            ),
          ],
        );
      },
    ),
  );

  return pdf;
}

// -------------------------------------------------------------
// 3. IMMUNIZATION RECORD FORM (IMZ-2026)
// -------------------------------------------------------------
pw.Document _buildImmunizationFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(
              formTitle: 'Barangay Child & Adult Immunization Record',
              formCode: 'IMZ-2026',
            ),

            _buildSectionHeader('1. Patient Demographic Information'),
            pw.Row(
              children: [
                pw.Expanded(flex: 7, child: _buildStackedField(label: 'Patient / Child Full Name', hint: '(Last Name, First Name, Middle Name)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Patient ID', hint: '(PAT-YYYY-XXXX)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Date of Birth', hint: '(YYYY-MM-DD)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 2, child: _buildStackedField(label: 'Age', hint: '(yrs/mos)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _buildCheckboxGroup(
                    label: 'Sex',
                    options: ['Male', 'Female'],
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 6, child: _buildStackedField(label: 'Mother / Father / Guardian Full Name', hint: '(Primary Caregiver)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Contact Number', hint: '(09XX-XXX-XXXX)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(flex: 8, child: _buildStackedField(label: 'Residence Address', hint: '(House / Street / Zone)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Barangay', hint: '(e.g. Barangay 03)', isRequired: true)),
              ],
            ),

            _buildSectionHeader('2. Vaccine & Antigen Administration Details'),
            pw.Row(
              children: [
                pw.Expanded(flex: 6, child: _buildStackedField(label: 'Vaccine / Antigen Type', hint: '(BCG, Pentavalent, OPV, IPV, PCV, Measles, MR, Covid-19, TT, Flu, HPV)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 5,
                  child: _buildCheckboxGroup(
                    label: 'Dose Number',
                    options: ['1st Dose', '2nd Dose', '3rd Dose', 'Booster'],
                    itemSpacing: 5,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(flex: 5, child: _buildStackedField(label: 'Vaccine Brand / Manufacturer', hint: '(e.g. Sanofi, GSK, Serum Inst.)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Batch / Lot Number', hint: '(Batch code)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Expiration Date', hint: '(YYYY-MM-DD)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 6,
                  child: _buildCheckboxGroup(
                    label: 'Route of Administration',
                    options: ['Intramuscular (IM)', 'Oral (OPV)', 'Subcutaneous (SC)', 'Intradermal (ID)'],
                    itemSpacing: 6,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 6,
                  child: _buildCheckboxGroup(
                    label: 'Injection Site',
                    options: ['Left Deltoid', 'Right Deltoid', 'Left Thigh (Anterolateral)', 'Right Thigh', 'Oral'],
                    itemSpacing: 5,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Date Administered', hint: '(YYYY-MM-DD)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Time Administered', hint: '(e.g. 09:30 AM)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 5, child: _buildStackedField(label: 'Vaccinator Name & Title', hint: '(BHW / Nurse / Midwife)')),
              ],
            ),

            _buildSectionHeader('3. Post-Vaccination Observation & Adverse Events (AEFI)'),
            _buildBoxField(
              label: 'Adverse Events Following Immunization (AEFI) / Clinical Notes',
              hint: '(Record any fever, local swelling, rash, or immediate anaphylactoid symptoms during 15-30 min observation)',
              lines: 2,
              lineHeight: 14,
            ),

            _buildSectionHeader('4. Next Dose Schedule, Status & Certification'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Next Dose Due Date', hint: '(YYYY-MM-DD)')),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 8,
                  child: _buildCheckboxGroup(
                    label: 'Immunization Status',
                    options: ['On-Schedule', 'Fully Immunized (FIC)', 'Catch-Up Dose', 'Deferred (Contraindicated)'],
                    itemSpacing: 6,
                  ),
                ),
              ],
            ),

            _buildSignatures(
              leftTitle: 'Vaccinating Health Worker / BHW',
              rightTitle: 'Supervising Public Health Nurse / Physician',
            ),
          ],
        );
      },
    ),
  );

  return pdf;
}

// -------------------------------------------------------------
// 4. MORTALITY NOTIFICATION & RECORD (MOR-2026)
// -------------------------------------------------------------
pw.Document _buildMortalityFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(
              formTitle: 'Barangay Mortality Notification & Record',
              formCode: 'MOR-2026',
            ),

            _buildSectionHeader('1. Deceased Individual Demographic Information'),
            pw.Row(
              children: [
                pw.Expanded(flex: 7, child: _buildStackedField(label: 'Full Name of Deceased', hint: '(Last Name, First Name, Middle Name)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Patient / Record ID', hint: '(ID Number)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Date of Birth', hint: '(YYYY-MM-DD)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 2, child: _buildStackedField(label: 'Age at Death', hint: '(yrs/days)', isRequired: true)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _buildCheckboxGroup(
                    label: 'Sex',
                    options: ['Male', 'Female'],
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 6,
                  child: _buildCheckboxGroup(
                    label: 'Civil Status',
                    options: ['Single', 'Married', 'Widowed', 'Separated'],
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Occupation', hint: '(Usual work)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(flex: 8, child: _buildStackedField(label: 'Usual Residence Address', hint: '(House / Street / Sitio)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Barangay', hint: '(e.g. Barangay 04)', isRequired: true)),
              ],
            ),

            _buildSectionHeader('2. Death Occurrence & Circumstances'),
            pw.Row(
              children: [
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Date of Death', hint: '(YYYY-MM-DD)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Time of Death', hint: '(e.g. 04:15 PM)')),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 8,
                  child: _buildCheckboxGroup(
                    label: 'Place of Death',
                    options: ['Home / Residence', 'Hospital / Clinic', 'Barangay Health Station', 'In Transit', 'Other'],
                    itemSpacing: 6,
                  ),
                ),
              ],
            ),

            _buildSectionHeader('3. Cause of Death & Clinical Details (COD)'),
            _buildBoxField(
              label: 'Immediate Cause of Death (Final disease or condition resulting in death)',
              hint: '(e.g. Acute Myocardial Infarction, Septic Shock, Severe Pneumonia)',
              lines: 2,
              lineHeight: 14,
            ),
            _buildBoxField(
              label: 'Antecedent & Underlying Causes / Contributing Co-morbidities',
              hint: '(Pre-existing conditions that gave rise to the immediate cause: e.g. Hypertension, Diabetes Mellitus Type 2, Stroke)',
              lines: 2,
              lineHeight: 14,
            ),

            _buildSectionHeader('4. Informant & Surveillance Reporting Details'),
            pw.Row(
              children: [
                pw.Expanded(flex: 5, child: _buildStackedField(label: 'Reported By (Informant Name)', hint: '(Next of kin / reporting BHW)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Relationship', hint: '(Spouse, Child, Parent, BHW)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Contact Number', hint: '(09XX-XXX-XXXX)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Date Reported', hint: '(YYYY-MM-DD)', isRequired: true)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(flex: 6, child: _buildStackedField(label: 'Attending Physician / Certifier Name', hint: '(Medical Officer / Certifying Doctor)')),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 6,
                  child: _buildCheckboxGroup(
                    label: 'Certification / Verification Status',
                    options: ['Medically Certified', 'BHS Verified', 'Pending Civil Registry'],
                    itemSpacing: 6,
                  ),
                ),
              ],
            ),

            _buildSignatures(
              leftTitle: 'Reporting BHW / Health Worker',
              rightTitle: 'Certifying Physician / Municipal Health Officer',
            ),
          ],
        );
      },
    ),
  );

  return pdf;
}

// -------------------------------------------------------------
// 5. MORBIDITY & DISEASE SURVEILLANCE FORM (MBD-2026)
// -------------------------------------------------------------
pw.Document _buildMorbidityFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(
              formTitle: 'Barangay Morbidity & Disease Surveillance Form',
              formCode: 'MBD-2026',
            ),

            _buildSectionHeader('1. Patient Demographic Information'),
            pw.Row(
              children: [
                pw.Expanded(flex: 7, child: _buildStackedField(label: 'Patient Full Name', hint: '(Last Name, First Name, Middle Name)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Patient ID', hint: '(PAT-YYYY-XXXX)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 3, child: _buildStackedField(label: 'Date of Birth', hint: '(YYYY-MM-DD)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 2, child: _buildStackedField(label: 'Age', hint: '(yrs/mos)', isRequired: true)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _buildCheckboxGroup(
                    label: 'Sex',
                    options: ['Male', 'Female'],
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 5, child: _buildStackedField(label: 'Contact Number', hint: '(09XX-XXX-XXXX)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 5, child: _buildStackedField(label: 'PhilHealth No.', hint: '(Member ID)')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(flex: 8, child: _buildStackedField(label: 'Residence Address', hint: '(House / Street / Zone / Sitio)')),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Barangay', hint: '(e.g. Barangay 05)', isRequired: true)),
              ],
            ),

            _buildSectionHeader('2. Disease & Morbidity Classification'),
            pw.Row(
              children: [
                pw.Expanded(flex: 7, child: _buildStackedField(label: 'Disease / Diagnosis (Dx)', hint: '(e.g. Dengue, Acute Gastroenteritis, URTI, Hypertension, Diabetes, TB)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 5,
                  child: _buildCheckboxGroup(
                    label: 'Classification',
                    options: ['Communicable', 'Non-Communicable (NCD)'],
                    itemSpacing: 6,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Date of Onset of Symptoms', hint: '(YYYY-MM-DD)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 4,
                  child: _buildCheckboxGroup(
                    label: 'Severity Level',
                    options: ['Mild', 'Moderate', 'Severe / Critical'],
                    itemSpacing: 5,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 4,
                  child: _buildCheckboxGroup(
                    label: 'Case Status',
                    options: ['Active Case', 'Recovered', 'Under Treatment'],
                    itemSpacing: 5,
                  ),
                ),
              ],
            ),

            _buildSectionHeader('3. Clinical Symptoms & Presentation'),
            _buildBoxField(
              label: 'Symptoms / Chief Complaints / Diagnostic Lab Findings',
              hint: '(e.g. High-grade fever, vomiting, rash, BP 160/100, Fasting Blood Sugar 180 mg/dL, cough > 2 weeks)',
              lines: 3,
              lineHeight: 14,
            ),

            _buildSectionHeader('4. Treatment, Medication & Intervention Taken'),
            _buildBoxField(
              label: 'Treatment Plan / Prescribed Medications (Rx) / Home Isolation or Referral',
              hint: '(Medications given, hydration plan, isolation instructions, health teachings)',
              lines: 3,
              lineHeight: 14,
            ),

            _buildSectionHeader('5. Surveillance, Reporting & Action Taken'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Date Reported', hint: '(YYYY-MM-DD)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(flex: 4, child: _buildStackedField(label: 'Reported By', hint: '(BHW / Surveillance Officer)', isRequired: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 5,
                  child: _buildCheckboxGroup(
                    label: 'Surveillance Action Taken',
                    options: ['Managed at BHS', 'Referred to RHU / Hospital', 'Isolation Enforced'],
                    itemSpacing: 5,
                  ),
                ),
              ],
            ),

            _buildSignatures(
              leftTitle: 'Surveillance Health Worker / BHW',
              rightTitle: 'City / Municipal Health Officer',
            ),
          ],
        );
      },
    ),
  );

  return pdf;
}
