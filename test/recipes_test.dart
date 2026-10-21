// The recipes published in docs/recipes, verified end to end. Keep the code
// of each `register…` function identical to its documentation page.
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

import 'helpers.dart';

// docs/recipes/rating-prompt.mdx
void registerRatingPrompt(Nudge nudge) {
  nudge
      .define('rating_prompt_v1')
      .when(
        NudgeCondition.all([
          // Experienced the app: a week since install, five sessions…
          nudge.when().app().firstSeen().olderThan(const Duration(days: 7)),
          nudge.when().app().sessions().greaterThanOrEqual(5),
          // …and succeeded at its core task a few times
          nudge.when().event('order_completed').count().greaterThanOrEqual(3),
          // Never right after something went wrong
          nudge.when().event('error').session().current().exists().not(),
        ]),
      )
      .group('interruptive')
      .groupOncePerSession()
      .cooldown(const Duration(days: 14))
      .maxFires(3, per: const Duration(days: 365))
      .register();
}

// docs/recipes/paywall.mdx
void registerPaywall(Nudge nudge) {
  nudge
      .define('export_paywall')
      .when(
        nudge
            .when()
            .event('export_attempted')
            .where('premium')
            .equalTo(true)
            .inLast(const Duration(days: 7))
            .count()
            .greaterThanOrEqual(3),
      )
      .group('interruptive')
      .groupOncePerSession()
      .cooldown(const Duration(hours: 1))
      .maxFires(2, per: const Duration(days: 1))
      .onOutcome(NudgeOutcome.accepted, disable: true)
      .register();
}

// docs/recipes/onboarding.mdx
const onboardingSteps = [
  'onboarding_started',
  'profile_completed',
  'first_project_created',
];

void registerOnboarding(Nudge nudge) {
  final onboarding = nudge.when().funnel(onboardingSteps);

  nudge
      .define('onboarding_nudge')
      .when(
        onboarding
            .dropOff(after: const Duration(days: 1))
            .and(nudge.when().app().sessions().greaterThanOrEqual(2)),
      )
      .cooldown(const Duration(days: 3))
      .maxFires(2)
      .register();

  nudge
      .define('onboarding_celebration')
      .when(onboarding.within(const Duration(days: 7)))
      .maxFires(1)
      .register();
}

// docs/recipes/abandoned-cart.mdx
void registerAbandonedCart(Nudge nudge) {
  nudge
      .define('cart_reminder')
      .when(
        nudge
            .when()
            .funnel(['add_to_cart', 'purchase'])
            .dropOff(after: const Duration(minutes: 30)),
      )
      .cooldown(const Duration(days: 1))
      .register();
}

// docs/recipes/feature-discovery.mdx
void registerFeatureDiscovery(Nudge nudge) {
  nudge
      .define('tip_saved_filters')
      .when(
        NudgeCondition.all([
          // Activated users only
          nudge.when().event('search').count().greaterThanOrEqual(10),
          // Who never used the feature
          nudge.when().event('saved_filter_used').exists().not(),
          // And are in the right context right now
          nudge
              .when()
              .event('screen_view')
              .where('screen')
              .equalTo('search')
              .session()
              .current()
              .count()
              .greaterThanOrEqual(2),
        ]),
      )
      .group('tips')
      .groupOncePerSession()
      .maxFires(3)
      .onOutcome(NudgeOutcome.accepted, disable: true)
      .register();
}

// docs/recipes/streaks.mdx
void registerStreaks(Nudge nudge) {
  final lessons = nudge.when().event('lesson_completed');

  for (final days in [3, 7, 30]) {
    nudge
        .define('streak_milestone_$days')
        .when(lessons.streak().greaterThanOrEqual(days))
        .maxFires(1)
        .register();
  }

  nudge
      .define('streak_at_risk')
      .when(
        lessons
            .streak()
            .greaterThanOrEqual(2)
            .and(lessons.today().exists().not()),
      )
      .oncePerSession()
      .cooldown(const Duration(hours: 12))
      .register();
}

// docs/recipes/win-back.mdx
void registerWinBack(Nudge nudge) {
  nudge
      .define('welcome_back')
      .when(
        nudge.when().app().previousSession().olderThan(
          const Duration(days: 14),
        ),
      )
      .oncePerSession()
      .cooldown(const Duration(days: 30))
      .register();
}

// docs/recipes/push-permission.mdx
void registerPushPrePrompt(Nudge nudge) {
  nudge
      .define('push_pre_prompt')
      .when(
        nudge
            .when()
            .app()
            .sessions()
            .greaterThanOrEqual(2)
            .and(
              nudge
                  .when()
                  .event('order_completed')
                  .session()
                  .current()
                  .exists(),
            ),
      )
      .group('interruptive')
      .groupOncePerSession()
      .onOutcome(NudgeOutcome.accepted, disable: true)
      .onOutcome(NudgeOutcome.dismissed, cooldown: const Duration(days: 14))
      .maxFires(4)
      .register();
}

// docs/recipes/nps-and-referral.mdx
void registerNpsAndReferral(Nudge nudge) {
  nudge
      .define('nps_survey')
      .when(
        nudge
            .when()
            .app()
            .firstSeen()
            .olderThan(const Duration(days: 30))
            .and(nudge.when().app().activeDays().greaterThanOrEqual(10)),
      )
      .group('interruptive')
      .groupOncePerSession()
      .cooldown(const Duration(days: 90))
      .onOutcome('later', cooldown: const Duration(days: 7))
      .register();

  final survey = nudge.when().fired('nps_survey');
  nudge
      .define('referral_ask')
      .when(
        survey
            .outcome('promoter')
            .inLast(const Duration(days: 30))
            .exists()
            // Never in the same session as the survey
            .and(survey.inCurrentSession().exists().not()),
      )
      .group('interruptive')
      .groupOncePerSession()
      .maxFires(1)
      .register();
}

// docs/recipes/activation.mdx
void registerActivation(Nudge nudge) {
  nudge
      .define('activation_celebration')
      .when(
        nudge
            .when()
            .event('task_completed')
            .count()
            .greaterThanOrEqual(10)
            .and(nudge.when().app().activeDays().greaterThanOrEqual(3)),
      )
      .maxFires(1)
      .register();
}

// docs/recipes/guest-to-account.mdx
void registerGuestToAccount(Nudge nudge) {
  nudge
      .define('create_account_nudge')
      .when(
        NudgeCondition.all([
          nudge.when().app().firstSeen().olderThan(const Duration(days: 2)),
          nudge.when().event('note_created').count().greaterThanOrEqual(3),
          nudge.when().event('signed_in').exists().not(),
        ]),
      )
      .cooldown(const Duration(days: 7))
      .maxFires(3)
      .onOutcome(NudgeOutcome.accepted, disable: true)
      .register();
}

// docs/recipes/frequency-capping.mdx
void registerFrequencyCapping(
  Nudge nudge, {
  required NudgeCondition pushCondition,
  required NudgeCondition paywallCondition,
  required NudgeCondition ratingCondition,
}) {
  const interruptive = 'interruptive';

  nudge
      .define('push_pre_prompt')
      .when(pushCondition)
      .group(interruptive)
      .priority(30)
      .groupOncePerSession()
      .groupCooldown(const Duration(days: 1))
      .register();

  nudge
      .define('export_paywall')
      .when(paywallCondition)
      .group(interruptive)
      .priority(20)
      .groupOncePerSession()
      .groupCooldown(const Duration(days: 1))
      .register();

  nudge
      .define('rating_prompt_v1')
      .when(ratingCondition)
      .group(interruptive)
      .priority(10)
      .groupOncePerSession()
      .groupCooldown(const Duration(days: 1))
      .register();
}

void main() {
  late TestClock clock;
  late Nudge nudge;

  setUp(() async {
    clock = TestClock();
    nudge = await initNudge(clock);
  });

  void newSession([Duration away = const Duration(hours: 1)]) =>
      backgroundFor(clock, away);

  void times(int count, String name, [Map<String, Object?>? metadata]) {
    for (var i = 0; i < count; i++) {
      nudge.logEvent(name, metadata);
    }
  }

  test('rating prompt', () {
    registerRatingPrompt(nudge);
    times(3, 'order_completed');
    expect(nudge.isEligible('rating_prompt_v1'), isFalse, reason: 'new user');

    for (var day = 0; day < 8; day++) {
      newSession(const Duration(days: 1));
    }
    expect(nudge.isEligible('rating_prompt_v1'), isTrue);

    nudge.logEvent('error');
    expect(nudge.isEligible('rating_prompt_v1'), isFalse);

    newSession();
    expect(nudge.checkpoint(group: 'interruptive'), isNotNull);
    expect(nudge.isEligible('rating_prompt_v1'), isFalse, reason: 'cooldown');

    newSession(const Duration(days: 15));
    expect(nudge.isEligible('rating_prompt_v1'), isTrue);
  });

  test('frequency capping', () {
    final always = nudge.when().app().sessions().greaterThanOrEqual(1);
    registerFrequencyCapping(
      nudge,
      pushCondition: nudge.when().event('order_completed').exists(),
      paywallCondition: always,
      ratingCondition: always,
    );

    expect(nudge.checkpoint(group: 'interruptive')?.nudgeId, 'export_paywall');
    expect(nudge.checkpoint(group: 'interruptive'), isNull, reason: 'session');

    newSession();
    expect(nudge.checkpoint(group: 'interruptive'), isNull, reason: '1 day');

    newSession(const Duration(days: 1));
    nudge.logEvent('order_completed');
    expect(nudge.checkpoint(group: 'interruptive')?.nudgeId, 'push_pre_prompt');
  });

  test('paywall', () {
    registerPaywall(nudge);
    times(2, 'export_attempted', {'premium': true});
    times(3, 'export_attempted', {'premium': false});
    expect(nudge.isEligible('export_paywall'), isFalse);

    times(1, 'export_attempted', {'premium': true});
    final fire = nudge.fire('export_paywall');
    expect(fire, isNotNull);
    fire!.complete(NudgeOutcome.dismissed);

    newSession(const Duration(hours: 2));
    expect(nudge.fire('export_paywall'), isNotNull);
    newSession(const Duration(hours: 2));
    expect(nudge.isEligible('export_paywall'), isFalse, reason: '2 per day');
  });

  test('onboarding', () {
    registerOnboarding(nudge);
    nudge.logEvent('onboarding_started');
    nudge.logEvent('profile_completed');

    newSession(const Duration(days: 1));
    expect(nudge.isEligible('onboarding_nudge'), isTrue);
    expect(nudge.isEligible('onboarding_celebration'), isFalse);

    nudge.logEvent('onboarding_started');
    nudge.logEvent('profile_completed');
    nudge.logEvent('first_project_created');
    expect(nudge.isEligible('onboarding_nudge'), isFalse);
    expect(nudge.isEligible('onboarding_celebration'), isTrue);
  });

  test('abandoned cart', () {
    registerAbandonedCart(nudge);
    nudge.logEvent('add_to_cart');
    clock.advance(const Duration(minutes: 31));
    expect(nudge.isEligible('cart_reminder'), isTrue);

    nudge.logEvent('purchase');
    expect(nudge.isEligible('cart_reminder'), isFalse);
  });

  test('feature discovery', () {
    registerFeatureDiscovery(nudge);
    times(10, 'search');
    times(2, 'screen_view', {'screen': 'search'});
    expect(nudge.isEligible('tip_saved_filters'), isTrue);

    nudge.fire('tip_saved_filters')!.complete(NudgeOutcome.accepted);
    newSession();
    times(2, 'screen_view', {'screen': 'search'});
    expect(nudge.isEligible('tip_saved_filters'), isFalse);
  });

  test('streaks', () {
    registerStreaks(nudge);
    for (var day = 0; day < 3; day++) {
      nudge.logEvent('lesson_completed');
      clock.advance(const Duration(days: 1));
    }

    expect(nudge.isEligible('streak_milestone_3'), isTrue);
    expect(nudge.isEligible('streak_milestone_7'), isFalse);
    expect(nudge.isEligible('streak_at_risk'), isTrue);

    nudge.logEvent('lesson_completed');
    expect(nudge.isEligible('streak_at_risk'), isFalse);
  });

  test('win-back', () {
    registerWinBack(nudge);
    newSession(const Duration(days: 2));
    expect(nudge.isEligible('welcome_back'), isFalse);

    newSession(const Duration(days: 20));
    expect(nudge.fire('welcome_back'), isNotNull);
    expect(nudge.isEligible('welcome_back'), isFalse);
  });

  test('push permission pre-prompt', () {
    registerPushPrePrompt(nudge);
    nudge.logEvent('order_completed');
    expect(nudge.isEligible('push_pre_prompt'), isFalse, reason: 'session 1');

    newSession();
    nudge.logEvent('order_completed');
    nudge.fire('push_pre_prompt')!.complete(NudgeOutcome.dismissed);

    newSession(const Duration(days: 15));
    nudge.logEvent('order_completed');
    nudge.fire('push_pre_prompt')!.complete(NudgeOutcome.accepted);

    newSession(const Duration(days: 60));
    nudge.logEvent('order_completed');
    expect(nudge.isEligible('push_pre_prompt'), isFalse);
  });

  test('NPS and referral', () {
    registerNpsAndReferral(nudge);
    for (var day = 0; day < 31; day++) {
      newSession(const Duration(days: 1));
    }

    nudge.checkpoint(group: 'interruptive')!.complete('promoter');
    expect(nudge.isEligible('referral_ask'), isFalse, reason: 'same session');

    newSession();
    expect(nudge.checkpoint(group: 'interruptive')?.nudgeId, 'referral_ask');
  });

  test('activation', () {
    registerActivation(nudge);
    times(10, 'task_completed');
    expect(nudge.isEligible('activation_celebration'), isFalse);

    newSession(const Duration(days: 1));
    newSession(const Duration(days: 1));
    expect(nudge.isEligible('activation_celebration'), isTrue);
  });

  test('guest to account', () {
    registerGuestToAccount(nudge);
    times(3, 'note_created');
    expect(nudge.isEligible('create_account_nudge'), isFalse);

    newSession(const Duration(days: 3));
    expect(nudge.isEligible('create_account_nudge'), isTrue);

    nudge.logEvent('signed_in');
    expect(nudge.isEligible('create_account_nudge'), isFalse);
  });
}
