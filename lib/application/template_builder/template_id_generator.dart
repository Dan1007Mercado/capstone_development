import 'dart:math';

import '../../core/ids/identifiers.dart';

abstract interface class TemplateIdGenerator {
  TemplateId generate();
}

/// Generates offline, name-independent 128-bit template identities.
final class RandomTemplateIdGenerator implements TemplateIdGenerator {
  RandomTemplateIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  TemplateId generate() {
    final buffer = StringBuffer('tmpl-');
    for (var index = 0; index < 16; index++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return TemplateId(buffer.toString());
  }
}
