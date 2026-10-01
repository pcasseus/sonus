import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

class ImportIdentityMetadataNormalizer {
  const ImportIdentityMetadataNormalizer();

  AudioMetadata normalize({
    required ImportCandidate candidate,
    required AudioMetadata metadata,
  }) {
    if (candidate.structure != ImportCandidateStructure.artistAlbum) {
      return metadata;
    }

    final folderArtist = _folderArtist(candidate.metadataFallbackPath);

    if (folderArtist == null) {
      return metadata;
    }

    final canonicalFolderArtist = TextNormalizer.canonicalize(folderArtist);

    final canonicalRawArtist = TextNormalizer.canonicalize(metadata.artistName);

    if (canonicalRawArtist == canonicalFolderArtist) {
      return metadata.copyWith(
        artistName: folderArtist,
        albumArtistName: folderArtist,
        featuredArtists: _deduplicate(metadata.featuredArtists),
      );
    }

    final explicitFeatureCredit = _parseExplicitFeatureCredit(
      metadata.artistName,
    );

    if (explicitFeatureCredit != null &&
        TextNormalizer.canonicalize(explicitFeatureCredit.primaryArtist) ==
            canonicalFolderArtist) {
      return metadata.copyWith(
        artistName: folderArtist,
        albumArtistName: folderArtist,
        featuredArtists: _deduplicate([
          ...metadata.featuredArtists,
          explicitFeatureCredit.featuredArtist,
        ]),
      );
    }

    return metadata.copyWith(
      albumArtistName: folderArtist,
      featuredArtists: _deduplicate(metadata.featuredArtists),
    );
  }

  String? ambiguousSeparatorArtistCredit({
    required ImportCandidate candidate,
    required AudioMetadata metadata,
  }) {
    if (candidate.structure != ImportCandidateStructure.artistAlbum) {
      return null;
    }

    final folderArtist = _folderArtist(candidate.metadataFallbackPath);

    if (folderArtist == null) {
      return null;
    }

    final rawCredit = metadata.artistName.trim();

    if (rawCredit.isEmpty) {
      return null;
    }

    final canonicalFolderArtist = TextNormalizer.canonicalize(folderArtist);
    final canonicalRawCredit = TextNormalizer.canonicalize(rawCredit);

    if (canonicalRawCredit == canonicalFolderArtist) {
      return null;
    }

    if (_parseExplicitFeatureCredit(rawCredit) != null) {
      return null;
    }

    final parts = rawCredit
        .split(RegExp(r'\s+&\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.length < 2) {
      return null;
    }

    final containsFolderArtist = parts.any(
      (part) => TextNormalizer.canonicalize(part) == canonicalFolderArtist,
    );

    return containsFolderArtist ? rawCredit : null;
  }

  String? _folderArtist(String? fallbackPath) {
    final cleaned = fallbackPath?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    final parts = cleaned
        .split(RegExp(r'[\\/]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.length < 3) {
      return null;
    }

    return parts.first;
  }

  _ExplicitFeatureCredit? _parseExplicitFeatureCredit(String rawCredit) {
    final cleaned = rawCredit.trim();

    if (cleaned.isEmpty) {
      return null;
    }

    final wrappedMatch = RegExp(
      r'^(.*?)\s*[\[(]\s*(?:feat\.?|ft\.?|featuring)\s+(.+?)\s*[\])]$',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (wrappedMatch != null) {
      return _featureCreditFromMatch(wrappedMatch);
    }

    final directMatch = RegExp(
      r'^(.*?)\s+(?:feat\.?|ft\.?|featuring)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (directMatch == null) {
      return null;
    }

    return _featureCreditFromMatch(directMatch);
  }

  _ExplicitFeatureCredit? _featureCreditFromMatch(RegExpMatch match) {
    final primaryArtist = match.group(1)?.trim() ?? '';
    final featuredArtist = match.group(2)?.trim() ?? '';

    if (primaryArtist.isEmpty || featuredArtist.isEmpty) {
      return null;
    }

    return _ExplicitFeatureCredit(
      primaryArtist: primaryArtist,
      featuredArtist: featuredArtist,
    );
  }

  List<String> _deduplicate(Iterable<String> artists) {
    final seen = <String>{};
    final result = <String>[];

    for (final artist in artists) {
      final cleaned = artist.trim();

      if (cleaned.isEmpty) {
        continue;
      }

      final canonical = TextNormalizer.canonicalize(cleaned);

      if (canonical.isEmpty || !seen.add(canonical)) {
        continue;
      }

      result.add(cleaned);
    }

    return List.unmodifiable(result);
  }
}

class _ExplicitFeatureCredit {
  const _ExplicitFeatureCredit({
    required this.primaryArtist,
    required this.featuredArtist,
  });

  final String primaryArtist;
  final String featuredArtist;
}
