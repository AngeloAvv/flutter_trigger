import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../model/event_record.dart';
import '../../model/event_stats.dart';
import '../../model/fire_record.dart';
import '../nudge_storage.dart';
import 'entities.dart';
import 'objectbox.g.dart';

/// The default [NudgeStorage], backed by an ObjectBox store dedicated to
/// the package.
class ObjectBoxNudgeStorage implements NudgeStorage {
  final Store _store;
  final Box<NudgeEventEntity> _events;
  final Box<NudgeFireEntity> _fires;
  final Box<NudgeStatsEntity> _stats;

  ObjectBoxNudgeStorage._(this._store)
    : _events = _store.box<NudgeEventEntity>(),
      _fires = _store.box<NudgeFireEntity>(),
      _stats = _store.box<NudgeStatsEntity>();

  /// Opens the store in [directory], defaulting to a `nudge` folder
  /// inside the application support directory (not backed up to iCloud as
  /// user documents, and not visible in the Files app).
  ///
  /// When a store is already open at that path, which happens after a hot
  /// restart because the native store outlives the Dart isolate, it is
  /// attached to instead of reopened.
  static Future<ObjectBoxNudgeStorage> open({String? directory}) async {
    final path =
        directory ??
        '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}nudge';

    final store = Store.isOpen(path)
        ? Store.attach(getObjectBoxModel(), path)
        : await openStore(directory: path);

    return ObjectBoxNudgeStorage._(store);
  }

  @override
  EventRecord insertEvent(EventRecord event) =>
      _store.runInTransaction(TxMode.write, () {
        final id = _events.put(
          NudgeEventEntity(
            name: event.name,
            timestamp: event.timestamp.millisecondsSinceEpoch,
            sessionId: event.sessionId,
            attributes: event.attributes.isEmpty ? null : event.attributes,
          ),
        );

        for (final name in {event.name, EventStats.anyEvent}) {
          final entity = _statsEntity(name);
          final stats = entity == null
              ? EventStats.first(name, event.timestamp)
              : _toStats(entity).record(event.timestamp);
          _stats.put(_toStatsEntity(stats, id: entity?.id ?? 0));
        }

        return event.copyWith(id: id);
      });

  @override
  int countEvents(EventQuery query) {
    final q = _events.query(_eventCondition(query)).build();
    try {
      return q.count();
    } finally {
      q.close();
    }
  }

  @override
  List<EventRecord> findEvents(EventQuery query) {
    final q = _events
        .query(_eventCondition(query))
        .order(NudgeEventEntity_.id)
        .build();
    try {
      return q.find().map(_toEvent).toList(growable: false);
    } finally {
      q.close();
    }
  }

  @override
  EventStats? stats(String name) {
    final entity = _statsEntity(name);
    return entity == null ? null : _toStats(entity);
  }

  @override
  FireRecord insertFire(FireRecord fire) =>
      fire.copyWith(id: _fires.put(_toFireEntity(fire)));

  @override
  void updateFire(FireRecord fire) => _fires.put(_toFireEntity(fire));

  @override
  List<FireRecord> findFires(FireQuery query) {
    final conditions = <Condition<NudgeFireEntity>>[
      if (query.nudgeId != null)
        NudgeFireEntity_.nudgeId.equals(query.nudgeId!),
      if (query.group != null) NudgeFireEntity_.group.equals(query.group!),
      if (query.sessionId != null)
        NudgeFireEntity_.sessionId.equals(query.sessionId!),
      if (query.outcome != null)
        NudgeFireEntity_.outcome.equals(query.outcome!),
      if (query.from != null)
        NudgeFireEntity_.firedAt.greaterOrEqual(
          query.from!.millisecondsSinceEpoch,
        ),
    ];

    final q = _fires
        .query(conditions.isEmpty ? null : conditions.reduce((a, b) => a & b))
        .order(NudgeFireEntity_.id)
        .build();
    try {
      return q.find().map(_toFire).toList(growable: false);
    } finally {
      q.close();
    }
  }

  @override
  int purgeEventsBefore(DateTime cutoff) {
    final q = _events
        .query(
          NudgeEventEntity_.timestamp.lessThan(cutoff.millisecondsSinceEpoch),
        )
        .build();
    try {
      return q.remove();
    } finally {
      q.close();
    }
  }

  @override
  int purgeEventsExceeding(int maxCount) {
    if (_events.count() <= maxCount) return 0;

    final q =
        _events
            .query()
            .order(NudgeEventEntity_.id, flags: Order.descending)
            .build()
          ..offset = maxCount;
    try {
      return _events.removeMany(q.findIds());
    } finally {
      q.close();
    }
  }

  @override
  int removeFires(String nudgeId) {
    final q = _fires.query(NudgeFireEntity_.nudgeId.equals(nudgeId)).build();
    try {
      return q.remove();
    } finally {
      q.close();
    }
  }

  @override
  void clear() => _store.runInTransaction(TxMode.write, () {
    _events.removeAll();
    _fires.removeAll();
    _stats.removeAll();
  });

  @override
  void close() => _store.close();

  Condition<NudgeEventEntity> _eventCondition(EventQuery query) {
    var condition = NudgeEventEntity_.name.oneOf(query.names.toList());

    final session = query.sessionId;
    if (session != null) {
      condition &= query.excludeSession
          ? NudgeEventEntity_.sessionId.notEquals(session)
          : NudgeEventEntity_.sessionId.equals(session);
    }
    if (query.from != null) {
      condition &= NudgeEventEntity_.timestamp.greaterOrEqual(
        query.from!.millisecondsSinceEpoch,
      );
    }
    if (query.to != null) {
      condition &= NudgeEventEntity_.timestamp.lessOrEqual(
        query.to!.millisecondsSinceEpoch,
      );
    }

    return condition;
  }

  NudgeStatsEntity? _statsEntity(String name) {
    final q = _stats.query(NudgeStatsEntity_.name.equals(name)).build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  static EventRecord _toEvent(NudgeEventEntity entity) => EventRecord(
    id: entity.id,
    name: entity.name,
    timestamp: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
    sessionId: entity.sessionId,
    attributes: {
      for (final MapEntry(:key, :value) in (entity.attributes ?? {}).entries)
        if (value != null) key: value as Object,
    },
  );

  static FireRecord _toFire(NudgeFireEntity entity) => FireRecord(
    id: entity.id,
    nudgeId: entity.nudgeId,
    group: entity.group,
    firedAt: DateTime.fromMillisecondsSinceEpoch(entity.firedAt),
    sessionId: entity.sessionId,
    outcome: entity.outcome,
    outcomeAt: entity.outcomeAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entity.outcomeAt!),
  );

  static NudgeFireEntity _toFireEntity(FireRecord fire) => NudgeFireEntity(
    id: fire.id,
    nudgeId: fire.nudgeId,
    group: fire.group,
    firedAt: fire.firedAt.millisecondsSinceEpoch,
    sessionId: fire.sessionId,
    outcome: fire.outcome,
    outcomeAt: fire.outcomeAt?.millisecondsSinceEpoch,
  );

  static EventStats _toStats(NudgeStatsEntity entity) => EventStats(
    name: entity.name,
    count: entity.count,
    firstAt: DateTime.fromMillisecondsSinceEpoch(entity.firstAt),
    lastAt: DateTime.fromMillisecondsSinceEpoch(entity.lastAt),
    activeDays: entity.activeDays,
    lastDayKey: entity.lastDayKey,
    streak: entity.streak,
  );

  static NudgeStatsEntity _toStatsEntity(EventStats stats, {int id = 0}) =>
      NudgeStatsEntity(
        id: id,
        name: stats.name,
        count: stats.count,
        firstAt: stats.firstAt.millisecondsSinceEpoch,
        lastAt: stats.lastAt.millisecondsSinceEpoch,
        activeDays: stats.activeDays,
        lastDayKey: stats.lastDayKey,
        streak: stats.streak,
      );
}
