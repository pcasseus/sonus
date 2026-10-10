import '../models/external_metadata_candidate.dart';
import '../models/external_metadata_candidate_ranking.dart';
import '../models/external_metadata_search_query.dart';
import 'external_metadata_confidence_evaluator.dart';

class ExternalMetadataCandidateRankingService {
  const ExternalMetadataCandidateRankingService({
    this.evaluator = const ExternalMetadataConfidenceEvaluator(),
  });

  final ExternalMetadataConfidenceEvaluator evaluator;

  ExternalMetadataCandidateRanking rank({
    required ExternalMetadataSearchQuery query,
    required List<ExternalMetadataCandidate> candidates,
  }) {
    final ranked = <ExternalMetadataRankedCandidate>[];

    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];

      ranked.add(
        ExternalMetadataRankedCandidate(
          candidate: candidate,
          evaluation: evaluator.evaluate(query: query, candidate: candidate),
          originalIndex: index,
        ),
      );
    }

    ranked.sort(_compare);

    final compatible = ranked
        .where((item) => item.evaluation.comparable)
        .toList(growable: false);

    final reasons = <String>[];

    if (compatible.length > 1) {
      final leader = compatible.first;

      for (final competitor in compatible.skip(1)) {
        if (_sameIdentity(leader, competitor)) {
          continue;
        }

        final scoreDifference =
            (leader.evaluation.score - competitor.evaluation.score).abs();

        final coverageDifference =
            (leader.evaluation.evidenceCoverage -
                    competitor.evaluation.evidenceCoverage)
                .abs();

        if (scoreDifference <= 5 && coverageDifference <= 10) {
          reasons.add(
            'Multiple distinct metadata candidates have similar '
            'match quality and evidence coverage.',
          );
          break;
        }
      }
    }

    return ExternalMetadataCandidateRanking(
      candidates: List.unmodifiable(ranked),
      isAmbiguous: reasons.isNotEmpty,
      ambiguityReasons: List.unmodifiable(reasons),
    );
  }

  int _compare(
    ExternalMetadataRankedCandidate left,
    ExternalMetadataRankedCandidate right,
  ) {
    final comparableComparison = _compareTrueFirst(
      left.evaluation.comparable,
      right.evaluation.comparable,
    );

    if (comparableComparison != 0) {
      return comparableComparison;
    }

    final evidenceComparison = _compareTrueFirst(
      left.evaluation.hasSufficientEvidence,
      right.evaluation.hasSufficientEvidence,
    );

    if (evidenceComparison != 0) {
      return evidenceComparison;
    }

    final scoreComparison = right.evaluation.score.compareTo(
      left.evaluation.score,
    );

    if (scoreComparison != 0) {
      return scoreComparison;
    }

    final coverageComparison = right.evaluation.evidenceCoverage.compareTo(
      left.evaluation.evidenceCoverage,
    );

    if (coverageComparison != 0) {
      return coverageComparison;
    }

    return left.originalIndex.compareTo(right.originalIndex);
  }

  int _compareTrueFirst(bool left, bool right) {
    if (left == right) {
      return 0;
    }

    return left ? -1 : 1;
  }

  bool _sameIdentity(
    ExternalMetadataRankedCandidate left,
    ExternalMetadataRankedCandidate right,
  ) {
    return left.candidate.provider == right.candidate.provider &&
        left.candidate.entityKind == right.candidate.entityKind &&
        left.candidate.providerEntityId == right.candidate.providerEntityId;
  }
}
