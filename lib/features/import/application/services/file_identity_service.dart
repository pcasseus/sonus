import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/database/library_mutation_coordinator.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../data/mappers/media_file_binding_row_mapper.dart';
import '../../data/services/possible_recording_store.dart';
import '../../domain/entities/media_file_binding.dart';
import '../../domain/entities/media_file_binding_factory.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/import_result.dart';
import '../../domain/models/import_scan_snapshot.dart';
import '../../domain/models/pending_possible_recording.dart';
import '../../domain/models/resolved_metadata.dart';
import '../../domain/services/audio_byte_source.dart';
import '../../domain/services/range_cached_audio_byte_source.dart';
import '../folders/source_folder_key.dart';
import '../identity/audio_identity/audio_identity_reader.dart';
import '../identity/audio_identity/tag_fingerprint_reader.dart';
import '../identity/recording_evidence.dart';
import 'existing_song_release_mover.dart';
import 'existing_song_tag_updater.dart';
import 'metadata_resolver.dart';

/// A file's audio identity and the state it was read in.
class FileIdentityReading {
  const FileIdentityReading({
    required this.identity,
    required this.fileSizeBytes,
    required this.modifiedAt,
    this.failure,
    this.tagFingerprint,
  });

  /// The tags' fingerprint (Refinement B); null when the tags could not be
  /// walked with confidence.
  final TagFingerprint? tagFingerprint;

  FileIdentityReading withTagFingerprint(TagFingerprint fingerprint) =>
      FileIdentityReading(
        identity: identity,
        fileSizeBytes: fileSizeBytes,
        modifiedAt: modifiedAt,
        failure: failure,
        tagFingerprint: fingerprint,
      );

  /// Null when the audio could not be read with confidence. Always holds a
  /// full hash when set.
  final AudioIdentity? identity;

  /// Why there is no [identity]: the file could not be read now (which says
  /// nothing about its audio), or its layout is not one the rules accept.
  final AudioIdentityFailure? failure;
  final int? fileSizeBytes;
  final DateTime? modifiedAt;
}

/// What came of the user's decision on a file in Import Review.
enum FileReviewDecisionOutcome {
  /// The song plays the file now; its Song ID and history are unchanged.
  done,

  /// The song already plays another file, so this one was not attached.
  songHasFile,

  /// The song is no longer in the library.
  songMissing,

  /// The file or its audio was permanently deleted from the library.
  deleted,

  /// The file could not be read; nothing changed.
  unreadable,

  /// The file is not, or no longer, the one Sonus knows at that location.
  notKnown,
}

/// What the identity pass decided for a scan (App Update 1.2, BUG-09).
class FileIdentityPlan {
  const FileIdentityPlan({this.results = const {}, this.readings = const {}});

  static const empty = FileIdentityPlan();

  /// Files the pass settled itself, by normalized path: a relinked file, a
  /// copy, a deleted recording, or a file sent to Import Review. They are
  /// not imported again.
  final Map<String, ImportResult> results;

  /// Audio identities read for the other files, by normalized path, to be
  /// kept on their bindings once the import has run.
  final Map<String, FileIdentityReading> readings;
}

/// Recognises files the library already knows by their audio, not their
/// location (App Update 1.2, BUG-09). Rules, in order:
///
/// - R0: audio of a permanently deleted file stays out.
/// - R1: a known file with the same size and modification time is not read.
/// - R2: a known file whose tags changed but whose audio did not keeps its
///   song; the new tags update it where the field's authority allows.
/// - R3: a known file whose audio changed goes to Import Review.
/// - R4: a new file whose whole audio is byte-identical to exactly one
///   song's missing file is that song's file again: the binding moves, the
///   Song ID stays. The sampled signature alone is never enough.
/// - R5: a new file byte-identical to a file still present is a copy.
/// - R6/R7: a new file that may be a missing song's file, but cannot be
///   proven to be (several matches, no stored proof, or no audio match but
///   a missing song of about the same length in the same folder), goes to
///   Import Review. No new song is made for it.
/// - R8: anything else imports as before.
///
/// Nothing is merged or deleted. Two existing songs are never combined.
class FileIdentityService {
  FileIdentityService({
    required this.appDatabase,
    required this.openSource,
    required this.metadataResolver,
    required this.tagUpdater,
    this.reviewStore,
    this.releaseMover,
    this.reader = const AudioIdentityReader(),
    this.tagReader = const TagFingerprintReader(),
  });

  /// Reads the tags' fingerprint (Refinement B).
  final TagFingerprintReader tagReader;

  /// Moves a song to the artist, album and edition its changed tags name
  /// (Refinement A); without one, those stay as they are.
  final ExistingSongReleaseMover? releaseMover;

  final AppDatabase appDatabase;
  final AudioByteSourceOpener openSource;
  final MetadataResolver metadataResolver;
  final ExistingSongTagUpdater tagUpdater;
  final PossibleRecordingStore? reviewStore;
  final AudioIdentityReader reader;

  /// Runs before a batch is imported. [prepared] holds the tags already
  /// read for new files.
  Future<FileIdentityPlan> plan(
    List<ImportCandidate> candidates, {
    ImportScanSnapshot? scan,
    Map<String, ResolvedMetadata> preparedMetadata = const {},
    required DateTime now,
  }) async {
    if (candidates.isEmpty) return FileIdentityPlan.empty;

    final db = await appDatabase.database;
    final bindings = [
      for (final row in await db.query(DatabaseTables.mediaFileBindings))
        MediaFileBindingRowMapper.fromRow(row),
    ];
    final byPath = {for (final b in bindings) b.normalizedPath: b};
    final deleted = {
      for (final row in await db.query(
        DatabaseTables.deletedAudioSignatures,
        columns: ['audio_signature'],
      ))
        row['audio_signature']! as String,
    };

    final results = <String, ImportResult>{};
    final readings = <String, FileIdentityReading>{};
    final claimed = <String>{};
    final releases = <ReleaseMoveIntent>[];

    for (final candidate in candidates) {
      final path = TextNormalizer.normalizePath(candidate.filePath);
      try {
        final known = byPath[path];
        if (known != null) {
          await _checkKnownFile(candidate, known, now: now, batch: releases);
          continue;
        }

        final reading = await _read(candidate);
        final identity = reading.identity;
        final outcome = identity == null
            ? null
            : await _matchByAudio(
                candidate,
                reading,
                bindings: bindings,
                deleted: deleted,
                claimed: claimed,
                scan: scan,
                metadata: preparedMetadata[path],
                now: now,
                batch: releases,
              );
        if (outcome != null) {
          results[path] = outcome;
          continue;
        }

        final replaced = await _possiblyReplaced(
          candidate,
          metadata: preparedMetadata[path],
          bindings: bindings,
          claimed: claimed,
          scan: scan,
          now: now,
        );
        if (replaced != null) {
          results[path] = replaced;
          continue;
        }

        if (identity != null) readings[path] = reading;
      } on LibraryMutationUnavailable {
        rethrow;
      } catch (error, stackTrace) {
        // The file imports as before; its identity is read on a later scan.
        _log('checking a file', error, stackTrace);
      }
    }

    await _settleReleases(releases, scan: scan, now: now);
    return FileIdentityPlan(results: results, readings: readings);
  }

  /// Keeps [reading] on the binding now at [normalizedPath], if any.
  Future<void> keep(String normalizedPath, FileIdentityReading reading) async {
    final identity = reading.identity;
    if (identity == null) return;
    await appDatabase.transaction((txn) async {
      final rows = await txn.query(
        DatabaseTables.mediaFileBindings,
        where: 'normalized_path = ?',
        whereArgs: [normalizedPath],
      );
      for (final row in rows) {
        final stored = MediaFileBindingRowMapper.fromRow(row);
        await txn.update(
          DatabaseTables.mediaFileBindings,
          _identityColumns(reading, stored: stored),
          where: 'id = ?',
          whereArgs: [stored.id],
        );
      }
    });
  }

  /// The user said the file at [filePath] is [songId]'s file (a replaced
  /// file in Import Review). The song keeps its ID and everything attached
  /// to it; its missing file's link moves to this file, or one is made.
  Future<FileReviewDecisionOutcome> useFileForSong(
    ImportCandidate candidate, {
    required String songId,
    required DateTime now,
  }) async {
    final reading = await _read(candidate);
    final path = TextNormalizer.normalizePath(candidate.filePath);
    if (reading.failure == AudioIdentityFailure.unreadable) {
      return FileReviewDecisionOutcome.unreadable;
    }
    final metadata = await _metadataOrNull(candidate);

    final outcome = await appDatabase.transaction((txn) async {
      if ((await txn.query(
        DatabaseTables.songs,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [songId],
      )).isEmpty) {
        return FileReviewDecisionOutcome.songMissing;
      }
      final deletedPath = await txn.query(
        DatabaseTables.libraryDeletionLedger,
        where: "entity_type = 'mediaFile' AND entity_id = ?",
        whereArgs: [path],
      );
      final signature = reading.identity?.signature;
      final deletedAudio = signature == null
          ? const <Map<String, Object?>>[]
          : await txn.query(
              DatabaseTables.deletedAudioSignatures,
              where: 'audio_signature = ?',
              whereArgs: [signature],
            );
      if (deletedPath.isNotEmpty || deletedAudio.isNotEmpty) {
        return FileReviewDecisionOutcome.deleted;
      }

      final songBindings = [
        for (final row in await txn.query(
          DatabaseTables.mediaFileBindings,
          where: 'song_id = ?',
          whereArgs: [songId],
          orderBy: 'last_seen_at DESC, updated_at DESC, id ASC',
        ))
          MediaFileBindingRowMapper.fromRow(row),
      ];
      if (songBindings.any((b) => b.isAvailable && b.normalizedPath != path)) {
        return FileReviewDecisionOutcome.songHasFile;
      }

      final stamp = now.toUtc().toIso8601String();
      final columns = {
        'file_path': candidate.filePath.trim(),
        'normalized_path': path,
        'source_id': candidate.sourceId,
        'is_available': 1,
        'last_seen_at': stamp,
        'updated_at': stamp,
        if (reading.identity != null)
          ..._identityColumns(
            reading,
            stored: songBindings.isEmpty ? null : songBindings.first,
          ),
      };
      if (songBindings.isEmpty) {
        await txn.insert(DatabaseTables.mediaFileBindings, {
          ...MediaFileBindingRowMapper.toRow(
            MediaFileBindingFactory.create(
              songId: songId,
              filePath: candidate.filePath,
              sourceId: candidate.sourceId,
              now: now,
            ),
          ),
          ...columns,
        });
      } else {
        await txn.update(
          DatabaseTables.mediaFileBindings,
          columns,
          where: 'id = ?',
          whereArgs: [songBindings.first.id],
        );
      }
      if (metadata != null) {
        await tagUpdater.apply(
          txn,
          songId: songId,
          metadata: metadata,
          candidate: candidate,
          now: now,
        );
      }
      return FileReviewDecisionOutcome.done;
    });
    if (outcome == FileReviewDecisionOutcome.done && metadata != null) {
      await _moveRelease(songId, metadata, candidate, now);
    }
    return outcome;
  }

  /// The user said a known file whose audio changed is still its song: the
  /// file as it is now becomes the reference, and its tags apply as for any
  /// other tag change.
  Future<FileReviewDecisionOutcome> keepChangedAudio(
    ImportCandidate candidate, {
    required DateTime now,
  }) async {
    final path = TextNormalizer.normalizePath(candidate.filePath);
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseTables.mediaFileBindings,
      where: 'normalized_path = ?',
      whereArgs: [path],
    );
    if (rows.isEmpty) return FileReviewDecisionOutcome.notKnown;
    final binding = MediaFileBindingRowMapper.fromRow(rows.single);

    final reading = await _read(candidate);
    if (reading.identity == null) return FileReviewDecisionOutcome.unreadable;
    final metadata = await _metadataOrNull(candidate);

    await appDatabase.transaction((txn) async {
      await _writeIdentityIn(txn, binding, reading);
      if (metadata != null) {
        await tagUpdater.apply(
          txn,
          songId: binding.songId,
          metadata: metadata,
          candidate: candidate,
          now: now,
        );
      }
    });
    if (metadata != null) {
      await _moveRelease(binding.songId, metadata, candidate, now);
    }
    return FileReviewDecisionOutcome.done;
  }

  /// Refinement A: the song follows its tags to another artist, album or
  /// edition where that is safe; otherwise it waits in Import Review. During
  /// a scan the wish is only collected into [batch] and settled with the
  /// rest of the scan (see [_settleReleases]), so a release retagged as a
  /// whole moves together and a single retagged song never splits one. A
  /// failure never undoes the identity work already committed.
  Future<void> _moveRelease(
    String songId,
    ResolvedMetadata metadata,
    ImportCandidate candidate,
    DateTime now, {
    List<ReleaseMoveIntent>? batch,
  }) async {
    final mover = releaseMover;
    if (mover == null) return;
    try {
      if (batch == null) {
        await mover.apply(
          songId: songId,
          metadata: metadata,
          candidate: candidate,
          now: now,
        );
        return;
      }
      final intent = await mover.evaluate(
        songId: songId,
        metadata: metadata,
        candidate: candidate,
      );
      if (intent != null) batch.add(intent);
    } on LibraryMutationUnavailable {
      rethrow;
    } catch (error, stackTrace) {
      _log('moving a song to its tagged release', error, stackTrace);
    }
  }

  Future<void> _settleReleases(
    List<ReleaseMoveIntent> batch, {
    required ImportScanSnapshot? scan,
    required DateTime now,
  }) async {
    final mover = releaseMover;
    if (mover == null || batch.isEmpty) return;
    try {
      await mover.settle(batch, scan: scan, now: now);
    } on LibraryMutationUnavailable {
      rethrow;
    } catch (error, stackTrace) {
      _log('moving songs to their tagged releases', error, stackTrace);
    }
  }

  /// The new tags' fingerprint when a file with unchanged size and time has
  /// new tags, otherwise null. The first fingerprint of a file is only kept
  /// (nothing says its tags changed), and so is one that differs only in
  /// its embedded pictures: Sonus does not use embedded artwork, so there
  /// is nothing to update. One that cannot be read now keeps the stored
  /// one untouched.
  Future<TagFingerprint?> _tagsEditedInPlace(
    ImportCandidate candidate,
    MediaFileBinding binding,
  ) async {
    final current = await _fingerprintOf(candidate);
    if (current == null) return null;
    final stored = TagFingerprint.tryParse(binding.tagFingerprint);
    if (stored != null && stored.text != current.text) return current;
    if (stored == null || stored.pictures != current.pictures) {
      await appDatabase.transaction(
        (txn) => txn.update(
          DatabaseTables.mediaFileBindings,
          {'tag_fingerprint': current.value},
          where: 'id = ?',
          whereArgs: [binding.id],
        ),
      );
    }
    return null;
  }

  // R1-R3.
  Future<void> _checkKnownFile(
    ImportCandidate candidate,
    MediaFileBinding binding, {
    required DateTime now,
    required List<ReleaseMoveIntent> batch,
  }) async {
    final stat = await _stat(candidate);
    final hasBaseline =
        binding.audioSignature != null &&
        binding.signatureVersion == AudioIdentity.currentVersion;
    TagFingerprint? editedTags;
    if (hasBaseline &&
        stat.$1 != null &&
        binding.fileSizeBytes == stat.$1 &&
        binding.modifiedAt?.toUtc() == stat.$2?.toUtc()) {
      // R1, unless the tags changed while size and time did not
      // (Refinement B): their fingerprint costs a few small reads.
      editedTags = await _tagsEditedInPlace(candidate, binding);
      if (editedTags == null) return;
    }

    var reading = await _read(candidate);
    // The edited tags were just read; a failure to read them again now
    // must not leave the old fingerprint to report the same edit again.
    if (reading.tagFingerprint == null && editedTags != null) {
      reading = reading.withTagFingerprint(editedTags);
    }
    final identity = reading.identity;

    // Not readable right now (no access, a device read failure): this says
    // nothing about the audio, so nothing is decided.
    if (reading.failure == AudioIdentityFailure.unreadable) return;

    if (!hasBaseline) {
      // First sight since version 43: the file as it is now becomes the
      // reference. Its tags are not re-applied: nothing says they changed.
      if (identity != null) await _writeIdentity(binding, reading);
      return;
    }

    final sameAudio =
        identity != null &&
        identity.signature == binding.audioSignature &&
        (binding.audioFullHash == null ||
            identity.fullHash == binding.audioFullHash);

    if (sameAudio) {
      // R2: only the tags changed.
      final metadata = await metadataResolver.resolve(candidate);
      await appDatabase.transaction((txn) async {
        await _writeIdentityIn(txn, binding, reading);
        await tagUpdater.apply(
          txn,
          songId: binding.songId,
          metadata: metadata,
          candidate: candidate,
          now: now,
        );
      });
      await _moveRelease(
        binding.songId,
        metadata,
        candidate,
        now,
        batch: batch,
      );
      return;
    }

    // Audio that can no longer be read with confidence is not a verified
    // change: the song keeps the file as it was known, and nothing is said.
    if (identity == null) return;

    // R3: the audio itself changed, verified from its bytes. Nothing is
    // written; the user decides.
    await _queue(
      candidate,
      kind: PendingFileReviewKind.audioChanged,
      songIds: [binding.songId],
      metadata: await _metadataOrNull(candidate),
      now: now,
    );
  }

  // R0, R4, R5, R6.
  Future<ImportResult?> _matchByAudio(
    ImportCandidate candidate,
    FileIdentityReading reading, {
    required List<MediaFileBinding> bindings,
    required Set<String> deleted,
    required Set<String> claimed,
    required ImportScanSnapshot? scan,
    required ResolvedMetadata? metadata,
    required DateTime now,
    required List<ReleaseMoveIntent> batch,
  }) async {
    final identity = reading.identity!;
    final path = TextNormalizer.normalizePath(candidate.filePath);

    if (deleted.contains(identity.signature)) {
      return ImportResult(
        status: ImportResultStatus.skipped,
        filePath: candidate.filePath,
        skipReason: ImportSkipReason.deletedFromLibrary,
      );
    }

    final sameSignature = [
      for (final b in bindings)
        if (b.audioSignature == identity.signature &&
            b.signatureVersion == AudioIdentity.currentVersion &&
            b.normalizedPath != path)
          b,
    ];
    if (sameSignature.isEmpty) return null;

    // R5: a copy of a file that is still there.
    for (final live in sameSignature.where(
      (b) => ImportScanSnapshot.isLive(b, scan),
    )) {
      final liveHash = live.audioFullHash ?? await _fullHashOf(live.filePath);
      if (liveHash != null && liveHash == identity.fullHash) {
        return ImportResult(
          status: ImportResultStatus.skipped,
          filePath: candidate.filePath,
          songId: live.songId,
          skipReason: ImportSkipReason.duplicateRecording,
        );
      }
    }

    final missing = [
      for (final b in sameSignature)
        if (!ImportScanSnapshot.isLive(b, scan) && !claimed.contains(b.id)) b,
    ];
    if (missing.isEmpty) return null;

    final songIds = {for (final b in missing) b.songId}.toList();
    final proven =
        missing.length == 1 &&
        missing.single.audioFullHash != null &&
        missing.single.audioFullHash == identity.fullHash;

    if (!proven) {
      // R6: the same sampled audio, but more than one candidate or no
      // stored proof of the whole audio.
      return _queue(
        candidate,
        kind: PendingFileReviewKind.possibleReplacedFile,
        songIds: songIds,
        metadata: metadata ?? await _metadataOrNull(candidate),
        now: now,
      );
    }

    // R4: byte-identical audio. The binding moves; the Song ID stays.
    final binding = missing.single;
    claimed.add(binding.id);
    final tags = metadata ?? await metadataResolver.resolve(candidate);
    await appDatabase.transaction((txn) async {
      await txn.update(
        DatabaseTables.mediaFileBindings,
        {
          'file_path': candidate.filePath.trim(),
          'normalized_path': path,
          'source_id': candidate.sourceId ?? binding.sourceId,
          'is_available': 1,
          'last_seen_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          ..._identityColumns(reading, stored: binding),
        },
        where: 'id = ?',
        whereArgs: [binding.id],
      );
      await tagUpdater.apply(
        txn,
        songId: binding.songId,
        metadata: tags,
        candidate: candidate,
        now: now,
      );
    });
    await _moveRelease(binding.songId, tags, candidate, now, batch: batch);

    return ImportResult(
      status: ImportResultStatus.relinked,
      filePath: candidate.filePath,
      songId: binding.songId,
    );
  }

  // R7: no audio proof, but a missing song of about the same length in the
  // same folder may be this file. It is not imported as a new song.
  Future<ImportResult?> _possiblyReplaced(
    ImportCandidate candidate, {
    required ResolvedMetadata? metadata,
    required List<MediaFileBinding> bindings,
    required Set<String> claimed,
    required ImportScanSnapshot? scan,
    required DateTime now,
  }) async {
    final folder = SourceFolderKey.of(candidate.filePath);
    if (folder == null) return null;

    final missingHere = [
      for (final b in bindings)
        if (!claimed.contains(b.id) &&
            !ImportScanSnapshot.isLive(b, scan) &&
            SourceFolderKey.of(b.filePath) == folder)
          b,
    ];
    if (missingHere.isEmpty) return null;

    final tags = metadata ?? await _metadataOrNull(candidate);
    if (tags == null || tags.metadata.durationSeconds <= 0) return null;
    final duration = tags.metadata.durationSeconds;

    final db = await appDatabase.database;
    final candidates = <(String, int)>[];
    for (final songId in {for (final b in missingHere) b.songId}) {
      if (await _hasLiveFile(db, songId, scan)) continue;
      final rows = await db.query(
        DatabaseTables.songs,
        columns: ['duration_seconds'],
        where: 'id = ?',
        whereArgs: [songId],
      );
      if (rows.isEmpty) continue;
      final songDuration = rows.single['duration_seconds'] as int? ?? 0;
      if (songDuration <= 0 ||
          RecordingEvidence.durationsDiffer(songDuration, duration)) {
        continue;
      }
      candidates.add((songId, (songDuration - duration).abs()));
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    return _queue(
      candidate,
      kind: PendingFileReviewKind.possibleReplacedFile,
      songIds: [for (final (id, _) in candidates) id],
      metadata: tags,
      now: now,
    );
  }

  Future<bool> _hasLiveFile(
    DatabaseExecutor db,
    String songId,
    ImportScanSnapshot? scan,
  ) async {
    for (final row in await db.query(
      DatabaseTables.mediaFileBindings,
      where: 'song_id = ?',
      whereArgs: [songId],
    )) {
      if (ImportScanSnapshot.isLiveRow(row, scan)) return true;
    }
    return false;
  }

  Future<ImportResult> _queue(
    ImportCandidate candidate, {
    required PendingFileReviewKind kind,
    required List<String> songIds,
    required ResolvedMetadata? metadata,
    required DateTime now,
  }) async {
    final tags = metadata?.metadata;
    final normalizedPath = TextNormalizer.normalizePath(candidate.filePath);
    await reviewStore?.upsert(
      PendingPossibleRecording(
        normalizedPath: normalizedPath,
        filePath: candidate.filePath.trim(),
        candidateSongId: songIds.first,
        otherCandidateSongIds: songIds.skip(1).toList(growable: false),
        title: tags?.title ?? '',
        artistName: tags?.artistName ?? '',
        albumTitle: tags?.albumTitle ?? '',
        discNumber: tags?.discNumber ?? 0,
        trackNumber: tags?.trackNumber ?? 0,
        durationSeconds: tags?.durationSeconds ?? 0,
        firstSeenAt: now.toUtc(),
        metadataFallbackPath: candidate.metadataFallbackPath,
        sourceId: candidate.sourceId,
        metadataSource: metadata?.source,
        kind: kind,
      ),
    );
    return ImportResult(
      status: ImportResultStatus.skipped,
      filePath: candidate.filePath,
      songId: songIds.first,
      skipReason: ImportSkipReason.awaitingFileReview,
    );
  }

  Future<ResolvedMetadata?> _metadataOrNull(ImportCandidate candidate) async {
    try {
      return await metadataResolver.resolve(candidate);
    } catch (error, stackTrace) {
      _log('reading tags for review', error, stackTrace);
      return null;
    }
  }

  Future<(int?, DateTime?)> _stat(ImportCandidate candidate) async {
    if (candidate.fileSizeBytes != null && candidate.modifiedAt != null) {
      return (candidate.fileSizeBytes, candidate.modifiedAt);
    }
    final source = await openSource(candidate.filePath);
    if (source == null) return (null, null);
    try {
      return (await source.length(), await source.modifiedAt());
    } finally {
      await source.close();
    }
  }

  /// The file's audio identity with its full hash, or why there is none.
  Future<FileIdentityReading> _read(ImportCandidate candidate) async {
    final source = await openSource(candidate.filePath);
    if (source == null) {
      return FileIdentityReading(
        identity: null,
        failure: AudioIdentityFailure.unreadable,
        fileSizeBytes: candidate.fileSizeBytes,
        modifiedAt: candidate.modifiedAt,
      );
    }
    try {
      final size = candidate.fileSizeBytes ?? await source.length();
      final modifiedAt = candidate.modifiedAt ?? await source.modifiedAt();
      final read = await reader.read(source);
      final sampled = read.identity;
      final hash = sampled == null
          ? null
          : await reader.fullHash(source, sampled.region);
      return FileIdentityReading(
        identity: hash == null ? null : sampled!.withFullHash(hash),
        failure:
            read.failure ??
            (hash == null ? AudioIdentityFailure.unreadable : null),
        fileSizeBytes: size,
        modifiedAt: modifiedAt,
        tagFingerprint: await tagReader.read(
          RangeCachedAudioByteSource(source, knownLength: size),
        ),
      );
    } finally {
      await source.close();
    }
  }

  Future<String?> _fullHashOf(String filePath) async {
    final source = await openSource(filePath);
    if (source == null) return null;
    try {
      final identity = (await reader.read(source)).identity;
      return identity == null
          ? null
          : await reader.fullHash(source, identity.region);
    } finally {
      await source.close();
    }
  }

  Future<void> _writeIdentity(
    MediaFileBinding binding,
    FileIdentityReading reading,
  ) =>
      appDatabase.transaction((txn) => _writeIdentityIn(txn, binding, reading));

  Future<void> _writeIdentityIn(
    DatabaseExecutor txn,
    MediaFileBinding binding,
    FileIdentityReading reading,
  ) => txn.update(
    DatabaseTables.mediaFileBindings,
    _identityColumns(reading, stored: binding),
    where: 'id = ?',
    whereArgs: [binding.id],
  );

  /// The identity columns of [reading], to write over [stored] (the
  /// binding's row before this write, if it has one).
  ///
  /// A tag fingerprint that could not be read this time (a temporary access
  /// error, or tags that cannot be walked) proves nothing about the tags,
  /// so the last trusted one is kept while the file is evidently the one it
  /// was taken from: the same size, time and audio. It is cleared only when
  /// the file itself changed, which proves it stale.
  static Map<String, Object?> _identityColumns(
    FileIdentityReading reading, {
    required MediaFileBinding? stored,
  }) {
    final identity = reading.identity!;
    final keepStoredFingerprint =
        reading.tagFingerprint == null &&
        stored?.tagFingerprint != null &&
        _sameFile(stored!, reading);
    return {
      'audio_signature': identity.signature,
      'audio_full_hash': identity.fullHash,
      'signature_version': identity.version,
      'file_size_bytes': reading.fileSizeBytes,
      'modified_at': reading.modifiedAt?.toUtc().toIso8601String(),
      if (!keepStoredFingerprint)
        'tag_fingerprint': reading.tagFingerprint?.value,
    };
  }

  /// [reading] is of the very file [stored] describes: its size and time
  /// are unchanged and, where an audio identity of the same rules is
  /// stored, so is its audio. Without one, size and time are the evidence,
  /// as for an unchanged file (R1).
  static bool _sameFile(MediaFileBinding stored, FileIdentityReading reading) {
    final identity = reading.identity!;
    final sameSizeAndTime =
        stored.fileSizeBytes != null &&
        stored.fileSizeBytes == reading.fileSizeBytes &&
        stored.modifiedAt != null &&
        stored.modifiedAt!.toUtc() == reading.modifiedAt?.toUtc();
    if (!sameSizeAndTime) return false;
    final comparable =
        stored.audioSignature != null &&
        stored.signatureVersion == identity.version;
    if (!comparable) return true;
    return stored.audioSignature == identity.signature &&
        (stored.audioFullHash == null ||
            stored.audioFullHash == identity.fullHash);
  }

  /// The tags' fingerprint alone: a few small reads, never the audio.
  /// Null when the file cannot be opened or its tags not walked.
  Future<TagFingerprint?> _fingerprintOf(ImportCandidate candidate) async {
    final source = await openSource(candidate.filePath);
    if (source == null) return null;
    try {
      // A few small reads at each end: served from one read each, which on
      // the phone is most of a scan's cost (BUG-09 profiling).
      return await tagReader.read(
        RangeCachedAudioByteSource(
          source,
          knownLength: candidate.fileSizeBytes,
        ),
      );
    } finally {
      await source.close();
    }
  }

  /// Logs the failure's type only: never a path or a title.
  static void _log(String step, Object error, StackTrace stackTrace) =>
      developer.log(
        'File identity failed while $step (${error.runtimeType})',
        name: 'sonus.import.file_identity',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
}
