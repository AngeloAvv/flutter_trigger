import '../models/event.dart';
import '../models/attribute_type.dart';
import '../../objectbox.g.dart';
import '../builder/query_filter.dart';

/// The type of aggregate operation to perform on attribute values.
enum AggregateType { sum, avg, min, max }

/// Evaluation helpers used by the trigger builder DSL.
///
/// All methods are designed to be called inside `.watch()` callbacks
/// and should be as efficient as possible.
class TriggerEvaluator {
  final Store _store;

  const TriggerEvaluator(this._store);

  /// Builds a combined ObjectBox condition based on event name and filter constraints.
  Condition<Event> _buildCondition(String eventName, QueryFilter? filter) {
    Condition<Event> cond = Event_.name.equals(eventName);

    if (filter != null) {
      // Session filter
      if (filter.sessionId != null) {
        if (filter.negateSession) {
          cond = cond.and(Event_.sessionId.notEquals(filter.sessionId!));
        } else {
          cond = cond.and(Event_.sessionId.equals(filter.sessionId!));
        }
      }

      // Temporal filters
      // Note: QueryDateProperty lacks >= and <=, so we use > (val - 1) and < (val + 1)
      if (filter.timestampAfter != null) {
        cond = cond.and(
          Event_.timestamp.greaterThan(
            filter.timestampAfter!.millisecondsSinceEpoch - 1,
          ),
        );
      }
      if (filter.timestampBefore != null) {
        cond = cond.and(
          Event_.timestamp.lessThan(
            filter.timestampBefore!.millisecondsSinceEpoch + 1,
          ),
        );
      }
    }

    return cond;
  }

  // ---------------------------------------------------------------------------
  // Count-based evaluation
  // ---------------------------------------------------------------------------

  /// Returns the count of events matching [eventName] and [filter].
  int evaluateCount(String eventName, {QueryFilter? filter}) {
    final box = _store.box<Event>();
    final query = box.query(_buildCondition(eventName, filter)).build();
    final count = query.count();
    query.close();
    return count;
  }

  // ---------------------------------------------------------------------------
  // Attribute-aggregate evaluation
  // ---------------------------------------------------------------------------

  /// Computes the [aggregateType] of a numeric attribute [attrKey] across all
  /// events matching [eventName] and [filter].
  ///
  /// Only attributes with [AttributeType.integer] or [AttributeType.number]
  /// are considered.
  double evaluateAttributeAggregate(
    String eventName,
    String attrKey,
    AggregateType aggregateType, {
    QueryFilter? filter,
  }) {
    final box = _store.box<Event>();
    final query = box.query(_buildCondition(eventName, filter)).build();
    final events = query.find();
    query.close();

    final values = <double>[];

    for (final event in events) {
      for (final attr in event.attributes) {
        if (attr.key != attrKey) continue;

        final type = AttributeType.fromIndex(attr.typeIndex);
        if (type == AttributeType.integer && attr.intValue != null) {
          values.add(attr.intValue!.toDouble());
        } else if (type == AttributeType.number && attr.doubleValue != null) {
          values.add(attr.doubleValue!);
        }
      }
    }

    if (values.isEmpty) return 0.0;

    switch (aggregateType) {
      case AggregateType.sum:
        return values.fold(0.0, (a, b) => a + b);
      case AggregateType.avg:
        return values.fold(0.0, (a, b) => a + b) / values.length;
      case AggregateType.min:
        return values.reduce((a, b) => a < b ? a : b);
      case AggregateType.max:
        return values.reduce((a, b) => a > b ? a : b);
    }
  }

  // ---------------------------------------------------------------------------
  // Session-count evaluation
  // ---------------------------------------------------------------------------

  /// Returns the number of **distinct sessions** in which [eventName] occurred,
  /// optionally narrowed by [filter] (timestamp constraints are respected;
  /// session-id constraints on the filter are intentionally ignored here
  /// because the caller is aggregating across sessions, not filtering to one).
  int evaluateSessionCount(String eventName, {QueryFilter? filter}) {
    final box = _store.box<Event>();

    // Build a condition that ignores any session filter but respects timestamp.
    Condition<Event> cond = Event_.name.equals(eventName);
    if (filter != null) {
      if (filter.timestampAfter != null) {
        cond = cond.and(
          Event_.timestamp.greaterThan(
            filter.timestampAfter!.millisecondsSinceEpoch - 1,
          ),
        );
      }
      if (filter.timestampBefore != null) {
        cond = cond.and(
          Event_.timestamp.lessThan(
            filter.timestampBefore!.millisecondsSinceEpoch + 1,
          ),
        );
      }
    }

    final query = box.query(cond).build();
    final events = query.find();
    query.close();

    return events.map((e) => e.sessionId).toSet().length;
  }

  // ---------------------------------------------------------------------------
  // Funnel evaluation
  // ---------------------------------------------------------------------------

  /// Evaluates a **loose funnel**: when the last step occurs, verifies that the
  /// previous steps exist in correct chronological order within [window].
  bool evaluateFunnel(
    List<String> events,
    Duration window, {
    QueryFilter? filter,
  }) {
    if (events.isEmpty) return false;

    final box = _store.box<Event>();

    // 1. Find the most recent occurrence of the LAST step that matches the filter.
    final lastStepName = events.last;
    final lastQuery = box
        .query(_buildCondition(lastStepName, filter))
        .order(Event_.timestamp, flags: Order.descending)
        .build();

    final lastStepEvents = lastQuery.find();
    lastQuery.close();

    if (lastStepEvents.isEmpty) return false;

    final lastEvent = lastStepEvents.first;
    final windowStart = lastEvent.timestamp.subtract(window);

    // The absolute lower-bound from the filter (timestampAfter) must be
    // respected by *every* step, not just the last one.
    final absoluteAfter = filter?.timestampAfter;
    final absoluteBefore = filter?.timestampBefore;

    // 2. Walk backwards through the funnel steps, verifying each exists in
    //    chronological order within the window.
    DateTime previousTimestamp = lastEvent.timestamp;

    for (int i = events.length - 2; i >= 0; i--) {
      final stepName = events[i];

      // The effective lower-bound is the latest of: windowStart and any
      // absolute timestampAfter constraint, so that all steps satisfy both.
      final effectiveLowerMs = absoluteAfter != null &&
              absoluteAfter.millisecondsSinceEpoch >
                  windowStart.millisecondsSinceEpoch
          ? absoluteAfter.millisecondsSinceEpoch
          : windowStart.millisecondsSinceEpoch;

      // The effective upper-bound is the earliest of: previousTimestamp and
      // any absolute timestampBefore constraint.
      final effectiveUpperMs = absoluteBefore != null &&
              absoluteBefore.millisecondsSinceEpoch <
                  previousTimestamp.millisecondsSinceEpoch
          ? absoluteBefore.millisecondsSinceEpoch
          : previousTimestamp.millisecondsSinceEpoch;

      final stepQuery = box
          .query(
            Event_.name
                .equals(stepName)
                .and(Event_.timestamp.greaterThan(effectiveLowerMs))
                .and(Event_.timestamp.lessThan(effectiveUpperMs)),
          )
          .order(Event_.timestamp, flags: Order.descending)
          .build();

      final candidates = stepQuery.find();
      stepQuery.close();

      if (candidates.isEmpty) return false;

      // Use the most recent candidate that is still before `previousTimestamp`.
      previousTimestamp = candidates.first.timestamp;
    }

    return true;
  }
}
