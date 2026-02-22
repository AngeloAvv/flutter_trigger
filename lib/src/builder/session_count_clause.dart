import '../models/event.dart';
import '../engine/trigger_evaluator.dart';
import '../../objectbox.g.dart';
import 'trigger_condition.dart';
import 'query_filter.dart';

/// A terminal condition that compares the number of **distinct sessions** in
/// which a given event occurred against a threshold.
///
/// Example:
/// ```dart
/// trigger.when().event("login").session().count().greaterThan(5)
/// ```
class SessionCountClause extends TriggerCondition {
  final Store _store;
  final String _eventName;
  final ComparisonOperator _operator;
  final int _threshold;
  final QueryFilter? _filter;

  const SessionCountClause._({
    required Store store,
    required String eventName,
    required ComparisonOperator operator,
    required int threshold,
    QueryFilter? filter,
  })  : _store = store,
        _eventName = eventName,
        _operator = operator,
        _threshold = threshold,
        _filter = filter;

  @override
  Stream<bool> watch() {
    final box = _store.box<Event>();

    // React to any change on the event by name (session / timestamp filters
    // are applied inside the evaluator).
    Condition<Event> watchCond = Event_.name.equals(_eventName);

    return box
        .query(watchCond)
        .watch(triggerImmediately: true)
        .map((query) {
          final evaluator = TriggerEvaluator(_store);
          final sessionCount =
              evaluator.evaluateSessionCount(_eventName, filter: _filter);
          query.close();
          return _compare(sessionCount);
        })
        .distinct();
  }

  bool _compare(int sessionCount) {
    switch (_operator) {
      case ComparisonOperator.greaterThan:
        return sessionCount > _threshold;
      case ComparisonOperator.greaterThanOrEqual:
        return sessionCount >= _threshold;
      case ComparisonOperator.lessThan:
        return sessionCount < _threshold;
      case ComparisonOperator.lessThanOrEqual:
        return sessionCount <= _threshold;
      case ComparisonOperator.equalTo:
        return sessionCount == _threshold;
    }
  }
}

/// Intermediate builder for session-count comparisons.
class SessionCountClauseBuilder {
  final Store _store;
  final String _eventName;
  final QueryFilter? _filter;

  const SessionCountClauseBuilder({
    required Store store,
    required String eventName,
    QueryFilter? filter,
  })  : _store = store,
        _eventName = eventName,
        _filter = filter;

  SessionCountClause greaterThan(int value) => SessionCountClause._(
        store: _store,
        eventName: _eventName,
        operator: ComparisonOperator.greaterThan,
        threshold: value,
        filter: _filter,
      );

  SessionCountClause greaterThanOrEqual(int value) => SessionCountClause._(
        store: _store,
        eventName: _eventName,
        operator: ComparisonOperator.greaterThanOrEqual,
        threshold: value,
        filter: _filter,
      );

  SessionCountClause lessThan(int value) => SessionCountClause._(
        store: _store,
        eventName: _eventName,
        operator: ComparisonOperator.lessThan,
        threshold: value,
        filter: _filter,
      );

  SessionCountClause lessThanOrEqual(int value) => SessionCountClause._(
        store: _store,
        eventName: _eventName,
        operator: ComparisonOperator.lessThanOrEqual,
        threshold: value,
        filter: _filter,
      );

  SessionCountClause equalTo(int value) => SessionCountClause._(
        store: _store,
        eventName: _eventName,
        operator: ComparisonOperator.equalTo,
        threshold: value,
        filter: _filter,
      );
}

