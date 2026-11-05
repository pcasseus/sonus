import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/song_credit_line.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/presentation/models/song_credit_summary.dart';

// UI redesign C2: compact credit summaries for soundtracks and cast
// recordings.
void main() {
  group('songCreditSummary', () {
    test('three or fewer credited names are never collapsed', () {
      final summary = songCreditSummary(
        primaryArtistName: 'Lead',
        featuredArtists: const ['Ada', 'Ben', 'Cy'],
        omitPrimary: true,
      );

      expect(summary.isCollapsible, isFalse);
      expect(summary.compact, isNull);
      expect(summary.full, 'Ft. Ada, Ben, Cy');
    });

    test('more than three names keep two and count the rest', () {
      final summary = songCreditSummary(
        primaryArtistName: 'Lead',
        featuredArtists: const ['Ada', 'Ben', 'Cy', 'Dee', 'Eve'],
        omitPrimary: true,
      );

      expect(summary.isCollapsible, isTrue);
      expect(summary.compact, 'Ft. Ada, Ben + 3 others');
      expect(summary.hiddenCount, 3);
      expect(summary.full, 'Ft. Ada, Ben, Cy, Dee, Eve');
    });

    test('keeps role connectors across roles', () {
      final summary = songCreditSummary(
        primaryArtistName: 'Lead',
        featuredArtists: const ['Ada'],
        guestArtists: const ['Ben', 'Cy', 'Dee'],
        omitPrimary: true,
      );

      expect(summary.compact, 'Ft. Ada with Ben + 2 others');
    });

    test('co-primary leads count when shown', () {
      final summary = songCreditSummary(
        primaryArtistName: 'Lead',
        coPrimaryArtists: const ['Co'],
        featuredArtists: const ['Ada', 'Ben'],
        omitPrimary: true,
      );

      expect(summary.compact, 'Lead & Co + 2 others');
      expect(summary.full, 'Lead & Co Ft. Ada, Ben');
    });

    test('full line always equals songCreditLine', () {
      const featured = ['Ada', ' ', 'Ben', 'Cy', 'Dee'];
      final summary = songCreditSummary(
        primaryArtistName: 'Lead',
        featuredArtists: featured,
        guestArtists: const ['Eve'],
      );

      expect(
        summary.full,
        songCreditLine(
          primaryArtistName: 'Lead',
          featuredArtists: featured,
          guestArtists: const ['Eve'],
        ),
      );
      expect(summary.compact, 'Lead Ft. Ada + 4 others');
    });

    test('blank names are not counted', () {
      final summary = songCreditSummary(
        primaryArtistName: 'Lead',
        featuredArtists: const ['Ada', '', ' ', 'Ben', 'Cy'],
        omitPrimary: true,
      );

      expect(summary.isCollapsible, isFalse);
    });

    test('the threshold is a named constant', () {
      expect(compactCreditMaxNames, 3);
      expect(compactCreditShownNames, 2);
      expect(compactCreditReleaseKinds, {
        ReleaseKind.soundtrack,
        ReleaseKind.castRecording,
      });
    });
  });
}
