import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../firebase_helper.dart';
import '../theme/app_theme.dart';

/// Live BHW notification surface.
///
/// Announcements are the CHO broadcast channel. Referral/system notifications
/// are restricted by Firestore rules to the signed-in recipient. Both streams
/// remain read-only here, so opening the panel cannot modify clinical data.
class BhwNotificationsDialog extends StatelessWidget {
  const BhwNotificationsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;

    if (user == null) {
      return const AlertDialog(
        title: Text('Notifications'),
        content: Text('Sign in again to view BHW notifications.'),
      );
    }

    final firestore = getFirestoreInstance();
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 600 ? 12 : 32,
        vertical: width < 600 ? 18 : 32,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: height * 0.82),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore.collection('announcements').limit(30).snapshots(),
          builder: (context, announcementSnapshot) {
            final announcements = _fromSnapshot(
              announcementSnapshot.data,
              source: _BhwNotificationSource.announcement,
            );

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestore
                  .collection('notifications')
                  .where('recipientUid', isEqualTo: user.uid)
                  .limit(30)
                  .snapshots(),
              builder: (context, notificationSnapshot) {
                final notifications = _fromSnapshot(
                  notificationSnapshot.data,
                  source: _BhwNotificationSource.notification,
                );
                final items = [...announcements, ...notifications]
                  ..sort((a, b) => b.sortDate.compareTo(a.sortDate));

                final streamError = announcementSnapshot.hasError
                    ? announcementSnapshot.error
                    : notificationSnapshot.error;

                return Column(
                  children: [
                    _buildHeader(context, items.length),
                    if (streamError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _ErrorNotice(error: streamError),
                      ),
                    Expanded(
                      child: items.isEmpty
                          ? _buildEmptyState(
                              isLoading:
                                  announcementSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  notificationSnapshot.connectionState ==
                                      ConnectionState.waiting,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                24,
                              ),
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _NotificationCard(item: items[index]),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      decoration: const BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  count == 0
                      ? 'You are up to date'
                      : '$count live update${count == 1 ? '' : 's'} from Firebase',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close notifications',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required bool isLoading}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLoading ? Icons.sync_rounded : Icons.notifications_off_outlined,
              color: AppColors.textSecondary,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              isLoading ? 'Loading updates…' : 'No notifications yet',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'CHO announcements and assigned referral updates will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  static List<_BhwNotificationItem> _fromSnapshot(
    QuerySnapshot<Map<String, dynamic>>? snapshot, {
    required _BhwNotificationSource source,
  }) {
    if (snapshot == null) return const [];
    return snapshot.docs
        .map(
          (document) => _BhwNotificationItem.fromMap(
            document.id,
            document.data(),
            source: source,
          ),
        )
        .toList(growable: false);
  }
}

enum _BhwNotificationSource { announcement, notification }

class _BhwNotificationItem {
  const _BhwNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.source,
    required this.sortDate,
    this.meta,
  });

  final String id;
  final String title;
  final String message;
  final _BhwNotificationSource source;
  final DateTime sortDate;
  final String? meta;

  factory _BhwNotificationItem.fromMap(
    String id,
    Map<String, dynamic> data, {
    required _BhwNotificationSource source,
  }) {
    final date =
        _parseDate(data['createdAt'] ?? data['updatedAt'] ?? data['date']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final title = _firstText(
      [data['title'], data['action'], data['type']],
      fallback: source == _BhwNotificationSource.announcement
          ? 'CHO announcement'
          : 'System notification',
    );
    final message = _firstText([
      data['message'],
      data['summary'],
      data['description'],
    ], fallback: 'Open AI-DSUHIS to review this update.');
    final meta = _firstText([
      data['module'],
      data['barangay'],
      data['audience'],
    ]);

    return _BhwNotificationItem(
      id: id,
      title: title,
      message: message,
      source: source,
      sortDate: date,
      meta: meta.isEmpty ? null : meta,
    );
  }

  static String _firstText(Iterable<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final _BhwNotificationItem item;

  @override
  Widget build(BuildContext context) {
    final isAnnouncement = item.source == _BhwNotificationSource.announcement;
    final color = isAnnouncement ? AppColors.primary : AppColors.referral;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.canvasLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isAnnouncement
                ? Icons.campaign_outlined
                : Icons.assignment_outlined,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (item.meta != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.meta!,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Some updates could not be loaded. Check the connection and retry. ($error)',
      style: const TextStyle(color: AppColors.error, fontSize: 12),
    );
  }
}
