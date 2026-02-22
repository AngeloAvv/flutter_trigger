import 'dart:async';
import 'package:flutter/widgets.dart';
import '../builder/trigger_condition.dart';

/// A widget that listens to a [TriggerCondition] and executes a callback
/// whenever the condition's state changes.
///
/// This widget does not rebuild its child when the trigger changes.
/// Use [TriggerWidgetBuilder] for UI rebuilds.
class TriggerListener extends StatefulWidget {
  /// The condition to watch.
  final TriggerCondition condition;

  /// Callback executed whenever the condition state changes (true/false).
  final void Function(BuildContext context, bool value) onTrigger;

  /// The child widget.
  final Widget child;

  const TriggerListener({
    super.key,
    required this.condition,
    required this.onTrigger,
    required this.child,
  });

  @override
  State<TriggerListener> createState() => _TriggerListenerState();
}

class _TriggerListenerState extends State<TriggerListener> {
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(TriggerListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition != widget.condition) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.condition.watch().listen((value) {
      if (mounted) {
        widget.onTrigger(context, value);
      }
    });
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
