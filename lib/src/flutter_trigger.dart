import 'dart:async';

import 'package:flutter/foundation.dart';
import 'models/event.dart';
import 'models/attribute.dart';
import 'engine/store_manager.dart';
import 'engine/maintenance_service.dart';
import 'engine/session_manager.dart';
import 'builder/base_trigger_builder.dart';
import 'builder/event_selector.dart';

/// The singleton facade for the flutter_trigger package.
///
/// ## Quick Start
/// ```dart
/// // Initialize (once at app startup)
/// final trigger = await FlutterTrigger.initialize();
///
/// // Log events
/// trigger.logEvent('purchase', {'price': 29.99, 'category': 'electronics'});
///
/// // Define reactive triggers
/// trigger.when()
///   .event('purchase')
///   .count()
///   .greaterThan(5)
///   .watch()
///   .listen((triggered) {
///     if (triggered) print('5+ purchases!');
///   });
///
/// // Clean up
/// trigger.dispose();
/// ```
class FlutterTrigger {
  static FlutterTrigger? _instance;

  final StoreManager _storeManager;
  final SessionManager _sessionManager;
  late final BaseTriggerBuilder _triggerBuilder;

  FlutterTrigger._(this._storeManager, this._sessionManager) {
    _triggerBuilder = BaseTriggerBuilder(
      store: _storeManager.store,
      sessionId: _sessionManager.sessionId,
    );
  }

  /// Returns the current [FlutterTrigger] instance.
  ///
  /// Throws [StateError] if [initialize] has not been called.
  static FlutterTrigger get instance {
    if (_instance == null) {
      throw StateError(
        'FlutterTrigger is not initialized. '
        'Call FlutterTrigger.initialize() first.',
      );
    }

    return _instance!;
  }

  /// Whether the [FlutterTrigger] instance has been initialized.
  static bool get isInitialized => _instance != null;

  /// The unique session identifier generated at initialization.
  String get sessionId => _sessionManager.sessionId;

  /// Initializes the [FlutterTrigger] singleton.
  ///
  /// - [ttl]: Duration after which events are considered expired and deleted
  ///   (default: 365 days).
  /// - [maxCapacity]: Maximum number of events to keep (default: 10,000).
  ///   Older events are bulk-deleted when this limit is exceeded.
  ///
  /// Log rotation runs asynchronously 2 seconds after initialization.
  ///
  /// Returns the initialized [FlutterTrigger] instance.
  static Future<FlutterTrigger> initialize({
    Duration ttl = const Duration(days: 365),
    int maxCapacity = 10000,
  }) async {
    if (_instance != null) return _instance!;

    final storeManager = StoreManager();
    await storeManager.initialize();

    final sessionManager = SessionManager();
    final trigger = FlutterTrigger._(storeManager, sessionManager);
    _instance = trigger;

    debugPrint(
      '[FlutterTrigger] Initialized with sessionId: ${sessionManager.sessionId}',
    );

    // Schedule maintenance asynchronously after 2 seconds.
    Future.delayed(const Duration(seconds: 2), () {
      final maintenance = MaintenanceService(
        storeManager.store,
        ttl: ttl,
        maxCapacity: maxCapacity,
      );
      maintenance.run().catchError((error) {
        debugPrint('[FlutterTrigger] Maintenance error: $error');
      });
    });

    return trigger;
  }

  // ---------------------------------------------------------------------------
  // Data Ingestion
  // ---------------------------------------------------------------------------

  /// Logs an event with the given [name] and optional [metadata].
  ///
  /// Each entry in [metadata] is automatically mapped to an [Attribute]:
  /// - [String] → `stringValue`
  /// - [int] → `intValue`
  /// - [double] → `doubleValue`
  /// - [bool] → `boolValue`
  ///
  /// Throws [ArgumentError] if a metadata value has an unsupported type.
  void logEvent(String name, [Map<String, dynamic>? metadata]) {
    final store = _storeManager.store;

    final event = Event(
      name: name,
      timestamp: DateTime.now(),
      sessionId: _sessionManager.sessionId,
    );

    // Map metadata entries to Attribute entities.
    if (metadata != null) {
      for (final entry in metadata.entries) {
        final attribute = Attribute.fromEntry(entry.key, entry.value);
        event.attributes.add(attribute);
      }
    }

    store.box<Event>().put(event);
  }

  // ---------------------------------------------------------------------------
  // Fluent API
  // ---------------------------------------------------------------------------

  /// Entry point for the trigger fluent API / DSL.
  ///
  /// Returns an [EventSelector] that allows chaining to define count-based,
  /// attribute-based, or funnel triggers.
  EventSelector when() => _triggerBuilder.when();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Closes the ObjectBox store and releases all resources.
  ///
  /// After calling this, the singleton is reset and [initialize] must be
  /// called again to use [FlutterTrigger].
  void dispose() {
    _storeManager.close();
    _instance = null;
    debugPrint('[FlutterTrigger] Disposed.');
  }
}
