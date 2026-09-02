import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

const Color _profileAqua = Color(0xFF2F80ED);
const Color _profileSurface = Colors.white;
const Color _profileInk = Color(0xFF0B1F3A);
const Color _profileMuted = Color(0xFF4B6075);

class BHWProfilePage extends StatefulWidget {
  const BHWProfilePage({super.key});

  @override
  State<BHWProfilePage> createState() => _BHWProfilePageState();
}

class _BHWProfilePageState extends State<BHWProfilePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _profile = <String, dynamic>{};
  UserAccessScope _scope = UserAccessScope.unauthenticated;
  final AccountPolicyService _accountPolicy = AccountPolicyService.instance;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('No authenticated user session found.');
      }

      await UserAccessScopeService.instance.ensureCurrentUserRootMirror();
      final scope = await UserAccessScopeService.instance.loadCurrentScope(
        forceRefresh: true,
      );
      final snapshot = await getFirestoreInstance()
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snapshot.data() ?? <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _scope = scope;
        _profile = <String, dynamic>{
          ...data,
          'uid': user.uid,
          'email': _firstValue([data['email'], user.email]),
          'displayName': _firstValue([
            data['fullName'],
            data['displayName'],
            data['username'],
            user.displayName,
          ]),
        };
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  static String _firstValue(Iterable<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  String get _displayName => _firstValue([
    _profile['fullName'],
    _profile['displayName'],
    _profile['username'],
  ], fallback: 'Barangay Health Worker');

  String get _assignedBarangay => _firstValue([
    _profile['barangay'],
    _profile['barangayName'],
    _profile['assignedBarangay'],
    _scope.barangay,
    _scope.barangayCode,
  ], fallback: 'Not assigned');

  String _formatDate(dynamic value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value != null) {
      date = DateTime.tryParse(value.toString());
    }
    if (date == null) return 'Not available';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      body: WebResponsiveBody(
        sidebar: WebAppSidebar(
          userName: _displayName,
          activeItem: WebSidebarItem.profile,
        ),
        title: 'Profile and Settings',
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _profileAqua),
              )
            : _error != null
            ? _buildErrorState()
            : RefreshIndicator(
                onRefresh: _loadProfile,
                color: _profileAqua,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileHero(),
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked = constraints.maxWidth < 850;
                              final identity = _buildInformationCard(
                                title: 'User Details',
                                icon: Icons.badge_outlined,
                                action: OutlinedButton.icon(
                                  onPressed: _showEditDialog,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Edit details'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _profileAqua,
                                    side: const BorderSide(color: _profileAqua),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                                rows: [
                                  _ProfileRow(
                                    'Full name',
                                    _displayName,
                                    Icons.person_outline,
                                  ),
                                  _ProfileRow(
                                    'Username',
                                    _firstValue([
                                      _profile['username'],
                                    ], fallback: 'Not provided'),
                                    Icons.alternate_email_rounded,
                                  ),
                                  _ProfileRow(
                                    'Email address',
                                    _firstValue([
                                      _profile['email'],
                                    ], fallback: 'Not provided'),
                                    Icons.email_outlined,
                                  ),
                                  _ProfileRow(
                                    'Contact number',
                                    _firstValue([
                                      _profile['contactNumber'],
                                      _profile['phoneNumber'],
                                      _profile['phone'],
                                    ], fallback: 'Not provided'),
                                    Icons.phone_outlined,
                                  ),
                                  _ProfileRow(
                                    'Role',
                                    'Barangay Health Worker (BHW)',
                                    Icons.medical_services_outlined,
                                  ),
                                ],
                              );
                              final assignment = _buildInformationCard(
                                title: 'Barangay Assignment',
                                icon: Icons.location_city_outlined,
                                rows: [
                                  _ProfileRow(
                                    'Assigned barangay',
                                    _assignedBarangay,
                                    Icons.location_on_outlined,
                                  ),
                                  _ProfileRow(
                                    'Barangay code',
                                    _firstValue([
                                      _profile['barangayCode'],
                                      _scope.barangayCode,
                                    ], fallback: 'Not provided'),
                                    Icons.tag_rounded,
                                  ),
                                  _ProfileRow(
                                    'District',
                                    _firstValue([
                                      _profile['barangayDistrict'],
                                      _scope.barangayDistrict,
                                    ], fallback: 'Not provided'),
                                    Icons.map_outlined,
                                  ),
                                  _ProfileRow(
                                    'Access scope',
                                    'Assigned barangay records only',
                                    Icons.lock_outline_rounded,
                                  ),
                                  _ProfileRow(
                                    'Member since',
                                    _formatDate(_profile['createdAt']),
                                    Icons.calendar_today_outlined,
                                  ),
                                ],
                              );
                              if (stacked) {
                                return Column(
                                  children: [
                                    identity,
                                    const SizedBox(height: 16),
                                    assignment,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: identity),
                                  const SizedBox(width: 20),
                                  Expanded(child: assignment),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildProfileHero() {
    final initial = _displayName.isEmpty ? 'B' : _displayName[0].toUpperCase();
    final accountStatus = _firstValue([
      _profile['accountStatus'],
      _profile['approvalStatus'],
    ], fallback: 'Active');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _profileAqua.withValues(alpha: 0.35)),
      ),
      child: Wrap(
        spacing: 22,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 82,
            height: 82,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _profileAqua.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: _profileAqua, width: 2),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: _profileInk,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  style: const TextStyle(
                    color: _profileInk,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Barangay Health Worker',
                  style: TextStyle(color: _profileMuted, fontSize: 14),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 9,
                  runSpacing: 8,
                  children: [
                    _buildHeroChip(
                      Icons.location_on_outlined,
                      _assignedBarangay,
                      _profileAqua,
                    ),
                    _buildHeroChip(
                      Icons.verified_user_outlined,
                      accountStatus,
                      _profileAqua,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _profileInk,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationCard({
    required String title,
    required IconData icon,
    Widget? action,
    required List<_ProfileRow> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _profileSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _profileAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _profileAqua, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _profileInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 17),
          ...rows.map(
            (row) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF3FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(row.icon, color: _profileMuted, size: 18),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.label,
                          style: const TextStyle(
                            color: _profileMuted,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          row.value,
                          style: const TextStyle(
                            color: _profileInk,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog() async {
    final fullNameController = TextEditingController(text: _displayName);
    final usernameController = TextEditingController(
      text: _firstValue([_profile['username']]),
    );
    final contactController = TextEditingController(
      text: _firstValue([
        _profile['contactNumber'],
        _profile['phoneNumber'],
        _profile['phone'],
      ]),
    );
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _profileSurface,
          title: const Text(
            'Edit profile details',
            style: TextStyle(color: _profileInk),
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: fullNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: contactController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact number',
                      hintText: '09XXXXXXXXX or +63XXXXXXXXXX',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Email, role, barangay assignment, and access status are managed by the CHO Admin.',
                      style: TextStyle(color: _profileMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final fullName = fullNameController.text.trim();
                      final username = usernameController.text.trim();
                      if (fullName.isEmpty || username.length < 3) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a full name and a username with at least 3 characters.',
                            ),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _accountPolicy.updateOwnBhwProfile(
                          fullName: fullName,
                          username: username,
                          contactNumber: contactController.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (!mounted) return;
                        await _loadProfile();
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Profile details updated.'),
                            backgroundColor: _profileAqua,
                          ),
                        );
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not update profile: ${error.toString()}',
                            ),
                          ),
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    fullNameController.dispose();
    usernameController.dispose();
    contactController.dispose();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: _profileAqua, size: 52),
            const SizedBox(height: 14),
            const Text(
              'Profile could not be loaded',
              style: TextStyle(
                color: _profileInk,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _profileMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow {
  final String label;
  final String value;
  final IconData icon;

  const _ProfileRow(this.label, this.value, this.icon);
}
