import 'resolved_metadata.dart';

/// Why a file waits in Import Review (App Update 1.2, BUG-09).
enum PendingFileReviewKind {
  /// Same title as a song, at another track position: maybe another
  /// recording (SN-50 §4).
  possibleDifferentRecording,

  /// A new file appeared where a song's file used to be, and its audio could
  /// not be proven to be that song's: maybe the same song, renamed, moved or
  /// rewritten.
  possibleReplacedFile,

  /// A known file's audio itself changed at the same location.
  audioChanged,
}

/// A file kept out of the library as a possible different recording of an
/// existing song, waiting on this device for the user's decision.
class PendingPossibleRecording {
  const PendingPossibleRecording({
    required this.normalizedPath,
    required this.filePath,
    required this.candidateSongId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.discNumber,
    required this.trackNumber,
    required this.durationSeconds,
    required this.firstSeenAt,
    this.metadataFallbackPath,
    this.sourceId,
    this.metadataSource,
    this.kind = PendingFileReviewKind.possibleDifferentRecording,
    this.otherCandidateSongIds = const [],
  });

  final String normalizedPath;
  final String filePath;

  /// The song this file may duplicate.
  final String candidateSongId;

  final String title;
  final String artistName;
  final String albumTitle;
  final int discNumber;
  final int trackNumber;
  final int durationSeconds;

  /// When a scan first reported the file, in UTC.
  final DateTime firstSeenAt;

  /// A readable path for a content URI, as the scan found it.
  final String? metadataFallbackPath;
  final String? sourceId;

  /// Where the reported tags came from. Null for entries saved before
  /// SN-50 §4, which were all read from tags.
  final MetadataSource? metadataSource;

  /// Why the file waits for the user.
  final PendingFileReviewKind kind;

  /// Further songs it may be, when its audio matches more than one missing
  /// file; [candidateSongId] is the first.
  final List<String> otherCandidateSongIds;

  /// Every song the file may be, [candidateSongId] first.
  List<String> get candidateSongIds => [
    candidateSongId,
    ...otherCandidateSongIds,
  ];

  /// Whether the entry was recorded from the path alone, not from tags.
  bool get recordedFromPath => metadataSource == MetadataSource.fallback;

  /// The path to show the user.
  String get displayPath {
    final fallback = metadataFallbackPath?.trim();
    return fallback == null || fallback.isEmpty ? filePath : fallback;
  }

  PendingPossibleRecording copyWith({DateTime? firstSeenAt}) {
    return PendingPossibleRecording(
      normalizedPath: normalizedPath,
      filePath: filePath,
      candidateSongId: candidateSongId,
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      discNumber: discNumber,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      metadataFallbackPath: metadataFallbackPath,
      sourceId: sourceId,
      metadataSource: metadataSource,
      kind: kind,
      otherCandidateSongIds: otherCandidateSongIds,
    );
  }

  Map<String, Object?> toJson() => {
    'normalizedPath': normalizedPath,
    'filePath': filePath,
    'candidateSongId': candidateSongId,
    'title': title,
    'artistName': artistName,
    'albumTitle': albumTitle,
    'discNumber': discNumber,
    'trackNumber': trackNumber,
    'durationSeconds': durationSeconds,
    'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
    'metadataFallbackPath': metadataFallbackPath,
    'sourceId': sourceId,
    if (metadataSource case final source?) 'metadataSource': source.name,
    'kind': kind.name,
    if (otherCandidateSongIds.isNotEmpty)
      'otherCandidateSongIds': otherCandidateSongIds,
  };

  /// Null when [json] is not a complete entry.
  static PendingPossibleRecording? tryFromJson(Object? json) {
    if (json is! Map) return null;

    final normalizedPath = json['normalizedPath'];
    final filePath = json['filePath'];
    final candidateSongId = json['candidateSongId'];
    final title = json['title'];
    final artistName = json['artistName'];
    final albumTitle = json['albumTitle'];
    final discNumber = json['discNumber'];
    final trackNumber = json['trackNumber'];
    final durationSeconds = json['durationSeconds'];
    final firstSeenAt = DateTime.tryParse('${json['firstSeenAt']}');
    final metadataFallbackPath = json['metadataFallbackPath'];
    final sourceId = json['sourceId'];

    if (normalizedPath is! String ||
        normalizedPath.isEmpty ||
        filePath is! String ||
        filePath.isEmpty ||
        candidateSongId is! String ||
        candidateSongId.isEmpty ||
        title is! String ||
        artistName is! String ||
        albumTitle is! String ||
        discNumber is! int ||
        trackNumber is! int ||
        durationSeconds is! int ||
        firstSeenAt == null ||
        (metadataFallbackPath != null && metadataFallbackPath is! String) ||
        (sourceId != null && sourceId is! String)) {
      return null;
    }

    return PendingPossibleRecording(
      normalizedPath: normalizedPath,
      filePath: filePath,
      candidateSongId: candidateSongId,
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      discNumber: discNumber,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      firstSeenAt: firstSeenAt.toUtc(),
      metadataFallbackPath: metadataFallbackPath as String?,
      sourceId: sourceId as String?,
      metadataSource: MetadataSource.values
          .where((source) => source.name == json['metadataSource'])
          .firstOrNull,
      // Entries saved before App Update 1.2 were all of the first kind.
      kind:
          PendingFileReviewKind.values
              .where((kind) => kind.name == json['kind'])
              .firstOrNull ??
          PendingFileReviewKind.possibleDifferentRecording,
      otherCandidateSongIds: [
        for (final id in json['otherCandidateSongIds'] as List? ?? const [])
          if (id is String && id.isNotEmpty) id,
      ],
    );
  }
}
