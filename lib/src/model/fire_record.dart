/// A persisted record of a nudge firing, and of the outcome reported for it.
///
/// Fire records are never touched by log rotation: cooldowns, caps and
/// chains keep working no matter how many events are purged.
class FireRecord {
  /// Identifier assigned by the storage.
  final int id;

  /// The id of the nudge that fired.
  final String nudgeId;

  /// The group the nudge belonged to when it fired, if any.
  final String? group;

  /// When the nudge fired.
  final DateTime firedAt;

  /// The session the nudge fired in.
  final String sessionId;

  /// The outcome reported through `NudgeFire.complete`, if any.
  final String? outcome;

  /// When the outcome was reported.
  final DateTime? outcomeAt;

  const FireRecord({
    this.id = 0,
    required this.nudgeId,
    this.group,
    required this.firedAt,
    required this.sessionId,
    this.outcome,
    this.outcomeAt,
  });

  FireRecord copyWith({int? id, String? outcome, DateTime? outcomeAt}) =>
      FireRecord(
        id: id ?? this.id,
        nudgeId: nudgeId,
        group: group,
        firedAt: firedAt,
        sessionId: sessionId,
        outcome: outcome ?? this.outcome,
        outcomeAt: outcomeAt ?? this.outcomeAt,
      );

  @override
  String toString() =>
      'FireRecord(#$id $nudgeId @ ${firedAt.toIso8601String()}, '
      'outcome: $outcome)';
}
