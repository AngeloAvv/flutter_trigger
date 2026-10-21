import '../dsl/event_selector.dart';
import '../dsl/nudge_condition.dart';
import '../engine/evaluation_context.dart';
import '../engine/nudge_engine.dart';
import '../model/fire_record.dart';

/// Common outcome names for [NudgeFire.complete]. Any string works; these
/// keep naming consistent across an app.
abstract final class NudgeOutcome {
  /// The user took the suggested action (rated, subscribed, enabled…).
  static const accepted = 'accepted';

  /// The user explicitly said no.
  static const declined = 'declined';

  /// The prompt was closed without an answer.
  static const dismissed = 'dismissed';

  /// The result is not observable, e.g. the OS review dialog, which never
  /// reports whether it was shown.
  static const unknown = 'unknown';
}

/// A registered nudge: a condition plus the policies that decide when it
/// may fire again.
///
/// Create one with `Nudge.define`:
///
/// ```dart
/// final ratingPrompt = nudge
///     .define('rating_prompt')
///     .when(nudge.when().event('order_completed').count().greaterThanOrEqual(3))
///     .cooldown(const Duration(days: 30))
///     .maxFires(3, per: const Duration(days: 365))
///     .register();
/// ```
class NudgeDefinition {
  /// Unique identifier. Fire history is stored under it: change it (e.g.
  /// `rating_prompt_v2`) to start over with a fresh history.
  final String id;

  /// The behavioural condition.
  final NudgeCondition condition;

  /// The group used by group policies and by `checkpoint(group: …)`.
  final String? group;

  /// Higher priorities win when several nudges are eligible at a
  /// checkpoint.
  final int priority;

  /// The policies, compiled to conditions over the fire history.
  final List<LabeledCondition> policies;

  const NudgeDefinition({
    required this.id,
    required this.condition,
    this.group,
    this.priority = 0,
    this.policies = const [],
  });

  /// The full eligibility condition: [condition] and every policy.
  NudgeCondition get eligibility => AllCondition([
    LabeledCondition('condition', condition),
    ...policies,
  ], 'nudge $id');

  /// Whether the nudge may fire right now.
  bool get isEligible => NudgeEngine.instance.isEligible(id);

  /// Explains why the nudge is or is not eligible right now.
  ConditionResult explain() => NudgeEngine.instance.explainNudge(id);

  /// Emits whether the nudge is eligible, every time it changes.
  Stream<bool> watchEligible() => eligibility.watch();

  /// Fires the nudge if eligible, see `Nudge.fire`.
  NudgeFire? fire({bool force = false}) =>
      NudgeEngine.instance.fire(id, force: force);

  /// Deletes the fire history of this nudge.
  void reset() => NudgeEngine.instance.resetNudge(id);
}

/// Builds a [NudgeDefinition].
class NudgeDefinitionBuilder {
  final String _id;
  NudgeCondition? _condition;
  String? _group;
  int _priority = 0;
  final _policies =
      <LabeledCondition Function(FireSelector self, String? group)>[];

  NudgeDefinitionBuilder(this._id);

  static const _when = EventSelector();

  /// The behavioural condition the nudge waits for.
  NudgeDefinitionBuilder when(NudgeCondition condition) {
    _condition = condition;
    return this;
  }

  /// Puts the nudge in [group], e.g. `interruptive` for modal prompts.
  NudgeDefinitionBuilder group(String group) {
    _group = group;
    return this;
  }

  /// Sets the priority used at checkpoints. Higher wins; ties go to the
  /// nudge registered first.
  NudgeDefinitionBuilder priority(int priority) {
    _priority = priority;
    return this;
  }

  /// Not eligible for [duration] after each fire.
  NudgeDefinitionBuilder cooldown(Duration duration) => _policy(
    (self, _) => LabeledCondition(
      'cooldown ${formatDuration(duration)}',
      self.inLast(duration).exists().not(),
    ),
  );

  /// Fires at most [count] times, ever or, with [per], within any rolling
  /// period of that length.
  NudgeDefinitionBuilder maxFires(int count, {Duration? per}) => _policy(
    (self, _) => LabeledCondition(
      'max $count fires${per == null ? '' : ' per ${formatDuration(per)}'}',
      (per == null ? self : self.inLast(per)).count().lessThan(count),
    ),
  );

  /// Fires at most once per session.
  NudgeDefinitionBuilder oncePerSession() => _policy(
    (self, _) => LabeledCondition(
      'once per session',
      self.inCurrentSession().exists().not(),
    ),
  );

  /// Not eligible for [duration] after any nudge of the same group fired.
  /// Requires [group].
  NudgeDefinitionBuilder groupCooldown(Duration duration) => _policy(
    (_, group) => LabeledCondition(
      'group cooldown ${formatDuration(duration)}',
      _when.group(_requireGroup(group)).inLast(duration).exists().not(),
    ),
  );

  /// Not eligible if any nudge of the same group already fired in this
  /// session. Requires [group].
  NudgeDefinitionBuilder groupOncePerSession() => _policy(
    (_, group) => LabeledCondition(
      'group once per session',
      _when.group(_requireGroup(group)).inCurrentSession().exists().not(),
    ),
  );

  /// Reacts to the outcome reported with `NudgeFire.complete`: not
  /// eligible for [cooldown] after a fire completed with [outcome], or never
  /// again when [disable] is true.
  ///
  /// ```dart
  /// .onOutcome(NudgeOutcome.accepted, disable: true)
  /// .onOutcome(NudgeOutcome.dismissed, cooldown: Duration(days: 90))
  /// ```
  NudgeDefinitionBuilder onOutcome(
    String outcome, {
    Duration? cooldown,
    bool disable = false,
  }) {
    assert(
      disable || cooldown != null,
      'onOutcome needs a cooldown or disable: true',
    );
    return _policy((self, _) {
      final selection = self.outcome(outcome);
      return disable
          ? LabeledCondition(
              'disabled after $outcome',
              selection.exists().not(),
            )
          : LabeledCondition(
              'cooldown ${formatDuration(cooldown!)} after $outcome',
              selection.inLast(cooldown).exists().not(),
            );
    });
  }

  /// Adds a custom policy, e.g. a condition on another nudge's history.
  NudgeDefinitionBuilder require(String label, NudgeCondition condition) =>
      _policy((_, _) => LabeledCondition(label, condition));

  /// Builds the definition without registering it.
  NudgeDefinition build() {
    final condition = _condition;
    if (condition == null) {
      throw StateError('Nudge $_id has no condition: call when() first.');
    }

    final self = _when.fired(_id);
    return NudgeDefinition(
      id: _id,
      condition: condition,
      group: _group,
      priority: _priority,
      policies: List.unmodifiable(
        _policies.map((policy) => policy(self, _group)),
      ),
    );
  }

  /// Builds the definition and registers it, replacing any nudge with the
  /// same id.
  NudgeDefinition register() {
    final definition = build();
    NudgeEngine.instance.register(definition);
    return definition;
  }

  NudgeDefinitionBuilder _policy(
    LabeledCondition Function(FireSelector self, String? group) policy,
  ) {
    _policies.add(policy);
    return this;
  }

  String _requireGroup(String? group) {
    if (group == null) {
      throw StateError('Nudge $_id uses a group policy without a group.');
    }
    return group;
  }
}

/// A nudge that fired. Report what happened with [complete].
class NudgeFire {
  final NudgeEngine _engine;
  final FireRecord _record;

  NudgeFire(this._engine, this._record);

  /// The id of the nudge that fired.
  String get nudgeId => _record.nudgeId;

  /// The group of the nudge that fired.
  String? get group => _record.group;

  /// When the nudge fired.
  DateTime get firedAt => _record.firedAt;

  /// The outcome, once reported.
  String? get outcome => _record.outcome;

  /// Records the [outcome] of this fire, e.g. [NudgeOutcome.accepted].
  /// Outcomes drive `onOutcome` policies and chained nudges.
  void complete(String outcome) => _engine.complete(_record, outcome);

  @override
  String toString() =>
      'NudgeFire($nudgeId @ ${firedAt.toIso8601String()}, '
      'outcome: $outcome)';
}
