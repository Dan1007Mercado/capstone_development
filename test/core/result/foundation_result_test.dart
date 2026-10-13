import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/core/result/validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ValidationResult', () {
    test('is valid when empty or warning-only', () {
      final empty = ValidationResult();
      final warningOnly = ValidationResult([
        ValidationIssue(
          code: 'MARGIN_SMALL',
          message: 'The margin is small.',
          severity: ValidationSeverity.warning,
        ),
      ]);

      expect(empty.isValid, isTrue);
      expect(empty.hasErrors, isFalse);
      expect(warningOnly.isValid, isTrue);
      expect(warningOnly.warnings, hasLength(1));
    });

    test('reports structured errors', () {
      final issue = ValidationIssue(
        code: 'FIELD_REQUIRED',
        message: 'A value is required.',
        severity: ValidationSeverity.error,
        path: 'template.name',
        metadata: const {'minimumLength': 1},
      );
      final result = ValidationResult([issue]);

      expect(result.isValid, isFalse);
      expect(result.hasErrors, isTrue);
      expect(result.errors, [issue]);
      expect(issue.metadata['minimumLength'], 1);
    });

    test('merges results without mutating either input', () {
      final warning = ValidationResult([
        ValidationIssue(
          code: 'WARNING',
          message: 'Review this value.',
          severity: ValidationSeverity.warning,
        ),
      ]);
      final error = ValidationResult([
        ValidationIssue(
          code: 'ERROR',
          message: 'This value is invalid.',
          severity: ValidationSeverity.error,
        ),
      ]);

      final merged = warning.merge(error);
      final combined = ValidationResult.combine([warning, error]);

      expect(merged.issues, hasLength(2));
      expect(combined.issues, hasLength(2));
      expect(warning.issues, hasLength(1));
      expect(error.issues, hasLength(1));
    });

    test('issue fields cannot be blank', () {
      expect(
        () => ValidationIssue(
          code: ' ',
          message: 'Message',
          severity: ValidationSeverity.error,
        ),
        throwsArgumentError,
      );
      expect(
        () => ValidationIssue(
          code: 'CODE',
          message: ' ',
          severity: ValidationSeverity.error,
        ),
        throwsArgumentError,
      );
    });
  });

  group('EngineResult', () {
    test('exposes a successful value', () {
      final result = EngineResult<int>.success(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.value, 42);
      expect(result.errorOrNull, isNull);
    });

    test('exposes a structured failure', () {
      final error = EngineError(
        code: 'ENGINE_FAILED',
        message: 'The operation failed.',
        details: const {'stage': 'validation'},
      );
      final result = EngineResult<int>.failure(error);

      expect(result.isFailure, isTrue);
      expect(result.error, same(error));
      expect(result.valueOrNull, isNull);
      expect(error.details['stage'], 'validation');
      expect(() => result.value, throwsStateError);
    });

    test('error code and message cannot be blank', () {
      expect(
        () => EngineError(code: '', message: 'Failure'),
        throwsArgumentError,
      );
      expect(
        () => EngineError(code: 'FAILED', message: ' '),
        throwsArgumentError,
      );
    });
  });
}
