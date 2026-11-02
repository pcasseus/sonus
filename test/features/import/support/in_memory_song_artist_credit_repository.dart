import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/domain/repositories/song_artist_credit_repository.dart';

/// Stored song credits for Import Review tests; reads only.
class InMemorySongArtistCreditRepository implements SongArtistCreditRepository {
  InMemorySongArtistCreditRepository([this.credits = const []]);

  final List<SongArtistCredit> credits;

  @override
  Future<List<SongArtistCredit>> getBySongId(String songId) async {
    return [
      for (final credit in credits)
        if (credit.songId == songId) credit,
    ];
  }

  @override
  Future<SongArtistCredit?> getById(String id) async {
    for (final credit in credits) {
      if (credit.id == id) return credit;
    }
    return null;
  }

  @override
  Future<List<SongArtistCredit>> getByArtistId(String artistId) async {
    return [
      for (final credit in credits)
        if (credit.artistId == artistId) credit,
    ];
  }

  @override
  Future<List<SongArtistCredit>> getUnlinkedByCanonicalName(
    String canonicalName,
  ) async {
    return const [];
  }

  @override
  Future<void> create(SongArtistCredit credit) {
    throw UnsupportedError('Import Review tests only read credits.');
  }

  @override
  Future<void> save(SongArtistCredit credit) {
    throw UnsupportedError('Import Review tests only read credits.');
  }

  @override
  Future<void> delete(String id) {
    throw UnsupportedError('Import Review tests only read credits.');
  }

  @override
  Future<void> deleteBySongId(String songId) {
    throw UnsupportedError('Import Review tests only read credits.');
  }
}
