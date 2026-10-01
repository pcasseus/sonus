import '../../../../core/identity/entity_id.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_context.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/song_artist_credit.dart';

class SongArtistCreditInput {
  const SongArtistCreditInput({
    required this.creditedName,
    required this.role,
    this.artistId,
  });

  final String creditedName;
  final SongArtistCreditRole role;
  final String? artistId;
}

class SongArtistCreditService {
  const SongArtistCreditService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<List<SongArtistCredit>> replaceCredits({
    required String? userId,
    required String songId,
    required String primaryArtistId,
    required Iterable<SongArtistCreditInput> additionalCredits,
    DateTime? now,
  }) {
    final normalizedSongId = songId.trim();
    final normalizedPrimaryArtistId = primaryArtistId.trim();
    final normalizedUserId = userId?.trim();

    if (normalizedSongId.isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'Song id must not be blank.');
    }

    if (normalizedPrimaryArtistId.isEmpty) {
      throw ArgumentError.value(
        primaryArtistId,
        'primaryArtistId',
        'Primary artist id must not be blank.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final credits = await replaceCreditsInContext(
        context: context,
        songId: normalizedSongId,
        primaryArtistId: normalizedPrimaryArtistId,
        additionalCredits: additionalCredits,
        now: timestamp,
      );

      final legacyFeaturedArtists = [
        for (final credit in credits)
          if (credit.role == SongArtistCreditRole.featured) credit.creditedName,
      ];

      final songChanged =
          song.artistId != normalizedPrimaryArtistId ||
          !_listsEqual(song.featuredArtists, legacyFeaturedArtists);

      if (songChanged) {
        final updatedSong = song.copyWith(
          artistId: normalizedPrimaryArtistId,
          featuredArtists: List<String>.unmodifiable(legacyFeaturedArtists),
          updatedAt: timestamp,
        );

        await context.songRepository.save(updatedSong);

        await context.localSyncRepository.recordUpsert(
          userId: normalizedUserId,
          entityType: CloudDataEntity.song,
          entityId: updatedSong.id,
        );
      }

      return credits;
    });
  }

  static Future<List<SongArtistCredit>> replaceCreditsInContext({
    required SyncMutationContext context,
    required String songId,
    required String primaryArtistId,
    required Iterable<SongArtistCreditInput> additionalCredits,
    DateTime? now,
  }) async {
    final normalizedSongId = songId.trim();
    final normalizedPrimaryArtistId = primaryArtistId.trim();

    if (normalizedSongId.isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'Song id must not be blank.');
    }

    if (normalizedPrimaryArtistId.isEmpty) {
      throw ArgumentError.value(
        primaryArtistId,
        'primaryArtistId',
        'Primary artist id must not be blank.',
      );
    }

    final song = await context.songRepository.getById(normalizedSongId);

    if (song == null) {
      throw StateError('Song not found: $normalizedSongId');
    }

    final primaryArtist = await context.artistRepository.getById(
      normalizedPrimaryArtistId,
    );

    if (primaryArtist == null) {
      throw StateError('Primary artist not found: $normalizedPrimaryArtistId');
    }

    final timestamp = now ?? DateTime.now();
    final allArtists = await context.artistRepository.getAll();

    final artistsByCanonicalName = <String, List<String>>{};

    for (final artist in allArtists) {
      artistsByCanonicalName
          .putIfAbsent(artist.canonicalName, () => <String>[])
          .add(artist.id);
    }

    final credits = <SongArtistCredit>[
      SongArtistCredit(
        id: EntityId.songArtistCredit(),
        songId: song.id,
        artistId: primaryArtist.id,
        creditedName: primaryArtist.name,
        canonicalCreditedName: primaryArtist.canonicalName,
        role: SongArtistCreditRole.primary,
        position: 0,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ];

    final seenCanonicalNames = <String>{primaryArtist.canonicalName};

    for (final input in additionalCredits) {
      if (input.role == SongArtistCreditRole.primary) {
        throw ArgumentError('Additional credits may not use the primary role.');
      }

      final creditedName = input.creditedName.trim();

      if (creditedName.isEmpty) {
        continue;
      }

      final canonicalName = TextNormalizer.canonicalize(creditedName);

      if (canonicalName.isEmpty || !seenCanonicalNames.add(canonicalName)) {
        continue;
      }

      final explicitArtistId = input.artistId?.trim();
      String? linkedArtistId;

      if (explicitArtistId != null && explicitArtistId.isNotEmpty) {
        final explicitArtist = await context.artistRepository.getById(
          explicitArtistId,
        );

        if (explicitArtist == null) {
          throw StateError('Artist not found: $explicitArtistId');
        }

        linkedArtistId = explicitArtist.id;
      } else {
        final matches =
            artistsByCanonicalName[canonicalName] ?? const <String>[];

        if (matches.length == 1) {
          linkedArtistId = matches.single;
        }
      }

      credits.add(
        SongArtistCredit(
          id: EntityId.songArtistCredit(),
          songId: song.id,
          artistId: linkedArtistId,
          creditedName: creditedName,
          canonicalCreditedName: canonicalName,
          role: input.role,
          position: credits.length,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
    }

    await context.songArtistCreditRepository.deleteBySongId(song.id);

    for (final credit in credits) {
      await context.songArtistCreditRepository.create(credit);
    }

    return List<SongArtistCredit>.unmodifiable(credits);
  }

  Future<int> linkUnlinkedCreditsForArtist({
    required String artistId,
    DateTime? now,
  }) {
    final normalizedArtistId = artistId.trim();

    if (normalizedArtistId.isEmpty) {
      throw ArgumentError.value(
        artistId,
        'artistId',
        'Artist id must not be blank.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final artist = await context.artistRepository.getById(normalizedArtistId);

      if (artist == null) {
        throw StateError('Artist not found: $normalizedArtistId');
      }

      final matchingArtists = (await context.artistRepository.getAll())
          .where((candidate) => candidate.canonicalName == artist.canonicalName)
          .toList(growable: false);

      if (matchingArtists.length != 1) {
        return 0;
      }

      final credits = await context.songArtistCreditRepository
          .getUnlinkedByCanonicalName(artist.canonicalName);

      for (final credit in credits) {
        await context.songArtistCreditRepository.save(
          credit.copyWith(artistId: artist.id, updatedAt: timestamp),
        );
      }

      return credits.length;
    });
  }

  static bool _listsEqual(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }
}
