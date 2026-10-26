import '../../core/errors/engine_error.dart';
import '../../core/result/engine_result.dart';
import '../../engines/pdf/application/questionnaire_pdf_engine.dart';
import '../../engines/pdf/domain/questionnaire_pdf_plan.dart';
import 'published_template_artifact.dart';

typedef QuestionnaireRenderer =
    Future<EngineResult<QuestionnairePdfArtifact>> Function(
      PublishedTemplateArtifact artifact,
    );

/// Generates a questionnaire only from the same immutable artifact used by
/// the published OMR answer sheet.
final class PublishedQuestionnaireService {
  PublishedQuestionnaireService({QuestionnairePdfEngine? engine})
    : _engine = engine ?? QuestionnairePdfEngine();

  final QuestionnairePdfEngine _engine;

  Future<EngineResult<QuestionnairePdfArtifact>> generate(
    PublishedTemplateArtifact artifact,
  ) async {
    final result = await _engine.render(artifact.template);
    if (result.isFailure) return EngineResult.failure(result.error);
    final questionnaire = result.value;
    if (questionnaire.templateId != artifact.templateId ||
        questionnaire.templateVersion != artifact.templateVersion) {
      return EngineResult.failure(
        EngineError(
          code: 'QUESTIONNAIRE_PUBLICATION_MISMATCH',
          message:
              'Questionnaire identity does not match its published answer sheet.',
          details: {
            'templateId': artifact.templateId.value,
            'templateVersion': artifact.templateVersion.value,
          },
        ),
      );
    }
    return result;
  }
}
