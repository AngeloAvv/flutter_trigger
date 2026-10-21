import 'package:flutter/foundation.dart';

import '../engine/evaluation_context.dart';
import '../model/event_record.dart';
import 'nudge_condition.dart';

/// A loose funnel: the steps must happen in order, with any other events in
/// between.
///
/// The funnel is met when the sequence was completed at least once in the
/// selected events. Order is decided by insertion order, so two steps logged
/// in the same millisecond still count, and a device clock moved backwards
/// cannot reorder them.
///
/// ```dart
/// // Steps in order, at any time
/// nudge.when().funnel(['sign_up', 'first_purchase']).watch();
///
/// // All steps within 24 hours of the first one
/// nudge.when()
///   .funnel(['view_item', 'add_to_cart', 'checkout'])
///   .within(Duration(hours: 24));
///
/// // All steps in one session (any session)
/// nudge.when().funnel(['search', 'purchase']).session().single();
///
/// // Started, but not completed for 24 hours
/// nudge.when()
///   .funnel(['add_to_cart', 'purchase'])
///   .dropOff(after: Duration(hours: 24));
/// ```
class FunnelBuilder extends NudgeCondition {
  final List<String> steps;
  final SessionScope sessionScope;

  /// Whether every step has to be logged in the same session.
  final bool singleSession;
  final DateTime? from;
  final DateTime? to;
  final Duration? inLastDuration;

  /// The maximum time between the first and the last step.
  final Duration? window;

  const FunnelBuilder(
    this.steps, {
    this.sessionScope = SessionScope.any,
    this.singleSession = false,
    this.from,
    this.to,
    this.inLastDuration,
    this.window,
  });

  FunnelBuilder copyWith({
    SessionScope? session,
    bool? singleSession,
    DateTime? from,
    DateTime? to,
    Duration? inLast,
    Duration? window,
  }) => FunnelBuilder(
    steps,
    sessionScope: session ?? sessionScope,
    singleSession: singleSession ?? this.singleSession,
    from: from ?? this.from,
    to: to ?? this.to,
    inLastDuration: inLast ?? inLastDuration,
    window: window ?? this.window,
  );

  /// Marks the funnel as loose, the only mode supported. Kept for
  /// readability.
  FunnelBuilder loose() => this;

  /// Session constraints for every step.
  FunnelSessionSelector session() => FunnelSessionSelector(this);

  /// Absolute time constraints for every step, or the funnel window.
  FunnelTimestampSelector timestamp() => FunnelTimestampSelector(this);

  /// All steps must happen within [duration] from the first one.
  FunnelBuilder within(Duration duration) => copyWith(window: duration);

  /// Only steps logged in the last [duration], measured every time the
  /// condition is evaluated.
  FunnelBuilder inLast(Duration duration) => copyWith(inLast: duration);

  /// Met when the funnel was started and has not been completed for
  /// [after] since the most recent start.
  ///
  /// The condition becomes true by the passing of time alone: watchers pick
  /// the change up on the periodic re-evaluation, on resume and at
  /// checkpoints.
  FunnelDropOffCondition dropOff({required Duration after}) =>
      FunnelDropOffCondition(this, after);

  @override
  ConditionResult resolve(EvaluationContext context) {
    final progress = _groups(context)
        .map((events) => _FunnelMatcher(steps, events, window).bestProgress())
        .fold(0, (best, progress) => progress > best ? progress : best);

    return ConditionResult(
      steps.isNotEmpty && progress == steps.length,
      '$label progress $progress/${steps.length}',
    );
  }

  /// The selected events, split by session when [singleSession] is set.
  Iterable<List<EventRecord>> _groups(EvaluationContext context) {
    if (steps.isEmpty) return const [];

    final events = context.storage.findEvents(
      eventQuery(
        steps.toSet(),
        context,
        session: sessionScope,
        from: from,
        to: to,
        inLast: inLastDuration,
      ),
    );
    if (!singleSession) return [events];

    final bySession = <String, List<EventRecord>>{};
    for (final event in events) {
      (bySession[event.sessionId] ??= []).add(event);
    }
    return bySession.values;
  }

  String get label =>
      'funnel(${[steps.join(' → '), if (sessionScope != SessionScope.any) '${sessionScope.name} session', if (singleSession) 'single session', if (window != null) 'within ${formatDuration(window!)}', if (inLastDuration != null) 'last ${formatDuration(inLastDuration!)}', if (from != null) 'from ${from!.toIso8601String()}', if (to != null) 'to ${to!.toIso8601String()}'].join(', ')})';

  @override
  bool operator ==(Object other) =>
      other is FunnelBuilder &&
      listEquals(other.steps, steps) &&
      other.sessionScope == sessionScope &&
      other.singleSession == singleSession &&
      other.from == from &&
      other.to == to &&
      other.inLastDuration == inLastDuration &&
      other.window == window;

  @override
  int get hashCode => Object.hash(
    FunnelBuilder,
    Object.hashAll(steps),
    sessionScope,
    singleSession,
    from,
    to,
    inLastDuration,
    window,
  );
}

/// Met when a funnel was started but not completed for a while.
class FunnelDropOffCondition extends NudgeCondition {
  final FunnelBuilder funnel;
  final Duration after;

  const FunnelDropOffCondition(this.funnel, this.after);

  @override
  ConditionResult resolve(EvaluationContext context) {
    String description(String detail) =>
        '${funnel.label} drop-off after ${formatDuration(after)}: $detail';

    EventRecord? start;
    List<EventRecord> candidates = const [];
    for (final events in funnel._groups(context)) {
      final latest = events.lastWhereOrNull(
        (event) => event.name == funnel.steps.first,
      );
      if (latest != null && (start == null || latest.id > start.id)) {
        start = latest;
        candidates = events;
      }
    }

    if (start == null) {
      return ConditionResult(false, description('not started'));
    }

    final matcher = _FunnelMatcher(funnel.steps, candidates, funnel.window);
    if (matcher.progressFrom(candidates.indexOf(start)) ==
        funnel.steps.length) {
      return ConditionResult(false, description('completed'));
    }

    final idle = context.now.difference(start.timestamp);
    return ConditionResult(
      idle >= after,
      description('started ${formatDuration(idle)} ago, not completed'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FunnelDropOffCondition &&
      other.funnel == funnel &&
      other.after == after;

  @override
  int get hashCode => Object.hash(FunnelDropOffCondition, funnel, after);
}

/// Session constraints for a [FunnelBuilder].
class FunnelSessionSelector {
  final FunnelBuilder _funnel;

  const FunnelSessionSelector(this._funnel);

  /// Every step in the current session.
  FunnelBuilder current() => _funnel.copyWith(session: SessionScope.current);

  /// Every step in the current session. Alias of [current].
  FunnelBuilder same() => current();

  /// Every step in sessions other than the current one.
  FunnelBuilder other() => _funnel.copyWith(session: SessionScope.other);

  /// Every step in one session, whichever it is.
  FunnelBuilder single() => _funnel.copyWith(singleSession: true);
}

/// Time constraints for a [FunnelBuilder], applied to every step.
class FunnelTimestampSelector {
  final FunnelBuilder _funnel;

  const FunnelTimestampSelector(this._funnel);

  /// Every step strictly after [dateTime].
  FunnelBuilder greaterThan(DateTime dateTime) => _narrow(
    from: DateTime.fromMillisecondsSinceEpoch(
      dateTime.millisecondsSinceEpoch + 1,
    ),
  );

  /// Every step at or after [dateTime].
  FunnelBuilder greaterThanOrEqual(DateTime dateTime) => _narrow(
    from: DateTime.fromMillisecondsSinceEpoch(dateTime.millisecondsSinceEpoch),
  );

  /// Every step strictly before [dateTime].
  FunnelBuilder lessThan(DateTime dateTime) => _narrow(
    to: DateTime.fromMillisecondsSinceEpoch(
      dateTime.millisecondsSinceEpoch - 1,
    ),
  );

  /// Every step at or before [dateTime].
  FunnelBuilder lessThanOrEqual(DateTime dateTime) => _narrow(
    to: DateTime.fromMillisecondsSinceEpoch(dateTime.millisecondsSinceEpoch),
  );

  /// All steps within [duration] from the first one. Same as
  /// [FunnelBuilder.within].
  FunnelBuilder within(Duration duration) => _funnel.within(duration);

  FunnelBuilder _narrow({DateTime? from, DateTime? to}) {
    final currentFrom = _funnel.from;
    final currentTo = _funnel.to;
    return _funnel.copyWith(
      from: from != null && currentFrom != null && currentFrom.isAfter(from)
          ? currentFrom
          : from,
      to: to != null && currentTo != null && currentTo.isBefore(to)
          ? currentTo
          : to,
    );
  }
}

/// Matches funnel steps against events ordered by id.
class _FunnelMatcher {
  final List<String> steps;
  final List<EventRecord> events;
  final Duration? window;

  /// For every step, the indexes in [events] of the events with its name.
  final List<List<int>> _positions;

  _FunnelMatcher(this.steps, this.events, this.window)
    : _positions = [
        for (final step in steps)
          [
            for (var i = 0; i < events.length; i++)
              if (events[i].name == step) i,
          ],
      ];

  /// The most steps completed, in order, by any attempt.
  int bestProgress() {
    if (steps.isEmpty) return 0;

    var best = 0;
    for (final start in _positions.first) {
      final progress = progressFrom(start);
      if (progress > best) best = progress;
      if (best == steps.length) break;
    }
    return best;
  }

  /// The steps completed by the attempt starting at [start], matching each
  /// following step greedily with its earliest occurrence.
  int progressFrom(int start) {
    if (start < 0) return 0;

    final startedAt = events[start].timestamp;
    var previous = start;
    for (var step = 1; step < steps.length; step++) {
      final next = _firstAfter(_positions[step], previous);
      if (next == null) return step;
      if (window != null &&
          events[next].timestamp.difference(startedAt) > window!) {
        return step;
      }
      previous = next;
    }
    return steps.length;
  }

  static int? _firstAfter(List<int> positions, int index) {
    var low = 0;
    var high = positions.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (positions[mid] <= index) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < positions.length ? positions[low] : null;
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
