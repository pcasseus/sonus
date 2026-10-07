import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_application_service.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/presentation/widgets/musicbrainz_search_dialog.dart';

void main() {
  testWidgets('shows MusicBrainz search results', (tester) async {
    final provider = _FakeMetadataProvider(
      results: const [
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.track,
          providerEntityId: 'recording-1',
          displayName: 'Halo',
          durationSeconds: 224,
          releaseTitle: 'I Am... Sasha Fierce',
          artistCredits: [ExternalMetadataArtistCredit(name: 'Beyoncé')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MusicBrainzSearchDialog(
          provider: provider,
          query: const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.track,
            title: 'Halo',
          ),
          applier: (_) async => const ExternalMetadataApplicationResult(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('musicbrainz-search-results')),
      findsOneWidget,
    );

    expect(find.text('Halo'), findsOneWidget);
    expect(find.textContaining('Beyoncé'), findsOneWidget);
    expect(find.textContaining('3:44'), findsOneWidget);
  });

  testWidgets('shows no-results state', (tester) async {
    final provider = _FakeMetadataProvider(results: const []);

    await tester.pumpWidget(
      MaterialApp(
        home: MusicBrainzSearchDialog(
          provider: provider,
          query: const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.artist,
            artistName: 'Nobody',
          ),
          applier: (_) async => const ExternalMetadataApplicationResult(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('musicbrainz-search-empty')),
      findsOneWidget,
    );
  });

  testWidgets('selecting and confirming candidate runs applier', (
    tester,
  ) async {
    var applyCount = 0;

    final provider = _FakeMetadataProvider(
      results: const [
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'artist-1',
          displayName: 'Beyoncé',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MusicBrainzSearchDialog(
          provider: provider,
          query: const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.artist,
            artistName: 'Beyonce',
          ),
          applier: (_) async {
            applyCount++;

            return const ExternalMetadataApplicationResult(
              changedFields: {'name'},
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Beyoncé'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('musicbrainz-apply-confirmation-dialog'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-apply-confirm')),
    );

    await tester.pumpAndSettle();

    expect(applyCount, 1);
  });
}

class _FakeMetadataProvider implements MetadataProvider {
  const _FakeMetadataProvider({required this.results});

  final List<ExternalMetadataCandidate> results;

  @override
  ExternalMetadataProviderKind get providerKind =>
      ExternalMetadataProviderKind.musicBrainz;

  @override
  Future<List<ExternalMetadataCandidate>> search(
    ExternalMetadataSearchQuery query,
  ) async {
    return results;
  }

  @override
  Future<ExternalMetadataCandidate?> lookup({
    required ExternalMetadataEntityKind entityKind,
    required String providerEntityId,
  }) async {
    return null;
  }
}
