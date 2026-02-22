import 'dart:async';

import 'package:rxdart/rxdart.dart';

/// The comparison operator used for trigger evaluation.
enum ComparisonOperator {
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  equalTo,
}

/// Abstract base class for all trigger conditions.
///
/// A [TriggerCondition] can be evaluated to a [bool] and can be composed
/// using logical operators [not], [and], and [or].
abstract class TriggerCondition {

  const TriggerCondition();

  /// Returns a reactive [Stream<bool>] that emits `true` / `false` whenever
  /// the condition state changes.
  ///
  /// The stream uses `.distinct()` to avoid duplicate emissions.
  Stream<bool> watch();

  /// Returns a new condition that is the logical NOT of this condition.
  TriggerCondition not() => _NotCondition(this);

  /// Returns a new condition that is the logical AND of this and [other].
  TriggerCondition and(TriggerCondition other) => _AndCondition(this, other);

  /// Returns a new condition that is the logical OR of this and [other].
  TriggerCondition or(TriggerCondition other) => _OrCondition(this, other);
}

// ---------------------------------------------------------------------------
// Logical Combinators
// ---------------------------------------------------------------------------

class _NotCondition extends TriggerCondition {
  final TriggerCondition _inner;

  _NotCondition(this._inner);

  @override
  Stream<bool> watch() => _inner.watch().map((value) => !value).distinct();
}

class _AndCondition extends TriggerCondition {
  final TriggerCondition _left;
  final TriggerCondition _right;

  _AndCondition(this._left, this._right);

  @override
  Stream<bool> watch() => Rx.combineLatest2<bool, bool, bool>(
    _left.watch(),
    _right.watch(),
    (a, b) => a && b,
  ).distinct();
}

class _OrCondition extends TriggerCondition {
  final TriggerCondition _left;
  final TriggerCondition _right;

  _OrCondition(this._left, this._right);

  @override
  Stream<bool> watch() => Rx.combineLatest2<bool, bool, bool>(
    _left.watch(),
    _right.watch(),
    (a, b) => a || b,
  ).distinct();
}
