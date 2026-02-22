import 'package:flutter/material.dart';
import 'package:flutter_trigger/flutter_trigger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterTrigger.initialize(ttl: Duration(days: 90), maxCapacity: 1000);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  void _logEvent() {
    FlutterTrigger.instance.logEvent('event');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      title: Text('Flutter Trigger Example'),
    ),
    body: Center(
      child: TriggerBuilder(
        condition: FlutterTrigger.instance
            .when()
            .event('event')
            .count()
            .greaterThan(5),
        builder: (context, triggered) => switch (triggered) {
          true => const Text('Event triggered!'),
          false => const Text('Waiting for events...'),
        },
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _logEvent,
      tooltip: 'Increment',
      child: const Icon(Icons.add),
    ),
  );
}
