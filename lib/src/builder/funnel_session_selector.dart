import 'funnel_clause.dart';

/// Returned by [FunnelBuilder.session].
///
/// Allows filtering the funnel's terminal event (and the entire chain's
/// session scope) to either the **same** session as the current one or any
/// **other** session.
///
/// ### Examples
/// ```dart
/// // All funnel steps occurred in the current session
/// trigger.when()
///   .funnel(['view_item', 'add_to_cart', 'checkout'])
///   .loose()
///   .session().same()
///   .watch();
///
/// // Funnel completed across a different session
/// trigger.when()
///   .funnel(['sign_up', 'first_purchase'])
///   .loose()
///   .session().other()
///   .watch();
/// ```
class FunnelSessionSelector {
  final FunnelBuilder _builder;
  final String _currentSessionId;

  const FunnelSessionSelector({
    required FunnelBuilder builder,
    required String currentSessionId,
  })  : _builder = builder,
        _currentSessionId = currentSessionId;

  /// Restricts the funnel to events recorded in the **same** (current) session.
  FunnelBuilder same() => _builder.copyWith(
        filter: _builder.filter.copyWith(
          sessionId: _currentSessionId,
          negateSession: false,
        ),
      );

  /// Restricts the funnel to events recorded in any session **other** than
  /// the current one.
  FunnelBuilder other() => _builder.copyWith(
        filter: _builder.filter.copyWith(
          sessionId: _currentSessionId,
          negateSession: true,
        ),
      );
}
