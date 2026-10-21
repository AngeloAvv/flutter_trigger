import '../engine/evaluation_context.dart';
import '../engine/session_manager.dart';
import '../model/event_stats.dart';
import 'funnel.dart';
import 'metrics.dart';
import 'numeric_clause.dart';
import 'occurrence.dart';

/// Entry point of the condition DSL, returned by `Nudge.when()`.
class EventSelector {
  const EventSelector();

  /// Selects the events named [name].
  EventClause event(String name) => EventClause(EventScope(name));

  /// Defines a funnel: [steps] must happen in this order.
  FunnelBuilder funnel(List<String> steps) => FunnelBuilder(steps);

  /// App-wide metrics: sessions, active days, streak and install age.
  AppSelector app() => const AppSelector();

  /// Selects the fire history of the nudge [nudgeId], to chain nudges
  /// or to write custom policies.
  FireSelector fired(String nudgeId) =>
      FireSelector(FireScope(nudgeId: nudgeId));

  /// Selects the fire history of every nudge in [group].
  FireSelector group(String group) => FireSelector(FireScope(group: group));
}

/// A selection of events, narrowed step by step, ending in a condition.
class EventClause {
  final EventScope _scope;

  const EventClause(this._scope);

  /// Restricts the selection by session, or counts distinct sessions.
  SessionSelector session() => SessionSelector(_scope);

  /// Restricts the selection to an absolute time range.
  TimestampSelector timestamp() => TimestampSelector(_scope);

  /// Restricts the selection to events logged in the last [duration],
  /// measured every time the condition is evaluated.
  ///
  /// ```dart
  /// nudge.when().event('workout').inLast(Duration(days: 7)).count().greaterThanOrEqual(3)
  /// ```
  EventClause inLast(Duration duration) =>
      EventClause(_scope.copyWith(inLast: duration));

  /// Restricts the selection to events logged today, since local midnight
  /// at the moment of evaluation.
  ///
  /// ```dart
  /// // Has not practiced yet today
  /// nudge.when().event('lesson_completed').today().exists().not()
  /// ```
  EventClause today() => EventClause(_scope.copyWith(today: true));

  /// Restricts the selection to events whose attribute [key] satisfies the
  /// comparison that follows.
  ///
  /// ```dart
  /// nudge.when().event('purchase').where('currency').equalTo('EUR').count()
  /// ```
  AttributeWhereSelector where(String key) =>
      AttributeWhereSelector(_scope, key);

  /// Counts the selected events.
  CountClauseBuilder count() => CountClauseBuilder(EventCountMetric(_scope));

  /// Met when at least one event is selected.
  CountClause exists() => count().greaterThan(0);

  /// Aggregates the numeric attribute [key] of the selected events.
  AttributeSelector attribute(String key) => AttributeSelector(_scope, key);

  /// Counts the distinct local days on which the selected events happened.
  CountClauseBuilder activeDays() =>
      CountClauseBuilder(ActiveDaysMetric(_scope));

  /// Counts the consecutive local days, ending today or yesterday, on which
  /// the selected events happened.
  CountClauseBuilder streak() => CountClauseBuilder(StreakMetric(_scope));

  /// Conditions on how long ago the first selected event happened.
  OccurrenceSelector firstOccurrence() =>
      OccurrenceSelector(EventOccurrenceSource(_scope), OccurrenceKind.first);

  /// Conditions on how long ago the last selected event happened.
  OccurrenceSelector lastOccurrence() =>
      OccurrenceSelector(EventOccurrenceSource(_scope), OccurrenceKind.last);
}

/// Session constraints for an [EventClause].
class SessionSelector {
  final EventScope _scope;

  const SessionSelector(this._scope);

  /// Only events logged in the current session.
  EventClause current() =>
      EventClause(_scope.copyWith(session: SessionScope.current));

  /// Only events logged in sessions other than the current one.
  EventClause other() =>
      EventClause(_scope.copyWith(session: SessionScope.other));

  /// Counts the distinct sessions the selected events were logged in.
  SessionCountClauseBuilder count() =>
      SessionCountClauseBuilder(DistinctSessionsMetric(_scope));
}

/// Absolute time constraints for an [EventClause], with millisecond
/// precision. Multiple constraints intersect.
class TimestampSelector {
  final EventScope _scope;

  const TimestampSelector(this._scope);

  /// Only events logged strictly after [dateTime].
  EventClause greaterThan(DateTime dateTime) =>
      EventClause(_scope.narrow(from: _plusOneMs(dateTime)));

  /// Only events logged at or after [dateTime].
  EventClause greaterThanOrEqual(DateTime dateTime) =>
      EventClause(_scope.narrow(from: _floorMs(dateTime)));

  /// Only events logged strictly before [dateTime].
  EventClause lessThan(DateTime dateTime) =>
      EventClause(_scope.narrow(to: _minusOneMs(dateTime)));

  /// Only events logged at or before [dateTime].
  EventClause lessThanOrEqual(DateTime dateTime) =>
      EventClause(_scope.narrow(to: _floorMs(dateTime)));

  /// Only events logged at exactly [dateTime].
  EventClause equalTo(DateTime dateTime) => EventClause(
    _scope.narrow(from: _floorMs(dateTime), to: _floorMs(dateTime)),
  );
}

/// Aggregates of a numeric attribute.
class AttributeSelector {
  final EventScope _scope;
  final String _key;

  const AttributeSelector(this._scope, this._key);

  /// The sum of the values; `0` when there are none.
  AggregateClauseBuilder sum() => _aggregate(AggregateType.sum);

  /// The average of the values; never met when there are none.
  AggregateClauseBuilder avg() => _aggregate(AggregateType.avg);

  /// The minimum value; never met when there are none.
  AggregateClauseBuilder min() => _aggregate(AggregateType.min);

  /// The maximum value; never met when there are none.
  AggregateClauseBuilder max() => _aggregate(AggregateType.max);

  /// The number of distinct values, of any type.
  ///
  /// ```dart
  /// // Explored at least three different features
  /// nudge.when().event('feature_used').attribute('feature').distinct().greaterThanOrEqual(3)
  /// ```
  CountClauseBuilder distinct() =>
      CountClauseBuilder(AttributeDistinctMetric(_scope, _key));

  AggregateClauseBuilder _aggregate(AggregateType type) =>
      AggregateClauseBuilder(AttributeAggregateMetric(_scope, _key, type));
}

/// Attribute constraints for an [EventClause].
class AttributeWhereSelector {
  final EventScope _scope;
  final String _key;

  const AttributeWhereSelector(this._scope, this._key);

  EventClause equalTo(Object value) => _with(AttributeOperator.equalTo, value);

  /// Also matches events without the attribute.
  EventClause notEqualTo(Object value) =>
      _with(AttributeOperator.notEqualTo, value);

  EventClause greaterThan(num value) =>
      _with(AttributeOperator.greaterThan, value);

  EventClause greaterThanOrEqual(num value) =>
      _with(AttributeOperator.greaterThanOrEqual, value);

  EventClause lessThan(num value) => _with(AttributeOperator.lessThan, value);

  EventClause lessThanOrEqual(num value) =>
      _with(AttributeOperator.lessThanOrEqual, value);

  EventClause oneOf(List<Object> values) =>
      _with(AttributeOperator.oneOf, List<Object>.unmodifiable(values));

  EventClause exists() => _with(AttributeOperator.exists);

  EventClause _with(AttributeOperator operator, [Object? value]) => EventClause(
    _scope.copyWith(
      where: [..._scope.where, AttributePredicate(_key, operator, value)],
    ),
  );
}

/// App-wide metrics, answered from lifetime stats that survive log rotation.
class AppSelector {
  const AppSelector();

  static const _sessions = EventScope(SessionManager.sessionStartEvent);
  static const _anyEvent = EventScope(EventStats.anyEvent);

  /// Number of sessions started so far, the current one included.
  CountClauseBuilder sessions() =>
      const CountClauseBuilder(EventCountMetric(_sessions));

  /// Number of distinct local days the app was used on.
  CountClauseBuilder activeDays() =>
      const CountClauseBuilder(ActiveDaysMetric(_anyEvent));

  /// Consecutive local days, ending today or yesterday, the app was used on.
  CountClauseBuilder streak() =>
      const CountClauseBuilder(StreakMetric(_anyEvent));

  /// Conditions on the start of the most recent session before the current
  /// one, i.e. how long the user had been away when this session started.
  ///
  /// ```dart
  /// // Welcome back after two weeks away
  /// nudge.when().app().previousSession().olderThan(Duration(days: 14))
  /// ```
  OccurrenceSelector previousSession() => const OccurrenceSelector(
    EventOccurrenceSource(
      EventScope(SessionManager.sessionStartEvent, session: SessionScope.other),
    ),
    OccurrenceKind.last,
  );

  /// Conditions on the first session ever recorded, i.e. the install age as
  /// far as the package can tell.
  OccurrenceSelector firstSeen() => const OccurrenceSelector(
    EventOccurrenceSource(_sessions),
    OccurrenceKind.first,
  );
}

/// A selection of nudge fires.
class FireSelector {
  final FireScope _scope;

  const FireSelector(this._scope);

  /// Only fires in the last [duration].
  FireSelector inLast(Duration duration) =>
      FireSelector(_scope.copyWith(inLast: duration));

  /// Only fires in the current session.
  FireSelector inCurrentSession() =>
      FireSelector(_scope.copyWith(currentSession: true));

  /// Only fires completed with [outcome].
  FireSelector outcome(String outcome) =>
      FireSelector(_scope.copyWith(outcome: outcome));

  /// Counts the selected fires.
  CountClauseBuilder count() => CountClauseBuilder(FireCountMetric(_scope));

  /// Met when at least one fire is selected.
  CountClause exists() => count().greaterThan(0);

  /// Conditions on how long ago the last selected fire happened.
  OccurrenceSelector lastFired() =>
      OccurrenceSelector(FireOccurrenceSource(_scope), OccurrenceKind.last);
}

DateTime _floorMs(DateTime dateTime) =>
    DateTime.fromMillisecondsSinceEpoch(dateTime.millisecondsSinceEpoch);

DateTime _plusOneMs(DateTime dateTime) =>
    DateTime.fromMillisecondsSinceEpoch(dateTime.millisecondsSinceEpoch + 1);

DateTime _minusOneMs(DateTime dateTime) =>
    DateTime.fromMillisecondsSinceEpoch(dateTime.millisecondsSinceEpoch - 1);
