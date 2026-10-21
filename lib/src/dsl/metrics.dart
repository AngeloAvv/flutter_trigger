import 'package:flutter/foundation.dart';

import '../engine/evaluation_context.dart';
import '../model/event_record.dart';
import '../model/event_stats.dart';

/// The aggregate applied to a numeric attribute.
enum AggregateType { sum, avg, min, max }

/// A number computed from the event history, compared by a `NumericClause`.
///
/// A metric returns `null` when it has no value, e.g. the average of an
/// attribute that was never logged; comparisons on `null` are never met.
@immutable
sealed class Metric {
  const Metric();

  num? compute(EvaluationContext context);

  String get label;
}

/// Number of events in a scope.
class EventCountMetric extends Metric {
  final EventScope scope;

  const EventCountMetric(this.scope);

  @override
  num compute(EvaluationContext context) => scope.count(context);

  @override
  String get label => 'count(${scope.label})';

  @override
  bool operator ==(Object other) =>
      other is EventCountMetric && other.scope == scope;

  @override
  int get hashCode => Object.hash(EventCountMetric, scope);
}

/// Number of distinct sessions in which events of a scope were logged.
class DistinctSessionsMetric extends Metric {
  final EventScope scope;

  const DistinctSessionsMetric(this.scope);

  @override
  num compute(EvaluationContext context) =>
      scope.find(context).map((event) => event.sessionId).toSet().length;

  @override
  String get label => 'sessions(${scope.label})';

  @override
  bool operator ==(Object other) =>
      other is DistinctSessionsMetric && other.scope == scope;

  @override
  int get hashCode => Object.hash(DistinctSessionsMetric, scope);
}

/// Number of distinct local days on which events of a scope were logged.
class ActiveDaysMetric extends Metric {
  final EventScope scope;

  const ActiveDaysMetric(this.scope);

  @override
  num compute(EvaluationContext context) => scope.isUnfiltered
      ? context.storage.stats(scope.name)?.activeDays ?? 0
      : _days(scope.find(context)).length;

  @override
  String get label => 'activeDays(${scope.label})';

  @override
  bool operator ==(Object other) =>
      other is ActiveDaysMetric && other.scope == scope;

  @override
  int get hashCode => Object.hash(ActiveDaysMetric, scope);
}

/// Consecutive local days, ending today or yesterday, on which events of a
/// scope were logged. A day without the event resets it to zero.
class StreakMetric extends Metric {
  final EventScope scope;

  const StreakMetric(this.scope);

  @override
  num compute(EvaluationContext context) {
    if (scope.isUnfiltered) {
      return context.storage.stats(scope.name)?.streakOn(context.now) ?? 0;
    }

    final days = _days(scope.find(context)).toList()
      ..sort((a, b) => b.compareTo(a));
    if (days.isEmpty || dayKeyOf(context.now) - days.first > 1) return 0;

    var streak = 1;
    while (streak < days.length && days[streak - 1] - days[streak] == 1) {
      streak++;
    }
    return streak;
  }

  @override
  String get label => 'streak(${scope.label})';

  @override
  bool operator ==(Object other) =>
      other is StreakMetric && other.scope == scope;

  @override
  int get hashCode => Object.hash(StreakMetric, scope);
}

/// An aggregate of a numeric attribute across the events of a scope.
class AttributeAggregateMetric extends Metric {
  final EventScope scope;
  final String key;
  final AggregateType type;

  const AttributeAggregateMetric(this.scope, this.key, this.type);

  @override
  num? compute(EvaluationContext context) {
    final values = [
      for (final event in scope.find(context))
        if (event.attributes[key] case final num value) value.toDouble(),
    ];

    if (values.isEmpty) return type == AggregateType.sum ? 0.0 : null;

    return switch (type) {
      AggregateType.sum => values.fold<double>(0, (a, b) => a + b),
      AggregateType.avg =>
        values.fold<double>(0, (a, b) => a + b) / values.length,
      AggregateType.min => values.reduce((a, b) => a < b ? a : b),
      AggregateType.max => values.reduce((a, b) => a > b ? a : b),
    };
  }

  @override
  String get label => '${type.name}(${scope.label}.$key)';

  @override
  bool operator ==(Object other) =>
      other is AttributeAggregateMetric &&
      other.scope == scope &&
      other.key == key &&
      other.type == type;

  @override
  int get hashCode => Object.hash(AttributeAggregateMetric, scope, key, type);
}

/// Number of distinct values of an attribute across the events of a scope.
class AttributeDistinctMetric extends Metric {
  final EventScope scope;
  final String key;

  const AttributeDistinctMetric(this.scope, this.key);

  @override
  num compute(EvaluationContext context) => {
    for (final event in scope.find(context))
      if (event.attributes[key] case final Object value) value,
  }.length;

  @override
  String get label => 'distinct(${scope.label}.$key)';

  @override
  bool operator ==(Object other) =>
      other is AttributeDistinctMetric &&
      other.scope == scope &&
      other.key == key;

  @override
  int get hashCode => Object.hash(AttributeDistinctMetric, scope, key);
}

/// Number of fire records in a scope.
class FireCountMetric extends Metric {
  final FireScope scope;

  const FireCountMetric(this.scope);

  @override
  num compute(EvaluationContext context) => scope.find(context).length;

  @override
  String get label => 'fires(${scope.label})';

  @override
  bool operator ==(Object other) =>
      other is FireCountMetric && other.scope == scope;

  @override
  int get hashCode => Object.hash(FireCountMetric, scope);
}

Set<int> _days(List<EventRecord> events) =>
    events.map((event) => dayKeyOf(event.timestamp)).toSet();
