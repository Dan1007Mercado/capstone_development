import '../errors/engine_error.dart';

/// A small typed success/failure result for engine operations.
final class EngineResult<T> {
  const EngineResult._({T? value, EngineError? error})
    : _value = value,
      _error = error;

  factory EngineResult.success(T value) => EngineResult._(value: value);

  factory EngineResult.failure(EngineError error) =>
      EngineResult._(error: error);

  final T? _value;
  final EngineError? _error;

  bool get isSuccess => _error == null;
  bool get isFailure => !isSuccess;

  T get value {
    if (isFailure) {
      throw StateError('A failed EngineResult has no value.');
    }
    return _value as T;
  }

  EngineError get error {
    if (isSuccess) {
      throw StateError('A successful EngineResult has no error.');
    }
    return _error!;
  }

  T? get valueOrNull => isSuccess ? _value : null;
  EngineError? get errorOrNull => _error;
}
