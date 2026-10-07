import 'audio_metadata.dart';

enum MetadataSource { embedded, mixed, fallback }

enum ImportMetadataFieldSource { embedded, fallback }

class ImportMetadataOrigins {
  const ImportMetadataOrigins({
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.albumArtistName,
    required this.trackNumber,
    required this.discNumber,
    required this.isSingle,
    required this.featuredArtists,
    required this.releaseDate,
    required this.genre,
  });

  const ImportMetadataOrigins.all(ImportMetadataFieldSource source)
    : title = source,
      artistName = source,
      albumTitle = source,
      albumArtistName = source,
      trackNumber = source,
      discNumber = source,
      isSingle = source,
      featuredArtists = source,
      releaseDate = source,
      genre = source;

  ImportMetadataOrigins copyWith({
    ImportMetadataFieldSource? title,
    ImportMetadataFieldSource? artistName,
    ImportMetadataFieldSource? albumTitle,
    ImportMetadataFieldSource? albumArtistName,
    ImportMetadataFieldSource? trackNumber,
    ImportMetadataFieldSource? discNumber,
    ImportMetadataFieldSource? isSingle,
    ImportMetadataFieldSource? featuredArtists,
    ImportMetadataFieldSource? releaseDate,
    ImportMetadataFieldSource? genre,
  }) {
    return ImportMetadataOrigins(
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      albumTitle: albumTitle ?? this.albumTitle,
      albumArtistName: albumArtistName ?? this.albumArtistName,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      isSingle: isSingle ?? this.isSingle,
      featuredArtists: featuredArtists ?? this.featuredArtists,
      releaseDate: releaseDate ?? this.releaseDate,
      genre: genre ?? this.genre,
    );
  }

  final ImportMetadataFieldSource title;
  final ImportMetadataFieldSource artistName;
  final ImportMetadataFieldSource albumTitle;
  final ImportMetadataFieldSource albumArtistName;
  final ImportMetadataFieldSource trackNumber;
  final ImportMetadataFieldSource discNumber;
  final ImportMetadataFieldSource isSingle;
  final ImportMetadataFieldSource featuredArtists;
  final ImportMetadataFieldSource releaseDate;
  final ImportMetadataFieldSource genre;
}

class ResolvedMetadata {
  const ResolvedMetadata({
    required this.metadata,
    required this.source,
    this.origins,
  });

  final AudioMetadata metadata;
  final MetadataSource source;

  /// Per-field origin information is populated by [MetadataResolver].
  ///
  /// This remains nullable so older/manual construction of [ResolvedMetadata]
  /// does not fabricate field-level provenance.
  final ImportMetadataOrigins? origins;

  bool get usedFallback => source != MetadataSource.embedded;
}
