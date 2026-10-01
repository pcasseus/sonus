import '../entities/song_artist_credit.dart';

abstract interface class SongArtistCreditRepository {
  Future<void> create(SongArtistCredit credit);

  Future<void> save(SongArtistCredit credit);

  Future<void> delete(String id);

  Future<SongArtistCredit?> getById(String id);

  Future<List<SongArtistCredit>> getBySongId(String songId);

  Future<List<SongArtistCredit>> getByArtistId(String artistId);

  Future<List<SongArtistCredit>> getUnlinkedByCanonicalName(
    String canonicalName,
  );
}
