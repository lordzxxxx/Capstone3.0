import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('turnstile')
external JSObject? get _globalTurnstile;

@JS()
extension type _Turnstile(JSObject _) implements JSObject {
  external JSAny? render(web.HTMLDivElement container, JSObject options);

  external void reset(JSAny widgetId);
}

class TurnstileChallenge extends StatefulWidget {
  const TurnstileChallenge({
    super.key,
    required this.action,
    required this.onTokenChanged,
    this.resetNonce = 0,
  });

  final String action;
  final ValueChanged<String?> onTokenChanged;
  final int resetNonce;

  @override
  State<TurnstileChallenge> createState() => _TurnstileChallengeState();
}

class _TurnstileChallengeState extends State<TurnstileChallenge> {
  static const String _siteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
  static int _nextViewId = 0;

  late final String _viewType;
  web.HTMLDivElement? _container;
  JSAny? _widgetId;
  Timer? _scriptPoll;
  int _lastResetNonce = 0;

  @override
  void initState() {
    super.initState();
    _lastResetNonce = widget.resetNonce;
    _viewType = 'ai-dsuhis-turnstile-${_nextViewId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final container = web.document.createElement('div') as web.HTMLDivElement;
      _container = container;
      _waitForTurnstile();
      return container;
    });
  }

  @override
  void didUpdateWidget(covariant TurnstileChallenge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetNonce != _lastResetNonce) {
      _lastResetNonce = widget.resetNonce;
      _reset();
    }
  }

  void _waitForTurnstile() {
    _scriptPoll?.cancel();
    var attempts = 0;
    _scriptPoll = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      attempts++;
      final turnstile = _globalTurnstile;
      if (turnstile != null) {
        timer.cancel();
        _render(turnstile);
      } else if (attempts >= 50) {
        timer.cancel();
        widget.onTokenChanged(null);
      }
    });
  }

  void _render(JSObject turnstileObject) {
    final container = _container;
    if (container == null || _siteKey.isEmpty || !mounted) return;
    final turnstile = _Turnstile(turnstileObject);

    final options =
        <String, dynamic>{
              'sitekey': _siteKey,
              'action': widget.action,
              // Cloudflare's compact mode is tall and nearly square. The normal
              // widget is the small horizontal 300x65 form that fits our auth cards.
              'size': 'normal',
              'theme': 'light',
              'callback': ((JSString token) {
                if (mounted) widget.onTokenChanged(token.toDart);
              }).toJS,
              'expired-callback': (() {
                if (mounted) widget.onTokenChanged(null);
              }).toJS,
              'error-callback': (() {
                if (mounted) widget.onTokenChanged(null);
              }).toJS,
            }.jsify()
            as JSObject;

    _widgetId = turnstile.render(container, options);
  }

  void _reset() {
    final turnstileObject = _globalTurnstile;
    final widgetId = _widgetId;
    if (turnstileObject != null && widgetId != null) {
      try {
        _Turnstile(turnstileObject).reset(widgetId);
      } catch (_) {
        // A destroyed widget is already reset by the browser.
      }
    }
    if (mounted) widget.onTokenChanged(null);
  }

  @override
  void dispose() {
    _scriptPoll?.cancel();
    _reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_siteKey.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text(
          'Security verification is not configured for this deployment.',
          style: TextStyle(color: Color(0xFFB42318), fontSize: 12),
        ),
      );
    }
    return Container(
      width: 300,
      height: 65,
      alignment: Alignment.centerLeft,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
