typedef PatientNameParts = ({String firstName, String surname});

String _text(dynamic value) => value?.toString().trim() ?? '';

PatientNameParts patientNameParts(Map<String, dynamic> patient) {
  final storedFirstName = _text(patient['firstName']);
  final storedSurname = _text(patient['surname']);
  if (storedFirstName.isNotEmpty || storedSurname.isNotEmpty) {
    return (firstName: storedFirstName, surname: storedSurname);
  }

  final fullName = [
    patient['fullName'],
    patient['patientName'],
    patient['patient'],
    patient['name'],
  ].map(_text).firstWhere((value) => value.isNotEmpty, orElse: () => '');
  if (fullName.isEmpty) return (firstName: '', surname: '');

  final normalized = fullName.replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.contains(',')) {
    final parts = normalized.split(',');
    return (
      firstName: parts.skip(1).join(' ').trim(),
      surname: parts.first.trim(),
    );
  }

  final parts = normalized.split(' ');
  if (parts.length == 1) {
    return (firstName: parts.first, surname: '');
  }
  return (
    firstName: parts.sublist(0, parts.length - 1).join(' '),
    surname: parts.last,
  );
}

String patientDisplayName(
  Map<String, dynamic> patient, {
  String fallback = 'Unknown patient',
}) {
  final parts = patientNameParts(patient);
  final combined = '${parts.firstName} ${parts.surname}'.trim();
  return combined.isEmpty ? fallback : combined;
}
