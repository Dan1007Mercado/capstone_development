/// Base class for stable semantic identifiers.
abstract class SemanticId {
  const SemanticId._(this.value);

  /// The trimmed, non-empty identifier value.
  final String value;

  static String normalize(String value, String typeName) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', '$typeName cannot be blank.');
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is SemanticId &&
          other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType($value)';
}

final class TemplateId extends SemanticId {
  factory TemplateId(String value) =>
      TemplateId._(SemanticId.normalize(value, 'TemplateId'));

  const TemplateId._(super.value) : super._();
}

final class PageId extends SemanticId {
  factory PageId(String value) =>
      PageId._(SemanticId.normalize(value, 'PageId'));

  const PageId._(super.value) : super._();
}

final class PacketId extends SemanticId {
  factory PacketId(String value) =>
      PacketId._(SemanticId.normalize(value, 'PacketId'));

  factory PacketId.fromSequence(int sequence) {
    if (sequence < 0 || sequence > 999) {
      throw RangeError.range(sequence, 0, 999, 'sequence');
    }
    final body = sequence.toString().padLeft(3, '0');
    final checksum = ((sequence * 2654435761) & 0xffff)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(4, '0');
    return PacketId._('P$body-$checksum');
  }

  const PacketId._(super.value) : super._();

  int get sequence {
    final match = RegExp(r'^P([0-9]{3})-[0-9A-F]{4}$').firstMatch(value);
    if (match == null) {
      throw StateError('PacketId is not a generated packet identity.');
    }
    return int.parse(match.group(1)!);
  }
}

final class ResponseId extends SemanticId {
  factory ResponseId(String value) =>
      ResponseId._(SemanticId.normalize(value, 'ResponseId'));

  factory ResponseId.fromSequence(int sequence) {
    if (sequence < 1) throw RangeError.range(sequence, 1, null, 'sequence');
    return ResponseId._('R${sequence.toString().padLeft(6, '0')}');
  }

  const ResponseId._(super.value) : super._();
}

final class SectionId extends SemanticId {
  factory SectionId(String value) =>
      SectionId._(SemanticId.normalize(value, 'SectionId'));

  const SectionId._(super.value) : super._();
}

final class QuestionId extends SemanticId {
  factory QuestionId(String value) =>
      QuestionId._(SemanticId.normalize(value, 'QuestionId'));

  const QuestionId._(super.value) : super._();
}

final class OptionId extends SemanticId {
  factory OptionId(String value) =>
      OptionId._(SemanticId.normalize(value, 'OptionId'));

  const OptionId._(super.value) : super._();
}

/// One-based immutable version of a published template.
final class TemplateVersion {
  factory TemplateVersion(int value) {
    if (value < 1) {
      throw RangeError.range(value, 1, null, 'value');
    }
    return TemplateVersion._(value);
  }

  const TemplateVersion._(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateVersion && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TemplateVersion($value)';
}
