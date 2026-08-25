import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/utils/browser_online_state.dart';

/// The browser's network state is a useful UX signal, but it is not proof that
/// Firestore is reachable. Firestore's persistent cache remains the source of
/// truth for reads and queued writes; this banner simply tells staff when the
/// current page may be showing cached data.
enum WebConnectionState { checking, online, offline }

class WebConnectivityBanner extends StatefulWidget {
  const WebConnectivityBanner({super.key, required this.child});

  final Widget child;

  /// Treat every non-[ConnectivityResult.none] result as potentially online.
  /// A captive portal or blocked Firestore request is still surfaced by the
  /// page-level error state, rather than being hidden behind this hint.
  static bool isPotentiallyOnline(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  static bool isOnline(
    List<ConnectivityResult> results, {
    bool? browserOnline,
  }) {
    return browserOnline != false && isPotentiallyOnline(results);
  }

  @override
  State<WebConnectivityBanner> createState() => _WebConnectivityBannerState();
}

class _WebConnectivityBannerState extends State<WebConnectivityBanner> {
  WebConnectionState _connectionState = WebConnectionState.checking;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  StreamSubscription<bool>? _browserSubscription;
  Timer? _connectivityPollTimer;
  Timer? _restoredMessageTimer;
  bool _showRestoredMessage = false;
  bool? _browserOnline;

  @override
  void initState() {
    super.initState();
    _browserOnline = browserIsOnline();
    _initializeConnectivity();
    _subscription = Connectivity().onConnectivityChanged.listen(
      _updateConnectivity,
    );
    _browserSubscription = browserOnlineChanges().listen((isOnline) {
      _browserOnline = isOnline;
      if (!isOnline) {
        _updateConnectionState(isOnline: false);
      } else {
        unawaited(_pollConnectivity());
      }
    });
    // Browser online/offline events can be suppressed by embedded webviews,
    // DevTools network emulation, or a backgrounded tab. A lightweight poll
    // keeps the visible state honest without replacing the immediate stream.
    _connectivityPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final observedBrowserState = browserIsOnline();
      if (observedBrowserState == false) {
        _browserOnline = false;
        _updateConnectionState(isOnline: false);
        return;
      }
      unawaited(_pollConnectivity());
    });
  }

  Future<void> _initializeConnectivity() async {
    try {
      _updateConnectivity(await Connectivity().checkConnectivity());
    } catch (_) {
      // Keep the child usable if the browser adapter is unavailable. The
      // Firestore error/empty states remain the authoritative fallback.
      if (mounted) {
        setState(() => _connectionState = WebConnectionState.online);
      }
    }
  }

  Future<void> _pollConnectivity() async {
    try {
      _updateConnectivity(await Connectivity().checkConnectivity());
    } catch (_) {
      // A failed fallback check is not evidence that the connection changed.
      // Page-level Firestore states still report actual request failures.
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    _updateConnectionState(
      isOnline: WebConnectivityBanner.isOnline(
        results,
        browserOnline: _browserOnline ?? browserIsOnline(),
      ),
    );
  }

  void _updateConnectionState({required bool isOnline}) {
    if (!mounted) return;
    final nextState = isOnline
        ? WebConnectionState.online
        : WebConnectionState.offline;
    if (nextState == _connectionState) return;
    final wasOffline = _connectionState == WebConnectionState.offline;
    _restoredMessageTimer?.cancel();
    setState(() {
      _connectionState = nextState;
      _showRestoredMessage =
          wasOffline && nextState == WebConnectionState.online;
    });
    if (_showRestoredMessage) {
      _restoredMessageTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showRestoredMessage = false);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _browserSubscription?.cancel();
    _connectivityPollTimer?.cancel();
    _restoredMessageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showOffline = _connectionState == WebConnectionState.offline;
    final showRestored = _showRestoredMessage && !showOffline;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: showOffline || showRestored
              ? _ConnectionBanner(offline: showOffline)
              : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final background = offline ? AppColors.warning : AppColors.success;
    final icon = offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded;
    final message = offline
        ? 'You are offline. Showing saved data; new changes will sync when the connection returns.'
        : 'Connection restored. Syncing the latest records.';

    return Semantics(
      liveRegion: true,
      container: true,
      label: message,
      child: Container(
        width: double.infinity,
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
