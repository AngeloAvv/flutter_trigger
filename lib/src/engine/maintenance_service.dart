import 'package:flutter/foundation.dart';

import '../models/event.dart';
import '../../objectbox.g.dart';

/// Performs log rotation to keep the event database lean.
///
/// Two strategies are applied:
/// 1. **TTL** — deletes events older than a configurable [Duration].
/// 2. **Max Capacity** — keeps only the latest N events, bulk-deleting older ones.
class MaintenanceService {
  final Store _store;
  final Duration ttl;
  final int maxCapacity;

  const MaintenanceService(
    this._store, {
    this.ttl = const Duration(days: 365),
    this.maxCapacity = 10000,
  });

  /// Runs all maintenance tasks.
  ///
  /// This is designed to be called asynchronously (e.g. 2 seconds after init).
  Future<void> run() async {
    await _purgeTtl();
    await _purgeCapacity();
  }

  /// Deletes events whose [Event.timestamp] is older than [ttl].
  Future<void> _purgeTtl() async {
    final cutoff = DateTime.now().subtract(ttl);
    final box = _store.box<Event>();

    final query = box
        .query(Event_.timestamp.lessThan(cutoff.millisecondsSinceEpoch))
        .build();

    final expired = query.findIds();
    query.close();

    if (expired.isNotEmpty) {
      box.removeMany(expired);
      debugPrint(
        '[FlutterTrigger] Maintenance: purged ${expired.length} '
        'events older than $ttl.',
      );
    }
  }

  /// If the total event count exceeds [maxCapacity], deletes the oldest events
  /// until only [maxCapacity] remain.
  Future<void> _purgeCapacity() async {
    final box = _store.box<Event>();
    final total = box.count();

    if (total <= maxCapacity) return;

    // Find the timestamp of the Nth-newest event.
    final query = box
        .query()
        .order(Event_.timestamp, flags: Order.descending)
        .build();

    final events = query.find();
    query.close();

    if (events.length <= maxCapacity) return;

    // Remove all events beyond maxCapacity (they are the oldest).
    final idsToRemove = events.sublist(maxCapacity).map((e) => e.id).toList();

    box.removeMany(idsToRemove);
    debugPrint(
      '[FlutterTrigger] Maintenance: purged ${idsToRemove.length} '
      'events exceeding max capacity of $maxCapacity.',
    );
  }
}
