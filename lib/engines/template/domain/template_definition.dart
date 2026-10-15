import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import 'template_section.dart';
import 'template_status.dart';
import 'value_equality.dart';

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
    Object? description = _unchanged,
    Iterable<TemplateSection>? sections,
  }) {
    if (status == TemplateStatus.published) {
      throw StateError(
        'Published templates require a new version via createDraftRevision.',
      );
    }
    return TemplateDefinition(
      id: id,
      version: version,
      name: name ?? this.name,
      description: identical(description, _unchanged)
          ? this.description
          : description as String?,
      status: status,
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

  /// Creates the frozen form of a draft after application-level validation.
  ///
  /// Callers must use the publication service so validation and repository
  /// uniqueness checks occur before this lifecycle transition.
  TemplateDefinition toPublishedAfterValidation() {
    if (status != TemplateStatus.draft) {
      throw StateError('Only a draft template can be published.');
    }
    return TemplateDefinition(
      id: id,
      version: version,
      name: name,
      description: description,
      status: TemplateStatus.published,
      sections: sections,
    );
  }

  /// Starts the immediately following editable version.
  TemplateDefinition createNextDraftRevision() =>
      createDraftRevision(TemplateVersion(version.value + 1));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateDefinition &&
          other.id == id &&
          other.version == version &&
          other.name == name &&
          other.description == description &&
          other.status == status &&
          listEqualsByValue(other.sections, sections);

  @override
  int get hashCode => Object.hash(
    id,
    version,
    name,
    description,
    status,
    Object.hashAll(sections),
  );

  static const Object _unchanged = Object();
}
