import '../models/event.dart';
import '../engine/trigger_evaluator.dart';
import '../../objectbox.g.dart';
import 'trigger_condition.dart';
import 'query_filter.dart';

/// A terminal condition for **count-based** triggers.
///
/// Example:
/// ```dart
/// trigger.when().event("purchase").count().greaterThan(5).watch()
/// ```
class CountClause extends TriggerCondition {
  final Store _store;
  final String _eventName;
  final ComparisonOperator _operator;
  final int _threshold;
  final QueryFilter? _filter;

  const CountClause._({
    required Store store,
    required String eventName,
    required ComparisonOperator operator,
    required int threshold,
    QueryFilter? filter,
  }) : _store = store,
       _eventName = eventName,
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
        // QueryDateProperty lacks greaterThanOrEqual; use > (val - 1)
        cond = cond.and(
          Event_.timestamp.greaterThan(
            filter.timestampAfter!.millisecondsSinceEpoch - 1,
          ),
        );
      }
      if (filter.timestampBefore != null) {
        // QueryDateProperty lacks lessThanOrEqual; use < (val + 1)
        cond = cond.and(
          Event_.timestamp.lessThan(
            filter.timestampBefore!.millisecondsSinceEpoch + 1,
          ),
        );
      }
    }

    return box.query(cond).watch(triggerImmediately: true).map((query) {
      final evaluator = TriggerEvaluator(_store);
      final count = evaluator.evaluateCount(_eventName, filter: _filter);
      query.close();
      return _compare(count);
    }).distinct();
  }

  bool _compare(int count) {
    switch (_operator) {
      case ComparisonOperator.greaterThan:
        return count > _threshold;
      case ComparisonOperator.greaterThanOrEqual:
        return count >= _threshold;
      case ComparisonOperator.lessThan:
        return count < _threshold;
      case ComparisonOperator.lessThanOrEqual:
        return count <= _threshold;
      case ComparisonOperator.equalTo:
        return count == _threshold;
    }
  }
}

/// Intermediate builder that holds the event name and exposes comparison
/// methods that produce a [CountClause].
class CountClauseBuilder {
  final Store _store;
  final String _eventName;
  final QueryFilter? _filter;

  CountClauseBuilder({
    required Store store,
    required String eventName,
    QueryFilter? filter,
  }) : _store = store,
       _eventName = eventName,
       _filter = filter;

  CountClause greaterThan(int value) => CountClause._(
    store: _store,
    eventName: _eventName,
    operator: ComparisonOperator.greaterThan,
    threshold: value,
    filter: _filter,
  );

  CountClause greaterThanOrEqual(int value) => CountClause._(
    store: _store,
    eventName: _eventName,
    operator: ComparisonOperator.greaterThanOrEqual,
    threshold: value,
    filter: _filter,
  );

  CountClause lessThan(int value) => CountClause._(
    store: _store,
    eventName: _eventName,
    operator: ComparisonOperator.lessThan,
    threshold: value,
    filter: _filter,
  );

  CountClause lessThanOrEqual(int value) => CountClause._(
    store: _store,
    eventName: _eventName,
    operator: ComparisonOperator.lessThanOrEqual,
    threshold: value,
    filter: _filter,
  );

  CountClause equalTo(int value) => CountClause._(
    store: _store,
    eventName: _eventName,
    operator: ComparisonOperator.equalTo,
    threshold: value,
    filter: _filter,
  );
}
