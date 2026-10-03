import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 3, 12);
  final updatedAt = DateTime.utc(2026, 10, 3, 13);

  Song createSong({
    String? versionLabel,
    List<SongVersionCharacteristic> versionCharacteristics = const [],
    SongReleaseStatus releaseStatus = SongReleaseStatus.released,
    bool isLeak = false,
  }) {
    return Song(
      id: 'song-1',
      artistId: 'artist-1',
      albumId: 'album-1',
      albumEditionId: 'edition-1',
      title: 'Song',
      canonicalTitle: 'song',
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      versionLabel: versionLabel,
      versionCharacteristics: versionCharacteristics,
      releaseStatus: releaseStatus,
      isLeak: isLeak,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  test('defaults version and release metadata safely', () {
    final song = createSong();

    expect(song.versionLabel, isNull);
    expect(song.versionCharacteristics, isEmpty);
    expect(song.releaseStatus, SongReleaseStatus.released);
    expect(song.isLeak, isFalse);
  });

  test('copyWith preserves, changes, and clears version metadata', () {
    final song = createSong(
      versionLabel: 'Early Mix',
      versionCharacteristics: const [
        SongVersionCharacteristic.live,
        SongVersionCharacteristic.acoustic,
      ],
      releaseStatus: SongReleaseStatus.unreleased,
      isLeak: true,
    );

    final preserved = song.copyWith(title: 'Updated Song');

    expect(preserved.versionLabel, 'Early Mix');
    expect(preserved.versionCharacteristics, const [
      SongVersionCharacteristic.live,
      SongVersionCharacteristic.acoustic,
    ]);
    expect(preserved.releaseStatus, SongReleaseStatus.unreleased);
    expect(preserved.isLeak, isTrue);

    final changed = song.copyWith(
      versionLabel: null,
      versionCharacteristics: const [SongVersionCharacteristic.remix],
      releaseStatus: SongReleaseStatus.released,
      isLeak: false,
    );

    expect(changed.versionLabel, isNull);
    expect(changed.versionCharacteristics, const [
      SongVersionCharacteristic.remix,
    ]);
    expect(changed.releaseStatus, SongReleaseStatus.released);
    expect(changed.isLeak, isFalse);
  });
}
