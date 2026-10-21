import 'dart:async';

import 'package:flutter/widgets.dart';

import '../dsl/nudge_condition.dart';

/// Rebuilds whenever a [NudgeCondition] changes.
///
/// The first frame already shows the current value: conditions are evaluated
/// synchronously, so there is no flash of the `false` state.
///
/// ```dart
/// NudgeBuilder(
///   condition: nudge.when().event('pro_feature_click').count().greaterThan(3),
///   builder: (context, active) =>
///       active ? const DiscountBanner() : const SizedBox.shrink(),
/// )
/// ```
class NudgeBuilder extends StatefulWidget {
  /// The condition to watch. Conditions are compared by value, so building
  /// it inline in a parent's `build` does not resubscribe.
  final NudgeCondition condition;

  /// Builds the widget for the current value of [condition].
  final Widget Function(BuildContext context, bool value) builder;

  const NudgeBuilder({
    super.key,
    required this.condition,
    required this.builder,
  });

  @override
  State<NudgeBuilder> createState() => _NudgeBuilderState();
}

class _NudgeBuilderState extends State<NudgeBuilder> {
  StreamSubscription<bool>? _subscription;
  bool _value = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NudgeBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition != widget.condition) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _value = widget.condition.evaluate();
    _subscription = widget.condition.watch().listen((value) {
      if (mounted && value != _value) setState(() => _value = value);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
