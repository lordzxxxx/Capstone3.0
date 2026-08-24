import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final outputDir = Directory('test_forms');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  print('Generating standardized AI-DSUHIS clinical PDF forms in ${outputDir.path}...');

  // 1. Check-Up Forms (CHK-2026)
  await generateCheckupForm(File('${outputDir.path}/checkup_form_test.pdf'), isBlank: false);
  await generateCheckupForm(File('${outputDir.path}/checkup_blank_template.pdf'), isBlank: true);

  // 2. Prenatal Care Forms (PNC-2026)
  await generatePrenatalForm(File('${outputDir.path}/prenatal_form_test.pdf'), isBlank: false);
  await generatePrenatalForm(File('${outputDir.path}/prenatal_blank_template.pdf'), isBlank: true);

  // 3. Immunization Forms (IMZ-2026)
  await generateImmunizationForm(File('${outputDir.path}/immunization_form_test.pdf'), isBlank: false);
  await generateImmunizationForm(File('${outputDir.path}/immunization_blank_template.pdf'), isBlank: true);

  // 4. Morbidity Surveillance Forms (MBD-2026)
  await generateMorbidityForm(File('${outputDir.path}/morbidity_form_test.pdf'), isBlank: false);
  await generateMorbidityForm(File('${outputDir.path}/morbidity_blank_template.pdf'), isBlank: true);

  // 5. Mortality Surveillance Forms (MOR-2026)
  await generateMortalityForm(File('${outputDir.path}/mortality_form_test.pdf'), isBlank: false);
  await generateMortalityForm(File('${outputDir.path}/mortality_blank_template.pdf'), isBlank: true);

  // 6. Patient Registration Forms (PAT-2026)
  await generatePatientRegistrationForm(File('${outputDir.path}/patient_registration_form_test.pdf'), isBlank: false);
  await generatePatientRegistrationForm(File('${outputDir.path}/patient_registration_blank_template.pdf'), isBlank: true);

  print('Successfully generated 12 standardized PDF forms (6 filled tests + 6 printable blank templates) in test_forms/!');
}

pw.Widget _buildHeader(String formTitle, String formCode, {bool isBlank = false}) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue900, width: 1.5)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'REPUBLIC OF THE PHILIPPINES',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'CITY HEALTH OFFICE - MALAYBALAY CITY',
              style: pw.TextStyle(fontSize: 9.5, color: PdfColors.blue900, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'AI-DSUHIS Clinical Intake & Surveillance Form',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              formTitle.toUpperCase(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
            ),
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (isBlank)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(right: 4),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      'BLANK TEMPLATE',
                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                    ),
                  ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: PdfColors.blue300),
                  ),
                  child: pw.Text(
                    'FORM: $formCode',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _buildSection(String title) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 6, bottom: 3),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    color: PdfColors.grey200,
    child: pw.Text(
      title,
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
    ),
  );
}

pw.Widget _buildFieldRow(List<Map<String, String>> fields, {bool isBlank = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: fields.map((f) {
        final label = f['label'] ?? '';
        final value = isBlank ? (f['blankGuide'] ?? '____________________') : (f['value'] ?? '');
        final flex = int.tryParse(f['flex'] ?? '1') ?? 1;

        return pw.Expanded(
          flex: flex,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(right: 6),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '$label: ',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.black),
                  ),
                  pw.TextSpan(
                    text: value,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: isBlank ? PdfColors.grey500 : PdfColors.blue900,
                      fontWeight: isBlank ? pw.FontWeight.normal : pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

pw.Widget _buildBoxField(String label, String value, {bool isBlank = false, double minHeight = 22}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.black),
        ),
        pw.SizedBox(height: 1.5),
        pw.Container(
          width: double.infinity,
          constraints: pw.BoxConstraints(minHeight: minHeight),
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
            borderRadius: pw.BorderRadius.circular(3),
            color: isBlank ? PdfColors.white : PdfColors.grey50,
          ),
          child: pw.Text(
            isBlank ? '' : value,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.blue900),
          ),
        ),
      ],
    ),
  );
}

// 1. Check-Up Form (CHK-2026)
Future<void> generateCheckupForm(File file, {bool isBlank = false}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader('General Clinical Check-Up Record', 'CHK-2026', isBlank: isBlank),
            _buildSection('1. PATIENT DEMOGRAPHIC & CONTACT INFORMATION'),
            _buildFieldRow([
              {'label': 'Patient Full Name', 'value': 'Juan Dela Cruz', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Patient ID', 'value': 'PAT-2026-0105', 'blankGuide': 'PAT-2026-____', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date of Birth', 'value': '1992-05-18', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Age', 'value': '34', 'blankGuide': '___ yrs'},
              {'label': 'Sex', 'value': '[X] Male  [ ] Female', 'blankGuide': '[ ] Male  [ ] Female'},
              {'label': 'Civil Status', 'value': '[X] Married  [ ] Single  [ ] Widowed  [ ] Separated', 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Contact Number', 'value': '0917-888-9900', 'blankGuide': '09XX-XXX-XXXX', 'flex': '1'},
              {'label': 'PhilHealth ID / No.', 'value': '12-345678901-2', 'blankGuide': 'XX-XXXXXXXXX-X', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Residential Address', 'value': '45 Rizal Ave, Purok 3', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Barangay', 'value': 'Casisang', 'blankGuide': '____________________', 'flex': '1'},
            ], isBlank: isBlank),

            _buildSection('2. VITAL SIGNS & ANTHROPOMETRIC MEASUREMENTS'),
            _buildFieldRow([
              {'label': 'Blood Pressure (BP)', 'value': '120/80 mmHg', 'blankGuide': '____/____ mmHg'},
              {'label': 'Body Temp (T)', 'value': '36.7 °C', 'blankGuide': '____._ °C'},
              {'label': 'Heart Rate (HR)', 'value': '74 bpm', 'blankGuide': '____ bpm'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Respiratory Rate (RR)', 'value': '18 cpm', 'blankGuide': '____ cpm'},
              {'label': 'Oxygen Saturation (SpO2)', 'value': '98 %', 'blankGuide': '____ %'},
              {'label': 'Weight (WT)', 'value': '68 kg', 'blankGuide': '____ kg'},
              {'label': 'Height (HT)', 'value': '172 cm', 'blankGuide': '____ cm'},
            ], isBlank: isBlank),

            _buildSection('3. CHIEF COMPLAINT & CLINICAL ASSESSMENT'),
            _buildBoxField('Chief Complaint / Symptoms', 'High fever for 3 days, body aches, and persistent dry cough', isBlank: isBlank),
            _buildBoxField('Clinical Diagnosis / Disease Condition (Dx)', 'Acute Viral Upper Respiratory Tract Infection', isBlank: isBlank),

            _buildSection('4. TREATMENT PLAN & PRESCRIBED MEDICATIONS (Rx)'),
            _buildBoxField('Treatment Plan / Prescribed Medications (Rx)', 'Paracetamol 500mg tab every 4 hours PRN, increase oral hydration, rest for 3 days', isBlank: isBlank),

            _buildSection('5. ENCOUNTER METADATA & VERIFICATION'),
            _buildFieldRow([
              {'label': 'Date of Visit', 'value': '2026-08-18', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Next Visit Date', 'value': '2026-08-25', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Attending Health Worker', 'value': 'BHW Elena Reyes', 'blankGuide': '____________________'},
            ], isBlank: isBlank),
          ],
        );
      },
    ),
  );

  await file.writeAsBytes(await pdf.save());
}

// 2. Prenatal Care Form (PNC-2026)
Future<void> generatePrenatalForm(File file, {bool isBlank = false}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader('Maternal & Prenatal Care Record', 'PNC-2026', isBlank: isBlank),
            _buildSection('1. MATERNAL DEMOGRAPHIC INFORMATION'),
            _buildFieldRow([
              {'label': 'Maternal Full Name', 'value': 'Maria Santos Cruz', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Patient ID', 'value': 'PAT-2026-042', 'blankGuide': 'PAT-2026-____', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date of Birth', 'value': '1999-03-12', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Age', 'value': '27', 'blankGuide': '___ yrs'},
              {'label': 'Civil Status', 'value': '[X] Married  [ ] Single  [ ] Widowed  [ ] Separated', 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
              {'label': 'Blood Type', 'value': 'O+', 'blankGuide': '[ ] A [ ] B [ ] AB [ ] O (+/-)'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Contact Number', 'value': '0918-987-6543', 'blankGuide': '09XX-XXX-XXXX'},
              {'label': 'PhilHealth ID / No.', 'value': '12-345678901-2', 'blankGuide': 'XX-XXXXXXXXX-X'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Residence Address', 'value': 'Zone 4, Sitio Riverside', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Barangay', 'value': 'Sumpong', 'blankGuide': '____________________', 'flex': '1'},
            ], isBlank: isBlank),

            _buildSection('2. OBSTETRICAL HISTORY (G-P-FT-PT-AB-LC)'),
            _buildFieldRow([
              {'label': 'Gravida (G)', 'value': '2', 'blankGuide': '___'},
              {'label': 'Para (P)', 'value': '1', 'blankGuide': '___'},
              {'label': 'Full Term (FT)', 'value': '1', 'blankGuide': '___'},
              {'label': 'Premature (PT)', 'value': '0', 'blankGuide': '___'},
              {'label': 'Abortion (AB)', 'value': '0', 'blankGuide': '___'},
              {'label': 'Living Children (LC)', 'value': '1', 'blankGuide': '___'},
            ], isBlank: isBlank),

            _buildSection('3. CURRENT PREGNANCY ASSESSMENT & GESTATIONAL DATA'),
            _buildFieldRow([
              {'label': 'LMP', 'value': '2026-01-10', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'EDD', 'value': '2026-10-17', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Age of Gestation (AOG)', 'value': '31 weeks', 'blankGuide': '____ weeks'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Fundal Height (FH)', 'value': '28 cm', 'blankGuide': '____ cm'},
              {'label': 'Fetal Heart Beat (FHB)', 'value': '142 bpm', 'blankGuide': '____ bpm'},
              {'label': 'Tetanus Toxoid (TT) Dose', 'value': 'TT3', 'blankGuide': '[ ] TT1 [ ] TT2 [ ] TT3 [ ] TT4 [ ] TT5'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Pregnancy Risk Assessment Level', 'value': '[X] Low Risk  [ ] Moderate Risk  [ ] High Risk', 'blankGuide': '[ ] Low Risk  [ ] Moderate Risk  [ ] High Risk'},
              {'label': 'Registration Date', 'value': '2026-08-16', 'blankGuide': 'YYYY-MM-DD'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Next Visit Due Date', 'value': '2026-08-30', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Attending Midwife / BHW', 'value': 'Midwife Ana Lopez', 'blankGuide': '____________________'},
            ], isBlank: isBlank),
          ],
        );
      },
    ),
  );

  await file.writeAsBytes(await pdf.save());
}

// 3. Child Immunization Form (IMZ-2026)
Future<void> generateImmunizationForm(File file, {bool isBlank = false}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader('EPI Child Immunization Card', 'IMZ-2026', isBlank: isBlank),
            _buildSection('1. INFANT / CHILD DEMOGRAPHIC INFORMATION'),
            _buildFieldRow([
              {'label': 'Patient / Child Full Name', 'value': 'Baby Gabriel Reyes', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Patient ID', 'value': 'PAT-2026-088', 'blankGuide': 'PAT-2026-____', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date of Birth', 'value': '2026-02-14', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Age', 'value': '6 mos', 'blankGuide': '___ mos/yrs'},
              {'label': 'Sex', 'value': '[X] Male  [ ] Female', 'blankGuide': '[ ] Male  [ ] Female'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Mother / Father / Guardian Full Name', 'value': 'Elena Reyes', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Contact Number', 'value': '0920-555-1234', 'blankGuide': '09XX-XXX-XXXX', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Residence Address', 'value': 'Purok 2, Brgy. Aglayan', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Barangay', 'value': 'Aglayan', 'blankGuide': '____________________', 'flex': '1'},
            ], isBlank: isBlank),

            _buildSection('2. VACCINE & IMMUNIZATION ADMINISTRATION DETAILS'),
            _buildFieldRow([
              {'label': 'Vaccine / Antigen Type', 'value': 'Pentavalent Vaccine', 'blankGuide': '[ ] BCG [ ] HepB [ ] Pentavalent [ ] OPV [ ] IPV [ ] PCV [ ] MMR', 'flex': '2'},
              {'label': 'Dose Number', 'value': '2nd Dose', 'blankGuide': '[ ] 1st [ ] 2nd [ ] 3rd [ ] Booster', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Batch / Lot Number', 'value': 'BATCH-PENTA-992', 'blankGuide': '____________________'},
              {'label': 'Expiration Date', 'value': '2027-12-31', 'blankGuide': 'YYYY-MM-DD'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date Administered', 'value': '2026-08-14', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Next Dose Due Date', 'value': '2026-09-14', 'blankGuide': 'YYYY-MM-DD'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Vaccinator Name & Title', 'value': 'Nurse Sarah Jenkins, RN', 'blankGuide': '______________________________'},
            ], isBlank: isBlank),
          ],
        );
      },
    ),
  );

  await file.writeAsBytes(await pdf.save());
}

// 4. Morbidity Surveillance Form (MBD-2026)
Future<void> generateMorbidityForm(File file, {bool isBlank = false}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader('Notifiable Disease Morbidity Surveillance', 'MBD-2026', isBlank: isBlank),
            _buildSection('1. CASE PATIENT DEMOGRAPHIC DETAILS'),
            _buildFieldRow([
              {'label': 'Patient Full Name', 'value': 'Ana Theresa Lim', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Patient ID', 'value': 'PAT-2026-215', 'blankGuide': 'PAT-2026-____', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date of Birth', 'value': '2005-09-08', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Age', 'value': '20', 'blankGuide': '___ yrs'},
              {'label': 'Sex', 'value': '[ ] Male  [X] Female', 'blankGuide': '[ ] Male  [ ] Female'},
              {'label': 'Contact Number', 'value': '0917-234-5678', 'blankGuide': '09XX-XXX-XXXX'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'PhilHealth ID / No.', 'value': '22-998877665-0', 'blankGuide': 'XX-XXXXXXXXX-X'},
              {'label': 'Residential Address', 'value': 'Street 3, Brgy. 05', 'blankGuide': '____________________'},
              {'label': 'Barangay', 'value': 'Barangay 05', 'blankGuide': '____________________'},
            ], isBlank: isBlank),

            _buildSection('2. EPIDEMIOLOGICAL SURVEILLANCE & CLINICAL FINDINGS'),
            _buildFieldRow([
              {'label': 'Clinical Diagnosis / Disease Condition (Dx)', 'value': 'Dengue Fever', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Date of Onset', 'value': '2026-08-10', 'blankGuide': 'YYYY-MM-DD', 'flex': '1'},
            ], isBlank: isBlank),
            _buildBoxField('Symptoms / Chief Complaints / Diagnostic Lab Findings', 'High grade fever, retro-orbital pain, skin petechiae', isBlank: isBlank),
            _buildBoxField('Treatment Plan / Prescribed Medications (Rx)', 'Oral Rehydration Therapy, close platelet monitoring', isBlank: isBlank),

            _buildSection('3. SURVEILLANCE RECORD METADATA'),
            _buildFieldRow([
              {'label': 'Date Reported', 'value': '2026-08-14', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Reported By', 'value': 'Health Worker Roy', 'blankGuide': '____________________'},
            ], isBlank: isBlank),
          ],
        );
      },
    ),
  );

  await file.writeAsBytes(await pdf.save());
}

// 5. Mortality Surveillance Form (MOR-2026)
Future<void> generateMortalityForm(File file, {bool isBlank = false}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader('Community Mortality Reporting Notification', 'MOR-2026', isBlank: isBlank),
            _buildSection('1. DECEASED INDIVIDUAL INFORMATION'),
            _buildFieldRow([
              {'label': 'Full Name of Deceased', 'value': 'Pedro Alvarez Cruz', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Patient ID', 'value': 'REC-2026-104', 'blankGuide': 'REC-2026-____', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date of Birth', 'value': '1952-11-20', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Age at Death', 'value': '73', 'blankGuide': '___ yrs'},
              {'label': 'Sex', 'value': '[X] Male  [ ] Female', 'blankGuide': '[ ] Male  [ ] Female'},
              {'label': 'Civil Status', 'value': '[X] Widowed  [ ] Single  [ ] Married  [ ] Separated', 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Occupation', 'value': 'Retired Farmer', 'blankGuide': '____________________'},
              {'label': 'Usual Residence Address', 'value': 'Zone 1, Brgy. 04', 'blankGuide': '____________________'},
              {'label': 'Barangay', 'value': 'Barangay 04', 'blankGuide': '____________________'},
            ], isBlank: isBlank),

            _buildSection('2. CAUSE AND CIRCUMSTANCE OF DEATH'),
            _buildBoxField('Immediate Cause of Death', 'Acute Myocardial Infarction', isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date of Death', 'value': '2026-08-12', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Time of Death', 'value': '04:30 PM', 'blankGuide': 'HH:MM AM/PM'},
              {'label': 'Place of Death', 'value': '[X] Residence  [ ] Hospital  [ ] Other', 'blankGuide': '[ ] Residence  [ ] Hospital  [ ] Other'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Reported By', 'value': 'Nurse Jane Santos', 'blankGuide': '______________________________'},
            ], isBlank: isBlank),
          ],
        );
      },
    ),
  );

  await file.writeAsBytes(await pdf.save());
}

// 6. Patient Registration Form (PAT-2026)
Future<void> generatePatientRegistrationForm(File file, {bool isBlank = false}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader('Patient Master Registration Card', 'PAT-2026', isBlank: isBlank),
            _buildSection('1. DEMOGRAPHIC PROFILE'),
            _buildFieldRow([
              {'label': 'Patient Full Name', 'value': 'Rodrigo Garcia Fernandez', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Patient ID', 'value': 'PAT-2026-001', 'blankGuide': 'PAT-2026-____', 'flex': '1'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Date of Birth', 'value': '1988-11-24', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Age', 'value': '37', 'blankGuide': '___ yrs'},
              {'label': 'Sex', 'value': '[X] Male  [ ] Female', 'blankGuide': '[ ] Male  [ ] Female'},
              {'label': 'Civil Status', 'value': '[X] Married  [ ] Single  [ ] Widowed  [ ] Separated', 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Contact Number', 'value': '0919-456-7890', 'blankGuide': '09XX-XXX-XXXX'},
              {'label': 'PhilHealth ID / No.', 'value': '11-887766554-3', 'blankGuide': 'XX-XXXXXXXXX-X'},
              {'label': 'Blood Type', 'value': 'A+', 'blankGuide': '[ ] A [ ] B [ ] AB [ ] O (+/-)'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Residential Address', 'value': 'Purok 4, Upper Casisang', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Barangay', 'value': 'Casisang', 'blankGuide': '____________________', 'flex': '1'},
            ], isBlank: isBlank),

            _buildSection('2. SOCIO-DEMOGRAPHIC & EMERGENCY CONTACT INFORMATION'),
            _buildFieldRow([
              {'label': 'Occupation', 'value': 'Teacher', 'blankGuide': '____________________'},
              {'label': 'Religion', 'value': 'Roman Catholic', 'blankGuide': '____________________'},
            ], isBlank: isBlank),
            _buildFieldRow([
              {'label': 'Emergency Contact Person', 'value': 'Teresa Fernandez', 'blankGuide': '______________________________', 'flex': '2'},
              {'label': 'Emergency Phone', 'value': '0917-111-2233', 'blankGuide': '09XX-XXX-XXXX', 'flex': '1'},
            ], isBlank: isBlank),

            _buildSection('3. REGISTRATION METADATA'),
            _buildFieldRow([
              {'label': 'Registration Date', 'value': '2026-08-20', 'blankGuide': 'YYYY-MM-DD'},
              {'label': 'Registered By', 'value': 'BHW Maria Cruz', 'blankGuide': '____________________'},
            ], isBlank: isBlank),
          ],
        );
      },
    ),
  );

  await file.writeAsBytes(await pdf.save());
}
