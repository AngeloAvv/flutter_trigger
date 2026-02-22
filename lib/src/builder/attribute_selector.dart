import 'package:objectbox/objectbox.dart';

import '../engine/trigger_evaluator.dart';
import 'aggregate_clause.dart';
import 'query_filter.dart';

/// Intermediate builder for selecting an aggregate operation on an attribute.
///
/// Example:
/// ```dart
/// .event("purchase").attribute("price").sum()
/// ```
class AttributeSelector {
  final Store _store;
  final String _eventName;
  final String _attrKey;
  final QueryFilter? _filter;

  const AttributeSelector({
    required Store store,
    required String eventName,
    required String attrKey,
    QueryFilter? filter,
  }) : _store = store,
       _eventName = eventName,
       _attrKey = attrKey,
       _filter = filter;

  /// Aggregates attribute values using **sum**.
  AggregateClauseBuilder sum() => AggregateClauseBuilder(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: AggregateType.sum,
    filter: _filter,
  );

  /// Aggregates attribute values using **average**.
  AggregateClauseBuilder avg() => AggregateClauseBuilder(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: AggregateType.avg,
    filter: _filter,
  );

  /// Aggregates attribute values using **minimum**.
  AggregateClauseBuilder min() => AggregateClauseBuilder(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: AggregateType.min,
    filter: _filter,
  );

  /// Aggregates attribute values using **maximum**.
  AggregateClauseBuilder max() => AggregateClauseBuilder(
    store: _store,
    eventName: _eventName,
    attrKey: _attrKey,
    aggregateType: AggregateType.max,
    filter: _filter,
  );
}
