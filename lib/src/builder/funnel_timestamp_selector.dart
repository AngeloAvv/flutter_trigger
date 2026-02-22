import 'funnel_clause.dart';
import 'query_filter.dart';

/// Returned by [FunnelBuilder.timestamp].
///
/// Provides comparison methods that constrain **when every step** of the
/// funnel must have occurred (not just the last one), and a convenience
/// `.within(duration)` method that constrains the whole funnel to complete
/// within a rolling time window.
///
/// Every method returns a [FunnelBuilder] so chaining can continue.
///
/// ### Examples
/// ```dart
/// // Every step must have occurred after a specific date
/// trigger.when()
///   .funnel(['sign_up', 'first_purchase'])
///   .loose()
///   .timestamp().greaterThan(DateTime(2025))
///   .watch();
///
/// // All steps within 24 hours of each other
/// trigger.when()
///   .funnel(['view_item', 'checkout'])
///   .loose()
///   .timestamp().within(Duration(hours: 24))
///   .watch();
/// ```
class FunnelTimestampSelector {
  final FunnelBuilder _builder;

  const FunnelTimestampSelector({required FunnelBuilder builder})
      : _builder = builder;

  FunnelBuilder _withFilter(QueryFilter f) => _builder.copyWith(filter: f);

  QueryFilter get _filter => _builder.filter;

  /// The last funnel step's timestamp must be strictly **after** [dateTime].
  FunnelBuilder greaterThan(DateTime dateTime) => _withFilter(
        _filter.copyWith(
          timestampAfter: dateTime.add(const Duration(microseconds: 1)),
        ),
      );

  /// The last funnel step's timestamp must be **on or after** [dateTime].
  FunnelBuilder greaterThanOrEqual(DateTime dateTime) =>
      _withFilter(_filter.copyWith(timestampAfter: dateTime));

  /// The last funnel step's timestamp must be strictly **before** [dateTime].
  FunnelBuilder lessThan(DateTime dateTime) => _withFilter(
        _filter.copyWith(
          timestampBefore: dateTime.subtract(const Duration(microseconds: 1)),
        ),
      );

  /// The last funnel step's timestamp must be **on or before** [dateTime].
  FunnelBuilder lessThanOrEqual(DateTime dateTime) =>
      _withFilter(_filter.copyWith(timestampBefore: dateTime));

  /// The last funnel step's timestamp must be **exactly** [dateTime].
  FunnelBuilder equalTo(DateTime dateTime) => _withFilter(
        _filter.copyWith(timestampAfter: dateTime, timestampBefore: dateTime),
      );

  /// All funnel steps must occur within [duration] of each other (rolling
  /// window measured from the last step backwards).
  ///
  /// Can be combined with the absolute timestamp methods above.
  FunnelBuilder within(Duration duration) =>
      _builder.copyWith(window: duration);
}

