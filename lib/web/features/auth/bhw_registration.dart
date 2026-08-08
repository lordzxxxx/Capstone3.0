import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/widgets/auth_page_transition.dart';

const _blue = Color(0xFF00A8B5);
const _blueDark = Color(0xFF0A2830);
const _aqua = Color(0xFF00A8B5);
const _ink = Color(0xFFF5F7FA);
const _muted = Color(0xFFA8BBC2);
const _page = Color(0xFF0A1F24);
const _surface = Color(0xFF102E38);
const _surfaceAlt = Color(0xFF123B46);
const _border = Color(0xFF28515A);

class BhwRegistrationPage extends StatefulWidget {
  const BhwRegistrationPage({super.key});

  @override
  State<BhwRegistrationPage> createState() => _BhwRegistrationPageState();
}

class _BhwRegistrationPageState extends State<BhwRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = getFirestoreInstance();
  final _policy = AccountPolicyService.instance;

  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _suffix = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _residentialAddress = TextEditingController();
  final _province = TextEditingController(text: 'Bukidnon');
  final _municipality = TextEditingController(text: 'Malaybalay City');
  final _sitio = TextEditingController();
  final _bhwId = TextEditingController();
  final _assignedSitio = TextEditingController();
  final _yearsOfService = TextEditingController();
  final _position = TextEditingController(text: 'Barangay Health Worker');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _dateOfBirthDisplay = TextEditingController();
  final _dateStartedDisplay = TextEditingController();

  DateTime? _dateOfBirth;
  DateTime? _dateStarted;
  String? _sex;
  String? _civilStatus;
  String _employmentStatus = 'Volunteer';
  BarangayReference? _residentialBarangay;
  BarangayReference? _assignedBarangay;
  bool _truthDeclaration = false;
  bool _reviewDeclaration = false;
  bool _privacyDeclaration = false;
  bool _dataPrivacyDeclaration = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  bool _submitted = false;
  bool _checkingUsername = false;
  bool _checkingEmail = false;
  bool? _usernameAvailable;
  bool? _emailAvailable;
  String? _usernameMessage;
  String? _emailMessage;
  Timer? _usernameDebounce;
  Timer? _emailDebounce;
  bool get _allDeclarations =>
      _truthDeclaration &&
      _reviewDeclaration &&
      _privacyDeclaration &&
      _dataPrivacyDeclaration;

  bool get _strongPassword =>
      _password.text.length >= 8 &&
      RegExp(r'[A-Z]').hasMatch(_password.text) &&
      RegExp(r'[a-z]').hasMatch(_password.text) &&
      RegExp(r'[0-9]').hasMatch(_password.text) &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(_password.text);

  @override
  void initState() {
    super.initState();
    _username.addListener(_scheduleUsernameCheck);
    _email.addListener(_scheduleEmailCheck);
    _password.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _emailDebounce?.cancel();
    for (final controller in <TextEditingController>[
      _firstName,
      _middleName,
      _lastName,
      _suffix,
      _contact,
      _email,
      _residentialAddress,
      _province,
      _municipality,
      _sitio,
      _bhwId,
      _assignedSitio,
      _yearsOfService,
      _position,
      _username,
      _password,
      _confirmPassword,
      _dateOfBirthDisplay,
      _dateStartedDisplay,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _scheduleUsernameCheck() {
    _usernameDebounce?.cancel();
    final value = _username.text.trim();
    if (value.length < 3) {
      setState(() {
        _usernameAvailable = null;
        _usernameMessage = null;
        _checkingUsername = false;
      });
      return;
    }
    setState(() {
      _checkingUsername = true;
      _usernameMessage = 'Checking availability...';
    });
    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final result = await _policy.validateRegistrationPolicy(
          username: value,
        );
        if (!mounted || _username.text.trim() != value) return;
        setState(() {
          _checkingUsername = false;
          _usernameAvailable = !result.usernameExists;
          _usernameMessage = result.usernameExists
              ? 'This username is already registered.'
              : 'Username is available.';
        });
      } catch (_) {
        if (!mounted || _username.text.trim() != value) return;
        setState(() {
          _checkingUsername = false;
          _usernameAvailable = null;
          _usernameMessage = 'Uniqueness will be verified on submission.';
        });
      }
    });
  }

  void _scheduleEmailCheck() {
    _emailDebounce?.cancel();
    final value = _email.text.trim().toLowerCase();
    if (!_validEmail(value)) {
      setState(() {
        _emailAvailable = null;
        _emailMessage = null;
        _checkingEmail = false;
      });
      return;
    }
    setState(() {
      _checkingEmail = true;
      _emailMessage = 'Checking availability...';
    });
    _emailDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final result = await _policy.validateRegistrationPolicy(email: value);
        if (!mounted || _email.text.trim().toLowerCase() != value) return;
        setState(() {
          _checkingEmail = false;
          _emailAvailable = !result.emailExists;
          _emailMessage = result.emailExists
              ? 'This email is already registered.'
              : 'Email is available.';
        });
      } catch (_) {
        if (!mounted || _email.text.trim().toLowerCase() != value) return;
        setState(() {
          _checkingEmail = false;
          _emailAvailable = null;
          _emailMessage = 'Uniqueness will be verified on submission.';
        });
      }
    });
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  String _dateText(DateTime? value) => value == null
      ? ''
      : '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _pickDate({required bool birthDate}) async {
    final initial = birthDate
        ? (_dateOfBirth ?? DateTime(1995))
        : (_dateStarted ?? DateTime.now());
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: birthDate ? DateTime(1940) : DateTime(1970),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _aqua,
            surface: _surface,
            onSurface: _ink,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: _surface),
        ),
        child: child!,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (birthDate) {
        _dateOfBirth = result;
        _dateOfBirthDisplay.text = _dateText(result);
      } else {
        _dateStarted = result;
        _dateStartedDisplay.text = _dateText(result);
      }
    });
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid ||
        _dateOfBirth == null ||
        _sex == null ||
        _civilStatus == null ||
        _residentialBarangay == null ||
        _assignedBarangay == null) {
      _showMessage(
        'Incomplete registration',
        'Please complete every required field.',
        error: true,
      );
      return;
    }
    if (!_allDeclarations) return;
    if (!_strongPassword) {
      _showMessage(
        'Weak password',
        'Your password must meet all five security requirements.',
        error: true,
      );
      return;
    }
    if (_password.text != _confirmPassword.text) {
      _showMessage(
        'Passwords do not match',
        'Re-enter the same password in both fields.',
        error: true,
      );
      return;
    }
    if (_checkingEmail || _checkingUsername) {
      _showMessage(
        'Validation in progress',
        'Please wait for the availability checks to finish.',
      );
      return;
    }
    if (_emailAvailable == false || _usernameAvailable == false) {
      _showMessage(
        'Account already registered',
        'Use a different username and email address.',
        error: true,
      );
      return;
    }
    setState(() => _submitting = true);
    UserCredential? credential;
    try {
      try {
        final policy = await _policy.validateRegistrationPolicy(
          email: _email.text.trim().toLowerCase(),
          username: _username.text.trim(),
        );
        if (policy.emailExists || policy.usernameExists) {
          throw StateError(
            'The email address or username is already registered.',
          );
        }
      } on StateError {
        rethrow;
      } catch (_) {
        // Auth and the Firestore username lock remain authoritative if the
        // optional policy endpoint is temporarily unavailable.
      }

      credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim().toLowerCase(),
        password: _password.text,
      );
      final user = credential.user!;
      await user.updateDisplayName(
        '${_firstName.text.trim()} ${_lastName.text.trim()}',
      );
      final usernameLower = _username.text.trim().toLowerCase();
      final userRef = _firestore.collection('users').doc(user.uid);
      final registrationRequestRef = _firestore
          .collection('bhw_registration_requests')
          .doc(user.uid);
      final usernameRef = _firestore
          .collection('registration_username_locks')
          .doc(usernameLower);
      final assignedBarangayCode = BarangayFirestorePaths.normalizeBarangayCode(
        _assignedBarangay!.code,
      );
      final residentialBarangayCode =
          BarangayFirestorePaths.normalizeBarangayCode(
            _residentialBarangay!.code,
          );
      final barangayUserRef = _firestore
          .collection('barangays')
          .doc(assignedBarangayCode)
          .collection('users')
          .doc(user.uid);
      final now = FieldValue.serverTimestamp();
      final payload = <String, dynamic>{
        'uid': user.uid,
        'role': 'BHW',
        'status': 'Pending Approval',
        'approvalStatus': 'pending',
        'accountStatus': 'pending_approval',
        'isApproved': false,
        'firstName': _firstName.text.trim(),
        'middleName': _middleName.text.trim(),
        'lastName': _lastName.text.trim(),
        'suffix': _suffix.text.trim(),
        'fullName':
            [_firstName.text, _middleName.text, _lastName.text, _suffix.text]
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .join(' '),
        'dateOfBirth': Timestamp.fromDate(_dateOfBirth!),
        'sex': _sex,
        'civilStatus': _civilStatus,
        'username': _username.text.trim(),
        'usernameLower': usernameLower,
        'email': _email.text.trim().toLowerCase(),
        'emailLower': _email.text.trim().toLowerCase(),
        'contactNumber': _contact.text.trim(),
        'residentialAddress': _residentialAddress.text.trim(),
        'address': {
          'province': _province.text.trim(),
          'municipality': _municipality.text.trim(),
          'barangay': _residentialBarangay!.name,
          'barangayCode': residentialBarangayCode,
          'sitio': _sitio.text.trim(),
        },
        'barangay': _assignedBarangay!.name,
        'barangayCode': assignedBarangayCode,
        'barangayDistrict': _assignedBarangay!.district,
        'accessScope': 'barangay',
        'organizationLevel': 'barangay',
        'barangayVerified': false,
        'bhw': {
          'bhwId': _bhwId.text.trim(),
          'assignedBarangay': _assignedBarangay!.name,
          'assignedBarangayCode': assignedBarangayCode,
          'assignedSitio': _assignedSitio.text.trim(),
          'yearsOfService': int.tryParse(_yearsOfService.text.trim()) ?? 0,
          'dateStarted': _dateStarted == null
              ? ''
              : Timestamp.fromDate(_dateStarted!),
          'position': 'Barangay Health Worker',
          'employmentStatus': _employmentStatus,
        },
        'declarations': {
          'informationCertified': true,
          'choReviewAcknowledged': true,
          'privacyPolicyAccepted': true,
          'dataPrivacyActAccepted': true,
          'acceptedAt': Timestamp.now(),
        },
        'createdAt': now,
        'updatedAt': now,
        'approvedBy': null,
        'approvedAt': null,
        'rejectionReason': null,
        'lastLogin': null,
      };

      await _firestore.runTransaction((transaction) async {
        final lock = await transaction.get(usernameRef);
        if (lock.exists && lock.data()?['uid'] != user.uid) {
          throw StateError('This username is already registered.');
        }
        transaction.set(userRef, payload);
        transaction.set(barangayUserRef, {
          ...payload,
          'rootUserPath': userRef.path,
        });
        transaction.set(registrationRequestRef, {
          ...payload,
          'requestId': user.uid,
          'applicantUid': user.uid,
          'requestType': 'BHW_ACCOUNT_REGISTRATION',
          'submissionStatus': 'submitted',
          'submittedAt': now,
          'profilePath': userRef.path,
          'barangayProfilePath': barangayUserRef.path,
          'source': 'public-bhw-registration',
        });
        transaction.set(usernameRef, {
          'uid': user.uid,
          'username': _username.text.trim(),
          'usernameLower': usernameLower,
          'updatedAt': now,
          'source': 'bhw-registration-request',
        });
      });

      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _submitted = true);
    } on FirebaseAuthException catch (error) {
      await _cleanupFailedRegistration(credential);
      final message = switch (error.code) {
        'email-already-in-use' => 'This email address is already registered.',
        'invalid-email' => 'Enter a valid email address.',
        'weak-password' => 'Use a stronger password.',
        'network-request-failed' =>
          'Check your internet connection and try again.',
        _ => error.message ?? 'Registration could not be submitted.',
      };
      _showMessage('Registration failed', message, error: true);
    } catch (error) {
      await _cleanupFailedRegistration(credential);
      _showMessage(
        'Registration failed',
        error.toString().replaceFirst('Bad state: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cleanupFailedRegistration(UserCredential? credential) async {
    try {
      await credential?.user?.delete();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  void _showMessage(String title, String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Semantics(liveRegion: true, child: Text('$title: $message')),
        backgroundColor: error ? Colors.red.shade700 : _blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _successPage();
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: _page,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back to login',
          onPressed: () => replaceWithAuthPage(context, const Login()),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Row(
          children: [
            const Icon(Icons.health_and_safety_rounded, color: _aqua),
            const SizedBox(width: 10),
            Text(
              'BHW Account Registration',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pageHeader(),
                    const SizedBox(height: 24),
                    _section(
                      number: '01',
                      title: 'Personal Information',
                      icon: Icons.badge_outlined,
                      children: [
                        _field(_firstName, 'First Name *', required: true),
                        _field(_middleName, 'Middle Name'),
                        _field(_lastName, 'Last Name *', required: true),
                        _field(_suffix, 'Suffix', hint: 'Jr., Sr., III'),
                        _dateField(
                          'Date of Birth *',
                          _dateOfBirth,
                          () => _pickDate(birthDate: true),
                          required: true,
                        ),
                        _dropdown('Sex *', _sex, const [
                          'Male',
                          'Female',
                        ], (value) => setState(() => _sex = value)),
                        _dropdown(
                          'Civil Status *',
                          _civilStatus,
                          const ['Single', 'Married', 'Widowed', 'Separated'],
                          (value) => setState(() => _civilStatus = value),
                        ),
                        _field(
                          _contact,
                          'Contact Number *',
                          required: true,
                          keyboard: TextInputType.phone,
                          formatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+]'),
                            ),
                            LengthLimitingTextInputFormatter(15),
                          ],
                          validator: (value) =>
                              RegExp(r'^(\+63|0)\d{10}$').hasMatch(value.trim())
                              ? null
                              : 'Use 09XXXXXXXXX or +639XXXXXXXXX.',
                        ),
                        _field(
                          _email,
                          'Email Address *',
                          required: true,
                          keyboard: TextInputType.emailAddress,
                          validator: (value) => _validEmail(value.trim())
                              ? null
                              : 'Enter a valid email address.',
                          helper: _emailMessage,
                          helperGood: _emailAvailable,
                        ),
                        _field(
                          _residentialAddress,
                          'Residential Address *',
                          required: true,
                          wide: true,
                          hint: 'House number, street or landmark',
                        ),
                        _field(_province, 'Province *', required: true),
                        _field(
                          _municipality,
                          'Municipality / City *',
                          required: true,
                        ),
                        _barangayDropdown(
                          'Barangay *',
                          _residentialBarangay,
                          (value) =>
                              setState(() => _residentialBarangay = value),
                        ),
                        _field(_sitio, 'Sitio / Purok'),
                      ],
                    ),
                    _section(
                      number: '02',
                      title: 'BHW Information',
                      icon: Icons.medical_services_outlined,
                      children: [
                        _field(
                          _bhwId,
                          'BHW ID Number',
                          hint: 'Optional if not yet assigned',
                        ),
                        _barangayDropdown(
                          'Assigned Barangay *',
                          _assignedBarangay,
                          (value) => setState(() => _assignedBarangay = value),
                        ),
                        _field(_assignedSitio, 'Assigned Sitio / Purok'),
                        _field(
                          _yearsOfService,
                          'Years of Service',
                          keyboard: TextInputType.number,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (value) =>
                              value.isNotEmpty &&
                                  (int.tryParse(value) ?? -1) < 0
                              ? 'Enter a valid number.'
                              : null,
                        ),
                        _dateField(
                          'Date Started as BHW',
                          _dateStarted,
                          () => _pickDate(birthDate: false),
                        ),
                        _field(_position, 'Position', readOnly: true),
                        _dropdown(
                          'Employment Status',
                          _employmentStatus,
                          const ['Active', 'Volunteer', 'Contractual'],
                          (value) => setState(
                            () => _employmentStatus = value ?? 'Volunteer',
                          ),
                        ),
                      ],
                    ),
                    _section(
                      number: '03',
                      title: 'Account Credentials',
                      icon: Icons.lock_person_outlined,
                      children: [
                        _field(
                          _username,
                          'Username *',
                          required: true,
                          validator: (value) =>
                              RegExp(
                                r'^[A-Za-z0-9._-]{3,30}$',
                              ).hasMatch(value.trim())
                              ? null
                              : 'Use 3–30 letters, numbers, dots, dashes, or underscores.',
                          helper: _usernameMessage,
                          helperGood: _usernameAvailable,
                        ),
                        _field(
                          _email,
                          'Account Email *',
                          required: true,
                          readOnly: true,
                          helper:
                              'Uses the email entered in Personal Information.',
                        ),
                        _passwordField(
                          _password,
                          'Password *',
                          _obscurePassword,
                          () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        _passwordField(
                          _confirmPassword,
                          'Confirm Password *',
                          _obscureConfirm,
                          () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                          confirm: true,
                        ),
                        _passwordRequirements(),
                      ],
                    ),
                    _declarationSection(),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton.icon(
                        onPressed: !_allDeclarations || _submitting
                            ? null
                            : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _aqua,
                          foregroundColor: _page,
                          disabledBackgroundColor: _surfaceAlt,
                          disabledForegroundColor: _muted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _submitting
                              ? 'Submitting registration...'
                              : 'Submit Registration Request',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
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

  Widget _pageHeader() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF123B46), _blueDark, Color(0xFF07191E)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _aqua.withValues(alpha: .22)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .30),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
        BoxShadow(color: _aqua.withValues(alpha: .06), blurRadius: 34),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _aqua.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _aqua.withValues(alpha: .28)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt_1_rounded, color: _aqua, size: 15),
              SizedBox(width: 7),
              Text(
                'BHW ACCOUNT ONBOARDING',
                style: TextStyle(
                  color: _aqua,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Create BHW Account',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Register your account to access AI-DSUHIS.',
          style: TextStyle(
            color: _ink,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your registration request will be reviewed by the City Health Office before your account is activated.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .84),
            height: 1.45,
          ),
        ),
      ],
    ),
  );

  Widget _section({
    required String number,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _aqua.withValues(alpha: .18)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .28),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _aqua.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _aqua.withValues(alpha: .20)),
              ),
              child: Icon(icon, color: _aqua),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                '$number  $title',
                style: GoogleFonts.plusJakartaSans(
                  color: _ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 580
                ? 2
                : 1;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 18,
              children: children
                  .map(
                    (child) => SizedBox(
                      width: child is _WideField ? constraints.maxWidth : width,
                      child: child,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool wide = false,
    bool readOnly = false,
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String value)? validator,
    String? helper,
    bool? helperGood,
  }) {
    final child = TextFormField(
      controller: controller,
      readOnly: readOnly,
      style: const TextStyle(color: _ink),
      cursorColor: _aqua,
      keyboardType: keyboard,
      inputFormatters: formatters,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: _decoration(
        label,
        hint: hint,
        helper: helper,
        helperGood: helperGood,
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (required && text.isEmpty) return '$label is required.';
        return validator?.call(text);
      },
    );
    return wide ? _WideField(child: child) : child;
  }

  Widget _passwordField(
    TextEditingController controller,
    String label,
    bool obscure,
    VoidCallback toggle, {
    bool confirm = false,
  }) => TextFormField(
    controller: controller,
    obscureText: obscure,
    style: const TextStyle(color: _ink),
    cursorColor: _aqua,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: _decoration(label).copyWith(
      suffixIcon: IconButton(
        tooltip: obscure ? 'Show password' : 'Hide password',
        onPressed: toggle,
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: (value) {
      if ((value ?? '').isEmpty) return '$label is required.';
      if (!confirm && !_strongPassword) {
        return 'Password does not meet the security requirements.';
      }
      if (confirm && value != _password.text) return 'Passwords do not match.';
      return null;
    },
  );

  Widget _dateField(
    String label,
    DateTime? value,
    VoidCallback onTap, {
    bool required = false,
  }) => TextFormField(
    readOnly: true,
    controller: label.startsWith('Date of Birth')
        ? _dateOfBirthDisplay
        : _dateStartedDisplay,
    style: const TextStyle(color: _ink),
    cursorColor: _aqua,
    onTap: onTap,
    decoration: _decoration(
      label,
    ).copyWith(suffixIcon: const Icon(Icons.calendar_month_outlined)),
    validator: (_) => required && value == null ? '$label is required.' : null,
  );

  Widget _dropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: _surfaceAlt,
    style: const TextStyle(color: _ink),
    iconEnabledColor: _aqua,
    decoration: _decoration(label),
    items: items
        .map(
          (item) => DropdownMenuItem(
            value: item,
            child: Text(item, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: onChanged,
    validator: (selected) =>
        label.contains('*') && selected == null ? '$label is required.' : null,
  );

  Widget _barangayDropdown(
    String label,
    BarangayReference? value,
    ValueChanged<BarangayReference?> onChanged,
  ) => DropdownButtonFormField<BarangayReference>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: _surfaceAlt,
    style: const TextStyle(color: _ink),
    iconEnabledColor: _aqua,
    decoration: _decoration(label),
    items: MalaybalayBarangays.all
        .map(
          (item) => DropdownMenuItem(
            value: item,
            child: Text(
              '${item.name} — ${item.district}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: onChanged,
    validator: (selected) => selected == null ? '$label is required.' : null,
  );

  InputDecoration _decoration(
    String label, {
    String? hint,
    String? helper,
    bool? helperGood,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperStyle: TextStyle(
      color: helperGood == true
          ? Colors.greenAccent.shade400
          : helperGood == false
          ? Colors.redAccent.shade100
          : _muted,
    ),
    labelStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
    floatingLabelStyle: const TextStyle(
      color: _aqua,
      fontWeight: FontWeight.w700,
    ),
    hintStyle: TextStyle(color: _muted.withValues(alpha: .72)),
    errorStyle: const TextStyle(color: Color(0xFFFF8A80)),
    suffixIconColor: _aqua,
    filled: true,
    fillColor: Colors.transparent,
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _aqua, width: 2),
    ),
  );

  Widget _passwordRequirements() {
    final checks = <String, bool>{
      'Minimum 8 characters': _password.text.length >= 8,
      'Uppercase letter': RegExp(r'[A-Z]').hasMatch(_password.text),
      'Lowercase letter': RegExp(r'[a-z]').hasMatch(_password.text),
      'Number': RegExp(r'[0-9]').hasMatch(_password.text),
      'Special character': RegExp(r'[^A-Za-z0-9]').hasMatch(_password.text),
    };
    final score = checks.values.where((value) => value).length;
    return _WideField(
      child: Semantics(
        label: 'Password strength: $score out of 5 requirements met',
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _page,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Password strength',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
                  ),
                  const Spacer(),
                  Text(
                    score <= 2
                        ? 'Weak'
                        : score < 5
                        ? 'Good'
                        : 'Strong',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: score == 5
                          ? Colors.greenAccent.shade400
                          : score <= 2
                          ? Colors.redAccent.shade100
                          : Colors.orangeAccent.shade200,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: score / 5,
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
                color: score == 5
                    ? Colors.green
                    : score <= 2
                    ? Colors.red
                    : Colors.orange,
                backgroundColor: _border,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: checks.entries
                    .map(
                      (entry) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            entry.value
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 17,
                            color: entry.value ? Colors.green : _muted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _declarationSection() => _section(
    number: '04',
    title: 'Declaration',
    icon: Icons.fact_check_outlined,
    children: [
      _WideField(
        child: Column(
          children: [
            _check(
              'I certify that all information provided is true and correct.',
              _truthDeclaration,
              (value) => setState(() => _truthDeclaration = value),
            ),
            _check(
              'I understand that my registration will be reviewed by the City Health Office.',
              _reviewDeclaration,
              (value) => setState(() => _reviewDeclaration = value),
            ),
            _check(
              'I agree to the Privacy Policy.',
              _privacyDeclaration,
              (value) => setState(() => _privacyDeclaration = value),
            ),
            _check(
              'I agree to the Data Privacy Act of 2012.',
              _dataPrivacyDeclaration,
              (value) => setState(() => _dataPrivacyDeclaration = value),
            ),
            if (!_allDeclarations)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select all declarations to enable submission.',
                    style: TextStyle(color: _muted, fontSize: 12.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          checkColor: _page,
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _aqua;
            if (states.contains(WidgetState.disabled)) {
              return _surfaceAlt.withValues(alpha: .55);
            }
            return _surfaceAlt;
          }),
          side: const BorderSide(color: Color(0xFFE7FAFC), width: 2),
          checkboxShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          overlayColor: WidgetStatePropertyAll(_aqua.withValues(alpha: .14)),
          title: Text(label, style: const TextStyle(color: _ink, fontSize: 14)),
          onChanged: _submitting
              ? null
              : (selected) => onChanged(selected ?? false),
        ),
      );

  Widget _successPage() => Scaffold(
    backgroundColor: _page,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 650),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .34),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Registration submitted',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: _ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Your account request has been submitted successfully.\n\nYour registration is currently under review by the City Health Office.\n\nYou will be able to log in once your account has been approved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 15, height: 1.55),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => replaceWithAuthPage(context, const Login()),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Back to Login'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _aqua,
                    foregroundColor: _page,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _WideField extends StatelessWidget {
  const _WideField({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
