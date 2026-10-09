import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_proposal.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
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

  testWidgets('ranks stronger MusicBrainz matches first', (tester) async {
    final provider = _FakeMetadataProvider(
      results: const [
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'weak-artist',
          displayName: 'Unrelated Artist',
        ),
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'strong-artist',
          displayName: 'Beyonce',
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
          applier: (_) async => const ExternalMetadataApplicationResult(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final strong = find.byKey(
      const ValueKey<String>('musicbrainz-result-strong-artist'),
    );
    final weak = find.byKey(
      const ValueKey<String>('musicbrainz-result-weak-artist'),
    );

    expect(strong, findsOneWidget);
    expect(weak, findsOneWidget);

    expect(tester.getTopLeft(strong).dy, lessThan(tester.getTopLeft(weak).dy));
  });

  testWidgets('warns when distinct candidates are ambiguous', (tester) async {
    final provider = _FakeMetadataProvider(
      results: const [
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'artist-a',
          displayName: 'Beyonce',
        ),
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'artist-b',
          displayName: 'Beyonce',
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
          applier: (_) async => const ExternalMetadataApplicationResult(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('musicbrainz-ambiguity-warning')),
      findsOneWidget,
    );

    expect(find.textContaining('similar match quality'), findsOneWidget);
  });
  testWidgets('shows match quality and evidence coverage', (tester) async {
    final provider = _FakeMetadataProvider(
      results: const [
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'artist-evidence',
          displayName: 'Beyonce',
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
          applier: (_) async => const ExternalMetadataApplicationResult(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final evidence = find.byKey(
      const ValueKey<String>('musicbrainz-evidence-artist-evidence'),
    );

    expect(evidence, findsOneWidget);
    expect(find.textContaining('Match quality:'), findsOneWidget);
    expect(find.textContaining('Evidence coverage:'), findsOneWidget);
  });

  testWidgets('warns when a track match has limited evidence', (tester) async {
    final provider = _FakeMetadataProvider(
      results: const [
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.track,
          providerEntityId: 'track-limited-evidence',
          displayName: 'Halo',
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
            artistName: 'Beyonce',
            albumTitle: 'I Am... Sasha Fierce',
            durationSeconds: 224,
          ),
          applier: (_) async => const ExternalMetadataApplicationResult(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('musicbrainz-evidence-track-limited-evidence'),
      ),
      findsOneWidget,
    );

    expect(
      find.byKey(
        const ValueKey<String>(
          'musicbrainz-evidence-warning-track-limited-evidence',
        ),
      ),
      findsOneWidget,
    );

    expect(find.textContaining('review carefully'), findsOneWidget);
  });
  testWidgets('cancelling proposal never invokes applier', (tester) async {
    var previewCount = 0;
    var applyCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MusicBrainzSearchDialog(
          provider: const _FakeMetadataProvider(
            results: [
              ExternalMetadataCandidate(
                provider: ExternalMetadataProviderKind.musicBrainz,
                entityKind: ExternalMetadataEntityKind.artist,
                providerEntityId: 'proposal-cancel',
                displayName: 'Beyonce',
              ),
            ],
          ),
          query: const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.artist,
            artistName: 'Beyonce',
          ),
          previewer: (candidate) async {
            previewCount++;
            return _artistProposal(candidate);
          },
          applier: (_) async {
            applyCount++;
            return const ExternalMetadataApplicationResult();
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-result-proposal-cancel')),
    );
    await tester.pumpAndSettle();

    expect(previewCount, 1);
    expect(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-review-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-cancel')),
    );
    await tester.pumpAndSettle();

    expect(applyCount, 0);
    expect(
      find.byKey(const ValueKey<String>('musicbrainz-search-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('confirming proposal invokes applier exactly once', (
    tester,
  ) async {
    var applyCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MusicBrainzSearchDialog(
          provider: const _FakeMetadataProvider(
            results: [
              ExternalMetadataCandidate(
                provider: ExternalMetadataProviderKind.musicBrainz,
                entityKind: ExternalMetadataEntityKind.artist,
                providerEntityId: 'proposal-apply',
                displayName: 'Beyonce',
              ),
            ],
          ),
          query: const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.artist,
            artistName: 'Beyonce',
          ),
          previewer: (candidate) async => _artistProposal(candidate),
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

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-result-proposal-apply')),
    );
    await tester.pumpAndSettle();

    expect(applyCount, 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
    );
    await tester.pumpAndSettle();

    expect(applyCount, 1);
  });

  testWidgets('preview failure never invokes applier', (tester) async {
    var applyCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicBrainzSearchDialog(
            provider: const _FakeMetadataProvider(
              results: [
                ExternalMetadataCandidate(
                  provider: ExternalMetadataProviderKind.musicBrainz,
                  entityKind: ExternalMetadataEntityKind.artist,
                  providerEntityId: 'proposal-error',
                  displayName: 'Beyonce',
                ),
              ],
            ),
            query: const ExternalMetadataSearchQuery(
              entityKind: ExternalMetadataEntityKind.artist,
              artistName: 'Beyonce',
            ),
            previewer: (_) async {
              throw StateError('Preview unavailable');
            },
            applier: (_) async {
              applyCount++;
              return const ExternalMetadataApplicationResult();
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-result-proposal-error')),
    );
    await tester.pumpAndSettle();

    expect(applyCount, 0);
    expect(
      find.byKey(
        const ValueKey<String>('musicbrainz-apply-confirmation-dialog'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-review-dialog')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('musicbrainz-apply-error')),
      findsOneWidget,
    );
  });

  testWidgets('ineligible proposal cannot invoke applier', (tester) async {
    var applyCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MusicBrainzSearchDialog(
          provider: const _FakeMetadataProvider(
            results: [
              ExternalMetadataCandidate(
                provider: ExternalMetadataProviderKind.musicBrainz,
                entityKind: ExternalMetadataEntityKind.artist,
                providerEntityId: 'proposal-protected',
                displayName: 'Beyonce',
              ),
            ],
          ),
          query: const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.artist,
            artistName: 'Beyonce',
          ),
          previewer: (candidate) async => ExternalMetadataProposal(
            entityType: MetadataEntityType.artist,
            entityId: 'artist_1',
            candidate: candidate,
            fields: const [
              ExternalMetadataProposalField(
                fieldName: MetadataFields.artistName,
                currentValue: 'Manual Artist',
                proposedValue: 'Beyonce',
                status: ExternalMetadataProposalFieldStatus.protected,
              ),
            ],
          ),
          applier: (_) async {
            applyCount++;
            return const ExternalMetadataApplicationResult();
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('musicbrainz-result-proposal-protected'),
      ),
    );
    await tester.pumpAndSettle();

    final applyButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
    );

    expect(applyButton.onPressed, isNull);
    expect(applyCount, 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-cancel')),
    );
    await tester.pumpAndSettle();

    expect(applyCount, 0);
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

ExternalMetadataProposal _artistProposal(ExternalMetadataCandidate candidate) {
  return ExternalMetadataProposal(
    entityType: MetadataEntityType.artist,
    entityId: 'artist_1',
    candidate: candidate,
    fields: const [
      ExternalMetadataProposalField(
        fieldName: MetadataFields.artistName,
        currentValue: 'Old Artist',
        proposedValue: 'Beyonce',
        status: ExternalMetadataProposalFieldStatus.valueChange,
      ),
    ],
  );
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
