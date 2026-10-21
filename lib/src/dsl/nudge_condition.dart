import '../engine/evaluation_context.dart';
import '../engine/nudge_engine.dart';

/// The comparison operator used by numeric clauses.
enum ComparisonOperator {
  greaterThan('>'),
  greaterThanOrEqual('>='),
  lessThan('<'),
  lessThanOrEqual('<='),
  equalTo('==');

  /// The operator as written in explanations, e.g. `>=`.
  final String symbol;

  const ComparisonOperator(this.symbol);

  /// Applies the operator to [value] and [threshold].
  bool compare(num value, num threshold) => switch (this) {
    greaterThan => value > threshold,
    greaterThanOrEqual => value >= threshold,
    lessThan => value < threshold,
    lessThanOrEqual => value <= threshold,
    equalTo => value == threshold,
  };
}

/// The outcome of evaluating a [NudgeCondition], with the reasoning behind
/// it.
///
/// Print it to understand why a condition is (or is not) met:
///
/// ```dart
/// print(condition.explain());
/// // ✗ AND
/// //   ✓ count(core_action) = 7 > 5
/// //   ✗ activeDays(any event) = 1 >= 3
/// ```
class ConditionResult {
  /// Whether the condition is met.
  final bool value;

  /// A human readable description of what was evaluated.
  final String description;

  /// The results of the sub-conditions, for composite conditions.
  final List<ConditionResult> children;

  const ConditionResult(
    this.value,
    this.description, [
    this.children = const [],
  ]);

  @override
  String toString() {
    final buffer = StringBuffer();
    _write(buffer, 0);
    return buffer.toString().trimRight();
  }

  void _write(StringBuffer buffer, int depth) {
    buffer
      ..write('  ' * depth)
      ..write(value ? '✓ ' : '✗ ')
      ..writeln(description);
    for (final child in children) {
      child._write(buffer, depth + 1);
    }
  }
}

/// A condition over the local event history.
///
/// Conditions are immutable descriptions: building one never touches the
/// database, two conditions built the same way are `==`, and they can be
/// declared once and reused. They are evaluated against the initialized
/// `Nudge` instance when you call [evaluate], [explain] or [watch].
///
/// Compose conditions with [and], [or] and [not].
abstract class NudgeCondition {
  const NudgeCondition();

  /// Evaluates the condition in [context].
  ///
  /// This is the extension point used by the engine; call [evaluate] or
  /// [explain] instead.
  ConditionResult resolve(EvaluationContext context);

  /// Evaluates the condition now, synchronously.
  bool evaluate() => explain().value;

  /// Evaluates the condition now and returns the reasoning behind the result.
  ConditionResult explain() => NudgeEngine.instance.explain(this);

  /// Emits the current value on listen, then every time it changes.
  ///
  /// The condition is re-evaluated after events are logged (changes made in
  /// the same frame are coalesced), after nudges fire or complete, when the
  /// app returns to the foreground and periodically while there are
  /// listeners, so conditions on relative time windows stay up to date.
  Stream<bool> watch() => NudgeEngine.instance.watch(this);

  /// The logical negation of this condition.
  NudgeCondition not() => NotCondition(this);

  /// Met when both this condition and [other] are met.
  NudgeCondition and(NudgeCondition other) =>
      AllCondition([this, other], 'AND');

  /// Met when this condition, [other] or both are met.
  NudgeCondition or(NudgeCondition other) => AnyCondition([this, other], 'OR');

  /// Met when every condition in [conditions] is met.
  static NudgeCondition all(List<NudgeCondition> conditions) =>
      AllCondition(conditions, 'ALL');

  /// Met when at least one condition in [conditions] is met.
  static NudgeCondition any(List<NudgeCondition> conditions) =>
      AnyCondition(conditions, 'ANY');
}

/// Negates a condition.
class NotCondition extends NudgeCondition {
  final NudgeCondition inner;

  const NotCondition(this.inner);

  @override
  ConditionResult resolve(EvaluationContext context) {
    final result = inner.resolve(context);
    return ConditionResult(!result.value, 'NOT', [result]);
  }

  @override
  bool operator ==(Object other) =>
      other is NotCondition && other.inner == inner;

  @override
  int get hashCode => Object.hash(NotCondition, inner);
}

/// Met when every child is met. Children are all evaluated in the same pass,
/// so a single change can never produce a transient, inconsistent value.
class AllCondition extends NudgeCondition {
  final List<NudgeCondition> conditions;
  final String label;

  const AllCondition(this.conditions, this.label);

  @override
  ConditionResult resolve(EvaluationContext context) {
    final results = conditions
        .map((condition) => condition.resolve(context))
        .toList(growable: false);
    return ConditionResult(
      results.every((result) => result.value),
      label,
      results,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AllCondition && _listEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(AllCondition, Object.hashAll(conditions));
}

/// Met when at least one child is met.
class AnyCondition extends NudgeCondition {
  final List<NudgeCondition> conditions;
  final String label;

  const AnyCondition(this.conditions, this.label);

  @override
  ConditionResult resolve(EvaluationContext context) {
    final results = conditions
        .map((condition) => condition.resolve(context))
        .toList(growable: false);
    return ConditionResult(
      results.any((result) => result.value),
      label,
      results,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnyCondition && _listEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(AnyCondition, Object.hashAll(conditions));
}

/// Wraps a condition with a label shown in explanations, e.g. the nudge
/// policy it implements.
class LabeledCondition extends NudgeCondition {
  final String label;
  final NudgeCondition inner;

  const LabeledCondition(this.label, this.inner);

  @override
  ConditionResult resolve(EvaluationContext context) {
    final result = inner.resolve(context);
    return ConditionResult(result.value, label, [result]);
  }

  @override
  bool operator ==(Object other) =>
      other is LabeledCondition && other.label == label && other.inner == inner;

  @override
  int get hashCode => Object.hash(LabeledCondition, label, inner);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
