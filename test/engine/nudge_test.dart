import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

import '../helpers.dart';

enum Plan { free, pro }

class _Custom {
  @override
  String toString() => 'custom';
}

void main() {
  late TestClock clock;

  setUp(() => clock = TestClock());

  group('initialization', () {
    test('instance throws before initialize', () {
      expect(Nudge.isInitialized, isFalse);
      expect(() => Nudge.instance, throwsStateError);
      expect(
        () => const EventSelector().event('x').exists().evaluate(),
        throwsStateError,
      );
    });

    test('concurrent calls share the same instance', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final results = await Future.wait([
        Nudge.initialize(storage: InMemoryNudgeStorage()),
        Nudge.initialize(storage: InMemoryNudgeStorage()),
      ]);
      addTearDown(Nudge.instance.dispose);

      expect(identical(results[0], results[1]), isTrue);
    });

    test('can be initialized again after dispose', () async {
      final first = await initNudge(clock);
      first.dispose();
      expect(Nudge.isInitialized, isFalse);

      final second = await initNudge(clock);
      expect(identical(first, second), isFalse);
      expect(second.when().app().sessions().equalTo(1).evaluate(), isTrue);
    });

    test('logs a session start', () async {
      final nudge = await initNudge(clock);

      expect(nudge.sessionId, isNotEmpty);
      expect(nudge.when().app().sessions().equalTo(1).evaluate(), isTrue);
    });
  });

  group('logEvent', () {
    late Nudge nudge;
    late InMemoryNudgeStorage storage;

    setUp(() async {
      storage = InMemoryNudgeStorage();
      nudge = await initNudge(clock, storage: storage);
    });

    EventRecord last(String name) =>
        storage.findEvents(EventQuery(names: {name})).last;

    test('stores supported values as they are', () {
      nudge.logEvent('purchase', {
        'item': 'pro',
        'quantity': 2,
        'price': 9.99,
        'first': true,
      });

      final event = last('purchase');
      expect(event.attributes, {
        'item': 'pro',
        'quantity': 2,
        'price': 9.99,
        'first': true,
      });
      expect(event.sessionId, nudge.sessionId);
      expect(event.timestamp, clock.now);
    });

    test('converts other values instead of throwing', () {
      final at = DateTime(2026, 1, 1);

      nudge.logEvent('signup', {
        'coupon': null,
        'at': at,
        'plan': Plan.pro,
        'custom': _Custom(),
        'tags': ['a'],
      });

      expect(last('signup').attributes, {
        'at': at.millisecondsSinceEpoch,
        'plan': 'pro',
        'custom': 'custom',
        'tags': '[a]',
      });
    });

    test('ignores empty and reserved names', () {
      nudge.logEvent('');
      nudge.logEvent(r'$session_start');

      expect(nudge.when().app().sessions().equalTo(1).evaluate(), isTrue);
      expect(storage.countEvents(const EventQuery(names: {''})), 0);
    });
  });

  group('maintenance', () {
    test(
      'purges expired and exceeding events, keeping lifetime stats',
      () async {
        final storage = InMemoryNudgeStorage();
        final nudge = await initNudge(
          clock,
          storage: storage,
          ttl: const Duration(days: 30),
          maxCapacity: 3,
        );

        nudge.logEvent('old');
        clock.advance(const Duration(days: 31));
        for (var i = 0; i < 4; i++) {
          nudge.logEvent('new');
        }
        nudge.runMaintenance();

        expect(storage.countEvents(const EventQuery(names: {'old'})), 0);
        expect(storage.countEvents(const EventQuery(names: {'new'})), 3);
        expect(nudge.when().event('old').exists().evaluate(), isTrue);
        expect(nudge.when().event('new').count().equalTo(4).evaluate(), isTrue);
      },
    );
  });

  group('clear', () {
    test('erases everything and starts a new session', () async {
      final nudge = await initNudge(clock);
      nudge.logEvent('purchase');
      nudge
          .define('prompt')
          .when(nudge.when().event('purchase').exists())
          .maxFires(1)
          .register()
          .fire();
      final before = nudge.sessionId;

      nudge.clear();

      expect(nudge.sessionId, isNot(before));
      expect(nudge.when().event('purchase').exists().evaluate(), isFalse);
      expect(nudge.when().fired('prompt').exists().evaluate(), isFalse);
      expect(nudge.when().app().sessions().equalTo(1).evaluate(), isTrue);
    });
  });
}
