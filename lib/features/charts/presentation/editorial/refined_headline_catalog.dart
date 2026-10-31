import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';

/// A refined-only rewording of a catalog headline (SN-50 editorial contract
/// §5). The line keeps its id and its place in the family; only stories told
/// under the refined rules use the new text. The legacy line is never
/// edited, so stories published before the refined rules keep their words.
class RefinedOverride {
  const RefinedOverride(
    this.id,
    this.build, {
    this.requires,
    required this.approved,
  });

  final String id;
  final String Function(MomentFacts f) build;

  /// The facts the new text needs; the legacy line's when null.
  final Set<MomentFact>? requires;

  /// Only approved changes take effect.
  final bool approved;
}

/// A catalog headline left out of refined stories, whenever [when] holds
/// (always when null).
class RefinedExclusion {
  const RefinedExclusion(this.id, {this.when, required this.approved});

  final String id;
  final bool Function(MomentFacts f)? when;
  final bool approved;
}

/// A headline only refined stories can use, placed after the family's
/// catalog lines.
class RefinedAddition {
  const RefinedAddition(this.family, this.variant, {required this.approved});

  final MomentFamily family;
  final HeadlineVariant variant;
  final bool approved;
}

/// The headlines of stories told under the refined Moments rules: the
/// catalog ([MomentHeadlines.legacyOf]) with approved overrides applied in
/// place, approved exclusions removed and approved additions appended.
///
/// Stories under the earlier rules never read this. Unapproved entries
/// have no effect anywhere.
class RefinedHeadlineCatalog {
  const RefinedHeadlineCatalog({
    this.overrides = const [],
    this.exclusions = const [],
    this.additions = const [],
  });

  /// The app's refined changes. Each entry needs its own editorial
  /// approval (SN50_Final_Editorial_Approval_and_Implementation_Contract.md).
  static final RefinedHeadlineCatalog standard = RefinedHeadlineCatalog(
    overrides: [],
    exclusions: [],
    additions: [],
  );

  final List<RefinedOverride> overrides;
  final List<RefinedExclusion> exclusions;
  final List<RefinedAddition> additions;

  List<HeadlineVariant> of(MomentFamily family, MomentFacts facts) {
    final reworded = {
      for (final override in overrides)
        if (override.approved) override.id: override,
    };
    bool excluded(String id) => exclusions.any(
      (exclusion) =>
          exclusion.approved &&
          exclusion.id == id &&
          (exclusion.when?.call(facts) ?? true),
    );

    return [
      for (final variant in MomentHeadlines.legacyOf(family))
        if (!excluded(variant.id))
          switch (reworded[variant.id]) {
            null => variant,
            final override => HeadlineVariant(
              variant.id,
              variant.publisher,
              override.build,
              requires: override.requires ?? variant.requires,
            ),
          },
      for (final addition in additions)
        if (addition.approved && addition.family == family) addition.variant,
    ];
  }
}
