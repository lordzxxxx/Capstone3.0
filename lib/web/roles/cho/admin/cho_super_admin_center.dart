import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/roles/cho/dashboard/cho_dashboard.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/shared/services/barangay_branding_service.dart';
import 'package:mycapstone_project/web/shared/widgets/barangay_logo_image.dart';
import 'package:universal_html/html.dart' as html;

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _panelSurface = Color(0xFF061920);
const Color _sidebarDark = Color(0xFF0E2F34);
const Color _mutedCoolGray = Color(0xFF546E7A);

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
    return normalized == 'cho_super_admin' ||
        normalized == 'super_admin' ||
        normalized == 'admin';
  }

  Future<void> _verifyAccess() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.offAll(() => const Login());
        return;
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final role = (userDoc.data()?['role'] ?? '').toString();

      if (_isSuperAdminRole(role)) {
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
        Get.offAll(() => const Login());
      }
    } catch (e) {
      if (kDebugMode) {
        print('CHO Super Admin access check failed: $e');
      }
      Get.snackbar(
        'Error',
        'Could not verify CHO Super Admin access.',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      if (mounted) {
        Get.offAll(() => const Login());
      }
    }
  }

  Future<void> _updateUserGovernance(
    String uid,
    Map<String, dynamic> updates,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final payload = <String, dynamic>{
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': currentUser?.uid,
    };

    await _firestore.collection('users').doc(uid).set(
      payload,
      SetOptions(merge: true),
    );

    try {
      final rtdbUpdates = <String, dynamic>{
        'updatedAt': ServerValue.timestamp,
      };
      if (updates.containsKey('role')) {
        rtdbUpdates['role'] = updates['role'];
      }
      if (updates.containsKey('barangay')) {
        rtdbUpdates['barangay'] = updates['barangay'] is FieldValue ? null : updates['barangay'];
      }
      if (updates.containsKey('barangayCode')) {
        rtdbUpdates['barangayCode'] = updates['barangayCode'] is FieldValue ? null : updates['barangayCode'];
      }
      if (updates.containsKey('barangayDistrict')) {
        rtdbUpdates['barangayDistrict'] = updates['barangayDistrict'] is FieldValue ? null : updates['barangayDistrict'];
      }
      if (updates.containsKey('accountStatus')) {
        rtdbUpdates['accountStatus'] = updates['accountStatus'];
      }
      if (updates.containsKey('approvalStatus')) {
        rtdbUpdates['approvalStatus'] = updates['approvalStatus'];
      }

      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(uid)
          .update(rtdbUpdates);
    } catch (e) {
      if (kDebugMode) {
        print('CHO Super Admin RTDB mirror update failed for $uid: $e');
      }
    }
  }

  Future<void> _setRole(String uid, String role) async {
    final isBarangayScoped = role.toUpperCase() == 'BHW';
    await _updateUserGovernance(uid, <String, dynamic>{
      'role': role,
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
    await _updateUserGovernance(uid, <String, dynamic>{'accountStatus': status});
    Get.snackbar(
      'Saved',
      'Account status updated to $status.',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _setApprovalStatus(String uid, String status) async {
    await _updateUserGovernance(uid, <String, dynamic>{
      'approvalStatus': status,
      if (status == 'approved') 'approvedAt': FieldValue.serverTimestamp(),
      if (status == 'approved')
        'approvedBy': FirebaseAuth.instance.currentUser?.uid,
    });
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
                    TextField(
                      controller: searchController,
                      onChanged: (_) => setPickerState(() {}),
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: InputDecoration(
                        hintText: 'Search barangay or district',
                        hintStyle: TextStyle(
                          color: _mutedCoolGray.withValues(alpha: 0.85),
                        ),
                        prefixIcon: const Icon(Icons.search, color: _primaryAqua),
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
                      initialValue: selectedDistrict,
                      dropdownColor: _panelSurface,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: InputDecoration(
                        labelText: 'District',
                        labelStyle: const TextStyle(color: _lightOffWhite),
                        filled: true,
                        fillColor: _panelSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: districtOptions
                          .map(
                            (district) => DropdownMenuItem<String>(
                              value: district,
                              child: Text(
                                district == 'ALL' ? 'All Districts' : district,
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
                    const SizedBox(height: 16),
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _panelSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
                        ),
                        child: filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'No barangay matched your search or district filter.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(alpha: 0.72),
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
                                      style: const TextStyle(color: _lightOffWhite),
                                    ),
                                    subtitle: Text(
                                      barangay.district,
                                      style: TextStyle(
                                        color: _lightOffWhite.withValues(alpha: 0.65),
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
    final emailController = TextEditingController();
    String selectedRole = 'BHW';
    BarangayReference? selectedBarangay;

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
                      items: MalaybalayBarangays.roleOptions
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
                    if (selectedRole == 'BHW') ...[
                      const SizedBox(height: 16),
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: _primaryAqua.withValues(alpha: 0.18),
                          ),
                        ),
                        tileColor: _panelSurface,
                        title: Text(
                          selectedBarangay?.name ?? 'Assign barangay',
                          style: const TextStyle(color: _lightOffWhite),
                        ),
                        subtitle: Text(
                          selectedBarangay?.district ??
                              'Choose from the official Malaybalay directory',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.65),
                          ),
                        ),
                        trailing: const Icon(
                          Icons.keyboard_arrow_down,
                          color: _primaryAqua,
                        ),
                        onTap: () async {
                          final picked = await _pickBarangay();
                          if (picked == null) return;
                          setInviteState(() {
                            selectedBarangay = picked;
                          });
                        },
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
                          'No barangay assignment is required for $selectedRole invitations.',
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
                    if (email.isEmpty || (selectedRole == 'BHW' && selectedBarangay == null)) {
                      Get.snackbar(
                        'Incomplete',
                        selectedRole == 'BHW'
                            ? 'Email and barangay are required for BHW invitations.'
                            : 'Email is required for invitations.',
                        backgroundColor: Colors.orange,
                        colorText: Colors.white,
                      );
                      return;
                    }

                    await _firestore.collection('invitations').add({
                      'email': email,
                      'emailLower': email.toLowerCase(),
                      'role': selectedRole,
                      'accessScope': selectedRole == 'BHW' ? 'barangay' : 'citywide',
                      'barangay': selectedBarangay?.name,
                      'barangayCode': selectedBarangay?.code,
                      'barangayDistrict': selectedBarangay?.district,
                      'status': 'pending',
                      'createdAt': FieldValue.serverTimestamp(),
                      'createdBy': FirebaseAuth.instance.currentUser?.uid,
                    });

                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    Get.snackbar(
                      'Invitation recorded',
                      'The invitation was stored for CHO review and onboarding.',
                      backgroundColor: Colors.green,
                      colorText: Colors.white,
                    );
                  },
                  child: const Text('Save invite'),
                ),
              ],
            );
          },
        );
      },
    );

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

    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    await input.onChange.first;
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) return null;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;

    final result = reader.result;
    if (result is ByteBuffer) {
      return _SelectedBrandingFile(
        bytes: Uint8List.view(result),
        fileName: file.name,
        contentType: file.type.isEmpty ? 'image/png' : file.type,
      );
    }
    if (result is Uint8List) {
      return _SelectedBrandingFile(
        bytes: result,
        fileName: file.name,
        contentType: file.type.isEmpty ? 'image/png' : file.type,
      );
    }
    return null;
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
                                      color: _lightOffWhite.withValues(alpha: 0.68),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    logoUrlController.text.trim().isNotEmpty
                                        ? 'Official logo URL is active and will render automatically during BHW registration.'
                                        : 'No official logo URL is set yet. A placeholder will remain active until a logo is uploaded or mapped.',
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(alpha: 0.78),
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
                        hint: 'https://yourdomain.com/assets/barangay-logos/${barangay.code}.png',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isUploadingLogo ? null : () => uploadAsset(false),
                            icon: isUploadingLogo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.upload_file_outlined),
                            label: Text(
                              isUploadingLogo ? 'Uploading logo...' : 'Upload logo file',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: _darkDeepTeal,
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
                              side: BorderSide(color: _primaryAqua.withValues(alpha: 0.35)),
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
                        hint: 'https://yourdomain.com/assets/barangay-logos/${barangay.code}-esign.png',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isUploadingSignature ? null : () => uploadAsset(true),
                            icon: isUploadingSignature
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.draw_outlined),
                            label: Text(
                              isUploadingSignature
                                  ? 'Uploading e-sign...'
                                  : 'Upload e-sign file',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: _darkDeepTeal,
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
                        hint: 'Usage notes, version details, or document references',
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
                          final effectiveDate = effectiveDateController.text.trim();
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
                              officialESignatureUrl: signatureUrlController.text,
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
      final status = (data['accountStatus'] ?? 'active').toString().toLowerCase();

      final matchesSearch =
          _searchQuery.isEmpty ||
          email.contains(_searchQuery) ||
          username.contains(_searchQuery) ||
          barangay.toLowerCase().contains(_searchQuery);
      final matchesRole =
          _selectedRoleFilter == 'ALL' || role == _selectedRoleFilter;
      final matchesBarangay =
          _selectedBarangayFilter == 'ALL' || barangay == _selectedBarangayFilter;
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primaryAqua),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
          ),
        ],
      ),
    );
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
        return Colors.redAccent;
      case 'pending':
        return Colors.orangeAccent;
      default:
        return Colors.greenAccent;
    }
  }

  Color _approvalColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.greenAccent;
      case 'rejected':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
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
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(18),
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
                  _buildChip(accountStatus.toUpperCase(), _statusColor(accountStatus)),
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
                    side: BorderSide(color: _primaryAqua.withValues(alpha: 0.35)),
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
              OutlinedButton.icon(
                onPressed: () async {
                  final nextStatus = approvalStatus.toLowerCase() == 'approved'
                      ? 'pending'
                      : 'approved';
                  await _setApprovalStatus(doc.id, nextStatus);
                },
                icon: const Icon(Icons.verified_user_outlined),
                label: Text(
                  approvalStatus.toLowerCase() == 'approved'
                      ? 'Mark pending'
                      : 'Approve user',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.greenAccent,
                  side: const BorderSide(color: Colors.greenAccent),
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
        final profiles = snapshot.data ??
            MalaybalayBarangays.all
                .map(BarangayBrandingProfile.fallback)
                .toList();
        final profileByCode = <String, BarangayBrandingProfile>{
          for (final profile in profiles) profile.barangay.code: profile,
        };

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(20),
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
              const SizedBox(height: 20),
              ...grouped.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
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
                          final profile = profileByCode[barangay.code] ??
                              BarangayBrandingProfile.fallback(barangay);

                          return Container(
                            width: 280,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _sidebarDark,
                              borderRadius: BorderRadius.circular(16),
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
                                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                              color: _lightOffWhite.withValues(alpha: 0.65),
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
                                                  ? Colors.greenAccent
                                                  : Colors.orangeAccent,
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
                                    color: _lightOffWhite.withValues(alpha: 0.78),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  profile.effectiveDate.trim().isEmpty
                                      ? 'No effective date recorded'
                                      : 'Effective: ${profile.effectiveDate}',
                                  style: TextStyle(
                                    color: _lightOffWhite.withValues(alpha: 0.65),
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
                                      color: _lightOffWhite.withValues(alpha: 0.58),
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () => _showBrandingEditor(barangay),
                                  icon: const Icon(Icons.photo_library_outlined),
                                  label: const Text('Manage logo and details'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _primaryAqua,
                                    side: BorderSide(
                                      color: _primaryAqua.withValues(alpha: 0.35),
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_authorized) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        title: const Text('CHO Super Admin Center'),
        backgroundColor: _darkDeepTeal,
        actions: [
          TextButton.icon(
            onPressed: () {
              Get.to(() => const ChoDashboard());
            },
            icon: const Icon(Icons.analytics_outlined, color: _primaryAqua),
            label: const Text(
              'CHO Dashboard',
              style: TextStyle(color: _primaryAqua),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load users: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final filteredDocs = _filterUsers(docs);
          final pendingApprovals = docs.where((doc) {
            final approval =
                (doc.data()['approvalStatus'] ?? 'pending').toString();
            return approval.toLowerCase() != 'approved';
          }).length;
          final activeBhw = docs.where((doc) {
            final role = (doc.data()['role'] ?? '').toString().toUpperCase();
            return role == 'BHW';
          }).length;
          final choScoped = docs.where((doc) {
            final role = (doc.data()['role'] ?? '').toString().toUpperCase();
            return role == 'CHO' || role == 'CHO_SUPER_ADMIN';
          }).length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 4 : 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.8,
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
                      label: 'Pending approvals',
                      value: pendingApprovals.toString(),
                      icon: Icons.rule_folder_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _panelSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
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
                            label: const Text('Record invite'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: _darkDeepTeal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 280,
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: _lightOffWhite),
                              decoration: InputDecoration(
                                hintText: 'Search email, username, barangay',
                                hintStyle: TextStyle(
                                  color: _mutedCoolGray.withValues(alpha: 0.85),
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: _primaryAqua,
                                ),
                                filled: true,
                                fillColor: _sidebarDark,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedRoleFilter,
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
                              items: <String>['ALL', ...MalaybalayBarangays.roleOptions]
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
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedBarangayFilter,
                              dropdownColor: _sidebarDark,
                              style: const TextStyle(color: _lightOffWhite),
                              decoration: InputDecoration(
                                labelText: 'Barangay',
                                labelStyle: const TextStyle(color: _lightOffWhite),
                                filled: true,
                                fillColor: _sidebarDark,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: <String>[
                                'ALL',
                                ...MalaybalayBarangays.all.map((item) => item.name),
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
                          ),
                          SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedStatusFilter,
                              dropdownColor: _sidebarDark,
                              style: const TextStyle(color: _lightOffWhite),
                              decoration: InputDecoration(
                                labelText: 'Status',
                                labelStyle: const TextStyle(color: _lightOffWhite),
                                filled: true,
                                fillColor: _sidebarDark,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${filteredDocs.length} user${filteredDocs.length == 1 ? '' : 's'} matched',
                        style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.68)),
                      ),
                      const SizedBox(height: 14),
                      ...filteredDocs.map(_buildUserCard),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildBarangayDirectory(docs),
              ],
            ),
          );
        },
      ),
    );
  }
}
