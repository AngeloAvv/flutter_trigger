import '../engine/evaluation_context.dart';
import 'nudge_condition.dart';

/// Which occurrence an [OccurrenceSelector] looks at.
enum OccurrenceKind { first, last }

/// Builds conditions on how long ago the first or last occurrence happened.
///
/// ```dart
/// // The user has been around for at least a week
/// nudge.when().app().firstSeen().olderThan(Duration(days: 7))
///
/// // The user used to open the app, but not in the last 14 days
/// nudge.when().event('app_open').lastOccurrence().olderThan(Duration(days: 14))
/// ```
class OccurrenceSelector {
  final OccurrenceSource _source;
  final OccurrenceKind _kind;

  const OccurrenceSelector(this._source, this._kind);

  /// Met when the occurrence happened more than [duration] ago. Never met if
  /// it never happened.
  OccurrenceCondition olderThan(Duration duration) =>
      OccurrenceCondition(_source, _kind, duration, older: true);

  /// Met when the occurrence happened at most [duration] ago. Never met if it
  /// never happened.
  OccurrenceCondition newerThan(Duration duration) =>
      OccurrenceCondition(_source, _kind, duration, older: false);
}

/// Where an occurrence is looked up: events or nudge fires.
sealed class OccurrenceSource {
  const OccurrenceSource();

  DateTime? find(EvaluationContext context, OccurrenceKind kind);

  String get label;
}

/// Occurrences of events in a scope.
class EventOccurrenceSource extends OccurrenceSource {
  final EventScope scope;

  const EventOccurrenceSource(this.scope);

  @override
  DateTime? find(EvaluationContext context, OccurrenceKind kind) {
    if (scope.isUnfiltered) {
      final stats = context.storage.stats(scope.name);
      return kind == OccurrenceKind.first ? stats?.firstAt : stats?.lastAt;
    }

    final events = scope.find(context);
    if (events.isEmpty) return null;
    return (kind == OccurrenceKind.first ? events.first : events.last)
        .timestamp;
  }

  @override
  String get label => scope.label;

  @override
  bool operator ==(Object other) =>
      other is EventOccurrenceSource && other.scope == scope;

  @override
  int get hashCode => Object.hash(EventOccurrenceSource, scope);
}

/// Occurrences of nudge fires in a scope.
class FireOccurrenceSource extends OccurrenceSource {
  final FireScope scope;

  const FireOccurrenceSource(this.scope);

  @override
  DateTime? find(EvaluationContext context, OccurrenceKind kind) {
    final fires = scope.find(context);
    if (fires.isEmpty) return null;
    return (kind == OccurrenceKind.first ? fires.first : fires.last).firedAt;
  }

  @override
  String get label => scope.label;

  @override
  bool operator ==(Object other) =>
      other is FireOccurrenceSource && other.scope == scope;

  @override
  int get hashCode => Object.hash(FireOccurrenceSource, scope);
}

/// A condition on the age of the first or last occurrence.
class OccurrenceCondition extends NudgeCondition {
  final OccurrenceSource source;
  final OccurrenceKind kind;
  final Duration duration;
  final bool older;

  const OccurrenceCondition(
    this.source,
    this.kind,
    this.duration, {
    required this.older,
  });

  @override
  ConditionResult resolve(EvaluationContext context) {
    final at = source.find(context, kind);
    final age = at == null ? null : context.now.difference(at);
    final value = age != null && (older ? age > duration : age <= duration);

    return ConditionResult(
      value,
      '${kind.name}(${source.label}) '
      '${age == null ? 'never happened' : '${formatDuration(age)} ago'}, '
      '${older ? 'older' : 'newer'} than ${formatDuration(duration)}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OccurrenceCondition &&
      other.source == source &&
      other.kind == kind &&
      other.duration == duration &&
      other.older == older;

  @override
  int get hashCode =>
      Object.hash(OccurrenceCondition, source, kind, duration, older);
}
