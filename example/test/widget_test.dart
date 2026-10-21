import 'package:example/main.dart';
import 'package:example/nudges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

void main() {
  setUp(() async {
    final nudge = await Nudge.initialize(
      storage: InMemoryNudgeStorage(),
      reevaluationInterval: Duration.zero,
    );
    registerNudges(nudge);
  });

  tearDown(() => Nudge.instance.dispose());

  testWidgets('asks for a rating after the third order, once per session', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    for (var order = 1; order <= 2; order++) {
      await tester.tap(find.byKey(const Key('complete_order')));
      await tester.pumpAndSettle();
      expect(find.byType(RatingDialog), findsNothing);
    }

    await tester.tap(find.byKey(const Key('complete_order')));
    await tester.pumpAndSettle();
    expect(find.byType(RatingDialog), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('complete_order')));
    await tester.pumpAndSettle();
    expect(find.byType(RatingDialog), findsNothing);
  });

  testWidgets('shows the big spender banner past 100', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Thanks for being a great customer!'), findsNothing);

    for (var order = 0; order < 3; order++) {
      Nudge.instance.logEvent(Events.orderCompleted, {'total': 42.5});
    }
    await tester.pump();

    expect(find.text('Thanks for being a great customer!'), findsOneWidget);
  });
}
