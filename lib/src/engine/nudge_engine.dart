import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../dsl/nudge_condition.dart';
import '../model/event_record.dart';
import '../model/fire_record.dart';
import '../storage/nudge_storage.dart';
import '../nudges/nudge_definition.dart';
import 'evaluation_context.dart';
import 'session_manager.dart';

/// Evaluates conditions, tracks sessions and fires nudges.
///
/// Every write goes through the engine, which then notifies watchers once
/// per microtask: a burst of events logged in the same frame causes a single
/// re-evaluation, and composite conditions are evaluated in one pass, so
/// watchers never observe intermediate states.
class NudgeEngine {
  static NudgeEngine? _instance;

  /// The engine of the initialized `Nudge`.
  static NudgeEngine get instance =>
      _instance ??
      (throw StateError(
        'Nudge is not initialized. '
        'Call Nudge.initialize() first.',
      ));

  final NudgeStorage storage;
  final Clock clock;
  final Duration ttl;
  final int maxCapacity;
  final Duration reevaluationInterval;
  late final SessionManager sessions;

  final _definitions = <String, NudgeDefinition>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  final _fires = StreamController<NudgeFire>.broadcast();
  final _outcomes = StreamController<NudgeFire>.broadcast();

  bool _notifyScheduled = false;
  bool _foreground = true;
  bool _disposed = false;
  int _watchers = 0;
  int _eventsSinceMaintenance = 0;
  Timer? _ticker;
  Timer? _maintenanceTimer;

  /// When false, events are not logged and nudges do not fire.
  bool enabled = true;

  /// How many logged events between two capacity checks.
  static const _maintenanceEvery = 500;

  NudgeEngine({
    required this.storage,
    required this.clock,
    required this.ttl,
    required this.maxCapacity,
    required Duration sessionTimeout,
    required this.reevaluationInterval,
  }) {
    sessions = SessionManager(
      timeout: sessionTimeout,
      clock: clock,
      onSessionStart: _onSessionStart,
      onResume: _onResume,
      onPause: _onPause,
    );
  }

  /// Makes this engine the current one and starts the first session.
  void start({Duration maintenanceDelay = const Duration(seconds: 2)}) {
    _instance = this;
    sessions.start();
    _maintenanceTimer = Timer(maintenanceDelay, runMaintenance);
  }

  EvaluationContext get _context => EvaluationContext(
    storage: storage,
    now: clock.now(),
    sessionId: sessions.sessionId,
  );

  /// Evaluates [condition] now.
  ConditionResult explain(NudgeCondition condition) =>
      condition.resolve(_context);

  /// See [NudgeCondition.watch].
  Stream<bool> watch(NudgeCondition condition) {
    late final StreamController<bool> controller;
    StreamSubscription<void>? subscription;
    bool? last;

    void evaluate() {
      try {
        final value = explain(condition).value;
        if (value != last) {
          last = value;
          controller.add(value);
        }
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<bool>(
      onListen: () {
        _watchers++;
        _updateTicker();
        evaluate();
        subscription = _changes.stream.listen(
          (_) => evaluate(),
          onDone: controller.close,
        );
      },
      onCancel: () {
        _watchers--;
        _updateTicker();
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// Schedules a re-evaluation of every watched condition.
  void notifyChanged() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) _changes.add(null);
    });
  }

  void _updateTicker() {
    final shouldTick =
        !_disposed &&
        _watchers > 0 &&
        _foreground &&
        reevaluationInterval > Duration.zero;
    if (shouldTick && _ticker == null) {
      _ticker = Timer.periodic(reevaluationInterval, (_) => notifyChanged());
    } else if (!shouldTick) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _onSessionStart(String sessionId) {
    _insert(SessionManager.sessionStartEvent, const {});
  }

  void _onResume() {
    _foreground = true;
    _updateTicker();
    notifyChanged();
  }

  void _onPause() {
    _foreground = false;
    _updateTicker();
  }

  /// Logs an event. Never throws: invalid names are ignored and unsupported
  /// metadata values are converted, both with a debug message.
  void logEvent(String name, [Map<String, Object?>? metadata]) {
    if (!enabled || _disposed) return;

    if (name.isEmpty || name.startsWith(r'$')) {
      debugPrint(
        '[Nudge] Ignored event "$name": names must be non-empty '
        r'and must not start with "$", which is reserved.',
      );
      return;
    }

    _insert(name, sanitize(metadata));

    if (++_eventsSinceMaintenance >= _maintenanceEvery) runMaintenance();
  }

  void _insert(String name, Map<String, Object> attributes) {
    storage.insertEvent(
      EventRecord(
        name: name,
        timestamp: clock.now(),
        sessionId: sessions.sessionId,
        attributes: attributes,
      ),
    );
    notifyChanged();
  }

  /// Converts metadata to the supported attribute types: `null` values are
  /// dropped, [DateTime]s become milliseconds since the epoch, enums their
  /// name and anything else its `toString()`.
  @visibleForTesting
  static Map<String, Object> sanitize(Map<String, Object?>? metadata) {
    if (metadata == null || metadata.isEmpty) return const {};

    return {
      for (final MapEntry(:key, :value) in metadata.entries)
        if (value != null)
          key: switch (value) {
            String() || bool() || int() || double() => value,
            DateTime() => value.millisecondsSinceEpoch,
            Enum() => value.name,
            _ => _unsupported(key, value),
          },
    };
  }

  static String _unsupported(String key, Object value) {
    debugPrint(
      '[Nudge] Attribute "$key" of type ${value.runtimeType} '
      'stored as String.',
    );
    return value.toString();
  }

  /// The registered nudges, by id.
  Map<String, NudgeDefinition> get definitions =>
      Map.unmodifiable(_definitions);

  void register(NudgeDefinition definition) {
    _definitions[definition.id] = definition;
    notifyChanged();
  }

  void unregister(String id) => _definitions.remove(id);

  NudgeDefinition _definition(String id) =>
      _definitions[id] ??
      (throw ArgumentError.value(id, 'id', 'No nudge registered'));

  bool isEligible(String id) =>
      enabled && !_disposed && explain(_definition(id).eligibility).value;

  ConditionResult explainNudge(String id) =>
      explain(_definition(id).eligibility);

  /// Fires [id] if it is eligible, or regardless with [force].
  NudgeFire? fire(String id, {bool force = false}) {
    final definition = _definition(id);
    if (!enabled || _disposed) return null;
    if (!force && !explain(definition.eligibility).value) return null;
    return _record(definition);
  }

  /// Fires the eligible nudge with the highest priority among the
  /// registered ones, optionally restricted to a [group] or to [ids].
  NudgeFire? checkpoint({String? group, Iterable<String>? ids}) {
    if (!enabled || _disposed) return null;

    final allowed = ids?.toSet();
    final context = _context;
    NudgeDefinition? best;
    for (final definition in _definitions.values) {
      if (group != null && definition.group != group) continue;
      if (allowed != null && !allowed.contains(definition.id)) continue;
      if (best != null && definition.priority <= best.priority) continue;
      if (definition.eligibility.resolve(context).value) best = definition;
    }

    return best == null ? null : _record(best);
  }

  NudgeFire _record(NudgeDefinition definition) {
    final record = storage.insertFire(
      FireRecord(
        nudgeId: definition.id,
        group: definition.group,
        firedAt: clock.now(),
        sessionId: sessions.sessionId,
      ),
    );
    notifyChanged();

    final fire = NudgeFire(this, record);
    _fires.add(fire);
    return fire;
  }

  void complete(FireRecord record, String outcome) {
    if (_disposed) return;

    final completed = record.copyWith(outcome: outcome, outcomeAt: clock.now());
    storage.updateFire(completed);
    notifyChanged();
    _outcomes.add(NudgeFire(this, completed));
  }

  /// Every fire, e.g. to forward it to a remote analytics tool.
  Stream<NudgeFire> get fires => _fires.stream;

  /// Every completed fire, with its outcome.
  Stream<NudgeFire> get outcomes => _outcomes.stream;

  void resetNudge(String id) {
    storage.removeFires(id);
    notifyChanged();
  }

  /// Applies the retention policy: events older than [ttl] and the oldest
  /// events beyond [maxCapacity] are deleted. Lifetime stats and fire history
  /// are kept.
  void runMaintenance() {
    if (_disposed) return;
    _eventsSinceMaintenance = 0;

    try {
      final expired = storage.purgeEventsBefore(clock.now().subtract(ttl));
      final exceeding = storage.purgeEventsExceeding(maxCapacity);
      if (expired + exceeding > 0) {
        debugPrint(
          '[Nudge] Maintenance: purged $expired expired and '
          '$exceeding exceeding events.',
        );
        notifyChanged();
      }
    } catch (error) {
      debugPrint('[Nudge] Maintenance error: $error');
    }
  }

  /// Deletes every event, stat and fire record, then starts a new session.
  void clear() {
    storage.clear();
    sessions.restart();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _ticker?.cancel();
    _maintenanceTimer?.cancel();
    sessions.stop();
    _changes.close();
    _fires.close();
    _outcomes.close();
    storage.close();

    if (identical(_instance, this)) _instance = null;
  }
}
