import '../../../../core/identity/text_normalizer.dart';
import '../models/external_metadata_candidate.dart';

enum ReleaseSelectionOutcome {
  /// Exactly one release fits the local edition.
  matched,

  /// Several releases fit equally; none is chosen.
  ambiguous,

  /// No release fits; none is chosen.
  none,
}

class ReleaseSelection {
  const ReleaseSelection(this.outcome, [this.release]);

  final ReleaseSelectionOutcome outcome;

  /// The chosen release, only when [outcome] is matched.
  final ExternalMetadataReleaseOption? release;
}

/// Chooses which of a candidate's releases is the local edition, or none.
///
/// Never "the first release": a release is chosen only when exactly one
/// matches the local edition's title, then its disc and track position and
/// its track count, as far as both sides know them. Anything less leaves the
/// release unchosen for the user to confirm.
class ExternalMetadataReleaseSelector {
  const ExternalMetadataReleaseSelector();

  ReleaseSelection select(
    ExternalMetadataCandidate candidate, {
    required List<String> localTitles,
    int? discNumber,
    int? trackNumber,
    int? editionTrackCount,
  }) {
    final titles = {
      for (final title in localTitles)
        if (title.trim().isNotEmpty) TextNormalizer.canonicalize(title),
    };

    var fits = candidate.releaseOptions
        .where(
          (option) =>
              titles.contains(TextNormalizer.canonicalize(option.title)),
        )
        .toList(growable: false);

    // Each refinement applies only where both sides know the value, and
    // never narrows the options to nothing.
    List<ExternalMetadataReleaseOption> narrow(
      bool Function(ExternalMetadataReleaseOption option) keep,
    ) {
      final kept = fits.where(keep).toList(growable: false);
      return kept.isEmpty ? fits : kept;
    }

    if (discNumber != null && discNumber > 0) {
      fits = narrow((o) => o.mediumPosition == discNumber);
    }
    if (trackNumber != null && trackNumber > 0) {
      fits = narrow((o) => o.trackNumber == trackNumber);
    }
    if (editionTrackCount != null && editionTrackCount > 0) {
      fits = narrow((o) => o.trackCount == editionTrackCount);
    }

    return switch (fits.length) {
      0 => const ReleaseSelection(ReleaseSelectionOutcome.none),
      1 => ReleaseSelection(ReleaseSelectionOutcome.matched, fits.single),
      _ => const ReleaseSelection(ReleaseSelectionOutcome.ambiguous),
    };
  }
}
