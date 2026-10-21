import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

/// Tracks the current session.
///
/// A session starts when the package is initialized and again whenever the
/// app comes back to the foreground after staying in the background for at
/// least the session timeout, as most analytics tools do. Each start is
/// logged as a [sessionStartEvent] event.
class SessionManager with WidgetsBindingObserver {
  /// The internal event logged at every session start.
  static const sessionStartEvent = r'$session_start';

  final Duration timeout;
  final Clock _clock;
  final void Function(String sessionId) _onSessionStart;
  final VoidCallback _onResume;
  final VoidCallback _onPause;

  String _sessionId = '';
  DateTime? _backgroundSince;

  SessionManager({
    required this.timeout,
    required Clock clock,
    required void Function(String sessionId) onSessionStart,
    required VoidCallback onResume,
    required VoidCallback onPause,
  }) : _clock = clock,
       _onSessionStart = onSessionStart,
       _onResume = onResume,
       _onPause = onPause;

  /// The identifier of the current session.
  String get sessionId => _sessionId;

  /// Starts the first session and begins observing the app lifecycle.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _startSession();
  }

  /// Stops observing the app lifecycle.
  void stop() => WidgetsBinding.instance.removeObserver(this);

  /// Ends the current session and starts a new one.
  void restart() => _startSession();

  void _startSession() {
    _sessionId = const Uuid().v4();
    _onSessionStart(_sessionId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundSince ??= _clock.now();
        _onPause();
      case AppLifecycleState.resumed:
        final since = _backgroundSince;
        _backgroundSince = null;
        if (since != null && _clock.now().difference(since) >= timeout) {
          _startSession();
        }
        _onResume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}
