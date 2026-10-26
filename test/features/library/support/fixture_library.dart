// Imports a fictional music folder through the real import pipeline
// (discovery layout, metadata resolution, folder planning, identity
// normalization, atomic import) into a disposable in-memory database. No
// audio files exist: each track's embedded tags are given directly.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/import_batch_executor.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/data/services/path_fallback_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';

/// One fictional file: its path under the music root and its tags.
class FixtureTrack {
  const FixtureTrack(
    this.path, {
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    this.track = 0,
  });

  /// Relative to the music root, e.g. `Artist/Album/01 Song.mp3` or
  /// `Soundtrack/01 Song.mp3`.
  final String path;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int track;
}

class _FixtureTags implements AudioMetadataReader {
  _FixtureTags(this._tags);

  final Map<String, AudioMetadata> _tags;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async =>
      _tags[candidate.filePath]!;
}

const String fixtureMusicRoot = '/storage/emulated/0/Music';

/// A fresh in-memory library database.
AppDatabase fixtureDatabase() {
  sqfliteFfiInit();
  return AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

/// Imports [tracks] as one batch, the way choosing their folder would.
/// Running it again with the same tracks is a rescan.
Future<void> importFixtureTracks(
  AppDatabase database,
  List<FixtureTrack> tracks, {
  String batchId = 'fixture',
}) async {
  final db = await database.database;
  final tags = <String, AudioMetadata>{};
  final candidates = <ImportCandidate>[];

  for (final fixture in tracks) {
    final file = '$fixtureMusicRoot/${fixture.path}';
    tags[file] = AudioMetadata(
      title: fixture.title,
      artistName: fixture.artist,
      albumTitle: fixture.album,
      albumArtistName: fixture.albumArtist,
      durationSeconds: 200,
      trackNumber: fixture.track,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
    candidates.add(
      ImportCandidate(
        filePath: file,
        normalizedPath: TextNormalizer.normalizePath(file),
        discoveredAt: DateTime.utc(2026, 10, 26),
        metadataFallbackPath: fixture.path,
        structure: fixture.path.split('/').length == 2
            ? ImportCandidateStructure.looseAlbum
            : ImportCandidateStructure.artistAlbum,
      ),
    );
  }

  await ImportBatchExecutor(
    libraryImportService: LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: _FixtureTags(tags),
        fallbackReader: const PathFallbackMetadataReader(),
      ),
      atomicImporter: AtomicLibraryImporter(appDatabase: database),
      mediaFileBindingRepository: SqliteMediaFileBindingRepository(
        MediaFileBindingDao(db),
      ),
    ),
    batchRepository: SqliteImportBatchRepository(ImportBatchDao(db)),
  ).execute(
    ImportBatch(
      id: batchId,
      createdAt: DateTime.utc(2026, 10, 26),
      items: [for (final c in candidates) ImportBatchItem(candidate: c)],
    ),
  );
}

/// Ids by name/title, for assertions.
Future<Map<String, String>> fixtureIds(
  AppDatabase database,
  String table,
  String column,
) async {
  final db = await database.database;
  return {
    for (final row in await db.query(table))
      row[column]! as String: row['id']! as String,
  };
}

Future<String> fixtureArtistId(AppDatabase database, String name) async =>
    (await fixtureIds(database, DatabaseTables.artists, 'name'))[name] ??
    (throw StateError('No artist named $name'));

Future<String> fixtureAlbumId(AppDatabase database, String title) async =>
    (await fixtureIds(database, DatabaseTables.albums, 'title'))[title] ??
    (throw StateError('No album titled $title'));
