import 'package:flutter/foundation.dart';

import '../model/event_record.dart';
import '../model/event_stats.dart';
import '../model/fire_record.dart';
import '../storage/nudge_storage.dart';

/// Everything a condition needs to evaluate itself: the storage, the current
/// time and the current session.
class EvaluationContext {
  final NudgeStorage storage;
  final DateTime now;
  final String sessionId;

  const EvaluationContext({
    required this.storage,
    required this.now,
    required this.sessionId,
  });
}

/// Which sessions an event selection is restricted to.
enum SessionScope {
  any,
  current,
  other;

  String get label => switch (this) {
    any => '',
    current => ', current session',
    other => ', other sessions',
  };
}

/// The comparison applied by an [AttributePredicate].
enum AttributeOperator {
  equalTo('=='),
  notEqualTo('!='),
  greaterThan('>'),
  greaterThanOrEqual('>='),
  lessThan('<'),
  lessThanOrEqual('<='),
  oneOf('in'),
  exists('exists');

  final String symbol;

  const AttributeOperator(this.symbol);
}

/// A constraint on an attribute of the selected events.
@immutable
class AttributePredicate {
  final String key;
  final AttributeOperator operator;
  final Object? value;

  const AttributePredicate(this.key, this.operator, [this.value]);

  bool matches(Map<String, Object> attributes) {
    final actual = attributes[key];
    if (actual == null) return operator == AttributeOperator.notEqualTo;

    return switch (operator) {
      AttributeOperator.equalTo => actual == value,
      AttributeOperator.notEqualTo => actual != value,
      AttributeOperator.oneOf => (value as List<Object>).contains(actual),
      AttributeOperator.exists => true,
      _ => _compare(actual),
    };
  }

  bool _compare(Object actual) {
    final threshold = value;
    if (actual is! num || threshold is! num) return false;

    return switch (operator) {
      AttributeOperator.greaterThan => actual > threshold,
      AttributeOperator.greaterThanOrEqual => actual >= threshold,
      AttributeOperator.lessThan => actual < threshold,
      AttributeOperator.lessThanOrEqual => actual <= threshold,
      _ => false,
    };
  }

  @override
  String toString() => operator == AttributeOperator.exists
      ? '$key exists'
      : '$key ${operator.symbol} $value';

  @override
  bool operator ==(Object other) =>
      other is AttributePredicate &&
      other.key == key &&
      other.operator == operator &&
      (value is List
          ? other.value is List &&
                listEquals(value as List, other.value as List)
          : other.value == value);

  @override
  int get hashCode => Object.hash(
    key,
    operator,
    value is List ? Object.hashAll(value as List) : value,
  );
}

/// A selection of events of one name, narrowed by session, time and
/// attributes.
@immutable
class EventScope {
  final String name;
  final SessionScope session;

  /// Inclusive absolute lower bound.
  final DateTime? from;

  /// Inclusive absolute upper bound.
  final DateTime? to;

  /// Relative lower bound: only events in the last [inLast], measured from
  /// the moment of evaluation.
  final Duration? inLast;

  /// Relative lower bound: only events since the local midnight of the
  /// moment of evaluation.
  final bool today;

  final List<AttributePredicate> where;

  const EventScope(
    this.name, {
    this.session = SessionScope.any,
    this.from,
    this.to,
    this.inLast,
    this.today = false,
    this.where = const [],
  });

  /// Whether the scope covers every event ever logged with [name], in which
  /// case lifetime [EventStats] answer instead of the (rotated) log.
  bool get isUnfiltered =>
      session == SessionScope.any &&
      from == null &&
      to == null &&
      inLast == null &&
      !today &&
      where.isEmpty;

  EventScope copyWith({
    SessionScope? session,
    DateTime? from,
    DateTime? to,
    Duration? inLast,
    bool? today,
    List<AttributePredicate>? where,
  }) => EventScope(
    name,
    session: session ?? this.session,
    from: from ?? this.from,
    to: to ?? this.to,
    inLast: inLast ?? this.inLast,
    today: today ?? this.today,
    where: where ?? this.where,
  );

  /// Narrows the absolute time range; bounds intersect with existing ones.
  EventScope narrow({DateTime? from, DateTime? to}) => EventScope(
    name,
    session: session,
    from: _latest(this.from, from),
    to: _earliest(this.to, to),
    inLast: inLast,
    today: today,
    where: where,
  );

  EventQuery toQuery(EvaluationContext context) => eventQuery(
    {name},
    context,
    session: session,
    from: from,
    to: to,
    inLast: inLast,
    today: today,
  );

  List<EventRecord> find(EvaluationContext context) {
    final events = context.storage.findEvents(toQuery(context));
    if (where.isEmpty) return events;

    return events
        .where((event) => where.every((p) => p.matches(event.attributes)))
        .toList(growable: false);
  }

  int count(EvaluationContext context) {
    if (isUnfiltered) return context.storage.stats(name)?.count ?? 0;
    if (where.isEmpty) return context.storage.countEvents(toQuery(context));
    return find(context).length;
  }

  String get label {
    final parts = [
      name == EventStats.anyEvent ? 'any event' : name,
      if (session != SessionScope.any) session.name,
      if (inLast != null) 'last ${formatDuration(inLast!)}',
      if (today) 'today',
      if (from != null) 'from ${from!.toIso8601String()}',
      if (to != null) 'to ${to!.toIso8601String()}',
      ...where.map((predicate) => predicate.toString()),
    ];
    return parts.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      other is EventScope &&
      other.name == name &&
      other.session == session &&
      other.from == from &&
      other.to == to &&
      other.inLast == inLast &&
      other.today == today &&
      listEquals(other.where, where);

  @override
  int get hashCode => Object.hash(
    name,
    session,
    from,
    to,
    inLast,
    today,
    Object.hashAll(where),
  );
}

/// Builds the storage query for [names], resolving the session scope and the
/// relative window against [context].
EventQuery eventQuery(
  Set<String> names,
  EvaluationContext context, {
  SessionScope session = SessionScope.any,
  DateTime? from,
  DateTime? to,
  Duration? inLast,
  bool today = false,
}) {
  final now = context.now;
  return EventQuery(
    names: names,
    sessionId: session == SessionScope.any ? null : context.sessionId,
    excludeSession: session == SessionScope.other,
    from: _latest(
      _latest(from, inLast == null ? null : now.subtract(inLast)),
      today ? _startOfLocalDay(now) : null,
    ),
    to: to,
  );
}

DateTime _startOfLocalDay(DateTime dateTime) {
  final local = dateTime.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// A selection of fire records of one nudge or of a group of nudges.
@immutable
class FireScope {
  final String? nudgeId;
  final String? group;
  final bool currentSession;
  final Duration? inLast;
  final String? outcome;

  const FireScope({
    this.nudgeId,
    this.group,
    this.currentSession = false,
    this.inLast,
    this.outcome,
  });

  FireScope copyWith({
    bool? currentSession,
    Duration? inLast,
    String? outcome,
  }) => FireScope(
    nudgeId: nudgeId,
    group: group,
    currentSession: currentSession ?? this.currentSession,
    inLast: inLast ?? this.inLast,
    outcome: outcome ?? this.outcome,
  );

  List<FireRecord> find(EvaluationContext context) => context.storage.findFires(
    FireQuery(
      nudgeId: nudgeId,
      group: group,
      sessionId: currentSession ? context.sessionId : null,
      outcome: outcome,
      from: inLast == null ? null : context.now.subtract(inLast!),
    ),
  );

  String get label => [
    nudgeId != null ? 'nudge $nudgeId' : 'group $group',
    if (outcome != null) 'outcome $outcome',
    if (currentSession) 'current session',
    if (inLast != null) 'last ${formatDuration(inLast!)}',
  ].join(', ');

  @override
  bool operator ==(Object other) =>
      other is FireScope &&
      other.nudgeId == nudgeId &&
      other.group == group &&
      other.currentSession == currentSession &&
      other.inLast == inLast &&
      other.outcome == outcome;

  @override
  int get hashCode =>
      Object.hash(nudgeId, group, currentSession, inLast, outcome);
}

/// Formats [duration] compactly for explanations, e.g. `30d`, `1h 30m`.
String formatDuration(Duration duration) {
  final parts = [
    if (duration.inDays != 0) '${duration.inDays}d',
    if (duration.inHours % 24 != 0) '${duration.inHours % 24}h',
    if (duration.inMinutes % 60 != 0) '${duration.inMinutes % 60}m',
    if (duration.inSeconds % 60 != 0) '${duration.inSeconds % 60}s',
  ];
  if (parts.isEmpty) return '${duration.inMilliseconds}ms';
  return parts.join(' ');
}

DateTime? _latest(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

DateTime? _earliest(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}
