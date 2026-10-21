import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

import '../helpers.dart';

void main() {
  late TestClock clock;
  late Nudge nudge;

  setUp(() async {
    clock = TestClock();
    nudge = await initNudge(clock);
  });

  test('a short background stay keeps the session', () {
    final first = nudge.sessionId;

    backgroundFor(clock, const Duration(minutes: 29));

    expect(nudge.sessionId, first);
  });

  test('returning after the timeout starts a new session', () {
    final first = nudge.sessionId;

    backgroundFor(clock, const Duration(minutes: 30));

    expect(nudge.sessionId, isNot(first));
    expect(nudge.when().app().sessions().equalTo(2).evaluate(), isTrue);
  });

  test('current and other follow the session at evaluation time', () {
    // Built before the session changes: conditions do not capture it.
    final current = nudge.when().event('click').session().current().count();
    final other = nudge.when().event('click').session().other().count();

    nudge.logEvent('click');
    nudge.logEvent('click');
    expect(current.equalTo(2).evaluate(), isTrue);
    expect(other.equalTo(0).evaluate(), isTrue);

    backgroundFor(clock, const Duration(hours: 1));
    nudge.logEvent('click');

    expect(current.equalTo(1).evaluate(), isTrue);
    expect(other.equalTo(2).evaluate(), isTrue);
  });

  test('session count counts distinct sessions of the event', () {
    final sessions = nudge.when().event('login').session().count();

    nudge.logEvent('login');
    nudge.logEvent('login');
    expect(sessions.equalTo(1).evaluate(), isTrue);

    backgroundFor(clock, const Duration(hours: 1));
    nudge.logEvent('login');
    backgroundFor(clock, const Duration(hours: 1));

    expect(sessions.equalTo(2).evaluate(), isTrue);
    expect(
      nudge
          .when()
          .event('login')
          .inLast(const Duration(minutes: 90))
          .session()
          .count()
          .equalTo(1)
          .evaluate(),
      isTrue,
    );
  });
}
