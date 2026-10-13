/// Optional non-OMR field printed for human-readable information.
final class HumanReadableTextField {
  const HumanReadableTextField({required this.label, this.instruction});

  final String label;
  final String? instruction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HumanReadableTextField &&
          other.label == label &&
          other.instruction == instruction;

  @override
  int get hashCode => Object.hash(label, instruction);
}
