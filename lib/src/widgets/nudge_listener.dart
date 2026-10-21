import 'dart:async';

import 'package:flutter/widgets.dart';

import '../dsl/nudge_condition.dart';

/// Calls [onChanged] whenever a [NudgeCondition] changes, without
/// rebuilding [child].
///
/// [onChanged] receives the value on every change. The value the condition
/// has when the listener subscribes is delivered too, unless
/// [skipInitialValue] is set.
///
/// For one-off actions such as dialogs prefer `NudgeFireListener`, which
/// records each fire and honours cooldowns and caps across launches. A plain
/// condition has no memory: if it is true at every launch, [onChanged] is
/// called with `true` at every launch.
class NudgeListener extends StatefulWidget {
  /// The condition to watch. Conditions are compared by value, so building
  /// it inline in a parent's `build` does not resubscribe.
  final NudgeCondition condition;

  /// Called with the new value of [condition].
  final void Function(BuildContext context, bool value) onChanged;

  /// Whether the value at subscription time is skipped.
  final bool skipInitialValue;

  final Widget child;

  const NudgeListener({
    super.key,
    required this.condition,
    required this.onChanged,
    this.skipInitialValue = false,
    required this.child,
  });

  @override
  State<NudgeListener> createState() => _NudgeListenerState();
}

class _NudgeListenerState extends State<NudgeListener> {
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NudgeListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition != widget.condition) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    var skip = widget.skipInitialValue;
    _subscription = widget.condition.watch().listen((value) {
      if (skip) {
        skip = false;
        return;
      }
      if (mounted) widget.onChanged(context, value);
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
