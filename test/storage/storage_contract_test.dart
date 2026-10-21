import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';
import 'package:nudge/src/storage/objectbox/objectbox_nudge_storage.dart';

/// Whether the ObjectBox native library can be loaded, see the CI workflow
/// for how it is installed.
bool _objectBoxAvailable() {
  final name = Platform.isMacOS
      ? 'libobjectbox.dylib'
      : Platform.isWindows
      ? 'objectbox.dll'
      : 'libobjectbox.so';
  for (final path in ['${Directory.current.path}/lib/$name', name]) {
    try {
      DynamicLibrary.open(path);
      return true;
    } on ArgumentError {
      continue;
    }
  }
  return false;
}

void main() {
  var objectBoxStores = 0;

  final storages = <String, Future<NudgeStorage> Function()>{
    'InMemoryNudgeStorage': () async => InMemoryNudgeStorage(),
    'ObjectBoxNudgeStorage': () => ObjectBoxNudgeStorage.open(
      directory: 'memory:nudge_test_${objectBoxStores++}',
    ),
  };

  // Locally the ObjectBox suite is skipped without the native library; in CI
  // the library is installed, so a missing one must fail instead.
  final objectBoxSkip =
      _objectBoxAvailable() || Platform.environment['CI'] == 'true'
      ? false
      : 'ObjectBox native library not found';

  for (final MapEntry(key: name, value: open) in storages.entries) {
    group(name, skip: name.startsWith('ObjectBox') ? objectBoxSkip : false, () {
      late NudgeStorage storage;
      final t0 = DateTime(2026, 1, 15, 12);

      setUp(() async {
        storage = await open();
        addTearDown(storage.close);
      });

      EventRecord event(
        String name, {
        Duration at = Duration.zero,
        String session = 's1',
        Map<String, Object> attributes = const {},
      }) => storage.insertEvent(
        EventRecord(
          name: name,
          timestamp: t0.add(at),
          sessionId: session,
          attributes: attributes,
        ),
      );

      test('assigns increasing ids and round-trips attributes', () {
        final first = event(
          'purchase',
          attributes: {'s': 'x', 'i': 1, 'd': 1.5, 'b': true},
        );
        final second = event('purchase');

        expect(second.id, greaterThan(first.id));
        final stored = storage.findEvents(
          const EventQuery(names: {'purchase'}),
        );
        expect(stored.map((e) => e.id), [first.id, second.id]);
        expect(stored.first.attributes, {
          's': 'x',
          'i': 1,
          'd': 1.5,
          'b': true,
        });
        expect(stored.first.timestamp, t0);
        expect(stored.first.sessionId, 's1');
      });

      test('filters by names, session and inclusive time bounds', () {
        event('a', at: const Duration(minutes: 1));
        event('b', at: const Duration(minutes: 2), session: 's2');
        event('a', at: const Duration(minutes: 3), session: 's2');
        event('c', at: const Duration(minutes: 4));

        int count(EventQuery query) {
          final found = storage.findEvents(query);
          expect(storage.countEvents(query), found.length);
          return found.length;
        }

        expect(count(const EventQuery(names: {'a', 'b'})), 3);
        expect(count(const EventQuery(names: {'a'}, sessionId: 's2')), 1);
        expect(
          count(
            const EventQuery(
              names: {'a', 'b', 'c'},
              sessionId: 's2',
              excludeSession: true,
            ),
          ),
          2,
        );
        expect(
          count(
            EventQuery(
              names: const {'a', 'b', 'c'},
              from: t0.add(const Duration(minutes: 2)),
              to: t0.add(const Duration(minutes: 3)),
            ),
          ),
          2,
        );
      });

      test('keeps lifetime stats per name and for any event', () {
        event('lesson');
        event('lesson', at: const Duration(hours: 1));
        event('lesson', at: const Duration(days: 1));
        event('other', at: const Duration(days: 3));

        final lesson = storage.stats('lesson')!;
        expect(lesson.count, 3);
        expect(lesson.firstAt, t0);
        expect(lesson.lastAt, t0.add(const Duration(days: 1)));
        expect(lesson.activeDays, 2);
        expect(lesson.streak, 2);

        final any = storage.stats(EventStats.anyEvent)!;
        expect(any.count, 4);
        expect(any.activeDays, 3);
        expect(any.streak, 1);
        expect(storage.stats('missing'), isNull);
      });

      test('purges by age and by capacity without touching stats', () {
        event('e', at: const Duration(days: -10));
        event('e', at: const Duration(days: -5));
        event('e', at: const Duration(days: -1));
        event('e');

        expect(
          storage.purgeEventsBefore(t0.subtract(const Duration(days: 7))),
          1,
        );
        expect(storage.purgeEventsExceeding(2), 1);
        expect(storage.purgeEventsExceeding(2), 0);

        final remaining = storage.findEvents(const EventQuery(names: {'e'}));
        expect(remaining.map((e) => e.timestamp), [
          t0.subtract(const Duration(days: 1)),
          t0,
        ]);
        expect(storage.stats('e')!.count, 4);
      });

      test('stores, updates, filters and removes fires', () {
        final fire = storage.insertFire(
          FireRecord(nudgeId: 't1', group: 'g', firedAt: t0, sessionId: 's1'),
        );
        storage.insertFire(
          FireRecord(
            nudgeId: 't2',
            firedAt: t0.add(const Duration(days: 1)),
            sessionId: 's2',
          ),
        );
        storage.updateFire(fire.copyWith(outcome: 'accepted', outcomeAt: t0));

        expect(storage.findFires(const FireQuery()).length, 2);
        expect(
          storage.findFires(const FireQuery(group: 'g')).single.id,
          fire.id,
        );
        expect(
          storage
              .findFires(const FireQuery(outcome: 'accepted'))
              .single
              .outcomeAt,
          t0,
        );
        expect(
          storage
              .findFires(FireQuery(from: t0.add(const Duration(hours: 1))))
              .single
              .nudgeId,
          't2',
        );
        expect(
          storage.findFires(const FireQuery(sessionId: 's2')).single.nudgeId,
          't2',
        );

        expect(storage.removeFires('t1'), 1);
        expect(storage.findFires(const FireQuery(nudgeId: 't1')), isEmpty);
      });

      test('clear removes events, stats and fires', () {
        event('e');
        storage.insertFire(
          FireRecord(nudgeId: 't', firedAt: t0, sessionId: 's1'),
        );

        storage.clear();

        expect(storage.countEvents(const EventQuery(names: {'e'})), 0);
        expect(storage.stats('e'), isNull);
        expect(storage.findFires(const FireQuery()), isEmpty);
      });
    });
  }
}
