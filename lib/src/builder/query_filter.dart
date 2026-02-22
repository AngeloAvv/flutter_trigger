/// A data class that holds filtering constraints for ObjectBox queries.
class QueryFilter {
  /// The session identifier to filter by (optional).
  final String? sessionId;

  /// If true, the [sessionId] filter is negated (not equal).
  final bool negateSession;

  /// Lower bound for event timestamp (inclusive).
  final DateTime? timestampAfter;

  /// Upper bound for event timestamp (inclusive).
  final DateTime? timestampBefore;

  const QueryFilter({
    this.sessionId,
    this.negateSession = false,
    this.timestampAfter,
    this.timestampBefore,
  });

  /// Creates a copy of this filter with some fields updated.
  QueryFilter copyWith({
    String? sessionId,
    bool? negateSession,
    DateTime? timestampAfter,
    DateTime? timestampBefore,
  }) {
    return QueryFilter(
      sessionId: sessionId ?? this.sessionId,
      negateSession: negateSession ?? this.negateSession,
      timestampAfter: timestampAfter ?? this.timestampAfter,
      timestampBefore: timestampBefore ?? this.timestampBefore,
    );
  }
}
