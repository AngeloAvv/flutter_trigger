import 'package:nudge/nudge.dart';

/// Event names used across the example.
abstract final class Events {
  static const orderCompleted = 'order_completed';
  static const orderFailed = 'order_failed';
}

/// Nudge ids used across the example.
abstract final class Nudges {
  static const ratingPrompt = 'rating_prompt_v1';
}

/// Registers the example nudges.
///
/// The rating prompt follows Apple's and Google's guidance: only after the
/// user completed a few orders, never right after a failure, at most three
/// times a year, never again once the user accepted.
void registerNudges(Nudge nudge) {
  nudge
      .define(Nudges.ratingPrompt)
      .when(
        nudge
            .when()
            .event(Events.orderCompleted)
            .count()
            .greaterThanOrEqual(3)
            .and(
              nudge
                  .when()
                  .event(Events.orderFailed)
                  .session()
                  .current()
                  .exists()
                  .not(),
            ),
      )
      .group('interruptive')
      .groupOncePerSession()
      .cooldown(const Duration(days: 30))
      .maxFires(3, per: const Duration(days: 365))
      .onOutcome(NudgeOutcome.accepted, disable: true)
      .register();
}

/// Met once the user spent at least 100 overall.
NudgeCondition bigSpender(Nudge nudge) => nudge
    .when()
    .event(Events.orderCompleted)
    .attribute('total')
    .sum()
    .greaterThanOrEqual(100);
