import '../model/event_record.dart';
import '../model/event_stats.dart';
import '../model/fire_record.dart';
import 'nudge_storage.dart';

/// A [NudgeStorage] that keeps everything in memory.
///
/// Meant for unit and widget tests: pass it to `Nudge.initialize` to
/// exercise your nudges without native libraries or files on disk.
///
/// ```dart
/// await Nudge.initialize(storage: InMemoryNudgeStorage());
/// ```
class InMemoryNudgeStorage implements NudgeStorage {
  final _events = <EventRecord>[];
  final _fires = <FireRecord>[];
  final _stats = <String, EventStats>{};
  int _nextEventId = 1;
  int _nextFireId = 1;

  @override
  EventRecord insertEvent(EventRecord event) {
    final stored = event.copyWith(id: _nextEventId++);
    _events.add(stored);

    for (final name in {event.name, EventStats.anyEvent}) {
      final current = _stats[name];
      _stats[name] = current == null
          ? EventStats.first(name, event.timestamp)
          : current.record(event.timestamp);
    }

    return stored;
  }

  @override
  int countEvents(EventQuery query) => _events.where(query.matches).length;

  @override
  List<EventRecord> findEvents(EventQuery query) =>
      _events.where(query.matches).toList(growable: false);

  @override
  EventStats? stats(String name) => _stats[name];

  @override
  FireRecord insertFire(FireRecord fire) {
    final stored = fire.copyWith(id: _nextFireId++);
    _fires.add(stored);
    return stored;
  }

  @override
  void updateFire(FireRecord fire) {
    final index = _fires.indexWhere((stored) => stored.id == fire.id);
    if (index >= 0) _fires[index] = fire;
  }

  @override
  List<FireRecord> findFires(FireQuery query) =>
      _fires.where(query.matches).toList(growable: false);

  @override
  int purgeEventsBefore(DateTime cutoff) {
    final before = _events.length;
    _events.removeWhere((event) => event.timestamp.isBefore(cutoff));
    return before - _events.length;
  }

  @override
  int purgeEventsExceeding(int maxCount) {
    final excess = _events.length - maxCount;
    if (excess <= 0) return 0;

    _events.removeRange(0, excess);
    return excess;
  }

  @override
  int removeFires(String nudgeId) {
    final before = _fires.length;
    _fires.removeWhere((fire) => fire.nudgeId == nudgeId);
    return before - _fires.length;
  }

  @override
  void clear() {
    _events.clear();
    _fires.clear();
    _stats.clear();
  }

  @override
  void close() {}
}
