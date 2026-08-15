import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final outputDir = Directory('docs/forms');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  print('Generating 5 printable PDF clinical and intake forms...');

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
// COMMON STYLING HELPERS
// -------------------------------------------------------------

pw.Widget _buildHeader({
  required String formTitle,
  required String formCode,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        'REPUBLIC OF THE PHILIPPINES  •  PROVINCE OF BUKIDNON',
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5),
      ),
      pw.Text(
        'CITY HEALTH OFFICE  •  BARANGAY HEALTH STATION',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5),
      ),
      pw.SizedBox(height: 6),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(color: PdfColors.black, width: 1),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              formTitle.toUpperCase(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'FORM: $formCode',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 6),
    ],
  );
}

pw.Widget _buildSectionHeader(String title) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    margin: const pw.EdgeInsets.only(top: 6, bottom: 4),
    decoration: const pw.BoxDecoration(
      color: PdfColors.grey300,
    ),
    child: pw.Text(
      title.toUpperCase(),
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _buildField({
  required String label,
  String value = '',
  double height = 20,
  pw.FlexColumnWidth? width,
}) {
  return pw.Container(
    height: height,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildUnderlineField({
  required String label,
  double height = 22,
}) {
  return pw.Container(
    height: height,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildBoxField({
  required String label,
  int lines = 2,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 2, bottom: 2),
    padding: const pw.EdgeInsets.all(4),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: (lines * 14).toDouble()),
      ],
    ),
  );
}

pw.Widget _buildSignatures() {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Container(
                height: 25,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Attending Health Worker / BHW (Signature over Printed Name)',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 30),
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Container(
                height: 25,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Physician / Nurse-in-Charge (Signature over Printed Name)',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// -------------------------------------------------------------
// 1. CHECK-UP CLINICAL INTAKE FORM
// -------------------------------------------------------------
pw.Document _buildCheckupFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
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
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Full Name')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Patient ID')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Age')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Sex (Male / Female)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Date of Birth (YYYY-MM-DD)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Civil Status')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Address')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Barangay')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Contact Number')),
              ],
            ),

            _buildSectionHeader('2. Vital Signs & Clinical Measurements'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildField(label: 'Blood Pressure (BP)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Body Temp (T in °C)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Pulse Rate (HR bpm)')),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: _buildField(label: 'Resp. Rate (RR cpm)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Oxygen Sat (SpO2 %)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Weight (kg)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Height (cm)')),
              ],
            ),

            _buildSectionHeader('3. Chief Complaint & Subjective Symptoms'),
            _buildBoxField(label: 'Chief Complaint / Symptoms', lines: 3),

            _buildSectionHeader('4. Clinical Assessment & Diagnosis'),
            _buildBoxField(label: 'Diagnosis / Disease Condition (Dx)', lines: 3),

            _buildSectionHeader('5. Treatment Plan & Recommendations'),
            _buildBoxField(label: 'Treatment Plan / Prescribed Medications (Rx) / Next Visit Date', lines: 3),

            _buildSectionHeader('6. Encounter Metadata & Verification'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Date of Visit (YYYY-MM-DD)')),
                pw.SizedBox(width: 12),
                pw.Expanded(child: _buildUnderlineField(label: 'Status (Completed / Follow-up / Pending)')),
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
// 2. PRENATAL CARE RECORD FORM
// -------------------------------------------------------------
pw.Document _buildPrenatalFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
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
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Patient Name (First Name, Surname)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Patient ID')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Age')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Date of Birth')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Civil Status')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Contact Number')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Address')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Barangay')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'PhilHealth No.')),
              ],
            ),

            _buildSectionHeader('2. Obstetrical & Pregnancy History'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Gravida (G)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Para (P)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'LMP (Last Menstrual Period)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'EDD (Expected Delivery Date)')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Age of Gestation (AOG weeks)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Blood Type (ABO/Rh)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Risk Level (Low / Moderate / High)')),
              ],
            ),

            _buildSectionHeader('3. Physical Examination & Vital Signs'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildField(label: 'Blood Pressure (BP)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Body Temp (T °C)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Weight (WT kg)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Height (HT cm)')),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: _buildField(label: 'Fundal Height (FH cm)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Fetal Heart Beat (DHB bpm)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Abdominal Tenderness (AT)')),
              ],
            ),

            _buildSectionHeader('4. Medical History, Allergies & Complications'),
            _buildBoxField(label: 'Pre-existing Conditions, Allergies & Complications', lines: 2),

            _buildSectionHeader('5. Prenatal Care Plan & Immunization (Tetanus Toxoid)'),
            _buildBoxField(label: 'Supplements (Iron/Folic Acid), TT Vaccine Dose & Advice', lines: 2),

            _buildSectionHeader('6. Visit Schedule & Notes'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Registration Date (YYYY-MM-DD)')),
                pw.SizedBox(width: 12),
                pw.Expanded(child: _buildUnderlineField(label: 'Next Prenatal Visit Due Date')),
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
// 3. IMMUNIZATION RECORD FORM
// -------------------------------------------------------------
pw.Document _buildImmunizationFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
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
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Patient Name (Full Name)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Patient ID')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Age')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Sex (Male / Female)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Date of Birth (YYYY-MM-DD)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Mother / Guardian Name')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Address')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Barangay')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Contact Number')),
              ],
            ),

            _buildSectionHeader('2. Vaccine & Antigen Information'),
            pw.Row(
              children: [
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Vaccine Type (e.g. BCG, Pentavalent, OPV, IPV, Measles, Covid-19, TT)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Dose No. (1, 2, 3, Booster)')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Vaccine Brand / Manufacturer')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Batch / Lot Number')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Expiration Date (YYYY-MM-DD)')),
              ],
            ),

            _buildSectionHeader('3. Administration Details'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildField(label: 'Date of Administration (YYYY-MM-DD)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Time Administered (e.g. 09:30 AM)')),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: _buildField(label: 'Route (IM / Oral / Subcutaneous / ID)')),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _buildField(label: 'Injection Site (Left Deltoid / Right Thigh / etc.)')),
              ],
            ),

            _buildSectionHeader('4. Post-Vaccination Observation & Adverse Events'),
            _buildBoxField(label: 'Adverse Events Following Immunization (AEFI) / Notes', lines: 2),

            _buildSectionHeader('5. Next Dose Schedule & Remarks'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Next Dose Due Date (YYYY-MM-DD)')),
                pw.SizedBox(width: 12),
                pw.Expanded(child: _buildUnderlineField(label: 'Status (Completed / Scheduled / Deferred)')),
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
// 4. MORTALITY RECORD FORM
// -------------------------------------------------------------
pw.Document _buildMortalityFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(
              formTitle: 'Barangay Mortality Notification & Record',
              formCode: 'MOR-2026',
            ),

            _buildSectionHeader('1. Deceased Individual Information'),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Name of Deceased (Full Name)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Patient / Record ID')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Age')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Sex (Male / Female)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Civil Status')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Occupation')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Residence Address')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Barangay / Purok')),
              ],
            ),

            _buildSectionHeader('2. Death Occurrence & Circumstances'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Date of Death (YYYY-MM-DD)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Time of Death (e.g. 04:15 PM)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Place of Death (Home / Hospital / BHS / Transit)')),
              ],
            ),

            _buildSectionHeader('3. Cause of Death & Clinical Details'),
            _buildBoxField(label: 'Immediate / Underlying Cause of Death (COD)', lines: 3),
            _buildBoxField(label: 'Antecedent / Contributing Conditions & Reasons', lines: 2),

            _buildSectionHeader('4. Certification, Informant & Surveillance Details'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Reported By (Informant Name)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Relationship to Deceased')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Date Reported (YYYY-MM-DD)')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Attending Physician / Certifier Name')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Verification Status (Verified / Certified / Pending)')),
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
// 5. MORBIDITY SURVEILLANCE FORM
// -------------------------------------------------------------
pw.Document _buildMorbidityFormPdf() {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
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
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Patient Name (Full Name)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Patient ID')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 1, child: _buildUnderlineField(label: 'Age')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Sex (Male / Female)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Date of Birth (YYYY-MM-DD)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Contact Number')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Address')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Barangay')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Purok / Zone')),
              ],
            ),

            _buildSectionHeader('2. Disease & Morbidity Classification'),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: _buildUnderlineField(label: 'Disease / Diagnosis (e.g. Dengue, Acute Gastroenteritis, URTI, Hypertension, Diabetes)')),
                pw.SizedBox(width: 8),
                pw.Expanded(flex: 2, child: _buildUnderlineField(label: 'Classification (Communicable / NCD)')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Date of Onset of Symptoms')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Severity Level (Mild / Moderate / Severe)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Case Status (Active / Recovered / Under Treatment)')),
              ],
            ),

            _buildSectionHeader('3. Clinical Symptoms & Presentation'),
            _buildBoxField(label: 'Symptoms / Chief Complaints / Diagnostic Findings', lines: 3),

            _buildSectionHeader('4. Treatment, Medication & Intervention'),
            _buildBoxField(label: 'Treatment Plan / Prescribed Medications (Rx) / Isolation Measures', lines: 3),

            _buildSectionHeader('5. Reporting & Surveillance Details'),
            pw.Row(
              children: [
                pw.Expanded(child: _buildUnderlineField(label: 'Date Reported (YYYY-MM-DD)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Reported By (BHW / Health Staff)')),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildUnderlineField(label: 'Action Taken (Managed Locally / Referred)')),
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
