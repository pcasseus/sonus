import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/presentation/widgets/cover_art_album_search_dialog.dart';

const _releaseGroupId = '22222222-2222-4222-8222-222222222222';

const _album = ExternalMetadataCandidate(
  provider: ExternalMetadataProviderKind.musicBrainz,
  entityKind: ExternalMetadataEntityKind.album,
  providerEntityId: _releaseGroupId,
  displayName: 'Test Album',
  artistCredits: [ExternalMetadataArtistCredit(name: 'Test Artist')],
  releaseGroupId: _releaseGroupId,
);

const _query = ExternalMetadataSearchQuery(
  entityKind: ExternalMetadataEntityKind.album,
  title: 'Test Album',
  artistName: 'Test Artist',
);

void main() {
  testWidgets('shows album candidates without applying metadata', (
    tester,
  ) async {
    final provider = _FakeMetadataProvider(results: [_album]);

    await _showDialog(tester, provider);

    expect(
      find.byKey(const ValueKey('cover-art-album-search-results')),
      findsOneWidget,
    );
    expect(find.text('Test Album'), findsOneWidget);
    expect(find.textContaining('Test Artist'), findsOneWidget);
    expect(provider.searchCount, 1);
  });

  testWidgets('returns selected album candidate', (tester) async {
    final provider = _FakeMetadataProvider(results: [_album]);
    ExternalMetadataCandidate? selected;

    await _showDialog(
      tester,
      provider,
      onSelection: (candidate) => selected = candidate,
    );

    await tester.tap(
      find.byKey(const ValueKey('cover-art-album-result-$_releaseGroupId')),
    );
    await tester.pumpAndSettle();

    expect(selected, same(_album));
    expect(
      find.byKey(const ValueKey('cover-art-album-search-dialog')),
      findsNothing,
    );
  });

  testWidgets('cancellation returns no candidate', (tester) async {
    final provider = _FakeMetadataProvider(results: [_album]);
    ExternalMetadataCandidate? selected;

    await _showDialog(
      tester,
      provider,
      onSelection: (candidate) => selected = candidate,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(
      find.byKey(const ValueKey('cover-art-album-search-dialog')),
      findsNothing,
    );
  });

  testWidgets('shows empty search results', (tester) async {
    await _showDialog(tester, _FakeMetadataProvider(results: []));

    expect(
      find.byKey(const ValueKey('cover-art-album-search-empty')),
      findsOneWidget,
    );
  });

  testWidgets('shows failure and allows retry', (tester) async {
    final provider = _FakeMetadataProvider(
      results: [_album],
      failFirstSearch: true,
    );

    await _showDialog(tester, provider);

    expect(
      find.byKey(const ValueKey('cover-art-album-search-error')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('cover-art-album-search-retry')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('cover-art-album-search-results')),
      findsOneWidget,
    );
    expect(provider.searchCount, 2);
  });

  testWidgets('filters out non-album candidates', (tester) async {
    final provider = _FakeMetadataProvider(
      results: [
        _album,
        const ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.track,
          providerEntityId: 'recording-1',
          displayName: 'Other Track',
        ),
      ],
    );

    await _showDialog(tester, provider);

    expect(find.text('Test Album'), findsOneWidget);
    expect(find.text('Other Track'), findsNothing);
  });
}

Future<void> _showDialog(
  WidgetTester tester,
  MetadataProvider provider, {
  void Function(ExternalMetadataCandidate?)? onSelection,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final candidate = await showDialog<ExternalMetadataCandidate>(
                  context: context,
                  builder: (_) => CoverArtAlbumSearchDialog(
                    provider: provider,
                    query: _query,
                  ),
                );
                onSelection?.call(candidate);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _FakeMetadataProvider implements MetadataProvider {
  _FakeMetadataProvider({required this.results, this.failFirstSearch = false});

  final List<ExternalMetadataCandidate> results;
  final bool failFirstSearch;
  int searchCount = 0;

  @override
  ExternalMetadataProviderKind get providerKind =>
      ExternalMetadataProviderKind.musicBrainz;

  @override
  Future<List<ExternalMetadataCandidate>> search(
    ExternalMetadataSearchQuery query,
  ) async {
    searchCount++;

    if (failFirstSearch && searchCount == 1) {
      throw StateError('Simulated search failure.');
    }

    return results;
  }

  @override
  Future<ExternalMetadataCandidate?> lookup({
    required ExternalMetadataEntityKind entityKind,
    required String providerEntityId,
  }) async => null;
}
