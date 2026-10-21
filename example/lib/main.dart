import 'package:flutter/material.dart';
import 'package:nudge/nudge.dart';

import 'nudges.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final nudge = await Nudge.initialize(
    ttl: const Duration(days: 90),
    maxCapacity: 1000,
  );
  registerNudges(nudge);

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'nudge example',
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
    home: const ShopPage(),
  );
}

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  Nudge get _nudge => Nudge.instance;

  Future<void> _completeOrder(BuildContext context) async {
    _nudge.logEvent(Events.orderCompleted, {'total': 42.5});

    // A natural pause: the order is done, the user is not in the middle of
    // a task. Ask the engine whether an interruptive prompt is due.
    final fire = _nudge.checkpoint(group: 'interruptive');
    if (fire == null || !context.mounted) return;

    final rated = await showDialog<bool>(
      context: context,
      builder: (context) => const RatingDialog(),
    );
    // With the real OS dialog the outcome is not observable: report
    // NudgeOutcome.unknown there.
    fire.complete(
      rated == true ? NudgeOutcome.accepted : NudgeOutcome.dismissed,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('nudge example')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NudgeBuilder(
          condition: bigSpender(_nudge),
          builder: (context, isBigSpender) => isBigSpender
              ? const Card(
                  child: ListTile(
                    leading: Icon(Icons.star),
                    title: Text('Thanks for being a great customer!'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        FilledButton(
          key: const Key('complete_order'),
          onPressed: () => _completeOrder(context),
          child: const Text('Complete an order'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _nudge.logEvent(Events.orderFailed),
          child: const Text('Fail an order'),
        ),
        const SizedBox(height: 24),
        const Text('Why is the rating prompt (not) eligible?'),
        const SizedBox(height: 8),
        const _Explanation(),
      ],
    ),
  );
}

/// Shows the live explanation of the rating prompt eligibility.
class _Explanation extends StatelessWidget {
  const _Explanation();

  @override
  Widget build(BuildContext context) {
    final nudge = Nudge.instance;
    final eligibility = nudge.nudges[Nudges.ratingPrompt]!.eligibility;

    return NudgeBuilder(
      // Rebuilds on eligibility changes; the explanation is recomputed then.
      condition: eligibility,
      builder: (context, _) => Text(
        nudge.explain(eligibility).toString(),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }
}

/// Stands in for the OS review dialog, which apps cannot customize.
class RatingDialog extends StatelessWidget {
  const RatingDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enjoying the app?'),
    content: const Text('In a real app, call the in-app review API here.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Not now'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Rate'),
      ),
    ],
  );
}
