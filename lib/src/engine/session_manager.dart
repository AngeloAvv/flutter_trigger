import 'package:uuid/uuid.dart';

/// Manages the unique identifier for the current application session.
class SessionManager {
  final String _sessionId;

  SessionManager() : _sessionId = const Uuid().v4();

  /// Returns the unique session identifier for the current app launch.
  String get sessionId => _sessionId;
}
