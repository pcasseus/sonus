import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/settings/presentation/pages/blacklisted_songs_page.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  testWidgets('shows unavailable state without library repository', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BlacklistedSongsPage()));

    expect(
      find.byKey(const ValueKey<String>('blacklisted-songs-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('shows only blacklisted songs', (tester) async {
    final repository = _FakeLibraryQueryRepository(
      tracks: [
        _track(
          songId: 'blocked-1',
          title: 'Blacklisted One',
          isSongBlocked: true,
        ),
        _track(songId: 'normal', title: 'Normal Song'),
        _track(
          songId: 'blocked-2',
          title: 'Blacklisted Two',
          isSongBlocked: true,
        ),
      ],
    );

    await tester.pumpWidget(_buildSubject(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Blacklisted One'), findsOneWidget);
    expect(find.text('Blacklisted Two'), findsOneWidget);
    expect(find.text('Normal Song'), findsNothing);

    expect(
      find.byKey(const ValueKey<String>('blacklisted-songs-list')),
      findsOneWidget,
    );
  });

  testWidgets('shows empty state when no songs are blacklisted', (
    tester,
  ) async {
    final repository = _FakeLibraryQueryRepository(
      tracks: [_track(songId: 'normal', title: 'Normal Song')],
    );

    await tester.pumpWidget(_buildSubject(repository: repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('blacklisted-songs-empty')),
      findsOneWidget,
    );
    expect(find.text('No blacklisted songs'), findsOneWidget);
  });

  testWidgets('removes song from blacklist and refreshes list', (tester) async {
    final repository = _FakeLibraryQueryRepository(
      tracks: [
        _track(songId: 'blocked-song', title: 'Remove Me', isSongBlocked: true),
      ],
    );

    final service = _FakeSongBlockService(
      onSetBlocked: ({required songId, required isBlocked}) {
        repository.setBlocked(songId, isBlocked);
      },
    );

    final accountController = AccountController(
      repository: const _FakeAccountRepository(
        currentUser: AccountUser(id: 'user-1', email: 'user@example.com'),
      ),
    );

    await tester.pumpWidget(
      _buildSubject(
        repository: repository,
        songBlockService: service,
        accountController: accountController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remove Me'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('remove-blacklisted-song-blocked-song'),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.setBlockedCallCount, 1);
    expect(service.lastUserId, 'user-1');
    expect(service.lastSongId, 'blocked-song');
    expect(service.lastIsBlocked, isFalse);

    expect(find.text('Remove Me'), findsNothing);
    expect(find.text('No blacklisted songs'), findsOneWidget);
    expect(find.text('Removed from blacklist.'), findsOneWidget);
  });

  testWidgets('signed-out user can remove a song from the blacklist locally', (
    tester,
  ) async {
    final repository = _FakeLibraryQueryRepository(
      tracks: [
        _track(
          songId: 'blocked-song',
          title: 'Blocked Song',
          isSongBlocked: true,
        ),
      ],
    );

    final service = _FakeSongBlockService(
      onSetBlocked: ({required songId, required isBlocked}) {
        repository.setBlocked(songId, isBlocked);
      },
    );

    await tester.pumpWidget(
      _buildSubject(repository: repository, songBlockService: service),
    );
    await tester.pumpAndSettle();

    final buttonFinder = find.byKey(
      const ValueKey<String>('remove-blacklisted-song-blocked-song'),
    );

    final button = tester.widget<IconButton>(buttonFinder);

    expect(button.onPressed, isNotNull);
    expect(find.byTooltip('Remove from blacklist'), findsOneWidget);

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(service.setBlockedCallCount, 1);
    expect(service.lastUserId, isNull);
    expect(service.lastSongId, 'blocked-song');
    expect(service.lastIsBlocked, isFalse);

    expect(find.text('Blocked Song'), findsNothing);
    expect(find.text('No blacklisted songs'), findsOneWidget);
    expect(find.text('Removed from blacklist.'), findsOneWidget);
  });
}

Widget _buildSubject({
  required LibraryQueryRepository repository,
  SongBlockService? songBlockService,
  AccountController? accountController,
}) {
  return MultiProvider(
    providers: [
      Provider<LibraryQueryRepository?>.value(value: repository),
      Provider<SongBlockService?>.value(value: songBlockService),
      ChangeNotifierProvider<AccountController?>.value(
        value: accountController,
      ),
    ],
    child: const MaterialApp(home: BlacklistedSongsPage()),
  );
}

LibraryTrack _track({
  required String songId,
  required String title,
  bool isSongBlocked = false,
  bool isAvailable = true,
  String? filePath = '/music/song.mp3',
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: 'artist-1',
    artistName: 'Artist',
    albumId: 'album-1',
    albumTitle: 'Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath,
    isAvailable: isAvailable,
    isSongBlocked: isSongBlocked,
  );
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({List<LibraryTrack> tracks = const []})
    : _tracks = List<LibraryTrack>.from(tracks);

  final List<LibraryTrack> _tracks;

  void setBlocked(String songId, bool isBlocked) {
    final index = _tracks.indexWhere((track) => track.songId == songId);

    if (index < 0) {
      return;
    }

    final track = _tracks[index];

    _tracks[index] = LibraryTrack(
      songId: track.songId,
      title: track.title,
      artistId: track.artistId,
      artistName: track.artistName,
      albumId: track.albumId,
      albumTitle: track.albumTitle,
      albumEditionId: track.albumEditionId,
      albumEditionTitle: track.albumEditionTitle,
      albumEditionType: track.albumEditionType,
      trackNumber: track.trackNumber,
      discNumber: track.discNumber,
      durationSeconds: track.durationSeconds,
      isSingle: track.isSingle,
      featuredArtists: track.featuredArtists,
      dateAdded: track.dateAdded,
      filePath: track.filePath,
      isAvailable: track.isAvailable,
      isSongBlocked: isBlocked,
      artworkId: track.artworkId,
      artworkPath: track.artworkPath,
    );
  }

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return List<LibraryTrack>.from(_tracks);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async =>
      const [];

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async => null;

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async =>
      const [];

  @override
  Future<List<LibraryArtist>> getArtists() async => const [];

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async => null;

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async =>
      const [];

  @override
  Future<LibraryTrack?> getTrackById(String songId) async => null;

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async =>
      const [];

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];
}

class _FakeSongBlockService extends SongBlockService {
  _FakeSongBlockService({this.onSetBlocked})
    : super(mutationRunner: _UnusedMutationRunner());

  final void Function({required String songId, required bool isBlocked})?
  onSetBlocked;

  int setBlockedCallCount = 0;
  String? lastUserId;
  String? lastSongId;
  bool? lastIsBlocked;

  @override
  Future<Song> setBlocked({
    String? userId,
    required String songId,
    required bool isBlocked,
    DateTime? now,
  }) async {
    setBlockedCallCount++;
    lastUserId = userId;
    lastSongId = songId;
    lastIsBlocked = isBlocked;

    onSetBlocked?.call(songId: songId, isBlocked: isBlocked);

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return Song(
      id: songId,
      artistId: 'artist-1',
      albumId: 'album-1',
      albumEditionId: 'edition-1',
      title: 'Song',
      canonicalTitle: 'song',
      trackNumber: 1,
      discNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      artworkId: null,
      isBlocked: isBlocked,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}

class _FakeAccountRepository implements AccountRepository {
  const _FakeAccountRepository({this.currentUser});

  @override
  final AccountUser? currentUser;

  @override
  Stream<AccountUser?> watchAuthState() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _UnusedMutationRunner implements SyncMutationRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Mutation runner should not be used.');
  }
}
