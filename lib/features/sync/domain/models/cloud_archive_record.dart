import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Kinds of user-created and historical data kept in the cloud archive,
/// alongside the library tables.
enum CloudArchiveKind {
  playlist('playlist', mutable: true),
  listeningSession('listening_session', mutable: false),
  lyrics('lyrics', mutable: true),
  artworkCrop('artwork_crop', mutable: true),
  releaseClassification('release_classification', mutable: true),
  projectAssignment('project_assignment', mutable: true),
  allTimeMoment('all_time_moment', mutable: false);

  const CloudArchiveKind(this.wireName, {required this.mutable});

  /// The `kind` value stored in the cloud.
  final String wireName;

  /// Immutable records (listening history, all-time Moments) are written
  /// once and never changed; the first copy in the cloud stands.
  final bool mutable;

  static CloudArchiveKind? fromWire(String value) =>
      {for (final kind in values) kind.wireName: kind}[value];
}

/// One record of the cloud archive.
class CloudArchiveRecord {
  const CloudArchiveRecord({
    required this.kind,
    required this.key,
    required this.payload,
    required this.clientUpdatedAt,
    this.isDeleted = false,
    this.serverRevision,
    this.serverUpdatedAt,
  });

  final CloudArchiveKind kind;

  /// Permanent identity within its kind, such as a playlist or session id.
  final String key;

  /// The record's content, as plain JSON values.
  final Map<String, Object?> payload;

  /// When the content last changed on the device that wrote it.
  final DateTime clientUpdatedAt;

  /// Removed on some device. Never removes anything on another device.
  final bool isDeleted;

  final int? serverRevision;
  final DateTime? serverUpdatedAt;

  /// `kind:key`, the cloud's ordering id.
  String get recordId => '${kind.wireName}:$key';

  /// Equal for equal content, whichever device computed it.
  String get fingerprint => fingerprintOf(payload, isDeleted: isDeleted);

  static String fingerprintOf(
    Map<String, Object?> payload, {
    bool isDeleted = false,
  }) {
    final canonical = jsonEncode({
      'deleted': isDeleted,
      'payload': _canonical(payload),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static Object? _canonical(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final key in map.keys.toList()..sort()) key: _canonical(map[key]),
    },
    final Map map => _canonical(Map<String, Object?>.from(map)),
    final List list => [for (final item in list) _canonical(item)],
    // JSON makes no difference between 1 and 1.0; neither may this.
    final double number when number == number.truncateToDouble() =>
      number.toInt(),
    _ => value,
  };
}

/// Where the archive pull has reached.
class CloudArchiveCursor {
  const CloudArchiveCursor({
    required this.serverUpdatedAt,
    required this.recordId,
  });

  final DateTime serverUpdatedAt;
  final String recordId;
}
