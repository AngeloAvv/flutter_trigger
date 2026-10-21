# nudge

A local-first nudge engine for Flutter. Log behavioural events on device, describe conditions with
a fluent DSL, and fire rate prompts, upsells and tips at the right moment — with cooldowns, caps,
outcomes and chaining.

[![Pub](https://img.shields.io/pub/v/nudge.svg)](https://pub.dev/packages/nudge)
![Pipeline](https://github.com/AngeloAvv/nudge/workflows/Pipeline/badge.svg)
[![Star on GitHub](https://img.shields.io/github/stars/AngeloAvv/nudge.svg?style=flat&logo=github&colorB=deeppink&label=stars)](https://github.com/AngeloAvv/nudge)
[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-purple.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
[![](https://img.shields.io/static/v1?label=Sponsor&message=%E2%9D%A4&logo=GitHub&color=%23fe8e86)](https://github.com/sponsors/AngeloAvv)

**📖 Documentation: [docs.page/AngeloAvv/nudge](https://docs.page/AngeloAvv/nudge)**

## Why

Every app ends up writing the same logic by hand: _ask for a review after the third successful
order, but not right after an error, and not more than three times a year_. `nudge` turns
it into declarations, evaluated on device:

```dart
final nudge = await Nudge.initialize();

// Log behaviour
nudge.logEvent('order_completed', {'total': 42.5});

// Declare a nudge and its policies
nudge
    .define('rating_prompt')
    .when(
      nudge.when().event('order_completed').count().greaterThanOrEqual(3)
          .and(nudge.when().event('error').session().current().exists().not()),
    )
    .group('interruptive')
    .groupOncePerSession()
    .cooldown(const Duration(days: 14))
    .maxFires(3, per: const Duration(days: 365))
    .register();

// At a natural pause, ask the engine
final fire = nudge.checkpoint(group: 'interruptive');
if (fire != null) {
  await InAppReview.instance.requestReview();
  fire.complete(NudgeOutcome.unknown);
}
```

## Features

- **Local-first**: events stay on device (ObjectBox); evaluation is synchronous
- **Fluent conditions**: counts, attribute filters and aggregates, distinct sessions, active days,
  streaks, recency and inactivity, install age, loose funnels with windows and drop-off
- **Nudges with memory**: cooldowns, caps, once per session, group caps and priorities,
  outcome-based policies — persisted across launches
- **Chaining**: nudges can depend on other nudges' fires and outcomes
- **Explainable**: `explainNudge(id)` shows which part of a condition or policy is blocking
- **Testable**: in-memory storage and an injectable clock
- **Widgets**: `NudgeBuilder`, `NudgeListener`, `NudgeFireListener`

## Installation

```yaml
dependencies:
  nudge: ^0.1.0
```

Supported platforms: Android, iOS, macOS, Linux, Windows.

## Learn more

- [Getting started](https://docs.page/AngeloAvv/nudge/getting-started)
- [Core concepts](https://docs.page/AngeloAvv/nudge/concepts)
- [Recipes](https://docs.page/AngeloAvv/nudge/recipes): rating prompt, paywall,
  onboarding, abandoned cart, feature discovery, streaks, win-back, push permission, NPS and
  referral, activation, guest to account, frequency capping

## License

nudge is available under the GNU General Public License Version 3. See the LICENSE file
for more info.
