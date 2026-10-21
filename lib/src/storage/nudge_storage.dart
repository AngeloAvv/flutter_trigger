import '../model/event_record.dart';
import '../model/event_stats.dart';
import '../model/fire_record.dart';

/// Selects events by name, session and time range.
class EventQuery {
  /// The event names to match. Never empty.
  final Set<String> names;

  /// When set, only events of this session match (or, with
  /// [excludeSession], only events of any other session).
  final String? sessionId;

  /// Inverts the [sessionId] constraint.
  final bool excludeSession;

  /// Inclusive lower bound on the event timestamp.
  final DateTime? from;

  /// Inclusive upper bound on the event timestamp.
  final DateTime? to;

  const EventQuery({
    required this.names,
    this.sessionId,
    this.excludeSession = false,
    this.from,
    this.to,
  });

  /// Whether [event] satisfies this query.
  bool matches(EventRecord event) {
    if (!names.contains(event.name)) return false;

    final session = sessionId;
    if (session != null && (event.sessionId == session) == excludeSession) {
      return false;
    }

    final ms = event.timestamp.millisecondsSinceEpoch;
    if (from != null && ms < from!.millisecondsSinceEpoch) return false;
    if (to != null && ms > to!.millisecondsSinceEpoch) return false;

    return true;
  }
}

/// Selects fire records by nudge, group, session, outcome and time.
class FireQuery {
  /// Only records of this nudge.
  final String? nudgeId;

  /// Only records of nudges in this group.
  final String? group;

  /// Only records fired in this session.
  final String? sessionId;

  /// Only records that completed with this outcome.
  final String? outcome;

  /// Inclusive lower bound on [FireRecord.firedAt].
  final DateTime? from;

  const FireQuery({
    this.nudgeId,
    this.group,
    this.sessionId,
    this.outcome,
    this.from,
  });

  /// Whether [fire] satisfies this query.
  bool matches(FireRecord fire) =>
      (nudgeId == null || fire.nudgeId == nudgeId) &&
      (group == null || fire.group == group) &&
      (sessionId == null || fire.sessionId == sessionId) &&
      (outcome == null || fire.outcome == outcome) &&
      (from == null ||
          fire.firedAt.millisecondsSinceEpoch >= from!.millisecondsSinceEpoch);
}

/// Persistence used by the nudge engine.
///
/// The engine performs all evaluation logic itself, so an implementation only
/// stores and filters records. All methods are synchronous: evaluation runs on
/// the caller's isolate and must return a value immediately.
///
/// Two implementations ship with the package: the default ObjectBox-backed
/// storage and [InMemoryNudgeStorage], meant for tests.
abstract interface class NudgeStorage {
  /// Stores [event], assigns its id and updates the [EventStats] of its name
  /// and of [EventStats.anyEvent] in the same write.
  EventRecord insertEvent(EventRecord event);

  /// Counts events matching [query].
  int countEvents(EventQuery query);

  /// Returns events matching [query], ordered by id ascending.
  List<EventRecord> findEvents(EventQuery query);

  /// Returns the lifetime stats of [name], or `null` if it was never logged.
  EventStats? stats(String name);

  /// Stores [fire] and returns it with its id assigned.
  FireRecord insertFire(FireRecord fire);

  /// Replaces the stored fire record with the same id.
  void updateFire(FireRecord fire);

  /// Returns fire records matching [query], ordered by id ascending.
  List<FireRecord> findFires(FireQuery query);

  /// Deletes events logged before [cutoff] and returns how many were removed.
  int purgeEventsBefore(DateTime cutoff);

  /// Deletes the oldest events so that at most [maxCount] remain, and returns
  /// how many were removed.
  int purgeEventsExceeding(int maxCount);

  /// Deletes every fire record of [nudgeId].
  int removeFires(String nudgeId);

  /// Deletes every event, stat and fire record.
  void clear();

  /// Releases resources. The storage is unusable afterwards.
  void close();
}
