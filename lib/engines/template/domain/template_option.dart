import '../../../core/ids/identifiers.dart';

/// One semantic response option, without printable geometry.
final class TemplateOption {
  TemplateOption({required this.id, required this.label, this.value}) {
    final semanticValue = value;
    if (!_isSupportedValue(semanticValue)) {
      throw ArgumentError.value(
        semanticValue,
        'value',
        'Semantic values must be null, String, num, or bool.',
      );
    }
    if (semanticValue is double && !semanticValue.isFinite) {
      throw ArgumentError.value(
        semanticValue,
        'value',
        'Numeric values must be finite.',
      );
    }
  }

  final OptionId id;
  final String label;

  /// A contained primitive semantic value for scales and coded responses.
  ///
  /// Primitive `Object?` keeps early template values flexible without exposing
  /// `dynamic` or accepting mutable domain state.
  final Object? value;

  static bool _isSupportedValue(Object? value) =>
      value == null || value is String || value is num || value is bool;

  TemplateOption copyWith({String? label, Object? value = _unchanged}) =>
      TemplateOption(
        id: id,
        label: label ?? this.label,
        value: identical(value, _unchanged) ? this.value : value,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateOption &&
          other.id == id &&
          other.label == label &&
          other.value == value;

  @override
  int get hashCode => Object.hash(id, label, value);

  static const Object _unchanged = Object();
}
