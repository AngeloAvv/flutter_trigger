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

  void log(List<String> names, {Duration gap = const Duration(minutes: 1)}) {
    for (final name in names) {
      nudge.logEvent(name);
      clock.advance(gap);
    }
  }

  test('is met when the steps happen in order', () {
    final funnel = nudge.when().funnel(['view', 'cart', 'buy']).loose();

    log(['view', 'cart']);
    expect(funnel.evaluate(), isFalse);

    log(['buy']);
    expect(funnel.evaluate(), isTrue);
  });

  test('is not met when the steps happen in another order', () {
    log(['buy', 'cart', 'view']);

    expect(nudge.when().funnel(['view', 'cart', 'buy']).evaluate(), isFalse);
  });

  test('tolerates other events and repeated steps in between', () {
    log(['view', 'other', 'view', 'cart', 'other', 'buy']);

    expect(nudge.when().funnel(['view', 'cart', 'buy']).evaluate(), isTrue);
  });

  test('steps logged in the same millisecond keep their order', () {
    nudge.logEvent('add_to_cart');
    nudge.logEvent('checkout');

    expect(nudge.when().funnel(['add_to_cart', 'checkout']).evaluate(), isTrue);
    expect(
      nudge.when().funnel(['checkout', 'add_to_cart']).evaluate(),
      isFalse,
    );
  });

  test('a repeated step needs two occurrences', () {
    final funnel = nudge.when().funnel(['lesson', 'lesson']);

    log(['lesson']);
    expect(funnel.evaluate(), isFalse);

    log(['lesson']);
    expect(funnel.evaluate(), isTrue);
  });

  test('stays met once completed, even if the last step happens again', () {
    final funnel = nudge
        .when()
        .funnel(['view', 'buy'])
        .within(const Duration(hours: 1));

    log(['view', 'buy']);
    expect(funnel.evaluate(), isTrue);

    clock.advance(const Duration(days: 1));
    log(['buy']);
    expect(funnel.evaluate(), isTrue);
  });

  test('within requires every step close to the first one', () {
    final funnel = nudge
        .when()
        .funnel(['view', 'cart', 'buy'])
        .timestamp()
        .within(const Duration(hours: 1));

    log(['view', 'cart'], gap: const Duration(minutes: 40));
    log(['buy']);
    expect(funnel.evaluate(), isFalse, reason: '80 minutes from first step');

    log(['view', 'cart', 'buy'], gap: const Duration(minutes: 10));
    expect(funnel.evaluate(), isTrue, reason: 'a later attempt fits');
  });

  test('session().same() requires every step in the current session', () {
    final sameSession = nudge
        .when()
        .funnel(['view', 'checkout'])
        .loose()
        .session()
        .same();

    log(['view']);
    backgroundFor(clock, const Duration(hours: 1));
    log(['checkout']);

    expect(sameSession.evaluate(), isFalse);
    expect(nudge.when().funnel(['view', 'checkout']).evaluate(), isTrue);

    log(['view', 'checkout']);
    expect(sameSession.evaluate(), isTrue);
  });

  test('session().single() requires one session, whichever it is', () {
    final single = nudge
        .when()
        .funnel(['search', 'purchase'])
        .session()
        .single();

    log(['search']);
    backgroundFor(clock, const Duration(hours: 1));
    log(['purchase']);
    expect(single.evaluate(), isFalse);

    log(['search', 'purchase']);
    backgroundFor(clock, const Duration(hours: 1));
    expect(single.evaluate(), isTrue, reason: 'completed in a past session');
  });

  test('session().other() ignores the current session', () {
    final other = nudge.when().funnel(['a', 'b']).session().other();

    log(['a', 'b']);
    expect(other.evaluate(), isFalse);

    backgroundFor(clock, const Duration(hours: 1));
    expect(other.evaluate(), isTrue);
  });

  test('absolute time constraints apply to every step', () {
    log(['onboard']);
    final cutoff = clock.now;
    log(['invite']);

    final funnel = nudge.when().funnel(['onboard', 'invite']);
    expect(funnel.timestamp().greaterThanOrEqual(cutoff).evaluate(), isFalse);
    expect(funnel.timestamp().lessThan(cutoff).evaluate(), isFalse);
    expect(funnel.evaluate(), isTrue);
  });

  test('inLast only considers recent steps', () {
    log(['view']);
    clock.advance(const Duration(days: 10));
    log(['buy']);

    final funnel = nudge.when().funnel(['view', 'buy']);
    expect(funnel.inLast(const Duration(days: 7)).evaluate(), isFalse);
    expect(funnel.inLast(const Duration(days: 30)).evaluate(), isTrue);
  });

  test('an empty funnel is never met and does not throw', () {
    final funnel = nudge.when().funnel([]);

    expect(funnel.evaluate(), isFalse);
    expect(funnel.dropOff(after: const Duration(hours: 1)).evaluate(), isFalse);
  });

  test('a single-step funnel is met by one occurrence', () {
    log(['signup']);

    expect(nudge.when().funnel(['signup']).evaluate(), isTrue);
  });

  group('dropOff', () {
    late NudgeCondition abandoned;

    setUp(() {
      abandoned = nudge
          .when()
          .funnel(['add_to_cart', 'purchase'])
          .dropOff(after: const Duration(hours: 24));
    });

    test('is not met before the funnel starts', () {
      expect(abandoned.evaluate(), isFalse);
    });

    test('is met once the grace period passes without completion', () {
      log(['add_to_cart']);
      expect(abandoned.evaluate(), isFalse);

      clock.advance(const Duration(hours: 24));
      expect(abandoned.evaluate(), isTrue);
    });

    test('is not met when the funnel is completed', () {
      log(['add_to_cart', 'purchase']);
      clock.advance(const Duration(days: 2));

      expect(abandoned.evaluate(), isFalse);
    });

    test('looks at the most recent start', () {
      log(['add_to_cart', 'purchase']);
      clock.advance(const Duration(days: 2));
      log(['add_to_cart']);
      expect(abandoned.evaluate(), isFalse);

      clock.advance(const Duration(days: 1));
      expect(abandoned.evaluate(), isTrue);
    });
  });

  test('explain reports the progress', () {
    log(['view', 'cart']);

    final result = nudge.when().funnel(['view', 'cart', 'buy']).explain();

    expect(result.value, isFalse);
    expect(result.description, contains('progress 2/3'));
  });
}
