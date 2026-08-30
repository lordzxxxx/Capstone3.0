import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_database_helper.dart';

/// Notification item representation for the mobile app
class DashboardNotificationItem {
  final String id;
  final String title;
  final String message;
  final String type; // 'alert', 'announcement', 'clinical', 'referral', 'system'
  final IconData icon;
  final Color color;
  final DateTime timestamp;
  final String? route;
  final Map<String, dynamic>? metadata;
  bool isRead;

  DashboardNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.icon,
    required this.color,
    required this.timestamp,
    this.route,
    this.metadata,
    this.isRead = false,
  });
}

class DashboardNotificationsSheet extends StatefulWidget {
  final User? user;
  final ValueChanged<int>? onUnreadCountChanged;
  final Future<void> Function({required String title, required String body})? onTriggerLocalNotification;

  const DashboardNotificationsSheet({
    super.key,
    this.user,
    this.onUnreadCountChanged,
    this.onTriggerLocalNotification,
  });

  /// Static helper to count unread notifications across local and remote sources
  static Future<int> fetchUnreadCount(User? user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final readIds = prefs.getStringList('read_notifications_ids')?.toSet() ?? <String>{};
      final items = await _aggregateAllNotifications(user: user, readIds: readIds);
      return items.where((i) => !i.isRead).length;
    } catch (_) {
      return 0;
    }
  }

  /// Aggregates all notification sources
  static Future<List<DashboardNotificationItem>> _aggregateAllNotifications({
    required User? user,
    required Set<String> readIds,
  }) async {
    final List<DashboardNotificationItem> items = [];
    final now = DateTime.now();

    // 1. Fetch CHO Announcements from Firestore (if available)
    try {
      final firestore = getFirestoreInstance();
      final snapshot = await firestore
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get(const GetOptions(source: Source.serverAndCache));

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final id = 'ann_${doc.id}';
        final title = (data['title'] ?? 'City Health Announcement').toString();
        final message = (data['message'] ?? data['content'] ?? data['body'] ?? '').toString();
        final sender = (data['sender'] ?? data['author'] ?? 'City Health Office (CHO)').toString();
        final priority = (data['priority'] ?? 'normal').toString().toLowerCase();

        DateTime date = now;
        if (data['createdAt'] is Timestamp) {
          date = (data['createdAt'] as Timestamp).toDate();
        } else if (data['timestamp'] is Timestamp) {
          date = (data['timestamp'] as Timestamp).toDate();
        }

        final isUrgent = priority == 'urgent' || priority == 'high';

        items.add(
          DashboardNotificationItem(
            id: id,
            title: title,
            message: message.isNotEmpty ? message : 'New announcement posted by $sender',
            type: 'announcement',
            icon: isUrgent ? Icons.campaign_rounded : Icons.announcement_outlined,
            color: isUrgent ? Colors.redAccent : AppDesign.blue,
            timestamp: date,
            isRead: readIds.contains(id),
            metadata: {
              'sender': sender,
              'priority': priority,
              'fullBody': message,
            },
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('Firestore announcements query skipped: $e');
    }

    // 2. Fetch User Specific Notifications (if logged in)
    if (user != null) {
      try {
        final firestore = getFirestoreInstance();
        final snapshot = await firestore
            .collection('notifications')
            .where('recipientUid', isEqualTo: user.uid)
            .limit(15)
            .get(const GetOptions(source: Source.serverAndCache));

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final id = 'notif_${doc.id}';
          final title = (data['title'] ?? 'System Notification').toString();
          final message = (data['message'] ?? data['body'] ?? '').toString();
          DateTime date = now;
          if (data['timestamp'] is Timestamp) {
            date = (data['timestamp'] as Timestamp).toDate();
          }

          items.add(
            DashboardNotificationItem(
              id: id,
              title: title,
              message: message,
              type: 'system',
              icon: Icons.notifications_active_rounded,
              color: AppDesign.navySoft,
              timestamp: date,
              isRead: readIds.contains(id),
            ),
          );
        }
      } catch (_) {}
    }

    // 3. Fetch Referrals Updates from Firestore
    try {
      final firestore = getFirestoreInstance();
      final snapshot = await firestore
          .collection('referrals')
          .limit(15)
          .get(const GetOptions(source: Source.serverAndCache));

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = (data['status'] ?? 'Pending').toString();
        final patientName = (data['patientName'] ?? data['patient'] ?? 'Patient').toString();
        final receivingFacility = (data['receivingFacility'] ?? data['referralCenter'] ?? 'Health Facility').toString();
        final id = 'ref_${doc.id}';

        DateTime date = now;
        if (data['createdAt'] is Timestamp) {
          date = (data['createdAt'] as Timestamp).toDate();
        } else if (data['date'] is String) {
          date = DateTime.tryParse(data['date']) ?? now;
        }

        Color color = Colors.orange;
        IconData icon = Icons.swap_horiz_rounded;
        String title = 'Referral Update: $patientName';
        String message = 'Status: $status -> $receivingFacility';

        if (status.toLowerCase() == 'pending') {
          color = Colors.amber.shade800;
          title = 'Pending Referral: $patientName';
          message = 'Awaiting transfer/acknowledgment by $receivingFacility';
        } else if (status.toLowerCase() == 'accepted') {
          color = Colors.green;
          title = 'Referral Accepted: $patientName';
          message = 'Accepted by $receivingFacility. Ready for handoff.';
        }

        items.add(
          DashboardNotificationItem(
            id: id,
            title: title,
            message: message,
            type: 'referral',
            icon: icon,
            color: color,
            timestamp: date,
            route: MobileRoutes.referrals,
            isRead: readIds.contains(id),
            metadata: data,
          ),
        );
      }
    } catch (_) {}

    // 4. Clinical High-Risk Prenatal Cases from SQLite
    try {
      final prenatalRecords = await PrenatalDatabaseHelper.instance.getAllRecords();
      for (final record in prenatalRecords) {
        final riskAssessment = (record['riskAssessment'] ?? '').toString().toLowerCase();
        final isHighRisk = riskAssessment.contains('high') ||
            (record['highRiskPregnancy'] == 'Yes' || record['highRiskPregnancy'] == 'true');

        if (isHighRisk) {
          final id = 'prenatal_risk_${record['id']}';
          final name = (record['patientName'] ?? record['name'] ?? 'Mother').toString();
          final factors = (record['highRiskFactors'] ?? record['riskFactors'] ?? 'High risk indicators detected').toString();

          items.add(
            DashboardNotificationItem(
              id: id,
              title: 'High-Risk Prenatal Case: $name',
              message: 'Conditions: $factors. Requires timely prenatal monitoring.',
              type: 'clinical',
              icon: Icons.pregnant_woman_rounded,
              color: Colors.redAccent,
              timestamp: now.subtract(const Duration(minutes: 30)),
              route: MobileRoutes.prenatal,
              isRead: readIds.contains(id),
            ),
          );
        }
      }
    } catch (_) {}

    // 5. Clinical Immunization Schedule Alerts from SQLite
    try {
      final imzRecords = await ImmunizationDatabaseHelper.instance.getAllRecords();
      if (imzRecords.isNotEmpty) {
        final sample = imzRecords.first;
        final childName = (sample['childName'] ?? sample['patientName'] ?? 'Child').toString();
        final id = 'imz_due_${sample['id']}';
        items.add(
          DashboardNotificationItem(
            id: id,
            title: 'Immunization Schedule Active',
            message: 'Active routine vaccination tracker for $childName and ${imzRecords.length} registered children.',
            type: 'clinical',
            icon: Icons.vaccines_rounded,
            color: const Color(0xFF4CAF50),
            timestamp: now.subtract(const Duration(hours: 1)),
            route: MobileRoutes.immunization,
            isRead: readIds.contains(id),
          ),
        );
      }
    } catch (_) {}

    // 6. Clinical Morbidity Surveillance Threshold Alerts
    try {
      final morbidityRecords = await MorbidityDatabaseHelper.instance.getAllRecords();
      if (morbidityRecords.isNotEmpty) {
        final id = 'mbd_alert_${morbidityRecords.length}';
        items.add(
          DashboardNotificationItem(
            id: id,
            title: 'Morbidity Surveillance Registry',
            message: '${morbidityRecords.length} disease cases logged in community health surveillance.',
            type: 'alert',
            icon: Icons.healing_rounded,
            color: AppDesign.navySoft,
            timestamp: now.subtract(const Duration(hours: 2)),
            route: MobileRoutes.morbidity,
            isRead: readIds.contains(id),
          ),
        );
      }
    } catch (_) {}

    // 7. Clinical Check-up Registry Update
    try {
      final checkupRecords = await DatabaseHelper.instance.getAllRecords();
      if (checkupRecords.isNotEmpty) {
        final id = 'chk_status_${checkupRecords.length}';
        items.add(
          DashboardNotificationItem(
            id: id,
            title: 'Clinical Check-Up Records',
            message: '${checkupRecords.length} general check-up consultations completed and synchronized.',
            type: 'clinical',
            icon: Icons.medical_services_rounded,
            color: AppDesign.blue,
            timestamp: now.subtract(const Duration(hours: 3)),
            route: MobileRoutes.checkups,
            isRead: readIds.contains(id),
          ),
        );
      }
    } catch (_) {}

    // 8. Master Patient Registry Update
    try {
      final patientRecords = await PatientDatabaseHelper.instance.getAllRecords();
      if (patientRecords.isNotEmpty) {
        final id = 'pat_registry_${patientRecords.length}';
        items.add(
          DashboardNotificationItem(
            id: id,
            title: 'Master Patient Registry',
            message: '${patientRecords.length} registered patients available across all clinical services.',
            type: 'system',
            icon: Icons.people_alt_rounded,
            color: AppDesign.navy,
            timestamp: now.subtract(const Duration(hours: 4)),
            route: MobileRoutes.patients,
            isRead: readIds.contains(id),
          ),
        );
      }
    } catch (_) {}

    // 9. System Health Status
    final systemStatusId = 'sys_status_${now.year}_${now.month}_${now.day}';
    items.add(
      DashboardNotificationItem(
        id: systemStatusId,
        title: 'System Online & Synchronized',
        message: 'DSUHIS local database and secure sync services are fully operational.',
        type: 'system',
        icon: Icons.check_circle_outline_rounded,
        color: Colors.green,
        timestamp: now.subtract(const Duration(minutes: 5)),
        isRead: readIds.contains(systemStatusId),
      ),
    );

    // Sort by timestamp descending
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  @override
  State<DashboardNotificationsSheet> createState() => _DashboardNotificationsSheetState();
}

class _DashboardNotificationsSheetState extends State<DashboardNotificationsSheet> {
  static const Color _primaryAqua = AppDesign.blue;
  static const Color _darkDeepTeal = AppDesign.page;
  static const Color _mutedCoolGray = AppDesign.muted;
  static const Color _lightOffWhite = AppDesign.ink;

  List<DashboardNotificationItem> _notifications = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  Set<String> _readIds = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _readIds = prefs.getStringList('read_notifications_ids')?.toSet() ?? <String>{};

      final items = await DashboardNotificationsSheet._aggregateAllNotifications(
        user: widget.user,
        readIds: _readIds,
      );

      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
      });

      _notifyUnreadCount();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _notifyUnreadCount() {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    widget.onUnreadCountChanged?.call(unreadCount);
  }

  Future<void> _markItemAsRead(DashboardNotificationItem item) async {
    if (item.isRead) return;
    setState(() {
      item.isRead = true;
      _readIds.add(item.id);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('read_notifications_ids', _readIds.toList());
    _notifyUnreadCount();
  }

  Future<void> _markAllAsRead() async {
    setState(() {
      for (final item in _notifications) {
        item.isRead = true;
        _readIds.add(item.id);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('read_notifications_ids', _readIds.toList());
    _notifyUnreadCount();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleNotificationTap(DashboardNotificationItem item) {
    _markItemAsRead(item);

    if (item.metadata != null && item.type == 'announcement') {
      _showAnnouncementDetailDialog(item);
      return;
    }

    if (item.route != null) {
      Navigator.of(context).pop();
      Get.toNamed(item.route!);
      return;
    }

    _showGenericNotificationDialog(item);
  }

  void _showAnnouncementDetailDialog(DashboardNotificationItem item) {
    final sender = item.metadata?['sender'] ?? 'City Health Office';
    final fullBody = item.metadata?['fullBody'] ?? item.message;
    final priority = item.metadata?['priority'] ?? 'Normal';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.2)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    'Broadcast from $sender',
                    style: TextStyle(color: _mutedCoolGray, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Priority: ${priority.toString().toUpperCase()}',
                style: TextStyle(color: item.color, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              fullBody,
              style: const TextStyle(color: _lightOffWhite, height: 1.45, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Text(
              _formatDetailedDate(item.timestamp),
              style: TextStyle(color: _mutedCoolGray, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: _primaryAqua)),
          ),
        ],
      ),
    );
  }

  void _showGenericNotificationDialog(DashboardNotificationItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.2)),
        ),
        title: Row(
          children: [
            Icon(item.icon, color: item.color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(color: _lightOffWhite, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          item.message,
          style: const TextStyle(color: _lightOffWhite, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: _primaryAqua)),
          ),
        ],
      ),
    );
  }

  List<DashboardNotificationItem> get _filteredNotifications {
    return _notifications.where((n) {
      if (_selectedFilter != 'All') {
        if (_selectedFilter == 'Alerts' && n.type != 'alert') return false;
        if (_selectedFilter == 'Announcements' && n.type != 'announcement') return false;
        if (_selectedFilter == 'Clinical' && (n.type != 'clinical' && n.type != 'referral')) return false;
        if (_selectedFilter == 'System' && n.type != 'system') return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesTitle = n.title.toLowerCase().contains(query);
        final matchesMsg = n.message.toLowerCase().contains(query);
        if (!matchesTitle && !matchesMsg) return false;
      }
      return true;
    }).toList();
  }

  String _formatNotificationTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }
  }

  String _formatDetailedDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: _darkDeepTeal,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top drag indicator handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _lightOffWhite.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: _primaryAqua, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Notifications',
                                style: TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (unreadCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$unreadCount new',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Live clinical alerts and announcements',
                            style: TextStyle(color: _mutedCoolGray, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mark all as read',
                      icon: const Icon(Icons.done_all_rounded, color: _primaryAqua),
                      onPressed: unreadCount > 0 ? _markAllAsRead : null,
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: _lightOffWhite),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Search Box & Category Filters
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      style: const TextStyle(color: _lightOffWhite, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search alerts & announcements...',
                        hintStyle: TextStyle(color: _mutedCoolGray, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: _primaryAqua, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: _mutedCoolGray, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: _lightOffWhite.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.15)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _primaryAqua, width: 1.5),
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    ),
                    const SizedBox(height: 10),

                    // Filter Chips Bar
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Alerts', 'Announcements', 'Clinical', 'System'].map((filter) {
                          final isSelected = _selectedFilter == filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(filter),
                              selected: isSelected,
                              onSelected: (_) => setState(() => _selectedFilter = filter),
                              backgroundColor: Colors.transparent,
                              selectedColor: _primaryAqua.withValues(alpha: 0.25),
                              labelStyle: TextStyle(
                                color: isSelected ? _primaryAqua : _mutedCoolGray,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              side: BorderSide(
                                color: isSelected ? _primaryAqua : _lightOffWhite.withValues(alpha: 0.2),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white12, height: 16),

              // Notifications List Body
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _primaryAqua))
                    : _filteredNotifications.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notifications_none_rounded, size: 56, color: _mutedCoolGray),
                                const SizedBox(height: 12),
                                const Text(
                                  'No notifications found',
                                  style: TextStyle(color: _lightOffWhite, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Try adjusting your search keywords'
                                      : 'You are all caught up on alerts and updates',
                                  style: TextStyle(color: _mutedCoolGray, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: _primaryAqua,
                            onRefresh: _loadNotifications,
                            child: ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              itemCount: _filteredNotifications.length,
                              separatorBuilder: (_, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = _filteredNotifications[index];
                                return _buildNotificationCard(item);
                              },
                            ),
                          ),
              ),

              // Bottom Action Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  border: Border(top: BorderSide(color: _lightOffWhite.withValues(alpha: 0.1))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (widget.onTriggerLocalNotification != null) {
                            await widget.onTriggerLocalNotification!(
                              title: '[ALERT] DSUHIS Test Alert',
                              body: 'Device notifications are active and functioning correctly on your mobile device.',
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Test notification sent to device! Check your notification bar.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.vibration_rounded, size: 18),
                        label: const Text('Test Alert', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _lightOffWhite,
                          side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.25)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _loadNotifications,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Refresh', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(DashboardNotificationItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleNotificationTap(item),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: item.isRead
                ? _lightOffWhite.withValues(alpha: 0.05)
                : _primaryAqua.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isRead
                  ? _lightOffWhite.withValues(alpha: 0.12)
                  : item.color.withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Badge
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 12),

              // Title and Message Body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              color: _lightOffWhite,
                              fontWeight: item.isRead ? FontWeight.w600 : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (!item.isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: item.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _formatNotificationTime(item.timestamp),
                          style: TextStyle(color: _mutedCoolGray, fontSize: 11),
                        ),
                        if (item.route != null) ...[
                          const SizedBox(width: 8),
                          Text('•', style: TextStyle(color: _mutedCoolGray, fontSize: 11)),
                          const SizedBox(width: 8),
                          Text(
                            'Tap to view module',
                            style: TextStyle(color: _primaryAqua, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
