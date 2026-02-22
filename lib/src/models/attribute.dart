import 'package:objectbox/objectbox.dart';

import 'attribute_type.dart';

/// An entity representing a typed key-value attribute attached to an [Event].
///
/// Each attribute stores its value in exactly one of the nullable typed fields,
/// determined by [typeIndex].
@Entity()
class Attribute {
  /// Auto-incremented primary key.
  @Id()
  int id;

  /// The attribute key name.
  @Index()
  String key;

  /// Index into [AttributeType] indicating which typed field holds the value.
  int typeIndex;

  /// Stores the value when [typeIndex] == [AttributeType.string].
  String? stringValue;

  /// Stores the value when [typeIndex] == [AttributeType.integer].
  int? intValue;

  /// Stores the value when [typeIndex] == [AttributeType.number].
  double? doubleValue;

  /// Stores the value (as 0/1) when [typeIndex] == [AttributeType.boolean].
  bool? boolValue;

  Attribute({
    this.id = 0,
    required this.key,
    required this.typeIndex,
    this.stringValue,
    this.intValue,
    this.doubleValue,
    this.boolValue,
  });

  /// Returns the stored value based on [typeIndex].
  dynamic get value {
    switch (AttributeType.fromIndex(typeIndex)) {
      case AttributeType.string:
        return stringValue;
      case AttributeType.integer:
        return intValue;
      case AttributeType.number:
        return doubleValue;
      case AttributeType.boolean:
        return boolValue;
    }
  }

  /// Creates an [Attribute] from a key and a dynamic Dart value.
  ///
  /// Supports [String], [int], [double], and [bool].
  /// Throws [ArgumentError] for unsupported types.
  factory Attribute.fromEntry(String key, dynamic value) {
    if (value is String) {
      return Attribute(
        key: key,
        typeIndex: AttributeType.string.index,
        stringValue: value,
      );
    } else if (value is int) {
      return Attribute(
        key: key,
        typeIndex: AttributeType.integer.index,
        intValue: value,
      );
    } else if (value is double) {
      return Attribute(
        key: key,
        typeIndex: AttributeType.number.index,
        doubleValue: value,
      );
    } else if (value is bool) {
      return Attribute(
        key: key,
        typeIndex: AttributeType.boolean.index,
        boolValue: value,
      );
    } else {
      throw ArgumentError(
        'Unsupported attribute type: ${value.runtimeType}. '
        'Supported types are: String, int, double, bool.',
      );
    }
  }
}
