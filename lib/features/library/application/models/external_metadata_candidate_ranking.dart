import 'external_metadata_candidate.dart';
import 'external_metadata_match_evaluation.dart';

class ExternalMetadataRankedCandidate {
  const ExternalMetadataRankedCandidate({
    required this.candidate,
    required this.evaluation,
    required this.originalIndex,
  });

  final ExternalMetadataCandidate candidate;
  final ExternalMetadataMatchEvaluation evaluation;
  final int originalIndex;
}

class ExternalMetadataCandidateRanking {
  const ExternalMetadataCandidateRanking({
    required this.candidates,
    required this.isAmbiguous,
    required this.ambiguityReasons,
  });

  /// Candidates ordered by Sonus match quality.
  final List<ExternalMetadataRankedCandidate> candidates;

  /// Whether the leading candidate has a meaningful competitor.
  final bool isAmbiguous;

  /// Human-readable explanations for ambiguous rankings.
  final List<String> ambiguityReasons;

  ExternalMetadataRankedCandidate? get bestCandidate {
    if (candidates.isEmpty) {
      return null;
    }

    final first = candidates.first;

    return first.evaluation.comparable && first.evaluation.evidenceCoverage > 0
        ? first
        : null;
  }

  bool get hasResults => candidates.isNotEmpty;

  bool get requiresCarefulReview =>
      isAmbiguous ||
      bestCandidate == null ||
      bestCandidate!.evaluation.requiresCarefulReview;
}
