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
    );
  }
}
