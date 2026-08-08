class UserAccessScope {
  final String userId;
  final String role;
  final String barangay;
  final String barangayCode;
  final String barangayDistrict;
  final DateTime? dataVisibleFrom;

  const UserAccessScope({
    required this.userId,
    required this.role,
    required this.barangay,
    required this.barangayCode,
    required this.barangayDistrict,
    required this.dataVisibleFrom,
  });

  bool get isAuthenticated => userId.isNotEmpty;

  bool get canViewAllBarangays {
    return role == 'cho' ||
        role == 'cho_super_admin' ||
        role == 'super_admin' ||
        role == 'admin';
  }

  bool get isBhw => role == 'bhw';

  bool get hasVisibilityBoundary => dataVisibleFrom != null;

  static const UserAccessScope unauthenticated = UserAccessScope(
    userId: '',
    role: '',
    barangay: '',
    barangayCode: '',
    barangayDistrict: '',
    dataVisibleFrom: null,
  );
}