import 'package:objectbox/objectbox.dart';

/// ObjectBox entity backing an `EventRecord`.
@Entity()
class NudgeEventEntity {
  @Id()
  int id;

  @Index()
  String name;

  /// Milliseconds since the epoch, UTC.
  @Index()
  int timestamp;

  @Index()
  String sessionId;

  /// Event metadata stored as a FlexBuffer map, so no extra entity (and no
  /// orphaned rows after purging) is needed.
  @Property(type: PropertyType.flex)
  Map<String, dynamic>? attributes;

  NudgeEventEntity({
    this.id = 0,
    required this.name,
    required this.timestamp,
    required this.sessionId,
    this.attributes,
  });
}

/// ObjectBox entity backing a `FireRecord`.
@Entity()
class NudgeFireEntity {
  @Id()
  int id;

  @Index()
  String nudgeId;

  @Index()
  String? group;

  /// Milliseconds since the epoch, UTC.
  int firedAt;

  String sessionId;

  String? outcome;

  /// Milliseconds since the epoch, UTC.
  int? outcomeAt;

  NudgeFireEntity({
    this.id = 0,
    required this.nudgeId,
    this.group,
    required this.firedAt,
    required this.sessionId,
    this.outcome,
    this.outcomeAt,
  });
}

/// ObjectBox entity backing an `EventStats`.
@Entity()
class NudgeStatsEntity {
  @Id()
  int id;

  @Unique()
  String name;

  int count;

  /// Milliseconds since the epoch, UTC.
  int firstAt;

  /// Milliseconds since the epoch, UTC.
  int lastAt;

  int activeDays;

  int lastDayKey;

  int streak;

  NudgeStatsEntity({
    this.id = 0,
    required this.name,
    required this.count,
    required this.firstAt,
    required this.lastAt,
    required this.activeDays,
    required this.lastDayKey,
    required this.streak,
  });
}
