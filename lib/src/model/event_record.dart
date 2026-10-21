/// An immutable event as stored in the local log.
class EventRecord {
  /// Monotonic identifier assigned by the storage. It reflects insertion
  /// order, which is the order events actually happened in, even when two
  /// events share the same millisecond or the device clock moves backwards.
  final int id;

  /// The event name, e.g. `purchase`.
  final String name;

  /// When the event was logged, with millisecond precision.
  final DateTime timestamp;

  /// The session the event was logged in.
  final String sessionId;

  /// The sanitized metadata attached to the event. Values are `String`,
  /// `int`, `double` or `bool`.
  final Map<String, Object> attributes;

  const EventRecord({
    this.id = 0,
    required this.name,
    required this.timestamp,
    required this.sessionId,
    this.attributes = const {},
  });

  EventRecord copyWith({int? id}) => EventRecord(
    id: id ?? this.id,
    name: name,
    timestamp: timestamp,
    sessionId: sessionId,
    attributes: attributes,
  );

  @override
  String toString() =>
      'EventRecord(#$id $name @ ${timestamp.toIso8601String()}, '
      'session: $sessionId, attributes: $attributes)';
}
