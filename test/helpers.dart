import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/nudge.dart';

/// A clock that only moves when told to.
class TestClock {
  DateTime now;

  TestClock([DateTime? start]) : now = start ?? DateTime(2026, 1, 15, 12);

  Clock get clock => Clock(() => now);

  void advance(Duration duration) => now = now.add(duration);
}

/// Initializes [Nudge] on an in-memory storage driven by [clock],
/// and disposes it at the end of the test.
Future<Nudge> initNudge(
  TestClock clock, {
  Duration ttl = const Duration(days: 365),
  int maxCapacity = 10000,
  Duration sessionTimeout = const Duration(minutes: 30),
  NudgeStorage? storage,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nudge = await Nudge.initialize(
    storage: storage ?? InMemoryNudgeStorage(),
    clock: clock.clock,
    ttl: ttl,
    maxCapacity: maxCapacity,
    sessionTimeout: sessionTimeout,
    reevaluationInterval: Duration.zero,
  );
  addTearDown(() {
    if (Nudge.isInitialized) Nudge.instance.dispose();
  });
  return nudge;
}

/// Simulates the app going to the background for [duration] and coming back.
void backgroundFor(TestClock clock, Duration duration) {
  final binding = WidgetsBinding.instance;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  clock.advance(duration);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

/// Lets coalesced change notifications reach the watchers.
Future<void> settle() => Future<void>.delayed(Duration.zero);
