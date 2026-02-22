import 'package:objectbox/objectbox.dart';

import 'attribute.dart';

/// An entity representing a tracked analytics event.
@Entity()
class Event {
  /// Auto-incremented primary key.
  @Id()
  int id;

  /// The event name (e.g. "purchase", "sign_up").
  @Index()
  String name;

  /// The timestamp when this event was logged.
  @Index()
  @Property(type: PropertyType.date)
  DateTime timestamp;

  /// The session identifier (UUID generated at app startup).
  @Index()
  String sessionId;

  /// Related attributes for this event.
  final attributes = ToMany<Attribute>();

  Event({
    this.id = 0,
    required this.name,
    required this.timestamp,
    required this.sessionId,
  });
}
