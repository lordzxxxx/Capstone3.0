import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/shared/services/barangay_branding_service.dart';
import 'package:mycapstone_project/web/shared/widgets/barangay_logo_image.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/components/role_decision_support_panel.dart';
import 'package:mycapstone_project/web/shared/utils/web_file_picker.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';

const Color _primaryAqua = AppColors.primary;
// Super-admin uses the same light CHO content surfaces as the other CHO
// workspaces. The shared navy remains reserved for navigation chrome.
const Color _lightOffWhite = AppColors.textPrimary;
const Color _panelSurface = AppColors.surfaceLight;
const Color _sidebarDark = AppColors.surfaceSubtle;
const Color _mutedCoolGray = AppColors.textSecondary;

class _SelectedBrandingFile {
  final Uint8List bytes;
  final String fileName;
  final String contentType;

  const _SelectedBrandingFile({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });
}

class ChoSuperAdminCenter extends StatefulWidget {
  const ChoSuperAdminCenter({super.key});

  @override
  State<ChoSuperAdminCenter> createState() => _ChoSuperAdminCenterState();
}

class _ChoSuperAdminCenterState extends State<ChoSuperAdminCenter> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final BarangayBrandingService _brandingService =
      BarangayBrandingService.instance;
  final AccountPolicyService _accountPolicyService =
      AccountPolicyService.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _checkingAccess = true;
  bool _authorized = false;
  String _searchQuery = '';
  String _selectedRoleFilter = 'ALL';
  String _selectedBarangayFilter = 'ALL';
  String _selectedStatusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _verifyAccess();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSuperAdminRole(String role) {
    final normalized = role.trim().toLowerCase();
    return normalized == 'cho_admin' ||
        normalized == 'cho_super_admin' ||
        normalized == 'super_admin' ||
        normalized == 'admin';
  }

  Future<void> _verifyAccess() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.offAllNamed(WebRoutes.login);
        return;
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final profile = userDoc.data() ?? <String, dynamic>{};
      final role = (profile['role'] ?? '').toString();
      final approval = (profile['approvalStatus'] ?? '')
          .toString()
          .toLowerCase();
      final status = (profile['accountStatus'] ?? profile['status'] ?? '')
          .toString()
          .toLowerCase();

      if (_isSuperAdminRole(role) &&
          approval == 'approved' &&
          status == 'active') {
        if (!mounted) return;
        setState(() {
          _authorized = true;
          _checkingAccess = false;
        });
        return;
      }

      Get.snackbar(
        'Access denied',
        'You need a CHO Super Admin account to open this module.',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        Get.offAllNamed(WebRoutes.login);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CHO Super Admin access check failed: $e');
      }
      Get.snackbar(
        'Error',
        'Could not verify CHO Super Admin access.',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      if (mounted) {
        Get.offAllNamed(WebRoutes.login);
      }
    }
  }

  Future<void> _updateUserGovernance(
    String uid,
    Map<String, dynamic> updates,
  ) async {
    await _accountPolicyService.updateChoAccount(
      uid: uid,
      role: updates['role']?.toString(),
      accountStatus: updates['accountStatus']?.toString(),
      barangay: updates.containsKey('barangay')
          ? (updates['barangay'] is FieldValue
                ? ''
                : updates['barangay']?.toString())
          : null,
      barangayCode: updates.containsKey('barangayCode')
          ? (updates['barangayCode'] is FieldValue
                ? ''
                : updates['barangayCode']?.toString())
          : null,
      barangayDistrict: updates.containsKey('barangayDistrict')
          ? (updates['barangayDistrict'] is FieldValue
                ? ''
                : updates['barangayDistrict']?.toString())
          : null,
    );
  }

  Future<void> _setRole(String uid, String role) async {
    final isBarangayScoped = role.toUpperCase() == 'BHW';
    await _updateUserGovernance(uid, <String, dynamic>{
      'role': role,
      if (isBarangayScoped) 'accountStatus': 'disabled',
      'accessScope': isBarangayScoped ? 'barangay' : 'citywide',
      if (!isBarangayScoped) 'barangay': FieldValue.delete(),
      if (!isBarangayScoped) 'barangayCode': FieldValue.delete(),
      if (!isBarangayScoped) 'barangayDistrict': FieldValue.delete(),
      if (!isBarangayScoped) 'barangayVerified': false,
    });
    Get.snackbar(
      'Saved',
      'User role updated to $role.',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _setAccountStatus(String uid, String status) async {
    await _updateUserGovernance(uid, <String, dynamic>{
      'accountStatus': status,
    });
    Get.snackbar(
      'Saved',
      'Account status updated to $status.',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _setApprovalStatus(String uid, String status) async {
    if (status.toLowerCase() != 'approved') {
      Get.snackbar(
        'Approval is retained',
        'Use account status to disable access. BHW approvals are not silently revoked from the user list.',
        backgroundColor: AppColors.warning,
        colorText: Colors.white,
      );
      return;
    }
    await _accountPolicyService.reviewBhwRegistration(uid: uid, approved: true);
    Get.snackbar(
      'Saved',
      'Approval status updated to $status.',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _assignBarangay(String uid, BarangayReference barangay) async {
    await _updateUserGovernance(uid, <String, dynamic>{
      'barangay': barangay.name,
      'barangayCode': barangay.code,
      'barangayDistrict': barangay.district,
      'barangayVerified': true,
    });
    Get.snackbar(
      'Saved',
      'Assigned ${barangay.name} to the user profile.',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _releaseBarangay(String uid) async {
    await _updateUserGovernance(uid, <String, dynamic>{
      'accountStatus': 'disabled',
      'barangay': FieldValue.delete(),
      'barangayCode': FieldValue.delete(),
      'barangayDistrict': FieldValue.delete(),
      'barangayVerified': false,
    });
    Get.snackbar(
      'Saved',
      'Barangay assignment released from the user profile.',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<BarangayReference?> _pickBarangay() async {
    return showDialog<BarangayReference>(
      context: context,
      builder: (dialogContext) {
        final searchController = TextEditingController();
        String selectedDistrict = 'ALL';
        final districtOptions = <String>[
          'ALL',
          ...{
            ...MalaybalayBarangays.districtOrder,
            ...MalaybalayBarangays.all.map((barangay) => barangay.district),
          },
        ];

        return StatefulBuilder(
          builder: (context, setPickerState) {
            final filtered = MalaybalayBarangays.search(
              searchController.text,
              district: selectedDistrict == 'ALL' ? null : selectedDistrict,
            );

            return AlertDialog(
              backgroundColor: _sidebarDark,
              title: const Text(
                'Assign Barangay',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WebSearchField(
                      controller: searchController,
                      hintText: 'Search barangay or district',
                      onChanged: (_) => setPickerState(() {}),
                      onClear: () {
                        searchController.clear();
                        setPickerState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    WebFilterSurface(
                      padding: const EdgeInsets.all(10),
                      child: WebFilterDropdown<String>(
                        label: 'District',
                        width: double.infinity,
                        value: selectedDistrict,
                        items: districtOptions
                            .map(
                              (district) => DropdownMenuItem<String>(
                                value: district,
                                child: Text(
                                  district == 'ALL'
                                      ? 'All Districts'
                                      : district,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setPickerState(() {
                            selectedDistrict = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _panelSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.18),
                          ),
                        ),
                        child: filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'No barangay matched your search or district filter.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(
                                        alpha: 0.72,
                                      ),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final barangay = filtered[index];
                                  return ListTile(
                                    title: Text(
                                      barangay.name,
                                      style: const TextStyle(
                                        color: _lightOffWhite,
                                      ),
                                    ),
                                    subtitle: Text(
                                      barangay.district,
                                      style: TextStyle(
                                        color: _lightOffWhite.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.of(dialogContext).pop(barangay);
                                    },
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showInviteDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    String selectedRole = 'DOCTOR';
    String specialization = 'General Medicine';
    String availability = 'available';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setInviteState) {
            return AlertDialog(
              backgroundColor: _sidebarDark,
              title: const Text(
                'Invite User',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: InputDecoration(
                        hintText: 'user@example.com',
                        hintStyle: TextStyle(
                          color: _mutedCoolGray.withValues(alpha: 0.85),
                        ),
                        filled: true,
                        fillColor: _panelSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      dropdownColor: _panelSurface,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: InputDecoration(
                        labelText: 'Role',
                        labelStyle: const TextStyle(color: _lightOffWhite),
                        filled: true,
                        fillColor: _panelSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: const <String>['CHO', 'DOCTOR']
                          .map(
                            (role) => DropdownMenuItem<String>(
                              value: role,
                              child: Text(role),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setInviteState(() {
                          selectedRole = value;
                        });
                      },
                    ),
                    if (selectedRole == 'DOCTOR') ...[
                      const SizedBox(height: 16),
                      TextField(
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: const InputDecoration(
                          labelText: 'Specialization',
                        ),
                        onChanged: (value) => specialization = value,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: availability,
                        items:
                            const <String>[
                                  'available',
                                  'busy',
                                  'limited',
                                  'unavailable',
                                ]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => setInviteState(
                          () => availability = value ?? availability,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _panelSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          'CHO accounts receive city-wide access. The account holder will activate access through a secure email from AI-DSUHIS.',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final email = emailController.text.trim();
                    final fullName = nameController.text.trim();
                    if (email.isEmpty || fullName.isEmpty) {
                      Get.snackbar(
                        'Incomplete',
                        'Full name and email are required.',
                        backgroundColor: Colors.orange,
                        colorText: Colors.white,
                      );
                      return;
                    }
                    try {
                      final result = await _accountPolicyService
                          .createChoAccount(
                            fullName: fullName,
                            email: email,
                            role: selectedRole,
                            specialization: specialization,
                            availability: availability,
                          );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      Get.snackbar(
                        result.activationEmailSent
                            ? 'Account created'
                            : 'Account created; email pending',
                        result.activationEmailSent
                            ? 'A secure activation email was sent from AI-DSUHIS.'
                            : 'The account exists, but the system mailer could not send the activation email.',
                        backgroundColor: result.activationEmailSent
                            ? AppColors.success
                            : AppColors.warning,
                        colorText: Colors.white,
                      );
                    } catch (error) {
                      Get.snackbar(
                        'Account creation failed',
                        error.toString(),
                        backgroundColor: AppColors.error,
                        colorText: Colors.white,
                      );
                    }
                  },
                  child: const Text('Create account'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
  }

  Future<_SelectedBrandingFile?> _pickBrandingFile() async {
    if (!kIsWeb) {
      Get.snackbar(
        'Unsupported',
        'Direct file uploads are currently available on the web admin portal only.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return null;
    }

    final file = await pickWebFile(accept: 'image/*');
    if (file == null) return null;
    return _SelectedBrandingFile(
      bytes: file.bytes,
      fileName: file.name,
      contentType: file.mimeType.isEmpty ? 'image/png' : file.mimeType,
    );
  }

  Future<void> _showBrandingEditor(BarangayReference barangay) async {
    final current = await _brandingService.getBranding(barangay);
    if (!mounted) return;
    final logoUrlController = TextEditingController(text: current.logoUrl);
    final signatureUrlController = TextEditingController(
      text: current.officialESignatureUrl,
    );
    final assignedOfficialController = TextEditingController(
      text: current.assignedOfficial,
    );
    final effectiveDateController = TextEditingController(
      text: current.effectiveDate,
    );
    final notesController = TextEditingController(text: current.notes);

    String logoStoragePath = current.logoStoragePath;
    bool isSaving = false;
    bool isUploadingLogo = false;
    bool isUploadingSignature = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final resolvedLogoUrl = logoUrlController.text.trim().isNotEmpty
                ? logoUrlController.text.trim()
                : BarangayBrandingService.placeholderLogoUrl;
            final resolvedSignatureUrl =
                signatureUrlController.text.trim().isNotEmpty
                ? signatureUrlController.text.trim()
                : BarangayBrandingService.placeholderLogoUrl;

            Future<void> uploadAsset(bool isSignature) async {
              final selected = await _pickBrandingFile();
              if (selected == null) return;

              setDialogState(() {
                if (isSignature) {
                  isUploadingSignature = true;
                } else {
                  isUploadingLogo = true;
                }
              });

              try {
                final uploaded = await _brandingService.uploadBrandingAsset(
                  barangay: barangay,
                  bytes: selected.bytes,
                  originalFileName: selected.fileName,
                  contentType: selected.contentType,
                  isSignature: isSignature,
                );

                setDialogState(() {
                  if (isSignature) {
                    signatureUrlController.text = uploaded.downloadUrl;
                  } else {
                    logoUrlController.text = uploaded.downloadUrl;
                    logoStoragePath = uploaded.storagePath;
                  }
                });
              } catch (e) {
                Get.snackbar(
                  'Upload failed',
                  'Could not upload the selected image: $e',
                  backgroundColor: Colors.redAccent,
                  colorText: Colors.white,
                );
              } finally {
                setDialogState(() {
                  if (isSignature) {
                    isUploadingSignature = false;
                  } else {
                    isUploadingLogo = false;
                  }
                });
              }
            }

            return AlertDialog(
              backgroundColor: _sidebarDark,
              title: Text(
                'Manage ${barangay.name} Branding',
                style: const TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _panelSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BarangayLogoImage(
                              imageUrl: resolvedLogoUrl,
                              size: 104,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    barangay.name,
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    barangay.district,
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(
                                        alpha: 0.68,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    logoUrlController.text.trim().isNotEmpty
                                        ? 'Official logo URL is active and will render automatically during BHW registration.'
                                        : 'No official logo URL is set yet. A placeholder will remain active until a logo is uploaded or mapped.',
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(
                                        alpha: 0.78,
                                      ),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildBrandingInput(
                        controller: logoUrlController,
                        label: 'Logo URL',
                        hint:
                            'https://yourdomain.com/assets/barangay-logos/${barangay.code}.png',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isUploadingLogo
                                ? null
                                : () => uploadAsset(false),
                            icon: isUploadingLogo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.upload_file_outlined),
                            label: Text(
                              isUploadingLogo
                                  ? 'Uploading logo...'
                                  : 'Upload logo file',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: logoUrlController.text.trim().isEmpty
                                ? null
                                : () {
                                    setDialogState(() {
                                      logoUrlController.clear();
                                      logoStoragePath = '';
                                    });
                                  },
                            icon: const Icon(Icons.layers_clear_outlined),
                            label: const Text('Use placeholder'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primaryAqua,
                              side: BorderSide(
                                color: _primaryAqua.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildBrandingInput(
                        controller: assignedOfficialController,
                        label: 'Assigned official',
                        hint: 'Barangay Captain or authorized official',
                      ),
                      const SizedBox(height: 12),
                      _buildBrandingInput(
                        controller: effectiveDateController,
                        label: 'Effective date',
                        hint: 'YYYY-MM-DD',
                      ),
                      const SizedBox(height: 12),
                      _buildBrandingInput(
                        controller: signatureUrlController,
                        label: 'E-signature URL',
                        hint:
                            'https://yourdomain.com/assets/barangay-logos/${barangay.code}-esign.png',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isUploadingSignature
                                ? null
                                : () => uploadAsset(true),
                            icon: isUploadingSignature
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.draw_outlined),
                            label: Text(
                              isUploadingSignature
                                  ? 'Uploading e-sign...'
                                  : 'Upload e-sign file',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          if (signatureUrlController.text.trim().isNotEmpty)
                            BarangayLogoImage(
                              imageUrl: resolvedSignatureUrl,
                              size: 52,
                              borderRadius: BorderRadius.circular(12),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildBrandingInput(
                        controller: notesController,
                        label: 'Notes',
                        hint:
                            'Usage notes, version details, or document references',
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final effectiveDate = effectiveDateController.text
                              .trim();
                          if (effectiveDate.isNotEmpty &&
                              DateTime.tryParse(effectiveDate) == null) {
                            Get.snackbar(
                              'Invalid date',
                              'Use YYYY-MM-DD for the effective date.',
                              backgroundColor: Colors.orange,
                              colorText: Colors.white,
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            await _brandingService.saveBranding(
                              barangay: barangay,
                              logoUrl: logoUrlController.text,
                              logoStoragePath: logoStoragePath,
                              assignedOfficial: assignedOfficialController.text,
                              officialESignatureUrl:
                                  signatureUrlController.text,
                              effectiveDate: effectiveDateController.text,
                              notes: notesController.text,
                              updatedBy: FirebaseAuth.instance.currentUser?.uid,
                            );
                            if (context.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            Get.snackbar(
                              'Branding saved',
                              '${barangay.name} logo mapping and metadata were updated.',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                            );
                          } catch (e) {
                            Get.snackbar(
                              'Save failed',
                              'Could not save barangay branding details: $e',
                              backgroundColor: Colors.redAccent,
                              colorText: Colors.white,
                            );
                          } finally {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  child: Text(isSaving ? 'Saving...' : 'Save branding'),
                ),
              ],
            );
          },
        );
      },
    );

    logoUrlController.dispose();
    signatureUrlController.dispose();
    assignedOfficialController.dispose();
    effectiveDateController.dispose();
    notesController.dispose();
  }

  Widget _buildBrandingInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: _lightOffWhite),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _lightOffWhite),
        hintStyle: TextStyle(color: _mutedCoolGray.withValues(alpha: 0.85)),
        filled: true,
        fillColor: _panelSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filtered = docs.where((doc) {
      final data = doc.data();
      final email = (data['email'] ?? '').toString().toLowerCase();
      final username = (data['username'] ?? '').toString().toLowerCase();
      final role = (data['role'] ?? '').toString().toUpperCase();
      final barangay = (data['barangay'] ?? '').toString();
      final status = (data['accountStatus'] ?? 'active')
          .toString()
          .toLowerCase();

      final matchesSearch =
          _searchQuery.isEmpty ||
          email.contains(_searchQuery) ||
          username.contains(_searchQuery) ||
          barangay.toLowerCase().contains(_searchQuery);
      final matchesRole =
          _selectedRoleFilter == 'ALL' || role == _selectedRoleFilter;
      final matchesBarangay =
          _selectedBarangayFilter == 'ALL' ||
          barangay == _selectedBarangayFilter;
      final matchesStatus =
          _selectedStatusFilter == 'ALL' || status == _selectedStatusFilter;

      return matchesSearch && matchesRole && matchesBarangay && matchesStatus;
    }).toList();

    filtered.sort((a, b) {
      final aEmail = (a.data()['email'] ?? '').toString().toLowerCase();
      final bEmail = (b.data()['email'] ?? '').toString().toLowerCase();
      return aEmail.compareTo(bEmail);
    });
    return filtered;
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return AppMetricCard(label: label, value: value, icon: icon, compact: true);
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'disabled':
        return AppColors.error;
      case 'pending':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  Color _approvalColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  Widget _buildUserCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final username = (data['username'] ?? 'Unnamed User').toString();
    final email = (data['email'] ?? 'No email').toString();
    final role = (data['role'] ?? 'BHW').toString().toUpperCase();
    final barangay = (data['barangay'] ?? '').toString();
    final district = (data['barangayDistrict'] ?? '').toString();
    final accountStatus = (data['accountStatus'] ?? 'active').toString();
    final approvalStatus = (data['approvalStatus'] ?? 'pending').toString();
    final requiresBarangay = role == 'BHW';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChip(role, _primaryAqua),
                  _buildChip(
                    accountStatus.toUpperCase(),
                    _statusColor(accountStatus),
                  ),
                  _buildChip(
                    approvalStatus.toUpperCase(),
                    _approvalColor(approvalStatus),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            requiresBarangay
                ? '${barangay.isEmpty ? 'Unassigned' : barangay} • ${district.isEmpty ? 'No district' : district}'
                : 'City-wide operational access',
            style: const TextStyle(
              color: _lightOffWhite,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (requiresBarangay) ...[
            const SizedBox(height: 6),
            Text(
              barangay.isEmpty
                  ? 'No barangay is currently locked to this account.'
                  : 'Super Admin can release or reassign this barangay for recovery, restructuring, or governance exceptions.',
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.64),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue: role,
                  dropdownColor: _sidebarDark,
                  style: const TextStyle(color: _lightOffWhite),
                  decoration: InputDecoration(
                    labelText: 'Role',
                    labelStyle: const TextStyle(color: _lightOffWhite),
                    filled: true,
                    fillColor: _sidebarDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: MalaybalayBarangays.roleOptions
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null || value == role) return;
                    await _setRole(doc.id, value);
                  },
                ),
              ),
              if (requiresBarangay)
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickBarangay();
                    if (picked == null) return;
                    await _assignBarangay(doc.id, picked);
                  },
                  icon: const Icon(Icons.location_city),
                  label: const Text('Assign barangay'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryAqua,
                    side: BorderSide(
                      color: _primaryAqua.withValues(alpha: 0.35),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              if (requiresBarangay && barangay.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    await _releaseBarangay(doc.id);
                  },
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Release barangay'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB74D),
                    side: const BorderSide(color: Color(0xFFFFB74D)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              if (requiresBarangay &&
                  approvalStatus.toLowerCase() != 'approved')
                OutlinedButton.icon(
                  onPressed: () async {
                    await _setApprovalStatus(doc.id, 'approved');
                  },
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Approve BHW'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final nextStatus = accountStatus.toLowerCase() == 'disabled'
                      ? 'active'
                      : 'disabled';
                  await _setAccountStatus(doc.id, nextStatus);
                },
                icon: const Icon(Icons.lock_reset_outlined),
                label: Text(
                  accountStatus.toLowerCase() == 'disabled'
                      ? 'Activate account'
                      : 'Disable account',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _statusColor(accountStatus),
                  side: BorderSide(color: _statusColor(accountStatus)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarangayDirectory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final counts = <String, int>{};
    for (final doc in docs) {
      final barangay = (doc.data()['barangay'] ?? '').toString();
      if (barangay.isEmpty) continue;
      counts.update(barangay, (value) => value + 1, ifAbsent: () => 1);
    }

    final grouped = MalaybalayBarangays.groupedByDistrict();
    return StreamBuilder<List<BarangayBrandingProfile>>(
      stream: _brandingService.watchAllBranding(),
      builder: (context, snapshot) {
        final profiles =
            snapshot.data ??
            MalaybalayBarangays.all
                .map(BarangayBrandingProfile.fallback)
                .toList();
        final profileByCode = <String, BarangayBrandingProfile>{
          for (final profile in profiles) profile.barangay.code: profile,
        };

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Official Barangay Directory',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'System-embedded registry used as the single source of truth for onboarding, logo mapping, e-sign metadata, and barangay asset governance.',
                style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
              ),
              const SizedBox(height: 14),
              ...grouped.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          color: _primaryAqua,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: entry.value.map((barangay) {
                          final assignedUsers = counts[barangay.name] ?? 0;
                          final profile =
                              profileByCode[barangay.code] ??
                              BarangayBrandingProfile.fallback(barangay);

                          return Container(
                            width: 280,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _sidebarDark,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _primaryAqua.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    BarangayLogoImage(
                                      imageUrl: profile.resolvedLogoUrl,
                                      size: 64,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            barangay.name,
                                            style: const TextStyle(
                                              color: _lightOffWhite,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$assignedUsers assigned user${assignedUsers == 1 ? '' : 's'}',
                                            style: TextStyle(
                                              color: _lightOffWhite.withValues(
                                                alpha: 0.65,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            profile.hasCustomLogo
                                                ? 'Official logo mapped'
                                                : 'Placeholder active',
                                            style: TextStyle(
                                              color: profile.hasCustomLogo
                                                  ? AppColors.success
                                                  : AppColors.warning,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  profile.assignedOfficial.trim().isEmpty
                                      ? 'No assigned official recorded'
                                      : 'Official: ${profile.assignedOfficial}',
                                  style: TextStyle(
                                    color: _lightOffWhite.withValues(
                                      alpha: 0.78,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  profile.effectiveDate.trim().isEmpty
                                      ? 'No effective date recorded'
                                      : 'Effective: ${profile.effectiveDate}',
                                  style: TextStyle(
                                    color: _lightOffWhite.withValues(
                                      alpha: 0.65,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                                if (profile.notes.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    profile.notes,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(
                                        alpha: 0.58,
                                      ),
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _showBrandingEditor(barangay),
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  label: const Text('Manage logo and details'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _primaryAqua,
                                    side: BorderSide(
                                      color: _primaryAqua.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_authorized) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: ChoColors.background,
      body: WebResponsiveBody(
        sidebar: const ChoNavigationDrawer(current: ChoDestination.dashboard),
        title: 'User Administration',
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore.collection('users').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ChoErrorState(
                message: 'User administration data could not be loaded.',
                onRetry: () => setState(() {}),
              );
            }
            if (!snapshot.hasData) {
              return const ChoLoadingSkeleton();
            }

            final docs = snapshot.data!.docs;
            final filteredDocs = _filterUsers(docs);
            final pendingApprovals = docs.where((doc) {
              final data = doc.data();
              final role = (data['role'] ?? '').toString().toUpperCase();
              final approval = (data['approvalStatus'] ?? 'pending')
                  .toString()
                  .toLowerCase();
              return role == 'BHW' && approval != 'approved';
            }).length;
            final activeBhw = docs.where((doc) {
              final role = (doc.data()['role'] ?? '').toString().toUpperCase();
              return role == 'BHW';
            }).length;
            final choScoped = docs.where((doc) {
              final role = (doc.data()['role'] ?? '').toString().toUpperCase();
              return role == 'CHO' ||
                  role == 'CHO_ADMIN' ||
                  role == 'CHO_SUPER_ADMIN';
            }).length;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Centralized governance for all Malaybalay barangays',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.74),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const RoleDecisionSupportPanel(
                    audience: DecisionSupportAudience.administrator,
                    summary:
                        'Administrative users manage access and provenance. Patient-level suggestions and clinical actions remain in authorized care workflows.',
                    items: <DecisionSupportItem>[
                      DecisionSupportItem(
                        label: 'Patient analysis',
                        value: 'Hidden in admin view',
                        icon: Icons.visibility_off_outlined,
                      ),
                      DecisionSupportItem(
                        label: 'Model artifact',
                        value: 'Hash verification required',
                        icon: Icons.verified_user_outlined,
                      ),
                      DecisionSupportItem(
                        label: 'Guidance content',
                        value: 'Human-reviewed sources',
                        icon: Icons.fact_check_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1000
                          ? 4
                          : constraints.maxWidth >= 600
                          ? 2
                          : 1;
                      return GridView.count(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: columns == 1 ? 3.2 : 1.8,
                        children: [
                          _buildStatCard(
                            label: 'Registered users',
                            value: docs.length.toString(),
                            icon: Icons.groups_2_outlined,
                          ),
                          _buildStatCard(
                            label: 'BHW accounts',
                            value: activeBhw.toString(),
                            icon: Icons.health_and_safety_outlined,
                          ),
                          _buildStatCard(
                            label: 'CHO governance roles',
                            value: choScoped.toString(),
                            icon: Icons.admin_panel_settings_outlined,
                          ),
                          _buildStatCard(
                            label: 'Pending BHW approvals',
                            value: pendingApprovals.toString(),
                            icon: Icons.rule_folder_outlined,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _panelSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'User Governance',
                                style: TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _showInviteDialog,
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: const Text('Create CHO account'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryAqua,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        WebFilterSurface(
                          padding: const EdgeInsets.all(10),
                          children: [
                            WebSearchField(
                              controller: _searchController,
                              width: 280,
                              hintText: 'Search email, username, barangay',
                            ),
                            WebFilterDropdown<String>(
                              label: 'Role',
                              value: _selectedRoleFilter,
                              width: 170,
                              items:
                                  <String>[
                                        'ALL',
                                        ...MalaybalayBarangays.roleOptions,
                                      ]
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedRoleFilter = value);
                              },
                            ),
                            WebFilterDropdown<String>(
                              label: 'Barangay',
                              value: _selectedBarangayFilter,
                              width: 220,
                              items:
                                  <String>[
                                        'ALL',
                                        ...MalaybalayBarangays.all.map(
                                          (item) => item.name,
                                        ),
                                      ]
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedBarangayFilter = value);
                              },
                            ),
                            WebFilterDropdown<String>(
                              label: 'Status',
                              value: _selectedStatusFilter,
                              width: 170,
                              items: const <String>['ALL', 'active', 'disabled']
                                  .map(
                                    (value) => DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value.toUpperCase()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedStatusFilter = value);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${filteredDocs.length} user${filteredDocs.length == 1 ? '' : 's'} matched',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.68),
                          ),
                        ),
                        const SizedBox(height: 14),
                        WebTableSurface(
                          minWidth: 1100,
                          child: Column(
                            children: filteredDocs.map(_buildUserCard).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildBarangayDirectory(docs),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
