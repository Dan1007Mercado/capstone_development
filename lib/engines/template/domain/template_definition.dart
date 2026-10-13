import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import 'template_section.dart';
import 'template_status.dart';

/// One exact, immutable semantic version of a template.
final class TemplateDefinition {
  TemplateDefinition({
    required this.id,
    required this.version,
    required this.name,
    required this.status,
    required Iterable<TemplateSection> sections,
    this.description,
  }) : sections = UnmodifiableListView(List.of(sections));

  final TemplateId id;
  final TemplateVersion version;
  final String name;
  final String? description;
  final TemplateStatus status;
  final List<TemplateSection> sections;

  /// Creates an updated draft while preserving this instance.
  ///
  /// Published versions cannot be copied in place; use [createDraftRevision].
  TemplateDefinition copyWith({
    String? name,
    String? description,
    TemplateStatus? status,
    Iterable<TemplateSection>? sections,
  }) {
    if (this.status == TemplateStatus.published) {
      throw StateError(
        'Published templates require a new version via createDraftRevision.',
      );
    }
    return TemplateDefinition(
      id: id,
      version: version,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      sections: sections ?? this.sections,
    );
  }

  /// Starts an editable version after a published historical definition.
  TemplateDefinition createDraftRevision(TemplateVersion nextVersion) {
    if (status != TemplateStatus.published) {
      throw StateError('Only a published template can start a revision.');
    }
    if (nextVersion.value <= version.value) {
      throw ArgumentError.value(
        nextVersion,
        'nextVersion',
        'A revision version must be greater than the published version.',
      );
    }
    return TemplateDefinition(
      id: id,
      version: nextVersion,
      name: name,
      description: description,
      status: TemplateStatus.draft,
      sections: sections,
    );
  }
}
