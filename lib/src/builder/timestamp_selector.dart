import 'event_clause.dart';
import 'query_filter.dart';

/// Provides comparison methods for event timestamps in the fluent API.
class TimestampSelector {
  final EventClause _clause;
  final QueryFilter _filter;

  const TimestampSelector(this._clause, this._filter);

  /// Filters events where the timestamp is strictly **greater than** [dateTime].
  EventClause greaterThan(DateTime dateTime) {
    return _clause.withFilter(
      _filter.copyWith(
        timestampAfter: dateTime.add(const Duration(microseconds: 1)),
      ),
    );
  }

  /// Filters events where the timestamp is **greater than or equal** to [dateTime].
  EventClause greaterThanOrEqual(DateTime dateTime) {
    return _clause.withFilter(_filter.copyWith(timestampAfter: dateTime));
  }

  /// Filters events where the timestamp is strictly **less than** [dateTime].
  EventClause lessThan(DateTime dateTime) {
    return _clause.withFilter(
      _filter.copyWith(
        timestampBefore: dateTime.subtract(const Duration(microseconds: 1)),
      ),
    );
  }

  /// Filters events where the timestamp is **less than or equal** to [dateTime].
  EventClause lessThanOrEqual(DateTime dateTime) {
    return _clause.withFilter(_filter.copyWith(timestampBefore: dateTime));
  }

  /// Filters events where the timestamp is **exactly** [dateTime].
  EventClause equalTo(DateTime dateTime) {
    return _clause.withFilter(
      _filter.copyWith(timestampAfter: dateTime, timestampBefore: dateTime),
    );
  }
}
