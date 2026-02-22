import 'package:objectbox/objectbox.dart';

import 'count_clause.dart';
import 'attribute_selector.dart';
import 'query_filter.dart';
import 'session_selector.dart';
import 'timestamp_selector.dart';

/// Intermediate builder returned after selecting an event by name.
///
/// Provides access to session filtering, temporal constraints,
/// and count/attribute-based trigger chains.
class EventClause {
  final Store _store;
  final String _eventName;
  final String _currentSessionId;
  final QueryFilter _filter;

  const EventClause({
    required Store store,
    required String eventName,
    required String sessionId,
    QueryFilter? filter,
  }) : _store = store,
       _eventName = eventName,
       _currentSessionId = sessionId,
       _filter = filter ?? const QueryFilter();

  /// Internal method to clone the clause with a new filter.
  EventClause withFilter(QueryFilter filter) {
    return EventClause(
      store: _store,
      eventName: _eventName,
      sessionId: _currentSessionId,
      filter: filter,
    );
  }

  /// Begin a **session-based** sub-chain.
  ///
  /// From here you can:
  /// - `.session().current()` – restrict to the current session.
  /// - `.session().other()`   – restrict to any other session.
  /// - `.session().count()`   – count distinct sessions and compare.
  ///
  /// Example:
  /// ```dart
  /// trigger.when().event("login").session().count().greaterThan(5)
  /// trigger.when().event("click").session().current().count().greaterThan(2)
  /// ```
  SessionSelector session() => SessionSelector(
        store: _store,
        eventName: _eventName,
        currentSessionId: _currentSessionId,
        filter: _filter,
      );

  /// Begin a **timestamp-based** constraint chain.
  ///
  /// Example: `.event("purchase").timestamp().greaterThan(dateTime)`
  TimestampSelector timestamp() => TimestampSelector(this, _filter);

  /// Begin a **count-based** trigger chain.
  ///
  /// Example: `.event("purchase").count().greaterThan(5)`
  CountClauseBuilder count() =>
      CountClauseBuilder(store: _store, eventName: _eventName, filter: _filter);

  /// Begin an **attribute-based** trigger chain.
  ///
  /// Example: `.event("purchase").attribute("price").sum().greaterThan(100.0)`
  AttributeSelector attribute(String key) => AttributeSelector(
    store: _store,
    eventName: _eventName,
    attrKey: key,
    filter: _filter,
  );
}
