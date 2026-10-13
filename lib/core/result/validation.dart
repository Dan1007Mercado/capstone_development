import 'dart:collection';

enum ValidationSeverity { warning, error }

/// One structured finding from validating domain or engine input.
final class ValidationIssue {
  ValidationIssue({
    required this.code,
    required this.message,
    required this.severity,
    this.path,
    Map<String, Object?> metadata = const {},
  }) : metadata = UnmodifiableMapView(Map.of(metadata)) {
    if (code.trim().isEmpty) {
      throw ArgumentError.value(code, 'code', 'Code cannot be blank.');
    }
    if (message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', 'Message cannot be blank.');
    }
    if (path != null && path!.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Path cannot be blank.');
    }
  }

  final String code;
  final String message;
  final ValidationSeverity severity;
  final String? path;
  final Map<String, Object?> metadata;
}

/// Immutable collection of structured validation findings.
final class ValidationResult {
  ValidationResult([Iterable<ValidationIssue> issues = const []])
    : issues = UnmodifiableListView(List.of(issues));

  final List<ValidationIssue> issues;

  bool get hasErrors =>
      issues.any((issue) => issue.severity == ValidationSeverity.error);

  bool get isValid => !hasErrors;

  List<ValidationIssue> get errors => UnmodifiableListView(
    issues
        .where((issue) => issue.severity == ValidationSeverity.error)
        .toList(growable: false),
  );

  List<ValidationIssue> get warnings => UnmodifiableListView(
    issues
        .where((issue) => issue.severity == ValidationSeverity.warning)
        .toList(growable: false),
  );

  ValidationResult merge(ValidationResult other) =>
      ValidationResult([...issues, ...other.issues]);

  static ValidationResult combine(Iterable<ValidationResult> results) =>
      ValidationResult(results.expand((result) => result.issues));
}
