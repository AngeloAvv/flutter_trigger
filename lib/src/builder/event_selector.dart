import 'package:objectbox/objectbox.dart';

import 'event_clause.dart';
import 'funnel_clause.dart';
import 'query_filter.dart';

/// Intermediate builder returned by [BaseTriggerBuilder.when].
///
/// Allows selecting either a single event or defining a funnel.
class EventSelector {
  final Store _store;
  final String _sessionId;

  const EventSelector({required Store store, required String sessionId})
    : _store = store,
      _sessionId = sessionId;

  /// Select a single event by [name] for count or attribute triggers.
  EventClause event(String name) =>
      EventClause(store: _store, eventName: name, sessionId: _sessionId);

  /// Define a funnel of chronologically-ordered event names.
  ///
  /// Returns a [FunnelBuilder] which can be further narrowed with
  /// `.session()`, `.timestamp()` (including `.within()`), or watched
  /// directly without any constraint.
  FunnelBuilder funnel(List<String> events, {QueryFilter? filter}) =>
      FunnelBuilder(
        store: _store,
        events: events,
        currentSessionId: _sessionId,
        filter: filter,
      );
}
