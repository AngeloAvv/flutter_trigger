import 'package:flutter/widgets.dart';
import '../builder/trigger_condition.dart';

/// A widget that rebuilds itself whenever a [TriggerCondition] state changes.
///
/// Similar to [StreamBuilder], but optimized for the flutter_trigger SDK.
class TriggerBuilder extends StatefulWidget {
  /// The condition to watch.
  final TriggerCondition condition;

  /// The builder function that creates a widget based on the current trigger state.
  final Widget Function(BuildContext context, bool value) builder;

  const TriggerBuilder({
    super.key,
    required this.condition,
    required this.builder,
  });

  @override
  State<TriggerBuilder> createState() => _TriggerBuilderState();
}

class _TriggerBuilderState extends State<TriggerBuilder> {
  bool _lastValue = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: widget.condition.watch(),
      initialData: _lastValue,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _lastValue = snapshot.data!;
        }
        return widget.builder(context, _lastValue);
      },
    );
  }
}
