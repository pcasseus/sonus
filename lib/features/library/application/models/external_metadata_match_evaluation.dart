enum ExternalMetadataMatchSignalKind { title, artist, album, duration }

enum ExternalMetadataMatchSignalStatus {
  match,
  partialMatch,
  mismatch,
  insufficientEvidence,
}

class ExternalMetadataMatchSignal {
  const ExternalMetadataMatchSignal({
    required this.kind,
    required this.status,
    required this.weight,
    required this.score,
    required this.explanation,
  });

  final ExternalMetadataMatchSignalKind kind;
  final ExternalMetadataMatchSignalStatus status;

  /// Maximum points available for this comparison signal.
  final int weight;

  /// Points earned from this signal.
  final double score;

  final String explanation;
}

class ExternalMetadataMatchEvaluation {
  const ExternalMetadataMatchEvaluation({
    required this.score,
    required this.evidenceCoverage,
    required this.signals,
    this.comparable = true,
  });

  /// Match quality, normalized to a 0–100 scale using observed evidence.
  final double score;

  /// Percentage of applicable evidence available for comparison, 0–100.
  final double evidenceCoverage;

  final List<ExternalMetadataMatchSignal> signals;

  /// False when the candidate and query represent different entity kinds.
  final bool comparable;

  bool get hasSufficientEvidence => comparable && evidenceCoverage >= 70;

  bool get isStrongMatch => hasSufficientEvidence && score >= 85;

  bool get requiresCarefulReview =>
      !comparable || !hasSufficientEvidence || score < 70;

  List<String> get explanations =>
      signals.map((signal) => signal.explanation).toList(growable: false);
}
