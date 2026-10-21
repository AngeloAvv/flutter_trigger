import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

import '../helpers.dart';

void main() {
  late TestClock clock;
  late Nudge nudge;
  late NudgeCondition engaged;

  setUp(() async {
    clock = TestClock();
    nudge = await initNudge(clock);
    engaged = nudge.when().event('core_action').count().greaterThanOrEqual(3);
  });

  void engage() {
    for (var i = 0; i < 3; i++) {
      nudge.logEvent('core_action');
    }
  }

  group('firing', () {
    test('fires only when the condition is met', () {
      final definition = nudge.define('prompt').when(engaged).register();

      expect(definition.isEligible, isFalse);
      expect(nudge.fire('prompt'), isNull);

      engage();
      expect(definition.isEligible, isTrue);

      final fire = nudge.fire('prompt');
      expect(fire, isNotNull);
      expect(fire!.nudgeId, 'prompt');
      expect(fire.firedAt, clock.now);
      expect(
        nudge.when().fired('prompt').count().equalTo(1).evaluate(),
        isTrue,
      );
    });

    test('force fires regardless of eligibility', () {
      nudge.define('prompt').when(engaged).register();

      expect(nudge.fire('prompt', force: true), isNotNull);
    });

    test('unknown nudges are reported', () {
      expect(() => nudge.fire('missing'), throwsArgumentError);
      expect(() => nudge.isEligible('missing'), throwsArgumentError);
    });

    test('a definition needs a condition', () {
      expect(() => nudge.define('prompt').register(), throwsStateError);
    });

    test('registering the same id replaces the definition', () {
      nudge.define('prompt').when(engaged).register();
      nudge
          .define('prompt')
          .when(nudge.when().event('other').exists())
          .register();

      nudge.logEvent('other');
      expect(nudge.isEligible('prompt'), isTrue);
      expect(nudge.nudges.keys, ['prompt']);
    });
  });

  group('policies', () {
    setUp(engage);

    test('cooldown', () {
      nudge
          .define('prompt')
          .when(engaged)
          .cooldown(const Duration(days: 30))
          .register();

      expect(nudge.fire('prompt'), isNotNull);
      expect(nudge.isEligible('prompt'), isFalse);

      clock.advance(const Duration(days: 30));
      expect(nudge.isEligible('prompt'), isFalse);

      clock.advance(const Duration(milliseconds: 1));
      expect(nudge.isEligible('prompt'), isTrue);
    });

    test('maxFires, ever and per period', () {
      nudge.define('ever').when(engaged).maxFires(2).register();
      nudge
          .define('yearly')
          .when(engaged)
          .maxFires(1, per: const Duration(days: 365))
          .register();

      expect(nudge.fire('ever'), isNotNull);
      expect(nudge.fire('ever'), isNotNull);
      expect(nudge.fire('ever'), isNull);

      expect(nudge.fire('yearly'), isNotNull);
      expect(nudge.fire('yearly'), isNull);
      clock.advance(const Duration(days: 366));
      expect(nudge.fire('yearly'), isNotNull);
      expect(nudge.fire('ever'), isNull);
    });

    test('oncePerSession', () {
      nudge.define('tip').when(engaged).oncePerSession().register();

      expect(nudge.fire('tip'), isNotNull);
      expect(nudge.fire('tip'), isNull);

      backgroundFor(clock, const Duration(hours: 1));
      expect(nudge.fire('tip'), isNotNull);
    });

    test('onOutcome disables or cools down by outcome', () {
      nudge
          .define('rating')
          .when(engaged)
          .onOutcome(NudgeOutcome.accepted, disable: true)
          .onOutcome(NudgeOutcome.dismissed, cooldown: const Duration(days: 90))
          .register();

      nudge.fire('rating')!.complete(NudgeOutcome.dismissed);
      expect(nudge.isEligible('rating'), isFalse);

      clock.advance(const Duration(days: 91));
      expect(nudge.isEligible('rating'), isTrue);

      nudge.fire('rating')!.complete(NudgeOutcome.accepted);
      clock.advance(const Duration(days: 3650));
      expect(nudge.isEligible('rating'), isFalse);
    });

    test('a fire without outcome still counts for cooldowns', () {
      nudge
          .define('rating')
          .when(engaged)
          .cooldown(const Duration(days: 7))
          .register();

      nudge.fire('rating');

      expect(nudge.isEligible('rating'), isFalse);
    });

    test('group cooldown and once per session span nudges', () {
      for (final id in ['paywall', 'rating']) {
        nudge
            .define(id)
            .when(engaged)
            .group('interruptive')
            .groupCooldown(const Duration(days: 3))
            .register();
      }
      nudge
          .define('survey')
          .when(engaged)
          .group('soft')
          .groupOncePerSession()
          .register();

      expect(nudge.fire('paywall'), isNotNull);
      expect(nudge.isEligible('rating'), isFalse);

      clock.advance(const Duration(days: 4));
      expect(nudge.isEligible('rating'), isTrue);

      expect(nudge.fire('survey'), isNotNull);
      expect(nudge.isEligible('survey'), isFalse);
    });

    test('group policies need a group', () {
      expect(
        () => nudge
            .define('x')
            .when(engaged)
            .groupCooldown(const Duration(days: 1))
            .register(),
        throwsStateError,
      );
    });

    test('custom policies with require', () {
      nudge
          .define('upsell')
          .when(engaged)
          .require(
            'not premium',
            nudge.when().event('subscribed').exists().not(),
          )
          .register();

      expect(nudge.isEligible('upsell'), isTrue);
      nudge.logEvent('subscribed');
      expect(nudge.isEligible('upsell'), isFalse);
    });

    test('fire history survives log rotation', () async {
      nudge.dispose();
      nudge = await initNudge(clock, maxCapacity: 1);
      engage();
      nudge.define('rating').when(engaged).maxFires(1).register();

      nudge.fire('rating');
      nudge.runMaintenance();

      expect(nudge.isEligible('rating'), isFalse);
    });

    test('resetNudge forgets the fire history', () {
      final definition = nudge
          .define('tip')
          .when(engaged)
          .maxFires(1)
          .register();
      definition.fire();
      expect(definition.isEligible, isFalse);

      definition.reset();
      expect(definition.isEligible, isTrue);
    });

    test('explain names the blocking policy', () {
      nudge
          .define('rating')
          .when(engaged)
          .cooldown(const Duration(days: 30))
          .register();
      nudge.fire('rating');

      final text = nudge.explainNudge('rating').toString();
      expect(text, contains('✗ nudge rating'));
      expect(text, contains('✓ condition'));
      expect(text, contains('✗ cooldown 30d'));
    });
  });

  group('checkpoint', () {
    setUp(engage);

    test('fires the eligible nudge with the highest priority', () {
      nudge.define('low').when(engaged).priority(1).register();
      nudge.define('high').when(engaged).priority(10).register();
      nudge.define('blocked').when(engaged.not()).priority(100).register();

      expect(nudge.checkpoint()?.nudgeId, 'high');
    });

    test('ties go to the nudge registered first', () {
      nudge.define('first').when(engaged).register();
      nudge.define('second').when(engaged).register();

      expect(nudge.checkpoint()?.nudgeId, 'first');
    });

    test('can be restricted to a group or to ids', () {
      nudge.define('a').when(engaged).group('g1').priority(5).register();
      nudge.define('b').when(engaged).group('g2').register();
      nudge.define('c').when(engaged).register();

      expect(nudge.checkpoint(group: 'g2')?.nudgeId, 'b');
      expect(nudge.checkpoint(ids: ['c'])?.nudgeId, 'c');
    });

    test('returns null when nothing is eligible', () {
      nudge.define('a').when(engaged.not()).register();

      expect(nudge.checkpoint(), isNull);
    });

    test('shows at most one prompt per checkpoint with a group cap', () {
      for (final id in ['a', 'b']) {
        nudge
            .define(id)
            .when(engaged)
            .group('modal')
            .groupOncePerSession()
            .register();
      }

      expect(nudge.checkpoint(group: 'modal'), isNotNull);
      expect(nudge.checkpoint(group: 'modal'), isNull);
    });
  });

  group('chaining', () {
    test('a nudge can depend on the outcome of another', () {
      engage();
      nudge.define('nps').when(engaged).maxFires(1).register();
      nudge
          .define('referral')
          .when(
            nudge
                .when()
                .fired('nps')
                .outcome('promoter')
                .lastFired()
                .olderThan(const Duration(days: 1)),
          )
          .maxFires(1)
          .register();

      nudge.fire('nps')!.complete('promoter');
      expect(
        nudge.isEligible('referral'),
        isFalse,
        reason: 'not right after the survey',
      );

      clock.advance(const Duration(days: 2));
      expect(nudge.isEligible('referral'), isTrue);
    });

    test('a detractor outcome does not unlock the chain', () {
      engage();
      nudge.define('nps').when(engaged).register();
      final referral = nudge
          .define('referral')
          .when(nudge.when().fired('nps').outcome('promoter').exists())
          .register();

      nudge.fire('nps')!.complete('detractor');

      expect(referral.isEligible, isFalse);
    });
  });

  group('streams and switches', () {
    test('fires and outcomes are broadcast', () async {
      engage();
      nudge.define('prompt').when(engaged).register();
      final fires = expectLater(
        nudge.fires.map((fire) => fire.nudgeId),
        emits('prompt'),
      );
      final outcomes = expectLater(
        nudge.outcomes.map((fire) => fire.outcome),
        emits(NudgeOutcome.accepted),
      );

      nudge.fire('prompt')!.complete(NudgeOutcome.accepted);

      await fires;
      await outcomes;
    });

    test('nothing fires and nothing is logged while disabled', () {
      nudge.define('prompt').when(engaged).register();
      nudge.enabled = false;

      engage();
      expect(nudge.when().event('core_action').exists().evaluate(), isFalse);

      nudge.enabled = true;
      engage();
      nudge.enabled = false;
      expect(nudge.fire('prompt'), isNull);
      expect(nudge.checkpoint(), isNull);
      expect(nudge.isEligible('prompt'), isFalse);
    });

    test('watchEligible follows policies', () async {
      engage();
      final definition = nudge
          .define('prompt')
          .when(engaged)
          .cooldown(const Duration(days: 1))
          .register();
      final values = <bool>[];
      final subscription = definition.watchEligible().listen(values.add);
      await settle();

      definition.fire();
      await settle();
      await subscription.cancel();

      expect(values, [true, false]);
    });
  });
}
