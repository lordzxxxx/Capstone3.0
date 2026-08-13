/// Plain-language privacy and permission information shared by the mobile and
/// web entry points. Keep this content factual and aligned with the current
/// implementation: the app does not request location access or run tracking.
class PrivacyNoticeSection {
  const PrivacyNoticeSection({required this.title, required this.body});

  final String title;
  final String body;
}

class PrivacyNoticeContent {
  PrivacyNoticeContent._();

  static const String title = 'Privacy and permissions';

  static const String summary =
      'AI-DSUHIS collects account, health-record, and activity information '
      'needed to provide authorized community-health services. Access is '
      'role-based and health information is only for approved care, reporting, '
      'and system operations.';

  static const List<PrivacyNoticeSection> sections = [
    PrivacyNoticeSection(
      title: 'What we collect and why',
      body:
          'The system may collect account details, patient identifiers, '
          'health observations, forms, attachments, report information, and '
          'audit activity. This supports registration, care documentation, '
          'authorized reporting, synchronization, and service security.',
    ),
    PrivacyNoticeSection(
      title: 'Who can access it',
      body:
          'Access is limited by the user role and assigned health-service '
          'scope. Authorized BHW and CHO personnel may view the records needed '
          'for their work. The system does not make health information public.',
    ),
    PrivacyNoticeSection(
      title: 'Mobile permissions',
      body:
          'Camera access is requested only when you choose document scanning, '
          'OCR, or a supporting photo. Photos/Gallery access is requested only '
          'when you choose an existing image for OCR or upload. Location access '
          'is not currently requested, and the app does not continuously track '
          'location or request background location access.',
    ),
    PrivacyNoticeSection(
      title: 'OCR and AI processing',
      body:
          'OCR extracts text from the image selected for that task. Extracted '
          'fields are normalized and shown for review; uncertain values are not '
          'silently treated as correct. AI features provide decision support '
          'using the minimum information needed for the feature. AI output is '
          'not a final diagnosis, prescription, or medication instruction. '
          'Authorized healthcare personnel must review, modify, accept, or '
          'reject important recommendations.',
    ),
    PrivacyNoticeSection(
      title: 'Your choices',
      body:
          'You may deny a permission and continue using unrelated features. '
          'If a feature needs a denied permission, the app explains the impact. '
          'You can enable the permission later from the device Settings app. '
          'Report incorrect records or AI/OCR output to an authorized health '
          'worker for correction.',
    ),
  ];

  static String get dialogText => sections
      .map((section) => '${section.title}\n${section.body}')
      .join('\n\n');
}
