import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/single_cover_policy.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';

/// App Update 1.3 (REF-1.3-04): one policy for where a Single's own cover
/// shows; everything else keeps its existing artwork.
SongSinglePresentation _single({
  String? cover = '/art/single.png',
  bool inCharts = false,
}) => SongSinglePresentation(
  songId: 's1',
  artworkId: cover == null ? null : 'art-single',
  artworkPath: cover,
  useArtworkInCharts: inCharts,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('Artist Profile Singles', () {
    test('the single cover first, then the existing artwork', () {
      expect(
        SingleCoverPolicy.profileCover(
          single: _single(),
          existing: '/art/album.png',
        ),
        '/art/single.png',
      );
      expect(
        SingleCoverPolicy.profileCover(single: null, existing: '/art/a.png'),
        '/art/a.png',
      );
      expect(
        SingleCoverPolicy.profileCover(
          single: _single(cover: null),
          existing: '/art/a.png',
        ),
        '/art/a.png',
      );
      expect(
        SingleCoverPolicy.profileCover(
          single: _single(cover: '  '),
          existing: ' ',
        ),
        isNull,
      );
    });
  });

  group('Moments', () {
    test('only for a Single whose cover was chosen for Moments', () {
      String? cover({required bool isSingle, required bool inCharts}) =>
          SingleCoverPolicy.momentCover(
            isSingle: isSingle,
            single: _single(inCharts: inCharts),
            existing: '/art/usual.png',
          );
      expect(cover(isSingle: true, inCharts: true), '/art/single.png');
      expect(cover(isSingle: true, inCharts: false), '/art/usual.png');
      expect(cover(isSingle: false, inCharts: true), '/art/usual.png');
      expect(cover(isSingle: false, inCharts: false), '/art/usual.png');
    });

    test('a chosen cover without a file falls back to the usual art', () {
      expect(
        SingleCoverPolicy.momentCover(
          isSingle: true,
          single: _single(cover: null, inCharts: true),
          existing: '/art/usual.png',
        ),
        '/art/usual.png',
      );
      expect(
        SingleCoverPolicy.momentCover(
          isSingle: true,
          single: null,
          existing: null,
        ),
        isNull,
      );
    });
  });
}
