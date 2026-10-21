/// Lifetime counters kept per event name and updated in the same write as the
/// event itself.
///
/// Stats survive log rotation, so lifetime questions ("has the user ever
/// purchased?", "how many sessions so far?") keep their answer after old
/// events are purged.
class EventStats {
  /// The event name, or [EventStats.anyEvent] for activity of any kind.
  final String name;

  /// Number of events ever logged with this name.
  final int count;

  /// First time the event was logged.
  final DateTime firstAt;

  /// Last time the event was logged.
  final DateTime lastAt;

  /// Number of distinct local calendar days the event was logged on.
  final int activeDays;

  /// The local calendar day of [lastAt], see [dayKeyOf].
  final int lastDayKey;

  /// Consecutive local days, ending on [lastDayKey], the event was logged on.
  final int streak;

  /// The reserved name under which activity of any event is aggregated.
  static const anyEvent = r'$any';

  const EventStats({
    required this.name,
    required this.count,
    required this.firstAt,
    required this.lastAt,
    required this.activeDays,
    required this.lastDayKey,
    required this.streak,
  });

  /// Stats for the first occurrence of an event at [timestamp].
  factory EventStats.first(String name, DateTime timestamp) => EventStats(
    name: name,
    count: 1,
    firstAt: timestamp,
    lastAt: timestamp,
    activeDays: 1,
    lastDayKey: dayKeyOf(timestamp),
    streak: 1,
  );

  /// Returns the stats after one more occurrence at [timestamp].
  EventStats record(DateTime timestamp) {
    final day = dayKeyOf(timestamp);
    final isNewDay = day > lastDayKey;

    return EventStats(
      name: name,
      count: count + 1,
      firstAt: timestamp.isBefore(firstAt) ? timestamp : firstAt,
      lastAt: timestamp.isAfter(lastAt) ? timestamp : lastAt,
      activeDays: isNewDay ? activeDays + 1 : activeDays,
      lastDayKey: isNewDay ? day : lastDayKey,
      streak: switch (day - lastDayKey) {
        <= 0 => streak,
        1 => streak + 1,
        _ => 1,
      },
    );
  }

  /// The streak as seen on [now]: it is broken once a full local day passes
  /// without the event.
  int streakOn(DateTime now) => dayKeyOf(now) - lastDayKey <= 1 ? streak : 0;
}

/// Identifies the local calendar day of [dateTime] as days since the epoch.
///
/// Uses the local date, so a streak follows the user's midnight rather than
/// UTC's.
int dayKeyOf(DateTime dateTime) {
  final local = dateTime.toLocal();
  return DateTime.utc(
        local.year,
        local.month,
        local.day,
      ).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
