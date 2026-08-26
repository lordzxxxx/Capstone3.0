import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/utils/browser_reload.dart';

/// Small, non-blocking deployment check for the web shell.
///
/// The build pipeline writes the same commit identifier to the compiled Dart
/// define and `/app-version.json`. A failed check is intentionally ignored so
/// a temporary CDN/network issue never interrupts the application.
class AppUpdateNotification extends StatefulWidget {
  const AppUpdateNotification({super.key});

  @override
  State<AppUpdateNotification> createState() => _AppUpdateNotificationState();
}

class _AppUpdateNotificationState extends State<AppUpdateNotification> {
  static const _loadedVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );
  static const _checkInterval = Duration(minutes: 5);

  Timer? _timer;
  bool _updateAvailable = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (_loadedVersion != 'dev') {
      _timer = Timer.periodic(_checkInterval, (_) => _checkForUpdate());
      Future<void>.delayed(const Duration(seconds: 20), _checkForUpdate);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    if (_checking || !mounted || _loadedVersion == 'dev') return;
    _checking = true;
    try {
      final uri = Uri.base.resolve(
        '/app-version.json?check=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http
          .get(uri, headers: const {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final payload = jsonDecode(response.body);
      final serverVersion = payload is Map
          ? payload['version']?.toString().trim() ?? ''
          : '';
      if (serverVersion.isNotEmpty &&
          serverVersion != _loadedVersion &&
          mounted) {
        setState(() => _updateAvailable = true);
      }
    } catch (_) {
      // Version checks are advisory. The portal continues normally offline.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_updateAvailable) return const SizedBox.shrink();
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Material(
          color: AppColors.secondary,
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'A newer version of AI-DSUHIS is available.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: reloadBrowserPage,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Update now'),
                ),
                IconButton(
                  tooltip: 'Dismiss update notice',
                  onPressed: () => setState(() => _updateAvailable = false),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
