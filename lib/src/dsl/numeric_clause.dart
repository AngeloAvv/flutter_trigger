import '../engine/evaluation_context.dart';
import 'metrics.dart';
import 'nudge_condition.dart';

/// A condition comparing a number computed from the history with a
/// threshold, e.g. `count(purchase) > 5`.
class NumericClause<T extends num> extends NudgeCondition {
  final Metric metric;
  final ComparisonOperator operator;
  final T threshold;

  const NumericClause(this.metric, this.operator, this.threshold);

  @override
  ConditionResult resolve(EvaluationContext context) {
    final value = metric.compute(context);
    return ConditionResult(
      value != null && operator.compare(value, threshold),
      '${metric.label} = ${value ?? 'none'} ${operator.symbol} $threshold',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NumericClause &&
      other.metric == metric &&
      other.operator == operator &&
      other.threshold == threshold;

  @override
  int get hashCode => Object.hash(NumericClause, metric, operator, threshold);
}

/// Exposes the comparisons that turn a metric into a [NumericClause].
class NumericClauseBuilder<T extends num> {
  final Metric _metric;

  const NumericClauseBuilder(this._metric);

  NumericClause<T> greaterThan(T value) =>
      NumericClause(_metric, ComparisonOperator.greaterThan, value);

  NumericClause<T> greaterThanOrEqual(T value) =>
      NumericClause(_metric, ComparisonOperator.greaterThanOrEqual, value);

  NumericClause<T> lessThan(T value) =>
      NumericClause(_metric, ComparisonOperator.lessThan, value);

  NumericClause<T> lessThanOrEqual(T value) =>
      NumericClause(_metric, ComparisonOperator.lessThanOrEqual, value);

  NumericClause<T> equalTo(T value) =>
      NumericClause(_metric, ComparisonOperator.equalTo, value);
}

/// A count-based condition, e.g. `.event('share').count().greaterThan(5)`.
typedef CountClause = NumericClause<int>;

/// Builds a [CountClause].
typedef CountClauseBuilder = NumericClauseBuilder<int>;

/// An attribute aggregate condition, e.g.
/// `.event('purchase').attribute('price').sum().greaterThan(100)`.
typedef AggregateClause = NumericClause<double>;

/// Builds an [AggregateClause].
typedef AggregateClauseBuilder = NumericClauseBuilder<double>;

/// A distinct-session condition, e.g.
/// `.event('login').session().count().greaterThan(5)`.
typedef SessionCountClause = NumericClause<int>;

/// Builds a [SessionCountClause].
typedef SessionCountClauseBuilder = NumericClauseBuilder<int>;
