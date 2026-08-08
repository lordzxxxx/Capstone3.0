# BHW Print-Ready Report Template

This project now uses a shared formal PDF layout for reporting modules through:

- `lib/web/shared/utils/bhw_report_generation.dart`
- `lib/web/shared/utils/report_generation.dart`

## PDF Layout Structure

1. Header
- Barangay Health Worker Information System
- Official report title
- Barangay name
- Reporting period
- Submission copy / reference number
- Date and time generated

2. Report Identification
- Report title
- Report type
- Module
- Reporting period
- Barangay name
- Date generated
- Prepared by
- Reference number

3. Summary Section
- Summary narrative
- Total records
- Unique patients / subjects
- Coverage window
- Sex distribution
- Status snapshot
- Top module-specific category

4. Main Records Table
- Auto-numbered `No.` column
- Module-specific reporting columns
- Repeating table header on succeeding pages
- Landscape A4 layout for better print readability

5. Totals / Aggregated Data
- Total encoded records
- Unique patients / subjects
- Date span of encoded records
- Sex distribution
- Status distribution
- Top module-specific category

6. Remarks / Notes
- Administrative remarks entered during report generation
- System notice for review before submission

7. Signature Section
- Prepared by
- Reviewed by
- Approved by
- Printed name
- Position
- Signature
- Date

8. Footer
- System-generated label
- Date and time generated
- Page `x of y`

## Professional Content Format

Use the following order in every report:

1. Official report title
2. Reporting period
3. Barangay name
4. Date generated
5. Prepared by
6. Summary
7. Main records table
8. Totals / aggregated data
9. Remarks / notes
10. Signature section

## Module Table Templates

### Check-up Report

- No.
- Patient Name
- Age
- Sex
- Address / Barangay
- Date of Check-up
- Chief Complaint
- Findings
- Diagnosis
- Treatment / Action Taken
- Remarks

### Morbidity Report

- No.
- Patient Name
- Age
- Sex
- Disease / Diagnosis
- Date Recorded
- Case Status
- Remarks

### Prenatal Report

- No.
- Patient ID
- Patient Name
- Age
- Registration Date
- Due Date
- Gestational Age
- Gravida
- Para
- Risk Level
- Status
- Address / Barangay
- Remarks

### Immunization Report

- No.
- Patient ID
- Patient Name
- Age
- Vaccine Type
- Administration Date
- Dose Number
- Status
- Administered By
- Route
- Injection Site
- Adverse Events

## Recommended Official Titles

### Check-up
- Monthly Check-up Accomplishment Report
- Quarterly Check-up Accomplishment Report
- Yearly Check-up Consolidated Report

### Morbidity
- Monthly Morbidity Case Report
- Quarterly Morbidity Surveillance Report
- Yearly Morbidity Consolidated Report

### Prenatal
- Monthly Prenatal Care Monitoring Report
- Quarterly Prenatal Service Accomplishment Report
- Yearly Prenatal Care Consolidated Report

### Immunization
- Monthly Immunization Accomplishment Report
- Quarterly Immunization Coverage Report
- Yearly Immunization Consolidated Report

### Patient Records
- Monthly Patient Registry Report
- Quarterly Patient Registry Summary Report
- Yearly Patient Registry Consolidated Report

### Barangay Records
- Monthly Barangay Health Profile Report
- Quarterly Barangay Health Situation Report
- Yearly Barangay Health Profile Report
