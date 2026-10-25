// J9: online metadata lookups had no first-use disclosure; the first search
// contacted MusicBrainz immediately.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sonus_next/core/privacy/online_lookup_consent.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_application_service.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/presentation/widgets/cover_art_album_search_dialog.dart';
import 'package:sonus_next/features/library/presentation/widgets/musicbrainz_search_dialog.dart';
import 'package:sonus_next/features/settings/application/controllers/metadata_intelligence_settings_controller.dart';

class _CountingProvider implements MetadataProvider {
  int searches = 0;

  @override
  ExternalMetadataProviderKind get providerKind =>
      ExternalMetadataProviderKind.musicBrainz;

  @override
  Future<List<ExternalMetadataCandidate>> search(
    ExternalMetadataSearchQuery query,
  ) async {
    searches++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Consent implements OnlineLookupConsent {
  _Consent({required this.isOnlineLookupAccepted});

  @override
  bool isOnlineLookupAccepted;

  @override
  Future<void> acceptOnlineLookup() async => isOnlineLookupAccepted = true;
}

void main() {
  const trackQuery = ExternalMetadataSearchQuery(
    entityKind: ExternalMetadataEntityKind.track,
    title: 'Song',
  );
  const albumQuery = ExternalMetadataSearchQuery(
    entityKind: ExternalMetadataEntityKind.album,
    albumTitle: 'Album',
  );

  Future<void> pump(WidgetTester tester, _Consent consent, Widget dialog) {
    return tester.pumpWidget(
      Provider<OnlineLookupConsent?>.value(
        value: consent,
        child: MaterialApp(home: dialog),
      ),
    );
  }

  final dialogs = <String, Widget Function(MetadataProvider)>{
    'MusicBrainz search': (provider) => MusicBrainzSearchDialog(
      provider: provider,
      query: trackQuery,
      applier: (_) async => const ExternalMetadataApplicationResult(),
    ),
    'cover art search': (provider) =>
        CoverArtAlbumSearchDialog(provider: provider, query: albumQuery),
  };

  for (final MapEntry(key: name, value: build) in dialogs.entries) {
    group(name, () {
      testWidgets('discloses before the first lookup', (tester) async {
        final provider = _CountingProvider();
        final consent = _Consent(isOnlineLookupAccepted: false);

        await pump(tester, consent, build(provider));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('online-lookup-disclosure')),
          findsOneWidget,
        );
        expect(provider.searches, 0, reason: 'nothing sent before consent');

        await tester.tap(
          find.byKey(const ValueKey<String>('online-lookup-accept')),
        );
        await tester.pumpAndSettle();

        expect(consent.isOnlineLookupAccepted, isTrue);
        expect(provider.searches, 1);
      });

      testWidgets('searches at once after consent', (tester) async {
        final provider = _CountingProvider();

        await pump(
          tester,
          _Consent(isOnlineLookupAccepted: true),
          build(provider),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('online-lookup-disclosure')),
          findsNothing,
        );
        expect(provider.searches, 1);
      });
    });
  }

  test('consent is off until accepted, then remembered', () async {
    SharedPreferences.setMockInitialValues({});

    final first = MetadataIntelligenceSettingsController();
    addTearDown(first.dispose);
    await first.load();
    expect(first.isOnlineLookupAccepted, isFalse);

    await first.acceptOnlineLookup();

    final later = MetadataIntelligenceSettingsController();
    addTearDown(later.dispose);
    await later.load();
    expect(later.isOnlineLookupAccepted, isTrue);
  });

  test('import never depends on the online metadata provider', () {
    final importFiles = Directory('lib/features/import')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in importFiles) {
      expect(
        file.readAsStringSync(),
        isNot(contains('metadata_provider.dart')),
        reason: '${file.path} must stay offline',
      );
    }
  });
}
