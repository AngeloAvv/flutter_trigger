/// Enum representing the type of value stored in an [Attribute].
enum AttributeType {
  /// A [String] value.
  string,

  /// An [int] value.
  integer,

  /// A [double] value.
  number,

  /// A [bool] value.
  boolean;

  /// Returns the [AttributeType] for the given [index].
  static AttributeType fromIndex(int index) => AttributeType.values[index];
}
