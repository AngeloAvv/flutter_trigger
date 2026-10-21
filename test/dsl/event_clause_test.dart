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

  group('count', () {
    test('compares the number of events with every operator', () {
      for (var i = 0; i < 3; i++) {
        nudge.logEvent('share');
      }
      final count = nudge.when().event('share').count();

      expect(count.greaterThan(2).evaluate(), isTrue);
      expect(count.greaterThan(3).evaluate(), isFalse);
      expect(count.greaterThanOrEqual(3).evaluate(), isTrue);
      expect(count.lessThan(3).evaluate(), isFalse);
      expect(count.lessThanOrEqual(3).evaluate(), isTrue);
      expect(count.equalTo(3).evaluate(), isTrue);
    });

    test('only counts events with the selected name', () {
      nudge.logEvent('share');
      nudge.logEvent('like');

      expect(nudge.when().event('share').count().equalTo(1).evaluate(), isTrue);
    });

    test('exists is met after the first event', () {
      final exists = nudge.when().event('purchase').exists();
      expect(exists.evaluate(), isFalse);

      nudge.logEvent('purchase');
      expect(exists.evaluate(), isTrue);
    });

    test('lifetime counts survive log rotation', () async {
      nudge.dispose();
      nudge = await initNudge(clock, maxCapacity: 2);
      for (var i = 0; i < 5; i++) {
        nudge.logEvent('purchase');
      }
      nudge.runMaintenance();

      expect(
        nudge.when().event('purchase').count().equalTo(5).evaluate(),
        isTrue,
      );
      expect(
        nudge
            .when()
            .event('purchase')
            .inLast(const Duration(days: 1))
            .count()
            .equalTo(2)
            .evaluate(),
        isTrue,
        reason: 'filtered counts read the rotated log',
      );
    });
  });

  group('inLast', () {
    test('is measured from the moment of evaluation', () {
      final recent = nudge
          .when()
          .event('workout')
          .inLast(const Duration(days: 7))
          .exists();

      nudge.logEvent('workout');
      expect(recent.evaluate(), isTrue);

      clock.advance(const Duration(days: 7));
      expect(recent.evaluate(), isTrue, reason: 'the bound is inclusive');

      clock.advance(const Duration(milliseconds: 1));
      expect(recent.evaluate(), isFalse);
    });
  });

  group('timestamp', () {
    test('strict and inclusive bounds differ at millisecond precision', () {
      final at = clock.now;
      nudge.logEvent('open');
      final timestamp = nudge.when().event('open').timestamp();

      expect(timestamp.greaterThan(at).count().equalTo(0).evaluate(), isTrue);
      expect(
        timestamp.greaterThanOrEqual(at).count().equalTo(1).evaluate(),
        isTrue,
      );
      expect(timestamp.lessThan(at).count().equalTo(0).evaluate(), isTrue);
      expect(
        timestamp.lessThanOrEqual(at).count().equalTo(1).evaluate(),
        isTrue,
      );
      expect(timestamp.equalTo(at).count().equalTo(1).evaluate(), isTrue);
    });

    test('multiple constraints intersect', () {
      nudge.logEvent('open');
      clock.advance(const Duration(hours: 1));
      nudge.logEvent('open');
      clock.advance(const Duration(hours: 1));
      nudge.logEvent('open');

      final start = clock.now.subtract(const Duration(hours: 2));
      final end = clock.now;
      final middle = nudge
          .when()
          .event('open')
          .timestamp()
          .greaterThan(start)
          .timestamp()
          .lessThan(end)
          .count()
          .equalTo(1);

      expect(middle.evaluate(), isTrue);
    });
  });

  group('where', () {
    setUp(() {
      nudge.logEvent('purchase', {'currency': 'EUR', 'total': 10});
      nudge.logEvent('purchase', {'currency': 'USD', 'total': 25.5});
      nudge.logEvent('purchase', {'total': 40});
    });

    CountClauseBuilder count(EventClause clause) => clause.count();

    test('equalTo and notEqualTo', () {
      final purchase = nudge.when().event('purchase');

      expect(
        count(purchase.where('currency').equalTo('EUR')).equalTo(1).evaluate(),
        isTrue,
      );
      expect(
        count(
          purchase.where('currency').notEqualTo('EUR'),
        ).equalTo(2).evaluate(),
        isTrue,
        reason: 'events without the attribute are not equal to EUR',
      );
    });

    test('numeric comparisons mix int and double values', () {
      final total = nudge.when().event('purchase').where('total');

      expect(count(total.greaterThan(10)).equalTo(2).evaluate(), isTrue);
      expect(count(total.greaterThanOrEqual(10)).equalTo(3).evaluate(), isTrue);
      expect(count(total.lessThan(25.5)).equalTo(1).evaluate(), isTrue);
      expect(count(total.lessThanOrEqual(25.5)).equalTo(2).evaluate(), isTrue);
    });

    test('oneOf, exists and chained predicates', () {
      final purchase = nudge.when().event('purchase');

      expect(
        count(
          purchase.where('currency').oneOf(['EUR', 'USD']),
        ).equalTo(2).evaluate(),
        isTrue,
      );
      expect(
        count(purchase.where('currency').exists()).equalTo(2).evaluate(),
        isTrue,
      );
      expect(
        count(
          purchase.where('currency').exists().where('total').greaterThan(20),
        ).equalTo(1).evaluate(),
        isTrue,
      );
    });
  });

  group('attribute', () {
    test('aggregates numeric values of int and double attributes', () {
      nudge.logEvent('purchase', {'price': 10});
      nudge.logEvent('purchase', {'price': 20.5});
      nudge.logEvent('purchase', {'price': 'free'});
      nudge.logEvent('purchase');
      final price = nudge.when().event('purchase').attribute('price');

      expect(price.sum().equalTo(30.5).evaluate(), isTrue);
      expect(price.avg().equalTo(15.25).evaluate(), isTrue);
      expect(price.min().equalTo(10).evaluate(), isTrue);
      expect(price.max().equalTo(20.5).evaluate(), isTrue);
    });

    test('without values the sum is zero and other aggregates are unmet', () {
      final price = nudge.when().event('purchase').attribute('price');

      expect(price.sum().lessThan(1).evaluate(), isTrue);
      expect(price.avg().lessThan(1).evaluate(), isFalse);
      expect(price.min().lessThan(1).evaluate(), isFalse);
      expect(price.max().lessThan(1).evaluate(), isFalse);
    });

    test('distinct counts different values', () {
      for (final feature in ['search', 'export', 'search', 'share']) {
        nudge.logEvent('feature_used', {'feature': feature});
      }

      expect(
        nudge
            .when()
            .event('feature_used')
            .attribute('feature')
            .distinct()
            .equalTo(3)
            .evaluate(),
        isTrue,
      );
    });
  });

  group('days', () {
    test('activeDays counts distinct local days', () {
      nudge.logEvent('lesson');
      nudge.logEvent('lesson');
      clock.advance(const Duration(days: 1));
      nudge.logEvent('lesson');
      clock.advance(const Duration(days: 3));
      nudge.logEvent('lesson');

      final days = nudge.when().event('lesson').activeDays();
      expect(days.equalTo(3).evaluate(), isTrue);
      expect(
        nudge
            .when()
            .event('lesson')
            .inLast(const Duration(days: 2))
            .activeDays()
            .equalTo(1)
            .evaluate(),
        isTrue,
      );
    });

    test('streak counts consecutive days and breaks after a missed day', () {
      final streak = nudge.when().event('lesson').streak();
      final filteredStreak = nudge
          .when()
          .event('lesson')
          .inLast(const Duration(days: 30))
          .streak();

      for (var day = 0; day < 3; day++) {
        nudge.logEvent('lesson');
        clock.advance(const Duration(days: 1));
      }

      expect(
        streak.equalTo(3).evaluate(),
        isTrue,
        reason: 'yesterday still counts',
      );
      expect(filteredStreak.equalTo(3).evaluate(), isTrue);

      clock.advance(const Duration(days: 1));
      expect(streak.equalTo(0).evaluate(), isTrue);
      expect(filteredStreak.equalTo(0).evaluate(), isTrue);

      nudge.logEvent('lesson');
      expect(streak.equalTo(1).evaluate(), isTrue);
      expect(filteredStreak.equalTo(1).evaluate(), isTrue);
    });
  });

  group('today', () {
    test('follows local midnight at evaluation time', () {
      clock.now = DateTime(2026, 1, 15, 23, 30);
      final today = nudge.when().event('lesson').today().exists();

      nudge.logEvent('lesson');
      expect(today.evaluate(), isTrue);

      clock.advance(const Duration(hours: 1));
      expect(today.evaluate(), isFalse, reason: 'a new day started');
    });
  });

  group('occurrences', () {
    test('lastOccurrence detects inactivity, never met when never seen', () {
      final inactive = nudge
          .when()
          .event('app_open')
          .lastOccurrence()
          .olderThan(const Duration(days: 14));
      expect(inactive.evaluate(), isFalse);

      nudge.logEvent('app_open');
      clock.advance(const Duration(days: 14));
      expect(inactive.evaluate(), isFalse);

      clock.advance(const Duration(seconds: 1));
      expect(inactive.evaluate(), isTrue);

      nudge.logEvent('app_open');
      expect(inactive.evaluate(), isFalse);
    });

    test('firstOccurrence and newerThan', () {
      nudge.logEvent('signup');
      clock.advance(const Duration(days: 2));
      nudge.logEvent('signup');

      final clause = nudge.when().event('signup');
      expect(
        clause.firstOccurrence().olderThan(const Duration(days: 1)).evaluate(),
        isTrue,
      );
      expect(
        clause.lastOccurrence().newerThan(const Duration(hours: 1)).evaluate(),
        isTrue,
      );
    });
  });

  group('app', () {
    test('previousSession measures the time away', () {
      final away = nudge.when().app().previousSession().olderThan(
        const Duration(days: 14),
      );
      expect(away.evaluate(), isFalse, reason: 'no previous session');

      backgroundFor(clock, const Duration(days: 3));
      expect(away.evaluate(), isFalse);

      backgroundFor(clock, const Duration(days: 15));
      expect(away.evaluate(), isTrue);
    });

    test('sessions, first seen and active days', () {
      final app = nudge.when().app();
      expect(app.sessions().equalTo(1).evaluate(), isTrue);
      expect(app.activeDays().equalTo(1).evaluate(), isTrue);
      expect(
        app.firstSeen().olderThan(const Duration(days: 7)).evaluate(),
        isFalse,
      );

      backgroundFor(clock, const Duration(days: 8));

      expect(app.sessions().equalTo(2).evaluate(), isTrue);
      expect(app.activeDays().equalTo(2).evaluate(), isTrue);
      expect(
        app.firstSeen().olderThan(const Duration(days: 7)).evaluate(),
        isTrue,
      );
    });
  });
}
