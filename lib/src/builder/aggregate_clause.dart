import '../models/event.dart';
import '../engine/trigger_evaluator.dart';
import '../../objectbox.g.dart';
import 'trigger_condition.dart';
import 'query_filter.dart';

/// A terminal condition for **attribute aggregate** triggers.
///
/// Example:
/// ```dart
/// trigger.when().event("purchase").attribute("price").sum().greaterThan(100.0).watch()
/// ```
class AggregateClause extends TriggerCondition {
  final Store _store;
  final String _eventName;
  final String _attrKey;
  final AggregateType _aggregateType;
  final ComparisonOperator _operator;
  final double _threshold;
  final QueryFilter? _filter;

  const AggregateClause._({
    required Store store,
    required String eventName,
    required String attrKey,
    required AggregateType aggregateType,
    required ComparisonOperator operator,
    required double threshold,
    QueryFilter? filter,
  }) : _store = store,
       _eventName = eventName,
       _attrKey = attrKey,
       _aggregateType = aggregateType,
       _operator = operator,
       _threshold = threshold,
       _filter = filter;

  @override
  Stream<bool> watch() {
    final box = _store.box<Event>();

    Condition<Event> cond = Event_.name.equals(_eventName);
    final filter = _filter;
    if (filter != null) {
      if (filter.sessionId != null) {
        if (filter.negateSession) {
          cond = cond.and(Event_.sessionId.notEquals(filter.sessionId!));
        } else {
          cond = cond.and(Event_.sessionId.equals(filter.sessionId!));
        }
      }
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

    return box.query(cond).watch(triggerImmediately: true).map((query) {
      final evaluator = TriggerEvaluator(_store);
      final result = evaluator.evaluateAttributeAggregate(
        _eventName,
        _attrKey,
        _aggregateType,
        filter: _filter,
      );
      query.close();
      return _compare(result);
    }).distinct();
  }

  bool _compare(double value) {
    switch (_operator) {
      case ComparisonOperator.greaterThan:
        return value > _threshold;
      case ComparisonOperator.greaterThanOrEqual:
        return value >= _threshold;
      case ComparisonOperator.lessThan:
        return value < _threshold;
      case ComparisonOperator.lessThanOrEqual:
        return value <= _threshold;
      case ComparisonOperator.equalTo:
        return value == _threshold;
    }
  }
}

/// Intermediate builder that holds aggregate context and exposes comparison
/// methods that produce an [AggregateClause].
class AggregateClauseBuilder {
  final Store _store;
  final String _eventName;
  final String _attrKey;
  final AggregateType _aggregateType;
  final QueryFilter? _filter;

  AggregateClauseBuilder({
    required Store store,
    required String eventName,
    required String attrKey,
    required AggregateType aggregateType,
    QueryFilter? filter,
  }) : _store = store,
       _eventName = eventName,
       _attrKey = attrKey,
       _aggregateType = aggregateType,
       _filter = filter;

  AggregateClause greaterThan(double value) => AggregateClause._(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: _aggregateType,
    operator: ComparisonOperator.greaterThan,
    threshold: value,
    filter: _filter,
  );

  AggregateClause greaterThanOrEqual(double value) => AggregateClause._(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: _aggregateType,
    operator: ComparisonOperator.greaterThanOrEqual,
    threshold: value,
    filter: _filter,
  );

  AggregateClause lessThan(double value) => AggregateClause._(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: _aggregateType,
    operator: ComparisonOperator.lessThan,
    threshold: value,
    filter: _filter,
  );

  AggregateClause lessThanOrEqual(double value) => AggregateClause._(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: _aggregateType,
    operator: ComparisonOperator.lessThanOrEqual,
    threshold: value,
    filter: _filter,
  );

  AggregateClause equalTo(double value) => AggregateClause._(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: _aggregateType,
    operator: ComparisonOperator.equalTo,
    threshold: value,
    filter: _filter,
  );
}
