import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/presentation/models/track_profile_edit_draft.dart';

void main() {
  final timestamp = DateTime.utc(2026, 10, 29);

  SongArtistCredit credit(
    String name,
    SongArtistCreditRole role,
    int position, {
    String? artistId,
  }) {
    return SongArtistCredit(
      id: 'credit-$position',
      songId: 'song-1',
      artistId: artistId,
      creditedName: name,
      canonicalCreditedName: name.toLowerCase(),
      role: role,
      position: position,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  String describe(TrackProfileCreditDraft draft) =>
      '${draft.role.name}:${draft.creditedName}:${draft.artistId}';

  group('trackStudioInitialCredits (SN-50 C-Q4)', () {
    test('seeds older featured names when no structured credits exist', () {
      final drafts = trackStudioInitialCredits(
        credits: const [],
        legacyFeaturedArtists: const ['Legacy Feat', 'Crane, The Lantern'],
        primaryArtistId: 'artist-ada',
        primaryArtistName: 'Ada Vale',
      );

      expect(drafts.map(describe), [
        'featured:Legacy Feat:null',
        'featured:Crane, The Lantern:null',
      ]);
    });

    test('adds older featured names after structured non-featured credits, '
        'skipping repeats and the primary artist', () {
      final drafts = trackStudioInitialCredits(
        credits: [
          credit('Eve Shore', SongArtistCreditRole.guest, 2),
          credit('Ada Vale', SongArtistCreditRole.primary, 0),
          credit(
            'Ben Moor',
            SongArtistCreditRole.coPrimary,
            1,
            artistId: 'artist-ben',
          ),
        ],
        legacyFeaturedArtists: const ['ada vale', 'Legacy Feat', 'EVE SHORE'],
        primaryArtistId: 'artist-ada',
        primaryArtistName: 'Ada Vale',
      );

      expect(drafts.map(describe), [
        'coPrimary:Ben Moor:artist-ben',
        'guest:Eve Shore:null',
        'featured:Legacy Feat:null',
      ]);
    });

    test('structured featured credits replace the older names', () {
      final drafts = trackStudioInitialCredits(
        credits: [credit('Cy Lark', SongArtistCreditRole.featured, 1)],
        legacyFeaturedArtists: const ['Stale Name'],
        primaryArtistId: 'artist-ada',
        primaryArtistName: 'Ada Vale',
      );

      expect(drafts.map(describe), ['featured:Cy Lark:null']);
    });

    test('saved drafts never link by a matching name alone (C-Q2)', () {
      const draft = TrackProfileCreditDraft(
        creditedName: 'Cy Lark',
        role: SongArtistCreditRole.featured,
      );

      expect(draft.toInput().linkByName, isFalse);
    });
  });
}
