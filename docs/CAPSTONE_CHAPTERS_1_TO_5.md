# Capstone Project: Smart Health Integration System
**A Unified Health Information System for Barangay-Level Primary Care in the Philippines**

---

## CHAPTER 1: INTRODUCTION

### 1.1 Background of the Study
In the Philippines, Barangay Health Centers (BHCs) serve as the primary providers of healthcare for local communities. They handle a variety of medical services, including routine check-ups, prenatal care, immunizations, and basic disease management. However, many BHCs still rely on manual, paper-based record-keeping systems. This results in fragmented patient histories, inefficient referral processes to City Health Offices (CHOs) or doctors, and difficulties in generating accurate health reports. 

To address these challenges, the "Smart Health Integration" system was developed. It is a unified health information system designed to digitize patient records, streamline the referral workflow between Barangay Health Workers (BHWs) and doctors, and provide offline-first data entry to accommodate areas with intermittent internet connectivity.

### 1.2 Statement of the Problem
The primary problem addressed by this study is the inefficiency and fragmentation of patient data management in barangay-level healthcare. Specifically, the study seeks to answer:
1. How can patient health records be digitized to ensure continuity of care across different consultations and referrals?
2. How can the system support offline data entry for health workers in areas with poor internet connectivity?
3. How can AI be safely utilized to assist health workers in providing non-prescriptive, supportive home-care guidance?
4. How can the system streamline the generation of periodic health reports?

### 1.3 Objectives of the Study
**General Objective:**
To design, develop, and implement the Smart Health Integration system to improve primary healthcare delivery at the barangay level.

**Specific Objectives:**
1. To develop a cross-platform (web and mobile) application with offline-first synchronization using SQLite and Firebase Firestore.
2. To implement a continuity of care feature through append-only Doctor Notes and a unified patient health timeline.
3. To integrate an AI-assisted classification system that provides safe, supportive home-care recommendations without prescribing medications.
4. To create a reporting module capable of generating bulk period reports and single-record PDFs.

### 1.4 Scope and Delimitations
**Scope:**
The system covers patient record management, prenatal tracking, check-ups, and a referral workflow mapping BHWs to Doctors and CHOs. It features an offline-first architecture to allow continuous usage without internet. The AI component analyzes patient symptoms to suggest home-care instructions, precautions, and estimated recovery times.

**Delimitations:**
The system is **not** an automated diagnosis or prescription tool. Following safety protocols, all AI-generated medication recommendations have been explicitly removed; the AI serves only to provide supportive information. All clinical decisions and prescriptions remain strictly under the responsibility of the attending physician. Furthermore, the system relies on user-inputted symptoms and vitals rather than automated hardware medical sensors.

### 1.5 Significance of the Study
- **For Barangay Health Workers (BHWs):** Reduces manual paperwork and allows for offline data gathering.
- **For Doctors and CHOs:** Provides a clear, chronological history of patient records and Doctor Notes, improving continuity of care.
- **For Patients:** Ensures their medical history is securely preserved and accurately communicated between healthcare providers.

---

## CHAPTER 2: REVIEW OF RELATED LITERATURE AND SYSTEMS

### 2.1 Related Literature
**Digital Health in the Philippines:**
The transition towards digital health records has been a priority for the Department of Health (DOH). Implementing electronic medical records (EMR) at the lowest unit of governance—the barangay—is crucial for universal healthcare.

**Offline-First Architecture:**
In developing countries, internet connectivity is often unstable. Offline-first architectures ensure that applications remain functional regardless of network status. Local caching using SQLite, paired with cloud synchronization tools like Firebase Firestore, provides a robust solution for data consistency once connectivity is restored.

**AI in Primary Healthcare:**
The role of AI in healthcare has shifted from attempted automated diagnoses to decision-support systems. Safety is the primary concern. Modern guidelines recommend that AI systems in clinical settings should provide non-prescriptive guidance (e.g., home care, triage categorization) while leaving medical diagnosis and drug prescriptions to licensed professionals.

### 2.2 Related Systems
**Local Systems:** Various LGU-specific health information systems exist, but many lack offline capabilities or seamless referral tracking between barangay workers and city doctors.
**Foreign Systems:** OpenMRS and District Health Information Software 2 (DHIS2) are widely used globally. While powerful, they can be overly complex for basic BHW workflows and often require constant server connectivity.

---

## CHAPTER 3: METHODOLOGY

### 3.1 System Development Life Cycle (SDLC)
The project utilized the **Agile Methodology**, allowing for iterative development, continuous feedback, and rapid adjustments. The development was broken down into sprints, prioritizing the core database architecture first, followed by offline syncing, UI development, and finally AI integration.

### 3.2 System Architecture
The system employs a serverless, cloud-synchronized architecture:
- **Frontend:** Built with Flutter, supporting both Web and Mobile platforms from a single codebase. It uses a modern Dark Theme UI for improved accessibility (WCAG AAA compliant).
- **Backend/Database:** Firebase Cloud Firestore serves as the primary cloud database, with Firebase Authentication and Cloud Functions handling secure operations (e.g., account management, password resets via Nodemailer).
- **Local Storage:** SQLite (via `sqflite`) is used for local data persistence, enabling the offline-first capability.
- **AI Engine:** A rule-based Dart classifier runs locally on the device to provide instant, offline classification and home-care guidance. An optional Python FastAPI backend utilizing a RandomForest model (trained on a dataset of 96,000+ records) is available for advanced research but kept strictly non-prescriptive in production.

### 3.3 Data Flow and Security
Data entered by a BHW is first written to the local SQLite database. A background sync manager listens for internet connectivity and pushes the data to Firestore. Security is enforced via Firebase Security Rules, ensuring that BHWs only access data within their jurisdiction, while Doctors and CHOs can view patient histories relevant to their assigned referrals.

---

## CHAPTER 4: RESULTS AND DISCUSSION

### 4.1 System Implementation
The Smart Health Integration system was successfully developed and deployed with the following core modules:
1. **Patient Registry & Timeline:** A unified view showing chronological check-ups, prenatal visits, and referrals.
2. **Offline-First Synchronization:** The system correctly caches records locally and syncs them automatically to Firestore without data loss.
3. **Continuity of Care (Doctor Notes):** Doctors can append notes to check-ups. These notes are read-only once created and are visible to subsequent assigned doctors, ensuring continuous patient care.
4. **Report Generation:** A built-in PDF generator creates printable health indicator reports directly on the client side, bypassing the need for a dedicated reporting server.

### 4.2 AI Classification Results
The AI classification module was implemented successfully. The system parses keywords from symptoms and vital signs to determine disease categories (e.g., Communicable, Non-Communicable, Emergency) and severity.
- **Safety Compliance:** The system successfully produces supportive home-care instructions, precautions, and general advice. All medication recommendations were verified to be removed from the system source code, aligning with clinical safety standards.
- **Performance:** The rule-based Dart classifier executes in under 10ms entirely offline, ensuring immediate feedback for BHWs.

### 4.3 UI/UX Enhancements
The analytics dashboard was redesigned using a professional Dark Deep Teal theme, which improved contrast ratios and readability for health workers analyzing data for extended periods.

---

## CHAPTER 5: SUMMARY, CONCLUSIONS, AND RECOMMENDATIONS

### 5.1 Summary
The Smart Health Integration system provides a comprehensive, digitized workflow for Barangay Health Centers. By combining offline-first data entry, secure cloud synchronization, and AI-assisted supportive guidance, the system bridges the communication gap between BHWs and City Health Doctors. The system successfully implements patient tracking, prenatal care, doctor notes, and PDF report generation.

### 5.2 Conclusions
Based on the implementation, the study concludes that:
1. Offline-first architecture using Flutter and Firebase is highly effective for healthcare applications in areas with unreliable internet.
2. Implementing append-only Doctor Notes significantly improves the continuity of care by providing a clear, immutable history of medical advice.
3. Artificial Intelligence can be safely utilized in primary care if heavily restricted to non-prescriptive, supportive guidance rather than automated medication prescriptions.

### 5.3 Recommendations
For future researchers and developers, the following are recommended:
1. **Integration with Hardware:** Incorporate IoT medical devices (e.g., smart blood pressure monitors, digital thermometers) to automate vital sign data entry.
2. **Expansion of AI Dataset:** Continuously evaluate and expand the dataset used for the ML classifier with localized clinical data from the Philippines to improve context-specific accuracy.
3. **SMS Integration:** Add SMS notifications for patients to remind them of upcoming prenatal check-ups or referral appointments.
4. **Full Migration to Design System:** Complete the migration of all legacy screens to the newly established unified design system (`AppTheme`) for consistent branding.
