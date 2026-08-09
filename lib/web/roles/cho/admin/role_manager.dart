import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _lightOffWhite = Color(0xFFF5F5F5);

class RoleManager extends StatefulWidget {
  const RoleManager({super.key});

  @override
  State<RoleManager> createState() => _RoleManagerState();
}

class _RoleManagerState extends State<RoleManager> {
  bool _checking = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _verifyAdmin();
  }

  Future<void> _verifyAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.offAll(() => const Login());
        return;
      }

      final doc = await getFirestoreInstance()
          .collection('users')
          .doc(user.uid)
          .get();
      final role = (doc.data()?['role'] ?? '').toString().toLowerCase();
      if (role.contains('admin')) {
        setState(() {
          _isAdmin = true;
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
        Get.offAll(() => const Login());
      }
    } catch (e) {
      if (kDebugMode) print('Admin verify error: $e');
      Get.snackbar(
        'Error',
        'Could not verify admin status',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      Get.offAll(() => const Login());
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
        print('RTDB role mirror update failed for $uid: $e');
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
      appBar: AppBar(
        title: const Text('Role Manager'),
        backgroundColor: _darkDeepTeal,
      ),
      backgroundColor: _darkDeepTeal,
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _darkDeepTeal,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Manage user roles (writes to users/{uid}.role)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final email = await _promptForEmail(context);
                      if (email != null && email.isNotEmpty) {
                        await _invite(email);
                      }
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('Invite'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                    ),
                  ),
                ],
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
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data() as Map<String, dynamic>;
                      final email =
                          data['email'] ??
                          data['emailAddress'] ??
                          data['email'] ??
                          '—';
                      final role = (data['role'] ?? '').toString();
                      String selected = role.isNotEmpty ? role : 'none';
                      return Card(
                        color: Colors.white,
                        child: ListTile(
                          title: Text(email.toString()),
                          subtitle: Text('Role: $selected'),
                          trailing: SizedBox(
                            width: 220,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                DropdownButton<String>(
                                  value: selected,
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
                                  onChanged: (v) async {
                                    if (v == null) return;
                                    setState(() => selected = v);
                                    final roleToSave = v == 'none' ? '' : v;
                                    await _setRole(d.id, roleToSave);
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    // remove role field only
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
                                        print(
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
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
