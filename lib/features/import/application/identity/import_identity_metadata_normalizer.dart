import 'package:sonus_next/core/identity/artist_credit_parser.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

class ImportIdentityMetadataNormalizer {
  const ImportIdentityMetadataNormalizer();

  static const _artistCreditParser = ArtistCreditParser();

  AudioMetadata normalize({
    required ImportCandidate candidate,
    required AudioMetadata metadata,
  }) {
    final folderArtist =
        candidate.structure == ImportCandidateStructure.artistAlbum
        ? _folderArtist(candidate.metadataFallbackPath)
        : null;

    if (folderArtist == null) {
      return _splitExplicitFeature(metadata);
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

    final explicitFeatureCredit = _artistCreditParser
        .parseExplicitFeatureCredit(metadata.artistName);

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

    return _splitExplicitFeature(
      metadata,
    ).copyWith(albumArtistName: folderArtist);
  }

  /// An explicit "A feat. B" / "A [Ft. B]" credit is A performing with B
  /// featured, whoever A is: A becomes the performer and B a featured
  /// credit, so the whole string never becomes an artist of its own. Any
  /// other credit, such as "A & B", is kept exactly as tagged.
  AudioMetadata _splitExplicitFeature(AudioMetadata metadata) {
    final credit = _artistCreditParser.parseExplicitFeatureCredit(
      metadata.artistName,
    );

    if (credit == null) {
      return metadata.copyWith(
        featuredArtists: _deduplicate(metadata.featuredArtists),
      );
    }

    return metadata.copyWith(
      artistName: credit.primaryArtist,
      featuredArtists: _deduplicate([
        ...metadata.featuredArtists,
        credit.featuredArtist,
      ]),
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

    if (_artistCreditParser.parseExplicitFeatureCredit(rawCredit) != null) {
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
