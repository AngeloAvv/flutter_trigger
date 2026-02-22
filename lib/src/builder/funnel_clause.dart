import '../models/event.dart';
import '../engine/trigger_evaluator.dart';
import '../../objectbox.g.dart';
import 'trigger_condition.dart';
import 'query_filter.dart';
import 'funnel_session_selector.dart';
import 'funnel_timestamp_selector.dart';

/// Intermediate builder **and** terminal condition for loose funnel triggers.
///
/// Returned by [EventSelector.funnel]. Mirrors the pattern of other selectors
/// ([TimestampSelector], [SessionSelector]): every modifier method returns a
/// new immutable [FunnelBuilder] so chains can be as long or short as needed.
/// Because [FunnelBuilder] extends [TriggerCondition], you can call `.watch()`
/// at any point — no terminal step is required.
///
/// ### Examples
///
/// ```dart
/// // Minimal — steps in order, no time constraint
/// trigger.when()
///   .funnel(['sign_up', 'first_purchase'])
///   .loose()
///   .watch();
///
/// // With a rolling time window
/// trigger.when()
///   .funnel(['view_item', 'add_to_cart', 'checkout'])
///   .loose()
///   .timestamp().within(Duration(hours: 24))
///   .watch();
///
/// // Last step must have occurred after a date
/// trigger.when()
///   .funnel(['onboard', 'invite_friend'])
///   .loose()
///   .timestamp().greaterThan(DateTime(2025))
///   .watch();
///
/// // Funnel scoped to the current session
/// trigger.when()
///   .funnel(['view_item', 'checkout'])
///   .loose()
///   .session().same()
///   .watch();
///
/// // Session filter + time window
/// trigger.when()
///   .funnel(['search', 'purchase'])
///   .loose()
///   .session().same()
///   .timestamp().within(Duration(minutes: 30))
///   .watch();
/// ```
class FunnelBuilder extends TriggerCondition {
  final Store _store;
  final List<String> _events;
  final String _currentSessionId;
  final QueryFilter _filter;

  /// The rolling time window within which all funnel steps must occur.
  /// `null` means no time constraint (steps can span any amount of time).
  final Duration? _window;

  const FunnelBuilder({
    required Store store,
    required List<String> events,
    required String currentSessionId,
    QueryFilter? filter,
    Duration? window,
  })  : _store = store,
        _events = events,
        _currentSessionId = currentSessionId,
        _filter = filter ?? const QueryFilter(),
        _window = window;

  // ---------------------------------------------------------------------------
  // Public accessors (used by FunnelSessionSelector / FunnelTimestampSelector)
  // ---------------------------------------------------------------------------

  QueryFilter get filter => _filter;
  String get currentSessionId => _currentSessionId;

  // ---------------------------------------------------------------------------
  // Chaining helpers
  // ---------------------------------------------------------------------------

  /// Marks this funnel as **loose** — steps must appear in chronological order
  /// but don't need to be immediately consecutive.
  ///
  /// Currently the only supported mode; kept for expressiveness and future
  /// extensibility (e.g. a `.strict()` variant).
  FunnelBuilder loose() => this;

  /// Opens a **session**-based sub-chain.
  ///
  /// - `.session().same()` — steps must belong to the current session.
  /// - `.session().other()` — steps must belong to a different session.
  FunnelSessionSelector session() => FunnelSessionSelector(
        builder: this,
        currentSessionId: _currentSessionId,
      );

  /// Opens a **timestamp**-based sub-chain.
  ///
  /// Use comparison methods (`greaterThan`, `lessThan`, …) to constrain
  /// the absolute time of the last funnel step, or call `.within(duration)`
  /// to set a rolling time window for the whole funnel.
  FunnelTimestampSelector timestamp() => FunnelTimestampSelector(
        builder: this,
      );

  // ---------------------------------------------------------------------------
  // Internal copy helper (used by selectors to return updated builders)
  // ---------------------------------------------------------------------------

  FunnelBuilder copyWith({QueryFilter? filter, Duration? window}) =>
      FunnelBuilder(
        store: _store,
        events: _events,
        currentSessionId: _currentSessionId,
        filter: filter ?? _filter,
        window: window ?? _window,
      );

  // ---------------------------------------------------------------------------
  // Terminal — TriggerCondition
  // ---------------------------------------------------------------------------

  @override
  Stream<bool> watch() {
    final box = _store.box<Event>();

    // Build the watch condition on the last funnel step, respecting any filter.
    Condition<Event> cond = Event_.name.equals(_events.last);
    final f = _filter;
    if (f.sessionId != null) {
      cond = f.negateSession
          ? cond.and(Event_.sessionId.notEquals(f.sessionId!))
          : cond.and(Event_.sessionId.equals(f.sessionId!));
    }
    if (f.timestampAfter != null) {
      cond = cond.and(
        Event_.timestamp
            .greaterThan(f.timestampAfter!.millisecondsSinceEpoch - 1),
      );
    }
    if (f.timestampBefore != null) {
      cond = cond.and(
        Event_.timestamp
            .lessThan(f.timestampBefore!.millisecondsSinceEpoch + 1),
      );
    }

    // Use a very large window when none is specified (~100 years ≈ "no limit").
    final effectiveWindow = _window ?? const Duration(days: 36500);

    return box
        .query(cond)
        .watch(triggerImmediately: true)
        .map((query) {
          final result = TriggerEvaluator(_store)
              .evaluateFunnel(_events, effectiveWindow, filter: _filter);
          query.close();
          return result;
        })
        .distinct();
  }
}
