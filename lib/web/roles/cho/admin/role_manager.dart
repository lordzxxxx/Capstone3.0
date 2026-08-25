import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

class RoleManager extends StatefulWidget {
  const RoleManager({super.key});

  @override
  State<RoleManager> createState() => _RoleManagerState();
}

class _RoleManagerState extends State<RoleManager> {
  bool _checking = true;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _verifyAdmin();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _verifyAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.offAllNamed(WebRoutes.login);
        return;
      }

      final doc = await getFirestoreInstance()
          .collection('users')
          .doc(user.uid)
          .get();
      final role = (doc.data()?['role'] ?? '').toString().toLowerCase();
      if (role.contains('admin')) {
        setState(() {
          _checking = false;
        });
      } else {
        Get.snackbar(
          'Access denied',
          'You must be an admin to manage roles',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
        );
        await Future.delayed(const Duration(milliseconds: 400));
        Get.offAllNamed(WebRoutes.login);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Admin verify error: $e');
      Get.snackbar(
        'Error',
        'Could not verify admin status',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      Get.offAllNamed(WebRoutes.login);
    }
  }

  Future<void> _setRole(String uid, String role) async {
    await getFirestoreInstance().collection('users').doc(uid).set({
      'role': role,
    }, SetOptions(merge: true));
    try {
      await FirebaseDatabase.instance.ref().child('users').child(uid).update({
        'role': role,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('RTDB role mirror update failed for $uid: $e');
      }
    }
    Get.snackbar(
      'Saved',
      'Role updated',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _invite(String email) async {
    // Create an invitation document — server or admin can act on this.
    await getFirestoreInstance().collection('invitations').add({
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
    });
    Get.snackbar(
      'Invited',
      'Invitation recorded. Create account via admin script.',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: ChoColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ChoNavigationDrawer(current: ChoDestination.dashboard),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ChoColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ChoColors.border),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 360),
                          child: Text(
                            'Manage user roles (writes to users/{uid}.role)',
                            style: TextStyle(
                              color: ChoColors.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            final email = await _promptForEmail(context);
                            if (email != null && email.isNotEmpty) {
                              await _invite(email);
                            }
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Invite'),
                          style: AppButtonStyles.primary(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  WebFilterSurface(
                    padding: const EdgeInsets.all(10),
                    child: LayoutBuilder(
                      builder: (context, constraints) => WebSearchField(
                        controller: _searchController,
                        width: constraints.maxWidth > 440
                            ? 440
                            : constraints.maxWidth,
                        hintText: 'Search users by email or role',
                        onChanged: (value) =>
                            setState(() => _query = value.trim().toLowerCase()),
                        onClear: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: getFirestoreInstance()
                          .collection('users')
                          .orderBy('email')
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(child: Text('Error: ${snap.error}'));
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final docs = snap.data!.docs.where((doc) {
                          if (_query.isEmpty) return true;
                          final data = doc.data() as Map<String, dynamic>;
                          final email =
                              (data['email'] ?? data['emailAddress'] ?? '')
                                  .toString()
                                  .toLowerCase();
                          final role = (data['role'] ?? '')
                              .toString()
                              .toLowerCase();
                          return '$email $role'.contains(_query);
                        }).toList();
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No matching users.',
                              style: TextStyle(color: ChoColors.muted),
                            ),
                          );
                        }
                        return WebTableSurface(
                          minWidth: 860,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Email')),
                              DataColumn(label: Text('Current role')),
                              DataColumn(label: Text('Change role')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: docs.map((d) {
                              final data = d.data() as Map<String, dynamic>;
                              final email =
                                  data['email'] ?? data['emailAddress'] ?? '—';
                              final role = (data['role'] ?? '').toString();
                              final selected = role.isNotEmpty ? role : 'none';
                              return DataRow(
                                cells: [
                                  DataCell(Text(email.toString())),
                                  DataCell(Text(selected)),
                                  DataCell(
                                    WebFilterDropdown<String>(
                                      label: 'Role',
                                      value: selected,
                                      width: 160,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'none',
                                          child: Text('none'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'BHW',
                                          child: Text('BHW'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'CHO',
                                          child: Text('CHO'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'admin',
                                          child: Text('admin'),
                                        ),
                                      ],
                                      onChanged: (value) async {
                                        if (value == null) return;
                                        await _setRole(
                                          d.id,
                                          value == 'none' ? '' : value,
                                        );
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      tooltip: 'Remove role',
                                      icon: const Icon(Icons.delete_outline),
                                      color: ChoColors.muted,
                                      onPressed: () async {
                                        await getFirestoreInstance()
                                            .collection('users')
                                            .doc(d.id)
                                            .set({
                                              'role': FieldValue.delete(),
                                            }, SetOptions(merge: true));
                                        try {
                                          await FirebaseDatabase.instance
                                              .ref()
                                              .child('users')
                                              .child(d.id)
                                              .child('role')
                                              .remove();
                                        } catch (e) {
                                          if (kDebugMode) {
                                            debugPrint(
                                              'RTDB role mirror delete failed for ${d.id}: $e',
                                            );
                                          }
                                        }
                                        Get.snackbar(
                                          'Removed',
                                          'Role removed',
                                          backgroundColor: Colors.orange,
                                          colorText: Colors.white,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        );
                      },
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

  Future<String?> _promptForEmail(BuildContext ctx) async {
    String? value;
    await showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Invite user'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'user@example.com'),
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Invite'),
          ),
        ],
      ),
    );
    return value;
  }
}
