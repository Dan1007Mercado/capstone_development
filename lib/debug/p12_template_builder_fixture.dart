import '../application/template_builder/template_builder_controller.dart';
import '../engines/template/domain/question_type.dart';

/// Populates the required P12 mixed-section demonstration without geometry.
TemplateBuilderController buildP12MixedTemplateDemo() {
  final controller = TemplateBuilderController(
    name: 'P12 Mixed Question Demo',
    description: 'Exercises every supported semantic question type.',
  );

  final sectionA = controller.addSection(title: 'Section A');
  controller.addQuestion(
    sectionA,
    type: QuestionType.likert,
    prompt: 'The instructions were clear.',
  );
  controller.addQuestion(
    sectionA,
    type: QuestionType.likert,
    prompt: 'The form was easy to complete.',
  );

  final sectionB = controller.addSection(title: 'Section B');
  controller.addQuestion(
    sectionB,
    type: QuestionType.multipleChoice,
    prompt: 'Which resources did you use?',
  );
  controller.addQuestion(sectionB, prompt: 'Choose your preferred response.');

  final sectionC = controller.addSection(title: 'Section C');
  controller.addQuestion(
    sectionC,
    type: QuestionType.likert,
    prompt: 'Rate your overall experience.',
  );
  controller.addQuestion(
    sectionC,
    type: QuestionType.yesNo,
    prompt: 'Would you participate again?',
  );

  final sectionD = controller.addSection(title: 'Section D');
  controller.addQuestion(
    sectionD,
    type: QuestionType.numericGrid,
    prompt: 'Enter your participant number.',
  );
  return controller;
}
