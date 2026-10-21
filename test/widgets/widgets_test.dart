import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

import '../helpers.dart';

/// Rebuilds its child on demand, to simulate parents rebuilding.
class _Rebuilder extends StatefulWidget {
  final Widget Function() builder;

  const _Rebuilder({super.key, required this.builder});

  @override
  State<_Rebuilder> createState() => _RebuilderState();
}

class _RebuilderState extends State<_Rebuilder> {
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.builder();
}

void main() {
  late TestClock clock;
  late Nudge nudge;

  setUp(() async {
    clock = TestClock();
    nudge = await initNudge(clock);
  });

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: child));

  group('NudgeBuilder', () {
    testWidgets('shows the current value on the first frame', (tester) async {
      nudge.logEvent('pro_click');

      await pump(
        tester,
        NudgeBuilder(
          condition: nudge.when().event('pro_click').exists(),
          builder: (context, value) => Text(value ? 'banner' : 'none'),
        ),
      );

      expect(find.text('banner'), findsOneWidget);
    });

    testWidgets('rebuilds when the condition changes', (tester) async {
      await pump(
        tester,
        NudgeBuilder(
          condition: nudge.when().event('pro_click').exists(),
          builder: (context, value) => Text(value ? 'banner' : 'none'),
        ),
      );
      expect(find.text('none'), findsOneWidget);

      nudge.logEvent('pro_click');
      await tester.pump();

      expect(find.text('banner'), findsOneWidget);
    });
  });

  group('NudgeListener', () {
    testWidgets('a parent rebuild with an inline condition does not call '
        'onChanged again', (tester) async {
      nudge.logEvent('milestone');
      final calls = <bool>[];
      final key = GlobalKey<_RebuilderState>();

      await pump(
        tester,
        _Rebuilder(
          key: key,
          builder: () => NudgeListener(
            condition: nudge.when().event('milestone').exists(),
            onChanged: (context, value) => calls.add(value),
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();

      key.currentState!.rebuild();
      await tester.pump();
      key.currentState!.rebuild();
      await tester.pump();

      expect(calls, [true]);
    });

    testWidgets('skipInitialValue reports changes only', (tester) async {
      final calls = <bool>[];

      await pump(
        tester,
        NudgeListener(
          condition: nudge.when().event('milestone').exists(),
          skipInitialValue: true,
          onChanged: (context, value) => calls.add(value),
          child: const SizedBox(),
        ),
      );
      await tester.pump();
      nudge.logEvent('milestone');
      await tester.pump();

      expect(calls, [true]);
    });
  });

  group('NudgeFireListener', () {
    testWidgets('fires once per session across rebuilds and remounts', (
      tester,
    ) async {
      final definition = nudge
          .define('celebration')
          .when(nudge.when().event('milestone').exists())
          .oncePerSession()
          .register();
      final fires = <NudgeFire>[];
      final key = GlobalKey<_RebuilderState>();

      Widget listener() => _Rebuilder(
        key: key,
        builder: () => NudgeFireListener(
          nudge: definition,
          onFire: (context, fire) => fires.add(fire),
          child: const SizedBox(),
        ),
      );

      await pump(tester, listener());
      await tester.pump();
      expect(fires, isEmpty);

      nudge.logEvent('milestone');
      await tester.pump();
      expect(fires, hasLength(1));

      key.currentState!.rebuild();
      await tester.pump();
      await pump(tester, const SizedBox());
      await pump(tester, listener());
      await tester.pump();
      expect(fires, hasLength(1));

      backgroundFor(clock, const Duration(hours: 1));
      await tester.pump();
      expect(fires, hasLength(2));
    });
  });
}
