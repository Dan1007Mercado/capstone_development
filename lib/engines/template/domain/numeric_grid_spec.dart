import 'dart:collection';

import 'value_equality.dart';

/// Semantic configuration for a numeric-grid response.
///
/// Validation is intentionally performed by `TemplateValidator` so invalid
/// drafts can produce structured issues rather than constructor exceptions.
final class NumericGridSpec {
  NumericGridSpec({
    required this.columnCount,
    Iterable<int> allowedDigits = const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  }) : allowedDigits = UnmodifiableListView(List.of(allowedDigits));

  final int columnCount;
  final List<int> allowedDigits;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NumericGridSpec &&
          other.columnCount == columnCount &&
          listEqualsByValue(other.allowedDigits, allowedDigits);

  @override
  int get hashCode => Object.hash(columnCount, Object.hashAll(allowedDigits));
}
