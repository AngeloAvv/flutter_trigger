import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

import '../helpers.dart';

void main() {
  late TestClock clock;
  late Nudge nudge;

  setUp(() async {
    clock = TestClock();
    nudge = await initNudge(clock);
  });

  group('equality', () {
    test('conditions built the same way are equal', () {
      NudgeCondition build() => nudge
          .when()
          .event('purchase')
          .where('currency')
          .oneOf(['EUR', 'USD'])
          .inLast(const Duration(days: 7))
          .attribute('total')
          .sum()
          .greaterThan(100)
          .and(nudge.when().funnel(['a', 'b']).session().single().not());

      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });

    test('different conditions are not equal', () {
      final count = nudge.when().event('share').count();

      expect(count.greaterThan(1), isNot(count.greaterThan(2)));
      expect(count.greaterThan(1), isNot(count.greaterThanOrEqual(1)));
      expect(
        nudge.when().funnel(['a', 'b']),
        isNot(nudge.when().funnel(['b', 'a'])),
      );
    });
  });

  group('logic', () {
    late NudgeCondition yes;
    late NudgeCondition no;

    setUp(() {
      nudge.logEvent('yes');
      yes = nudge.when().event('yes').exists();
      no = nudge.when().event('no').exists();
    });

    test('and, or, not', () {
      expect(yes.and(no).evaluate(), isFalse);
      expect(yes.or(no).evaluate(), isTrue);
      expect(no.not().evaluate(), isTrue);
      expect(yes.and(no.not()).evaluate(), isTrue);
    });

    test('all and any', () {
      expect(NudgeCondition.all([yes, yes, no]).evaluate(), isFalse);
      expect(NudgeCondition.any([no, no, yes]).evaluate(), isTrue);
      expect(NudgeCondition.all(const []).evaluate(), isTrue);
      expect(NudgeCondition.any(const []).evaluate(), isFalse);
    });

    test('explain shows every branch', () {
      final text = yes.and(no).explain().toString();

      expect(text, contains('✗ AND'));
      expect(text, contains('✓ count(yes) = 1 > 0'));
      expect(text, contains('✗ count(no) = 0 > 0'));
    });
  });

  group('watch', () {
    test('emits the current value, then changes only', () async {
      final values = <bool>[];
      final subscription = nudge
          .when()
          .event('share')
          .count()
          .greaterThanOrEqual(2)
          .watch()
          .listen(values.add);

      await settle();
      nudge.logEvent('share');
      await settle();
      nudge.logEvent('share');
      await settle();
      nudge.logEvent('share');
      await settle();
      await subscription.cancel();

      expect(values, [false, true]);
    });

    test('a burst of events in the same frame is evaluated once', () async {
      final values = <bool>[];
      final subscription = nudge
          .when()
          .event('tap')
          .count()
          .equalTo(1)
          .watch()
          .listen(values.add);
      await settle();

      nudge.logEvent('tap');
      nudge.logEvent('tap');
      await settle();
      await subscription.cancel();

      expect(values, [false], reason: 'count was never observed at exactly 1');
    });

    test('composite conditions never emit transient values', () async {
      final x = nudge.when().event('x').exists();
      final values = <bool>[];
      final subscription = x.and(x.not()).watch().listen(values.add);
      await settle();

      nudge.logEvent('x');
      await settle();
      await subscription.cancel();

      expect(values, [false]);
    });

    test('time-based conditions update on resume without new events', () async {
      final values = <bool>[];
      nudge.logEvent('open');
      final subscription = nudge
          .when()
          .event('open')
          .inLast(const Duration(days: 1))
          .exists()
          .watch()
          .listen(values.add);
      await settle();

      backgroundFor(clock, const Duration(days: 2));
      await settle();
      await subscription.cancel();

      expect(values, [true, false]);
    });

    test('streams complete when the instance is disposed', () async {
      final stream = nudge.when().event('x').exists().watch();
      final done = expectLater(stream, emitsInOrder([false, emitsDone]));
      await settle();

      nudge.dispose();
      await done;
    });
  });
}
