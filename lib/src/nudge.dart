import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import 'dsl/event_selector.dart';
import 'dsl/nudge_condition.dart';
import 'engine/nudge_engine.dart';
import 'storage/objectbox/objectbox_nudge_storage.dart';
import 'storage/nudge_storage.dart';
import 'nudges/nudge_definition.dart';

/// The entry point of the package.
///
/// ```dart
/// final nudge = await Nudge.initialize();
///
/// // Log behaviour
/// nudge.logEvent('order_completed', {'total': 42.5});
///
/// // Define a nudge with its policies
/// nudge
///     .define('rating_prompt')
///     .when(nudge.when().event('order_completed').count().greaterThanOrEqual(3))
///     .cooldown(const Duration(days: 30))
///     .register();
///
/// // Ask at a natural pause
/// final fire = nudge.checkpoint();
/// ```
class Nudge {
  static Nudge? _instance;
  static Future<Nudge>? _initializing;

  final NudgeEngine _engine;

  Nudge._(this._engine);

  /// The initialized instance.
  ///
  /// Throws a [StateError] if [initialize] has not completed.
  static Nudge get instance =>
      _instance ??
      (throw StateError(
        'Nudge is not initialized. '
        'Call Nudge.initialize() first.',
      ));

  /// Whether [initialize] has completed.
  static bool get isInitialized => _instance != null;

  /// Initializes the package. Concurrent and repeated calls return the same
  /// instance.
  ///
  /// - [ttl]: events older than this are deleted (default: 365 days).
  /// - [maxCapacity]: at most this many events are kept, the oldest are
  ///   deleted first (default: 10,000).
  /// - [sessionTimeout]: time in background after which returning to the app
  ///   starts a new session (default: 30 minutes).
  /// - [reevaluationInterval]: how often watched conditions are re-evaluated
  ///   while the app is in the foreground, so that time-based conditions
  ///   update without new events (default: 1 minute; [Duration.zero]
  ///   disables it).
  /// - [storage]: where data is kept. Defaults to an ObjectBox store; pass an
  ///   `InMemoryNudgeStorage` in tests.
  /// - [clock]: the source of the current time, replaceable in tests.
  ///
  /// Lifetime stats and the fire history are never deleted by [ttl] or
  /// [maxCapacity].
  static Future<Nudge> initialize({
    Duration ttl = const Duration(days: 365),
    int maxCapacity = 10000,
    Duration sessionTimeout = const Duration(minutes: 30),
    Duration reevaluationInterval = const Duration(minutes: 1),
    NudgeStorage? storage,
    Clock clock = const Clock(),
  }) {
    final instance = _instance;
    if (instance != null) return Future.value(instance);
    if (_initializing case final pending?) return pending;

    final initializing = () async {
      WidgetsFlutterBinding.ensureInitialized();

      final engine = NudgeEngine(
        storage: storage ?? await ObjectBoxNudgeStorage.open(),
        clock: clock,
        ttl: ttl,
        maxCapacity: maxCapacity,
        sessionTimeout: sessionTimeout,
        reevaluationInterval: reevaluationInterval,
      )..start();

      return _instance = Nudge._(engine);
    }();

    // Concurrent callers share this future; a failure allows a retry.
    _initializing = initializing;
    void done() {
      if (identical(_initializing, initializing)) _initializing = null;
    }

    initializing.then((_) => done(), onError: (_) => done());
    return initializing;
  }

  /// The identifier of the current session.
  String get sessionId => _engine.sessions.sessionId;

  /// When false, events are not logged and nudges do not fire. Use it to
  /// honour an analytics opt-out; the choice is not persisted.
  bool get enabled => _engine.enabled;
  set enabled(bool value) => _engine.enabled = value;

  /// Logs the event [name] with optional [metadata].
  ///
  /// Metadata values can be `String`, `int`, `double` or `bool`; `null`
  /// values are dropped, `DateTime`s are stored as milliseconds since the
  /// epoch, enums by name and anything else as its `toString()`. Names must
  /// be non-empty and must not start with `$`. Never throws.
  void logEvent(String name, [Map<String, Object?>? metadata]) =>
      _engine.logEvent(name, metadata);

  /// Starts a condition.
  ///
  /// ```dart
  /// nudge.when().event('share').count().greaterThan(5)
  /// ```
  EventSelector when() => const EventSelector();

  /// Explains why [condition] is or is not met right now.
  ConditionResult explain(NudgeCondition condition) =>
      _engine.explain(condition);

  /// Starts the definition of the nudge [id].
  NudgeDefinitionBuilder define(String id) => NudgeDefinitionBuilder(id);

  /// The registered nudges, by id.
  Map<String, NudgeDefinition> get nudges => _engine.definitions;

  /// Removes the nudge [id]. Its fire history is kept.
  void unregister(String id) => _engine.unregister(id);

  /// Whether the nudge [id] may fire right now.
  bool isEligible(String id) => _engine.isEligible(id);

  /// Explains why the nudge [id] is or is not eligible right now.
  ConditionResult explainNudge(String id) => _engine.explainNudge(id);

  /// Fires the nudge [id] if it is eligible and returns the fire, or
  /// `null`. With [force] it fires regardless, which is handy for QA.
  ///
  /// Firing is recorded immediately, so cooldowns and caps apply even if the
  /// app never reports an outcome.
  NudgeFire? fire(String id, {bool force = false}) =>
      _engine.fire(id, force: force);

  /// Fires the eligible nudge with the highest priority, optionally only
  /// among a [group] or a set of [ids], and returns it, or `null` if none is
  /// eligible.
  ///
  /// Call it at natural pauses (back on the home screen, after a task is
  /// completed) to show at most one prompt there.
  NudgeFire? checkpoint({String? group, Iterable<String>? ids}) =>
      _engine.checkpoint(group: group, ids: ids);

  /// Every fire, e.g. to forward it to a remote analytics tool.
  Stream<NudgeFire> get fires => _engine.fires;

  /// Every completed fire, with its outcome.
  Stream<NudgeFire> get outcomes => _engine.outcomes;

  /// Deletes the fire history of the nudge [id], making it fire as if it
  /// never did.
  void resetNudge(String id) => _engine.resetNudge(id);

  /// Applies the retention policy now. It also runs shortly after
  /// initialization and periodically while events are logged.
  void runMaintenance() => _engine.runMaintenance();

  /// Deletes every event, stat and fire record, e.g. on logout or when the
  /// user asks to erase their data. A new session starts.
  void clear() => _engine.clear();

  /// Releases every resource. Watched streams complete. [initialize] must be
  /// called again before further use.
  void dispose() {
    _engine.dispose();
    if (identical(_instance, this)) _instance = null;
  }
}
