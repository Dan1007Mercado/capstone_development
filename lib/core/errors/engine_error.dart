import 'dart:collection';

/// Structured failure information shared by engine boundaries.
final class EngineError {
  EngineError({
    required this.code,
    required this.message,
    Map<String, Object?> details = const {},
  }) : details = UnmodifiableMapView(Map.of(details)) {
    if (code.trim().isEmpty) {
      throw ArgumentError.value(code, 'code', 'Code cannot be blank.');
    }
    if (message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', 'Message cannot be blank.');
    }
  }

  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'EngineError(code: $code, message: $message)';
}
