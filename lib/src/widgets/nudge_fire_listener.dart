import 'dart:async';

import 'package:flutter/widgets.dart';

import '../nudges/nudge_definition.dart';

/// Fires a registered nudge as soon as it becomes eligible while this
/// widget is mounted, and calls [onFire] with the fire.
///
/// The fire is recorded before [onFire] runs, so cooldowns, caps and
/// once-per-session policies apply across rebuilds and launches. Report what
/// the user did with [NudgeFire.complete].
///
/// ```dart
/// NudgeFireListener(
///   nudge: ratingPrompt,
///   onFire: (context, fire) async {
///     await InAppReview.instance.requestReview();
///     fire.complete(NudgeOutcome.unknown);
///   },
///   child: const HomePage(),
/// )
/// ```
class NudgeFireListener extends StatefulWidget {
  /// The nudge to fire. It must be registered.
  final NudgeDefinition nudge;

  /// Called after the nudge fired.
  final void Function(BuildContext context, NudgeFire fire) onFire;

  final Widget child;

  const NudgeFireListener({
    super.key,
    required this.nudge,
    required this.onFire,
    required this.child,
  });

  @override
  State<NudgeFireListener> createState() => _NudgeFireListenerState();
}

class _NudgeFireListenerState extends State<NudgeFireListener> {
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NudgeFireListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nudge.id != widget.nudge.id) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.nudge.watchEligible().listen((eligible) {
      if (!eligible || !mounted) return;

      final fire = widget.nudge.fire();
      if (fire != null) widget.onFire(context, fire);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
