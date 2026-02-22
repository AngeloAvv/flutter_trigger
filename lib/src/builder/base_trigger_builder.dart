import 'package:objectbox/objectbox.dart';

import 'event_selector.dart';

/// Entry point for the trigger fluent API.
///
/// Usage:
/// ```dart
/// final trigger = FlutterTrigger.instance;
/// trigger.when().event("purchase").count().greaterThan(5).watch();
/// ```
class BaseTriggerBuilder {
  final Store _store;
  final String _sessionId;

  const BaseTriggerBuilder({required Store store, required String sessionId})
    : _store = store,
      _sessionId = sessionId;

  /// Begin defining a trigger condition.
  EventSelector when() => EventSelector(store: _store, sessionId: _sessionId);
}
