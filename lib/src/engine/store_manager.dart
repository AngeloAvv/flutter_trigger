import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../objectbox.g.dart';

/// Manages the ObjectBox [Store] lifecycle for the package.
///
/// This is an internal singleton — consumers interact via [FlutterTrigger].
class StoreManager {
  Store? _store;

  /// Whether the store is currently open.
  bool get isOpen => _store != null;

  /// The underlying ObjectBox [Store].
  ///
  /// Throws [StateError] if accessed before [initialize] or after [close].
  Store get store {
    final s = _store;
    if (s == null) {
      throw StateError(
        'ObjectBox Store is not initialized. '
        'Call FlutterTrigger.initialize() first.',
      );
    }
    return s;
  }

  /// Opens the ObjectBox store.
  ///
  /// On Flutter, the store is placed inside the app's documents directory.
  Future<Store> initialize() async {
    if (_store != null) return _store!;

    final dir = await getApplicationDocumentsDirectory();
    final storePath = '${dir.path}/flutter_trigger_objectbox';

    _store = await openStore(directory: storePath);
    debugPrint('[FlutterTrigger] ObjectBox store opened at $storePath');
    return _store!;
  }

  /// Closes the ObjectBox store and releases resources.
  void close() {
    _store?.close();
    _store = null;
  }
}
