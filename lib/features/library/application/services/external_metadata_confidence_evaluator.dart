import '../models/external_metadata_candidate.dart';
import '../models/external_metadata_match_evaluation.dart';
import '../models/external_metadata_search_query.dart';

class ExternalMetadataConfidenceEvaluator {
  const ExternalMetadataConfidenceEvaluator();

  /// The release title to compare with the local album: one of the
  /// recording's releases with that title if there is one, otherwise the
  /// single release the provider named. A recording on an album and a
  /// compilation matches the album, whichever release came first.
  static String? _releaseTitleFor(
    String? albumTitle,
    ExternalMetadataCandidate candidate,
  ) {
    final expected = albumTitle?.trim().toLowerCase();

    if (expected != null && expected.isNotEmpty) {
      for (final option in candidate.releaseOptions) {
        if (option.title.trim().toLowerCase() == expected) {
          return option.title;
        }
      }
    }

    return candidate.releaseTitle ??
        (candidate.releaseOptions.isEmpty
            ? null
            : candidate.releaseOptions.first.title);
  }

  ExternalMetadataMatchEvaluation evaluate({
    required ExternalMetadataSearchQuery query,
    required ExternalMetadataCandidate candidate,
  }) {
    if (query.entityKind != candidate.entityKind) {
      return const ExternalMetadataMatchEvaluation(
        score: 0,
        evidenceCoverage: 0,
        signals: [],
        comparable: false,
      );
    }

    final signals = <ExternalMetadataMatchSignal>[];

    switch (query.entityKind) {
      case ExternalMetadataEntityKind.artist:
        signals.add(
          _textSignal(
            kind: ExternalMetadataMatchSignalKind.title,
            weight: 40,
            expected: query.artistName ?? query.title,
            actual: candidate.displayName,
          ),
        );

      case ExternalMetadataEntityKind.album:
        signals.addAll([
          _textSignal(
            kind: ExternalMetadataMatchSignalKind.title,
            weight: 40,
            expected: query.albumTitle ?? query.title,
            actual: candidate.displayName,
          ),
          _artistSignal(expected: query.artistName, candidate: candidate),
        ]);

      case ExternalMetadataEntityKind.track:
        signals.addAll([
          _textSignal(
            kind: ExternalMetadataMatchSignalKind.title,
            weight: 40,
            expected: query.title,
            actual: candidate.displayName,
          ),
          _artistSignal(expected: query.artistName, candidate: candidate),
          _textSignal(
            kind: ExternalMetadataMatchSignalKind.album,
            weight: 15,
            expected: query.albumTitle,
            actual: _releaseTitleFor(query.albumTitle, candidate),
          ),
          _durationSignal(
            expected: query.durationSeconds,
            actual: candidate.durationSeconds,
          ),
        ]);
    }

    final applicableWeight = signals.fold<int>(
      0,
      (sum, signal) => sum + signal.weight,
    );

    final observed = signals.where(
      (signal) =>
          signal.status !=
          ExternalMetadataMatchSignalStatus.insufficientEvidence,
    );

    final observedWeight = observed.fold<int>(
      0,
      (sum, signal) => sum + signal.weight,
    );

    final earnedPoints = observed.fold<double>(
      0,
      (sum, signal) => sum + signal.score,
    );

    return ExternalMetadataMatchEvaluation(
      score: observedWeight == 0
          ? 0
          : (earnedPoints / observedWeight * 100).clamp(0.0, 100.0),
      evidenceCoverage: applicableWeight == 0
          ? 0
          : (observedWeight / applicableWeight * 100).clamp(0.0, 100.0),
      signals: List.unmodifiable(signals),
    );
  }

  ExternalMetadataMatchSignal _textSignal({
    required ExternalMetadataMatchSignalKind kind,
    required int weight,
    required String? expected,
    required String? actual,
  }) {
    final left = _normalize(expected);
    final right = _normalize(actual);
    final label = kind.name;

    if (left.isEmpty || right.isEmpty) {
      return ExternalMetadataMatchSignal(
        kind: kind,
        status: ExternalMetadataMatchSignalStatus.insufficientEvidence,
        weight: weight,
        score: 0,
        explanation: 'Insufficient $label information to compare.',
      );
    }

    if (left == right) {
      return ExternalMetadataMatchSignal(
        kind: kind,
        status: ExternalMetadataMatchSignalStatus.match,
        weight: weight,
        score: weight.toDouble(),
        explanation: 'Matching $label.',
      );
    }

    final leftTokens = left.split(' ').toSet();
    final rightTokens = right.split(' ').toSet();
    final intersection = leftTokens.intersection(rightTokens).length;
    final union = leftTokens.union(rightTokens).length;
    final similarity = union == 0 ? 0.0 : intersection / union;

    if (similarity >= 0.5) {
      return ExternalMetadataMatchSignal(
        kind: kind,
        status: ExternalMetadataMatchSignalStatus.partialMatch,
        weight: weight,
        score: weight * similarity,
        explanation: 'Partially matching $label.',
      );
    }

    return ExternalMetadataMatchSignal(
      kind: kind,
      status: ExternalMetadataMatchSignalStatus.mismatch,
      weight: weight,
      score: 0,
      explanation: 'Different $label.',
    );
  }

  ExternalMetadataMatchSignal _durationSignal({
    required int? expected,
    required int? actual,
  }) {
    const weight = 15;

    if (expected == null || actual == null || expected <= 0 || actual <= 0) {
      return const ExternalMetadataMatchSignal(
        kind: ExternalMetadataMatchSignalKind.duration,
        status: ExternalMetadataMatchSignalStatus.insufficientEvidence,
        weight: weight,
        score: 0,
        explanation: 'Insufficient duration information to compare.',
      );
    }

    final difference = (expected - actual).abs();

    if (difference <= 3) {
      return const ExternalMetadataMatchSignal(
        kind: ExternalMetadataMatchSignalKind.duration,
        status: ExternalMetadataMatchSignalStatus.match,
        weight: weight,
        score: 15,
        explanation: 'Matching duration within three seconds.',
      );
    }

    if (difference <= 15) {
      return ExternalMetadataMatchSignal(
        kind: ExternalMetadataMatchSignalKind.duration,
        status: ExternalMetadataMatchSignalStatus.partialMatch,
        weight: weight,
        score: weight * (1 - (difference - 3) / 24),
        explanation: 'Slightly different duration.',
      );
    }

    return const ExternalMetadataMatchSignal(
      kind: ExternalMetadataMatchSignalKind.duration,
      status: ExternalMetadataMatchSignalStatus.mismatch,
      weight: weight,
      score: 0,
      explanation: 'Substantially different duration.',
    );
  }

  ExternalMetadataMatchSignal _artistSignal({
    required String? expected,
    required ExternalMetadataCandidate candidate,
  }) {
    final credits = candidate.artistCredits;

    if (credits.isEmpty) {
      return _textSignal(
        kind: ExternalMetadataMatchSignalKind.artist,
        weight: 30,
        expected: expected,
        actual: null,
      );
    }

    final comparisons = credits
        .map(
          (credit) => _textSignal(
            kind: ExternalMetadataMatchSignalKind.artist,
            weight: 30,
            expected: expected,
            actual: credit.name,
          ),
        )
        .toList(growable: false);

    final best = comparisons.reduce(
      (current, next) => next.score > current.score ? next : current,
    );

    return best;
  }

  String _normalize(String? text) {
    if (text == null) return '';

    final lowercase = text.toLowerCase();

    const latinReplacements = <String, String>{
      'àáâãäåāăą': 'a',
      'çćč': 'c',
      'ďđ': 'd',
      'èéêëēĕėęě': 'e',
      'ğģ': 'g',
      'ìíîïīĭįı': 'i',
      'ł': 'l',
      'ñńň': 'n',
      'òóôõöøōŏő': 'o',
      'řŕ': 'r',
      'śšșş': 's',
      'ťțţ': 't',
      'ùúûüūŭůűų': 'u',
      'ýÿŷ': 'y',
      'źżž': 'z',
      'æ': 'ae',
      'œ': 'oe',
      'ß': 'ss',
      'þ': 'th',
      'ð': 'd',
    };

    var normalized = lowercase;

    for (final entry in latinReplacements.entries) {
      for (final character in entry.key.split('')) {
        normalized = normalized.replaceAll(character, entry.value);
      }
    }

    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
