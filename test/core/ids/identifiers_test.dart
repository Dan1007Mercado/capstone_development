import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('semantic identifiers', () {
    test('trim and store valid values', () {
      expect(TemplateId('  template-1  ').value, 'template-1');
      expect(PageId('page-1').value, 'page-1');
      expect(SectionId('section-1').value, 'section-1');
      expect(QuestionId('question-1').value, 'question-1');
      expect(OptionId('option-1').value, 'option-1');
    });

    test('reject blank values', () {
      expect(() => TemplateId('   '), throwsArgumentError);
      expect(() => QuestionId('\n\t'), throwsArgumentError);
    });

    test('compare by normalized value and concrete type', () {
      expect(TemplateId(' abc '), TemplateId('abc'));
      expect(TemplateId('abc').hashCode, TemplateId('abc').hashCode);
      expect(TemplateId('abc'), isNot(PageId('abc')));
    });

    test('provide useful string representations', () {
      expect(OptionId('a').toString(), 'OptionId(a)');
    });
  });

  group('TemplateVersion', () {
    test('accepts one-based versions', () {
      expect(TemplateVersion(1).value, 1);
      expect(TemplateVersion(2), TemplateVersion(2));
      expect(TemplateVersion(2).toString(), 'TemplateVersion(2)');
    });

    test('rejects zero', () {
      expect(() => TemplateVersion(0), throwsRangeError);
    });

    test('rejects negative values', () {
      expect(() => TemplateVersion(-1), throwsRangeError);
    });
  });
}
