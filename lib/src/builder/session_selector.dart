import 'package:objectbox/objectbox.dart';

import 'event_clause.dart';
import 'query_filter.dart';
import 'session_count_clause.dart';

/// Returned by [EventClause.session].
///
/// Provides three complementary sub-clauses for session-based filtering:
///
/// * [current] – keep only events that occurred in the **current** session.
/// * [other]   – keep only events that occurred in a **different** session.
/// * [count]   – count the **distinct sessions** the event appeared in, then
///               compare with a threshold (see [SessionCountClauseBuilder]).
///
/// ### Examples
/// ```dart
/// // events in the current session
/// trigger.when().event("click").session().current().count().greaterThan(2)
///
/// // events NOT in the current session
/// trigger.when().event("ad_view").session().other().count().greaterThan(0)
///
/// // event occurred in more than 5 distinct sessions
/// trigger.when().event("login").session().count().greaterThan(5)
/// ```
class SessionSelector {
  final Store _store;
  final String _eventName;
  final String _currentSessionId;
  final QueryFilter _filter;

  const SessionSelector({
    required Store store,
    required String eventName,
    required String currentSessionId,
    required QueryFilter filter,
  })  : _store = store,
        _eventName = eventName,
        _currentSessionId = currentSessionId,
        _filter = filter;

  /// Restricts subsequent clauses to events recorded in the **current** session.
  ///
  /// Returns an [EventClause] so you can continue chaining (e.g. `.count()`,
  /// `.attribute()`, `.timestamp()`).
  EventClause current() {
    return EventClause(
      store: _store,
      eventName: _eventName,
      sessionId: _currentSessionId,
      filter: _filter.copyWith(
        sessionId: _currentSessionId,
        negateSession: false,
      ),
    );
  }

  /// Restricts subsequent clauses to events recorded in a **different** session
  /// (i.e. any session other than the current one).
  ///
  /// Returns an [EventClause] so you can continue chaining.
  EventClause other() {
    return EventClause(
      store: _store,
      eventName: _eventName,
      sessionId: _currentSessionId,
      filter: _filter.copyWith(
        sessionId: _currentSessionId,
        negateSession: true,
      ),
    );
  }

  /// Counts the **number of distinct sessions** in which the event occurred
  /// and returns a [SessionCountClauseBuilder] for threshold comparisons.
  ///
  /// Timestamp constraints already applied to the chain are respected;
  /// session-id constraints are intentionally ignored (because the purpose
  /// here is to aggregate across sessions).
  SessionCountClauseBuilder count() {
    return SessionCountClauseBuilder(
      store: _store,
      eventName: _eventName,
      filter: _filter,
    );
  }
}

