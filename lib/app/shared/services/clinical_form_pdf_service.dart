import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart' as web_download;
import 'package:mycapstone_project/app/theme/app_theme.dart';

enum ClinicalFormType {
  checkup,
  prenatal,
  immunization,
  morbidity,
  mortality,
  patientRegistration,
}

class ClinicalFormPdfService {
  static const Map<ClinicalFormType, String> _formCodes = {
    ClinicalFormType.checkup: 'CHK-2026',
    ClinicalFormType.prenatal: 'PNC-2026',
    ClinicalFormType.immunization: 'IMZ-2026',
    ClinicalFormType.morbidity: 'MBD-2026',
    ClinicalFormType.mortality: 'MOR-2026',
    ClinicalFormType.patientRegistration: 'PAT-2026',
  };

  static const Map<ClinicalFormType, String> _formTitles = {
    ClinicalFormType.checkup: 'General Clinical Check-Up Record',
    ClinicalFormType.prenatal: 'Maternal & Prenatal Care Record',
    ClinicalFormType.immunization: 'EPI Child Immunization Card',
    ClinicalFormType.morbidity: 'Notifiable Disease Morbidity Surveillance',
    ClinicalFormType.mortality: 'Community Mortality Reporting Notification',
    ClinicalFormType.patientRegistration: 'Patient Master Registration Card',
  };

  static String getFormCode(ClinicalFormType type) => _formCodes[type] ?? 'MED-2026';
  static String getFormTitle(ClinicalFormType type) => _formTitles[type] ?? 'Clinical Form';

  /// Generates the raw PDF bytes for any clinical form.
  static Future<Uint8List> generateFormPdfBytes({
    required ClinicalFormType formType,
    Map<String, dynamic>? record,
    bool isBlank = false,
  }) async {
    final pdf = pw.Document();
    final rec = record ?? {};
    final formCode = getFormCode(formType);
    final formTitle = getFormTitle(formType);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(formTitle, formCode, isBlank: isBlank),
              ..._buildFormContent(formType, rec, isBlank: isBlank),
            ],
          );
        },
      ),
    );

    return await pdf.save();
  }

  /// Displays an interactive export/print bottom sheet on mobile or web.
  static void showExportDialog(
    BuildContext context, {
    required ClinicalFormType formType,
    Map<String, dynamic>? record,
    String? patientName,
  }) {
    final formCode = getFormCode(formType);
    final formTitle = getFormTitle(formType);
    final resolvedPatient = (patientName ??
            record?['patient'] ??
            record?['patientName'] ??
            record?['fullName'] ??
            record?['deceasedName'] ??
            '')
        .toString()
        .trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return Material(
          color: AppDesign.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppDesign.border),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pull handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppDesign.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title & Form Code Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppDesign.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: AppDesign.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formTitle,
                          style: const TextStyle(
                            color: AppDesign.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppDesign.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                formCode,
                                style: const TextStyle(
                                  color: AppDesign.blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (resolvedPatient.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '• $resolvedPatient',
                                  style: const TextStyle(
                                    color: AppDesign.muted,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Option 1: Export Completed Record PDF (if record provided)
              if (record != null && record.isNotEmpty) ...[
                _buildActionTile(
                  context,
                  title: 'Export Completed Record PDF',
                  subtitle: 'Official PDF with all current record details filled in.',
                  icon: Icons.download_rounded,
                  iconColor: AppDesign.blue,
                  onTap: () async {
                    Navigator.pop(bottomSheetContext);
                    await _executePdfExport(
                      context,
                      formType: formType,
                      record: record,
                      isBlank: false,
                    );
                  },
                ),
                const SizedBox(height: 10),
              ],

              // Option 2: Print / Download Blank Intake Template
              _buildActionTile(
                context,
                title: 'Print Blank Intake Template',
                subtitle: 'Printable template with lined boxes & checkboxes for handwriting.',
                icon: Icons.print_outlined,
                iconColor: Colors.tealAccent.shade400,
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  await _executePdfExport(
                    context,
                    formType: formType,
                    record: null,
                    isBlank: true,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

  static Widget _buildActionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppDesign.page.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppDesign.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppDesign.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppDesign.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppDesign.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _executePdfExport(
    BuildContext context, {
    required ClinicalFormType formType,
    Map<String, dynamic>? record,
    required bool isBlank,
  }) async {
    final formCode = getFormCode(formType).toLowerCase().replaceAll('-', '_');
    final suffix = isBlank ? 'blank_template' : 'record';
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = '${formCode}_${suffix}_$timestamp.pdf';

    // Show loading snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text('Generating ${getFormTitle(formType)} PDF...'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppDesign.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final pdfBytes = await generateFormPdfBytes(
        formType: formType,
        record: record,
        isBlank: isBlank,
      );

      if (kIsWeb) {
        web_download.downloadFile(
          bytes: pdfBytes,
          filename: filename,
          mimeType: 'application/pdf',
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Downloaded $filename successfully!'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Mobile / Desktop storage saving using path_provider
        Directory baseDir;
        try {
          baseDir = (await getExternalStorageDirectory()) ??
              (await getApplicationDocumentsDirectory());
        } catch (_) {
          try {
            baseDir = await getApplicationDocumentsDirectory();
          } catch (_) {
            try {
              baseDir = await getTemporaryDirectory();
            } catch (_) {
              baseDir = Directory.current;
            }
          }
        }

        final formsDir = Directory('${baseDir.path}/clinical_forms');
        if (!await formsDir.exists()) {
          await formsDir.create(recursive: true);
        }
        final savedFile = File('${formsDir.path}/$filename');
        await savedFile.writeAsBytes(pdfBytes);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✓ PDF Generated Successfully',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Saved: $filename (${(pdfBytes.length / 1024).toStringAsFixed(1)} KB)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // --- PDF Widget Builders ---

  static pw.Widget _buildHeader(String formTitle, String formCode, {bool isBlank = false}) {
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

  static pw.Widget _buildSection(String title) {
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

  static pw.Widget _buildFieldRow(List<Map<String, String>> fields, {bool isBlank = false}) {
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

  static pw.Widget _buildBoxField(String label, String value, {bool isBlank = false, double minHeight = 22}) {
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

  static List<pw.Widget> _buildFormContent(
    ClinicalFormType formType,
    Map<String, dynamic> r, {
    bool isBlank = false,
  }) {
    switch (formType) {
      case ClinicalFormType.checkup:
        return _buildCheckupContent(r, isBlank: isBlank);
      case ClinicalFormType.prenatal:
        return _buildPrenatalContent(r, isBlank: isBlank);
      case ClinicalFormType.immunization:
        return _buildImmunizationContent(r, isBlank: isBlank);
      case ClinicalFormType.morbidity:
        return _buildMorbidityContent(r, isBlank: isBlank);
      case ClinicalFormType.mortality:
        return _buildMortalityContent(r, isBlank: isBlank);
      case ClinicalFormType.patientRegistration:
        return _buildPatientRegistrationContent(r, isBlank: isBlank);
    }
  }

  static List<pw.Widget> _buildCheckupContent(Map<String, dynamic> r, {bool isBlank = false}) {
    final patient = (r['patient'] ?? r['patientName'] ?? r['fullName'] ?? 'Juan Dela Cruz').toString();
    final patientId = (r['patientId'] ?? r['id'] ?? 'PAT-2026-0105').toString();
    final dob = (r['dateOfBirth'] ?? r['birthDate'] ?? '1992-05-18').toString();
    final age = (r['age'] ?? '34').toString();
    final gender = (r['gender'] ?? r['sex'] ?? 'Male').toString();
    final civilStatus = (r['civilStatus'] ?? 'Married').toString();
    final contact = (r['contactNumber'] ?? r['phone'] ?? '0917-888-9900').toString();
    final philhealth = (r['philhealthNumber'] ?? r['philhealth'] ?? '12-345678901-2').toString();
    final address = (r['address'] ?? '45 Rizal Ave, Purok 3').toString();
    final barangay = (r['barangay'] ?? 'Casisang').toString();

    final bp = (r['bloodPressure'] ?? r['bp'] ?? '120/80 mmHg').toString();
    final temp = (r['temperature'] ?? r['temp'] ?? '36.7 °C').toString();
    final hr = (r['heartRate'] ?? r['hr'] ?? '74 bpm').toString();
    final rr = (r['respiratoryRate'] ?? r['rr'] ?? '18 cpm').toString();
    final spo2 = (r['oxygenSaturation'] ?? r['spo2'] ?? '98 %').toString();
    final wt = (r['weight'] ?? r['wt'] ?? '68 kg').toString();
    final ht = (r['height'] ?? r['ht'] ?? '172 cm').toString();

    final symptoms = (r['symptoms'] ?? r['chiefComplaint'] ?? 'High fever for 3 days, body aches, and persistent dry cough').toString();
    final diagnosis = (r['diagnosis'] ?? r['disease'] ?? 'Acute Viral Upper Respiratory Tract Infection').toString();
    final treatment = (r['treatment'] ?? r['treatmentPlan'] ?? 'Paracetamol 500mg tab every 4 hours PRN, increase oral hydration, rest for 3 days').toString();

    final visitDate = (r['date'] ?? r['visitDate'] ?? r['dateOfVisit'] ?? '2026-08-18').toString();
    final nextVisit = (r['nextVisitDate'] ?? r['followUpDate'] ?? '2026-08-25').toString();
    final worker = (r['attendingWorker'] ?? r['reportedBy'] ?? 'BHW Elena Reyes').toString();

    final genderDisplay = gender.toLowerCase() == 'female' ? '[ ] Male  [X] Female' : '[X] Male  [ ] Female';

    return [
      _buildSection('1. PATIENT DEMOGRAPHIC & CONTACT INFORMATION'),
      _buildFieldRow([
        {'label': 'Patient Full Name', 'value': patient, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Patient ID', 'value': patientId, 'blankGuide': 'PAT-2026-____', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date of Birth', 'value': dob, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Age', 'value': age, 'blankGuide': '___ yrs'},
        {'label': 'Sex', 'value': genderDisplay, 'blankGuide': '[ ] Male  [ ] Female'},
        {'label': 'Civil Status', 'value': civilStatus, 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Contact Number', 'value': contact, 'blankGuide': '09XX-XXX-XXXX', 'flex': '1'},
        {'label': 'PhilHealth ID / No.', 'value': philhealth, 'blankGuide': 'XX-XXXXXXXXX-X', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Residential Address', 'value': address, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Barangay', 'value': barangay, 'blankGuide': '____________________', 'flex': '1'},
      ], isBlank: isBlank),

      _buildSection('2. VITAL SIGNS & ANTHROPOMETRIC MEASUREMENTS'),
      _buildFieldRow([
        {'label': 'Blood Pressure (BP)', 'value': bp, 'blankGuide': '____/____ mmHg'},
        {'label': 'Body Temp (T)', 'value': temp, 'blankGuide': '____._ °C'},
        {'label': 'Heart Rate (HR)', 'value': hr, 'blankGuide': '____ bpm'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Respiratory Rate (RR)', 'value': rr, 'blankGuide': '____ cpm'},
        {'label': 'Oxygen Saturation (SpO2)', 'value': spo2, 'blankGuide': '____ %'},
        {'label': 'Weight (WT)', 'value': wt, 'blankGuide': '____ kg'},
        {'label': 'Height (HT)', 'value': ht, 'blankGuide': '____ cm'},
      ], isBlank: isBlank),

      _buildSection('3. CHIEF COMPLAINT & CLINICAL ASSESSMENT'),
      _buildBoxField('Chief Complaint / Symptoms', symptoms, isBlank: isBlank),
      _buildBoxField('Clinical Diagnosis / Disease Condition (Dx)', diagnosis, isBlank: isBlank),

      _buildSection('4. TREATMENT PLAN & PRESCRIBED MEDICATIONS (Rx)'),
      _buildBoxField('Treatment Plan / Prescribed Medications (Rx)', treatment, isBlank: isBlank),

      _buildSection('5. ENCOUNTER METADATA & VERIFICATION'),
      _buildFieldRow([
        {'label': 'Date of Visit', 'value': visitDate, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Next Visit Date', 'value': nextVisit, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Attending Health Worker', 'value': worker, 'blankGuide': '____________________'},
      ], isBlank: isBlank),
    ];
  }

  static List<pw.Widget> _buildPrenatalContent(Map<String, dynamic> r, {bool isBlank = false}) {
    final name = (r['patient'] ?? r['patientName'] ?? r['fullName'] ?? 'Maria Santos Cruz').toString();
    final pid = (r['patientId'] ?? r['id'] ?? 'PAT-2026-042').toString();
    final dob = (r['dateOfBirth'] ?? '1999-03-12').toString();
    final age = (r['age'] ?? '27').toString();
    final civilStatus = (r['civilStatus'] ?? 'Married').toString();
    final bloodType = (r['bloodType'] ?? 'O+').toString();
    final contact = (r['contactNumber'] ?? '0918-987-6543').toString();
    final philhealth = (r['philhealthNumber'] ?? '12-345678901-2').toString();
    final address = (r['address'] ?? 'Zone 4, Sitio Riverside').toString();
    final barangay = (r['barangay'] ?? 'Sumpong').toString();

    final g = (r['gravida'] ?? '2').toString();
    final p = (r['para'] ?? '1').toString();
    final ft = (r['fullTerm'] ?? '1').toString();
    final pt = (r['premature'] ?? '0').toString();
    final ab = (r['abortion'] ?? '0').toString();
    final lc = (r['livingChildren'] ?? '1').toString();

    final lmp = (r['lmp'] ?? r['lmpDate'] ?? '2026-01-10').toString();
    final edd = (r['edd'] ?? r['eddDate'] ?? '2026-10-17').toString();
    final aog = (r['aog'] ?? '31 weeks').toString();
    final fh = (r['fundalHeight'] ?? '28 cm').toString();
    final fhb = (r['fetalHeartBeat'] ?? '142 bpm').toString();
    final tt = (r['tetanusToxoid'] ?? 'TT3').toString();
    final risk = (r['riskLevel'] ?? 'Low Risk').toString();
    final regDate = (r['date'] ?? r['registrationDate'] ?? '2026-08-16').toString();
    final nextDate = (r['nextVisitDate'] ?? '2026-08-30').toString();
    final worker = (r['attendingWorker'] ?? r['reportedBy'] ?? 'Midwife Ana Lopez').toString();

    return [
      _buildSection('1. MATERNAL DEMOGRAPHIC INFORMATION'),
      _buildFieldRow([
        {'label': 'Maternal Full Name', 'value': name, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Patient ID', 'value': pid, 'blankGuide': 'PAT-2026-____', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date of Birth', 'value': dob, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Age', 'value': age, 'blankGuide': '___ yrs'},
        {'label': 'Civil Status', 'value': civilStatus, 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
        {'label': 'Blood Type', 'value': bloodType, 'blankGuide': '[ ] A [ ] B [ ] AB [ ] O (+/-)'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Contact Number', 'value': contact, 'blankGuide': '09XX-XXX-XXXX'},
        {'label': 'PhilHealth ID / No.', 'value': philhealth, 'blankGuide': 'XX-XXXXXXXXX-X'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Residence Address', 'value': address, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Barangay', 'value': barangay, 'blankGuide': '____________________', 'flex': '1'},
      ], isBlank: isBlank),

      _buildSection('2. OBSTETRICAL HISTORY (G-P-FT-PT-AB-LC)'),
      _buildFieldRow([
        {'label': 'Gravida (G)', 'value': g, 'blankGuide': '___'},
        {'label': 'Para (P)', 'value': p, 'blankGuide': '___'},
        {'label': 'Full Term (FT)', 'value': ft, 'blankGuide': '___'},
        {'label': 'Premature (PT)', 'value': pt, 'blankGuide': '___'},
        {'label': 'Abortion (AB)', 'value': ab, 'blankGuide': '___'},
        {'label': 'Living Children (LC)', 'value': lc, 'blankGuide': '___'},
      ], isBlank: isBlank),

      _buildSection('3. CURRENT PREGNANCY ASSESSMENT & GESTATIONAL DATA'),
      _buildFieldRow([
        {'label': 'LMP', 'value': lmp, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'EDD', 'value': edd, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Age of Gestation (AOG)', 'value': aog, 'blankGuide': '____ weeks'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Fundal Height (FH)', 'value': fh, 'blankGuide': '____ cm'},
        {'label': 'Fetal Heart Beat (FHB)', 'value': fhb, 'blankGuide': '____ bpm'},
        {'label': 'Tetanus Toxoid (TT) Dose', 'value': tt, 'blankGuide': '[ ] TT1 [ ] TT2 [ ] TT3 [ ] TT4 [ ] TT5'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Pregnancy Risk Assessment Level', 'value': risk, 'blankGuide': '[ ] Low Risk  [ ] Moderate Risk  [ ] High Risk'},
        {'label': 'Registration Date', 'value': regDate, 'blankGuide': 'YYYY-MM-DD'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Next Visit Due Date', 'value': nextDate, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Attending Midwife / BHW', 'value': worker, 'blankGuide': '____________________'},
      ], isBlank: isBlank),
    ];
  }

  static List<pw.Widget> _buildImmunizationContent(Map<String, dynamic> r, {bool isBlank = false}) {
    final child = (r['patient'] ?? r['patientName'] ?? r['childName'] ?? 'Baby Gabriel Reyes').toString();
    final pid = (r['patientId'] ?? r['id'] ?? 'PAT-2026-088').toString();
    final dob = (r['dateOfBirth'] ?? '2026-02-14').toString();
    final age = (r['age'] ?? '6 mos').toString();
    final sex = (r['gender'] ?? r['sex'] ?? 'Male').toString();
    final guardian = (r['guardianName'] ?? r['motherName'] ?? 'Elena Reyes').toString();
    final contact = (r['contactNumber'] ?? '0920-555-1234').toString();
    final address = (r['address'] ?? 'Purok 2, Brgy. Aglayan').toString();
    final barangay = (r['barangay'] ?? 'Aglayan').toString();

    final vaccine = (r['vaccine'] ?? r['vaccineType'] ?? 'Pentavalent Vaccine').toString();
    final dose = (r['dose'] ?? r['doseNumber'] ?? '2nd Dose').toString();
    final batch = (r['batchNumber'] ?? r['batch'] ?? 'BATCH-PENTA-992').toString();
    final exp = (r['expirationDate'] ?? '2027-12-31').toString();
    final adminDate = (r['date'] ?? r['dateAdministered'] ?? '2026-08-14').toString();
    final nextDose = (r['nextVisitDate'] ?? r['nextDoseDueDate'] ?? '2026-09-14').toString();
    final vaccinator = (r['reportedBy'] ?? r['vaccinatorName'] ?? 'Nurse Sarah Jenkins, RN').toString();

    return [
      _buildSection('1. INFANT / CHILD DEMOGRAPHIC INFORMATION'),
      _buildFieldRow([
        {'label': 'Patient / Child Full Name', 'value': child, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Patient ID', 'value': pid, 'blankGuide': 'PAT-2026-____', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date of Birth', 'value': dob, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Age', 'value': age, 'blankGuide': '___ mos/yrs'},
        {'label': 'Sex', 'value': sex, 'blankGuide': '[ ] Male  [ ] Female'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Mother / Father / Guardian Full Name', 'value': guardian, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Contact Number', 'value': contact, 'blankGuide': '09XX-XXX-XXXX', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Residence Address', 'value': address, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Barangay', 'value': barangay, 'blankGuide': '____________________', 'flex': '1'},
      ], isBlank: isBlank),

      _buildSection('2. VACCINE & IMMUNIZATION ADMINISTRATION DETAILS'),
      _buildFieldRow([
        {'label': 'Vaccine / Antigen Type', 'value': vaccine, 'blankGuide': '[ ] BCG [ ] HepB [ ] Pentavalent [ ] OPV [ ] IPV [ ] PCV [ ] MMR', 'flex': '2'},
        {'label': 'Dose Number', 'value': dose, 'blankGuide': '[ ] 1st [ ] 2nd [ ] 3rd [ ] Booster', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Batch / Lot Number', 'value': batch, 'blankGuide': '____________________'},
        {'label': 'Expiration Date', 'value': exp, 'blankGuide': 'YYYY-MM-DD'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date Administered', 'value': adminDate, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Next Dose Due Date', 'value': nextDose, 'blankGuide': 'YYYY-MM-DD'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Vaccinator Name & Title', 'value': vaccinator, 'blankGuide': '______________________________'},
      ], isBlank: isBlank),
    ];
  }

  static List<pw.Widget> _buildMorbidityContent(Map<String, dynamic> r, {bool isBlank = false}) {
    final patient = (r['patient'] ?? r['patientName'] ?? 'Ana Theresa Lim').toString();
    final pid = (r['patientId'] ?? r['id'] ?? 'PAT-2026-215').toString();
    final dob = (r['dateOfBirth'] ?? '2005-09-08').toString();
    final age = (r['age'] ?? '20').toString();
    final sex = (r['gender'] ?? r['sex'] ?? 'Female').toString();
    final contact = (r['contactNumber'] ?? '0917-234-5678').toString();
    final philhealth = (r['philhealthNumber'] ?? '22-998877665-0').toString();
    final address = (r['address'] ?? 'Street 3, Brgy. 05').toString();
    final barangay = (r['barangay'] ?? 'Barangay 05').toString();

    final disease = (r['disease'] ?? r['diagnosis'] ?? 'Dengue Fever').toString();
    final onset = (r['dateOfOnset'] ?? '2026-08-10').toString();
    final symptoms = (r['symptoms'] ?? 'High grade fever, retro-orbital pain, skin petechiae').toString();
    final treatment = (r['treatment'] ?? 'Oral Rehydration Therapy, close platelet monitoring').toString();
    final reportedDate = (r['date'] ?? r['dateReported'] ?? '2026-08-14').toString();
    final reporter = (r['reportedBy'] ?? 'Health Worker Roy').toString();

    return [
      _buildSection('1. CASE PATIENT DEMOGRAPHIC DETAILS'),
      _buildFieldRow([
        {'label': 'Patient Full Name', 'value': patient, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Patient ID', 'value': pid, 'blankGuide': 'PAT-2026-____', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date of Birth', 'value': dob, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Age', 'value': age, 'blankGuide': '___ yrs'},
        {'label': 'Sex', 'value': sex, 'blankGuide': '[ ] Male  [ ] Female'},
        {'label': 'Contact Number', 'value': contact, 'blankGuide': '09XX-XXX-XXXX'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'PhilHealth ID / No.', 'value': philhealth, 'blankGuide': 'XX-XXXXXXXXX-X'},
        {'label': 'Residential Address', 'value': address, 'blankGuide': '____________________'},
        {'label': 'Barangay', 'value': barangay, 'blankGuide': '____________________'},
      ], isBlank: isBlank),

      _buildSection('2. EPIDEMIOLOGICAL SURVEILLANCE & CLINICAL FINDINGS'),
      _buildFieldRow([
        {'label': 'Clinical Diagnosis / Disease Condition (Dx)', 'value': disease, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Date of Onset', 'value': onset, 'blankGuide': 'YYYY-MM-DD', 'flex': '1'},
      ], isBlank: isBlank),
      _buildBoxField('Symptoms / Chief Complaints / Diagnostic Lab Findings', symptoms, isBlank: isBlank),
      _buildBoxField('Treatment Plan / Prescribed Medications (Rx)', treatment, isBlank: isBlank),

      _buildSection('3. SURVEILLANCE RECORD METADATA'),
      _buildFieldRow([
        {'label': 'Date Reported', 'value': reportedDate, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Reported By', 'value': reporter, 'blankGuide': '____________________'},
      ], isBlank: isBlank),
    ];
  }

  static List<pw.Widget> _buildMortalityContent(Map<String, dynamic> r, {bool isBlank = false}) {
    final deceased = (r['patient'] ?? r['deceasedName'] ?? r['fullName'] ?? 'Pedro Alvarez Cruz').toString();
    final pid = (r['patientId'] ?? r['id'] ?? 'REC-2026-104').toString();
    final dob = (r['dateOfBirth'] ?? '1952-11-20').toString();
    final age = (r['age'] ?? '73').toString();
    final sex = (r['gender'] ?? r['sex'] ?? 'Male').toString();
    final civilStatus = (r['civilStatus'] ?? 'Widowed').toString();
    final occupation = (r['occupation'] ?? 'Retired Farmer').toString();
    final address = (r['address'] ?? 'Zone 1, Brgy. 04').toString();
    final barangay = (r['barangay'] ?? 'Barangay 04').toString();

    final cause = (r['cause'] ?? r['causeOfDeath'] ?? 'Acute Myocardial Infarction').toString();
    final dod = (r['date'] ?? r['dateOfDeath'] ?? '2026-08-12').toString();
    final tod = (r['time'] ?? r['timeOfDeath'] ?? '04:30 PM').toString();
    final place = (r['place'] ?? r['placeOfDeath'] ?? 'Residence').toString();
    final reporter = (r['reportedBy'] ?? 'Nurse Jane Santos').toString();

    return [
      _buildSection('1. DECEASED INDIVIDUAL INFORMATION'),
      _buildFieldRow([
        {'label': 'Full Name of Deceased', 'value': deceased, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Patient ID', 'value': pid, 'blankGuide': 'REC-2026-____', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date of Birth', 'value': dob, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Age at Death', 'value': age, 'blankGuide': '___ yrs'},
        {'label': 'Sex', 'value': sex, 'blankGuide': '[ ] Male  [ ] Female'},
        {'label': 'Civil Status', 'value': civilStatus, 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Occupation', 'value': occupation, 'blankGuide': '____________________'},
        {'label': 'Usual Residence Address', 'value': address, 'blankGuide': '____________________'},
        {'label': 'Barangay', 'value': barangay, 'blankGuide': '____________________'},
      ], isBlank: isBlank),

      _buildSection('2. CAUSE AND CIRCUMSTANCE OF DEATH'),
      _buildBoxField('Immediate Cause of Death', cause, isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date of Death', 'value': dod, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Time of Death', 'value': tod, 'blankGuide': 'HH:MM AM/PM'},
        {'label': 'Place of Death', 'value': place, 'blankGuide': '[ ] Residence  [ ] Hospital  [ ] Other'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Reported By', 'value': reporter, 'blankGuide': '______________________________'},
      ], isBlank: isBlank),
    ];
  }

  static List<pw.Widget> _buildPatientRegistrationContent(Map<String, dynamic> r, {bool isBlank = false}) {
    final name = (r['patient'] ?? r['patientName'] ?? r['fullName'] ?? 'Rodrigo Garcia Fernandez').toString();
    final pid = (r['patientId'] ?? r['id'] ?? 'PAT-2026-001').toString();
    final dob = (r['dateOfBirth'] ?? '1988-11-24').toString();
    final age = (r['age'] ?? '37').toString();
    final sex = (r['gender'] ?? r['sex'] ?? 'Male').toString();
    final civilStatus = (r['civilStatus'] ?? 'Married').toString();
    final contact = (r['contactNumber'] ?? '0919-456-7890').toString();
    final philhealth = (r['philhealthNumber'] ?? '11-887766554-3').toString();
    final bloodType = (r['bloodType'] ?? 'A+').toString();
    final address = (r['address'] ?? 'Purok 4, Upper Casisang').toString();
    final barangay = (r['barangay'] ?? 'Casisang').toString();

    final occupation = (r['occupation'] ?? 'Teacher').toString();
    final religion = (r['religion'] ?? 'Roman Catholic').toString();
    final emergency = (r['emergencyContact'] ?? 'Teresa Fernandez').toString();
    final emergencyPhone = (r['emergencyContactNumber'] ?? '0917-111-2233').toString();
    final regDate = (r['date'] ?? r['registrationDate'] ?? '2026-08-20').toString();
    final registrar = (r['reportedBy'] ?? r['registeredBy'] ?? 'BHW Maria Cruz').toString();

    return [
      _buildSection('1. DEMOGRAPHIC PROFILE'),
      _buildFieldRow([
        {'label': 'Patient Full Name', 'value': name, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Patient ID', 'value': pid, 'blankGuide': 'PAT-2026-____', 'flex': '1'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Date of Birth', 'value': dob, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Age', 'value': age, 'blankGuide': '___ yrs'},
        {'label': 'Sex', 'value': sex, 'blankGuide': '[ ] Male  [ ] Female'},
        {'label': 'Civil Status', 'value': civilStatus, 'blankGuide': '[ ] Single [ ] Married [ ] Widowed [ ] Separated', 'flex': '2'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Contact Number', 'value': contact, 'blankGuide': '09XX-XXX-XXXX'},
        {'label': 'PhilHealth ID / No.', 'value': philhealth, 'blankGuide': 'XX-XXXXXXXXX-X'},
        {'label': 'Blood Type', 'value': bloodType, 'blankGuide': '[ ] A [ ] B [ ] AB [ ] O (+/-)'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Residential Address', 'value': address, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Barangay', 'value': barangay, 'blankGuide': '____________________', 'flex': '1'},
      ], isBlank: isBlank),

      _buildSection('2. SOCIO-DEMOGRAPHIC & EMERGENCY CONTACT INFORMATION'),
      _buildFieldRow([
        {'label': 'Occupation', 'value': occupation, 'blankGuide': '____________________'},
        {'label': 'Religion', 'value': religion, 'blankGuide': '____________________'},
      ], isBlank: isBlank),
      _buildFieldRow([
        {'label': 'Emergency Contact Person', 'value': emergency, 'blankGuide': '______________________________', 'flex': '2'},
        {'label': 'Emergency Phone', 'value': emergencyPhone, 'blankGuide': '09XX-XXX-XXXX', 'flex': '1'},
      ], isBlank: isBlank),

      _buildSection('3. REGISTRATION METADATA'),
      _buildFieldRow([
        {'label': 'Registration Date', 'value': regDate, 'blankGuide': 'YYYY-MM-DD'},
        {'label': 'Registered By', 'value': registrar, 'blankGuide': '____________________'},
      ], isBlank: isBlank),
    ];
  }
}
