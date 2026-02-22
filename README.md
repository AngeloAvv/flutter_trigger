# flutter_trigger

A local-first, reactive trigger engine for Flutter. Empower your app with sophisticated, event-driven logic without the latency or privacy concerns of cloud-based solutions.

[![Pub](https://img.shields.io/pub/v/flutter_trigger.svg)](https://pub.dev/packages/flutter_trigger)
![Pipeline](https://github.com/AngeloAvv/flutter_trigger/workflows/Pipeline/badge.svg)
[![Star on GitHub](https://img.shields.io/github/stars/AngeloAvv/flutter_trigger.svg?style=flat&logo=github&colorB=deeppink&label=stars)](https://github.com/AngeloAvv/flutter_trigger)
[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-purple.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
[![](https://img.shields.io/static/v1?label=Sponsor&message=%E2%9D%A4&logo=GitHub&color=%23fe8e86)](https://github.com/sponsors/AngeloAvv)

## Why flutter_trigger?

*   **Privacy First**: All behavior data stays on the device. No event tracking is sent to external servers.
*   **Zero Latency**: Triggers are evaluated locally, ensuring sub-millisecond reactions.
*   **Reactive DSL**: A powerful, fluent API to define complex conditions (counts, aggregates, funnels) that react in real-time.
*   **Resource Efficient**: Built-in log rotation and automatic cleanup to keep your app's footprint small.

## Use Cases

*   **Smart Prompts**: Show a "Rate our App" dialog only after the user has successfully completed 5 "core_action" events across at least 2 sessions.
*   **Paywalls**: Trigger a subscription offer when the sum of "feature_usage" duration exceeds a specific threshold.
*   **Onboarding**: Detect when a user is "stuck" in a funnel (e.g., started signup but didn't finish within 24 hours).
*   **Feature Discovery**: Show a tooltip for a premium feature after a user has used related free features multiple times.

---

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_trigger: latest_version
```

Then run:

```bash
flutter pub get
```

---

## Initialization

Initialize the SDK once at app startup. You can configure the **Log Rotation** settings to control data retention.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with custom rotation settings
  await FlutterTrigger.initialize(
    ttl: Duration(days: 90),     // Keep events for 90 days
    maxCapacity: 5000,           // Keep at most 5,000 events
  );

  runApp(MyApp());
}
```

---

## Event Logging

Logging is extremely lightweight. You can log simple events or include rich metadata.

```dart
final trigger = FlutterTrigger.instance;

// Simple event
trigger.logEvent('app_open');

// Event with metadata
trigger.logEvent('purchase', {
  'item_id': 'premium_sub_01',
  'price': 29.99,
  'currency': 'USD',
  'is_first_purchase': true,
});
```

### Supported Attributes
The SDK supports the following attribute types:

- String
- int
- double
- bool

---

## The DSL (Deep Dive)

The core of `flutter_trigger` is its fluent API. Every trigger results in a `Stream<bool>` that you can `.watch()`.

### 1. Counting Events
Check how many times an event has occurred.

```dart
final trigger = FlutterTrigger.instance;

// "Has the user performed 'share' more than 5 times?"
final condition = trigger.when()
  .event('share')
  .count()
  .greaterThan(5);

condition.watch().listen((triggered) {
  if (triggered) print('Power user detected!');
});
```

### 2. Attribute Aggregates
Perform math on event metadata over time.

```dart
// "Is the total sum of 'price' for 'purchase' events greater than 100?"
final bigSpender = trigger.when()
  .event('purchase')
  .attribute('price')
  .sum()
  .greaterThan(100.0);

// Available aggregates: .sum(), .avg(), .min(), .max()
```

### 3. Session & Time Modifiers
Refine your search by session or timestamp.

```dart
// Events in the current app launch only
trigger.when()
  .event('click')
  .session()
  .current()
  .count()
  .greaterThan(2);

// Events NOT in the current session
trigger.when()
  .event('ad_view')
  .session()
  .other()
  .count()
  .greaterThan(0);

// Event occurred in more than 5 distinct sessions (great for retention triggers)
trigger.when()
  .event('login')
  .session()
  .count()
  .greaterThan(5);

// Timestamp filtering
final lastWeek = DateTime.now().subtract(Duration(days: 7));
trigger.when()
  .event('login')
  .timestamp()
  .greaterThan(lastWeek);
```

### 4. Loose Funnels
Verify a sequence of events occurred in chronological order. Both `.session()` and `.timestamp()` are optional modifiers — omit them to match across all sessions and all time.

```dart
// Minimal — steps in order, no constraint
trigger.when()
  .funnel(['sign_up', 'first_purchase'])
  .loose()
  .watch();

// Rolling time window: all steps within 24 h of each other
trigger.when()
  .funnel(['view_item', 'add_to_cart', 'checkout'])
  .loose()
  .timestamp().within(Duration(hours: 24))
  .watch();

// Absolute timestamp: every step must have occurred after a date
trigger.when()
  .funnel(['onboard', 'invite_friend'])
  .loose()
  .timestamp().greaterThan(DateTime(2025))
  .watch();

// Session scope: all steps in the current session
trigger.when()
  .funnel(['view_item', 'checkout'])
  .loose()
  .session().same()
  .watch();

// Session + time window combined
trigger.when()
  .funnel(['search', 'purchase'])
  .loose()
  .session().same()
  .timestamp().within(Duration(minutes: 30))
  .watch();
```

### 5. Logical Composition
Combine multiple triggers using standard Boolean logic.

```dart
final isHeavyUser = trigger.when().event('use_feature').count().greaterThan(10);
final hasPurchased = trigger.when().event('purchase').count().greaterThan(0);

// User is heavy BUT hasn't purchased yet
final targetAudience = isHeavyUser.and(hasPurchased.not());

// OR composition
final engagedUser = isHeavyUser.or(hasPurchased);
```

---

## Flutter UI Components

`flutter_trigger` provides native widgets to bridge the engine with your UI.

### TriggerBuilder
A reactive widget that rebuilds whenever the condition state changes.

```dart
TriggerBuilder(
  condition: trigger.when().event('pro_feature_click').count().greaterThan(3),
  builder: (context, triggered) {
    return Column(
      children: [
        if (triggered) DiscountBanner(),
        FeatureWidget(),
      ],
    );
  },
)
```

### TriggerListener
Use this for one-off actions like navigation, showing dialogs, or triggering snackbars. It does **not** rebuild the UI.

```dart
TriggerListener(
  condition: trigger.when().event('milestone_reached').count().equalTo(1),
  onTrigger: (context, triggered) {
    if (triggered) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CelebrationScreen()));
    }
  },
  child: MyScaffold(),
)
```

---

## Best Practices

*   **Initialization**: Always call `await FlutterTrigger.initialize()` before accessing `FlutterTrigger.instance`.
*   **Watch Cleanup**: If you manually call `.watch().listen(...)`, remember to cancel the `StreamSubscription` to prevent memory leaks.
*   **Disposal**: When the app is shutting down or you no longer need the SDK, call `trigger.dispose()` to safely close the underlying storage.
*   **Unique IDs**: Use clear, consistent event names and attribute keys across your app to ensure trigger logic remains robust as the app evolves.

---

## License

flutter_trigger is available under the GNU General Public License Version 3. See the COPYING file for more info.