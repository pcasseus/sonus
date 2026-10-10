import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_proposal.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/presentation/widgets/musicbrainz_proposal_review_dialog.dart';

void main() {
  ExternalMetadataProposal proposal(
    List<ExternalMetadataProposalField> fields, {
    MetadataEntityType entityType = MetadataEntityType.song,
    ExternalMetadataEntityKind entityKind = ExternalMetadataEntityKind.track,
  }) {
    return ExternalMetadataProposal(
      entityType: entityType,
      entityId: 'entity_1',
      candidate: ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: entityKind,
        providerEntityId: 'mb-1',
        displayName: 'Halo',
      ),
      fields: fields,
    );
  }

  ExternalMetadataProposalField field({
    required String name,
    required Object? current,
    required Object? proposed,
    required ExternalMetadataProposalFieldStatus status,
  }) {
    return ExternalMetadataProposalField(
      fieldName: name,
      currentValue: current,
      proposedValue: proposed,
      status: status,
    );
  }

  Future<void> showReview(
    WidgetTester tester,
    ExternalMetadataProposal review,
    ValueChanged<MusicBrainzProposalReviewDecision?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: FilledButton(
                  onPressed: () async {
                    final result =
                        await showDialog<MusicBrainzProposalReviewDecision>(
                          context: context,
                          builder: (_) =>
                              MusicBrainzProposalReviewDialog(proposal: review),
                        );
                    onResult(result);
                  },
                  child: const Text('Open review'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows proposed title and formatted duration', (tester) async {
    await showReview(
      tester,
      proposal([
        field(
          name: MetadataFields.songTitle,
          current: 'Old Track',
          proposed: 'Halo',
          status: ExternalMetadataProposalFieldStatus.valueChange,
        ),
        field(
          name: MetadataFields.songDuration,
          current: 224,
          proposed: 226,
          status: ExternalMetadataProposalFieldStatus.valueChange,
        ),
      ]),
      (_) {},
    );

    expect(find.text('Current: Old Track'), findsOneWidget);
    expect(find.text('Proposed: Halo'), findsOneWidget);
    expect(find.text('Current: 3:44'), findsOneWidget);
    expect(find.text('Proposed: 3:46'), findsOneWidget);
    expect(find.text('Eligible value change'), findsNWidgets(2));
  });

  testWidgets('shows protected and review-required explanations', (
    tester,
  ) async {
    await showReview(
      tester,
      proposal([
        field(
          name: MetadataFields.songTitle,
          current: 'Manual title',
          proposed: 'Halo',
          status: ExternalMetadataProposalFieldStatus.protected,
        ),
        field(
          name: MetadataFields.songDuration,
          current: 224,
          proposed: 226,
          status: ExternalMetadataProposalFieldStatus.reviewRequired,
        ),
      ]),
      (_) {},
    );

    expect(find.text('Protected fields will not be replaced.'), findsOneWidget);
    expect(
      find.text('Fields with unknown authority will remain unchanged.'),
      findsOneWidget,
    );
    expect(
      find.text('Protected by existing metadata authority'),
      findsOneWidget,
    );
    expect(
      find.text('Unknown authority; manual review required'),
      findsOneWidget,
    );

    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
    );
    expect(apply.onPressed, isNull);
  });

  testWidgets('cancellation returns null', (tester) async {
    MusicBrainzProposalReviewDecision? result =
        const MusicBrainzProposalReviewDecision(applyEligibleChanges: true);

    await showReview(
      tester,
      proposal([
        field(
          name: MetadataFields.songTitle,
          current: 'Old Track',
          proposed: 'Halo',
          status: ExternalMetadataProposalFieldStatus.valueChange,
        ),
      ]),
      (value) => result = value,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-cancel')),
    );
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('Apply is disabled when nothing is applicable', (tester) async {
    await showReview(
      tester,
      proposal([
        field(
          name: MetadataFields.songTitle,
          current: 'Halo',
          proposed: 'Halo',
          status: ExternalMetadataProposalFieldStatus.unchanged,
        ),
      ]),
      (_) {},
    );

    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
    );

    expect(apply.onPressed, isNull);
  });

  testWidgets('Apply returns decision for eligible changes', (tester) async {
    MusicBrainzProposalReviewDecision? result =
        const MusicBrainzProposalReviewDecision(applyEligibleChanges: true);

    await showReview(
      tester,
      proposal([
        field(
          name: MetadataFields.songTitle,
          current: 'Old Track',
          proposed: 'Halo',
          status: ExternalMetadataProposalFieldStatus.valueChange,
        ),
      ]),
      (value) => result = value,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
    );
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.applyEligibleChanges, isTrue);
    expect(result!.confirmedReviewFields, isEmpty);
  });

  testWidgets('provenance-only update permits confirmation', (tester) async {
    await showReview(
      tester,
      proposal(
        [
          field(
            name: MetadataFields.artistName,
            current: 'Beyonce',
            proposed: 'Beyonce',
            status: ExternalMetadataProposalFieldStatus.provenanceOnly,
          ),
        ],
        entityType: MetadataEntityType.artist,
        entityKind: ExternalMetadataEntityKind.artist,
      ),
      (_) {},
    );

    expect(
      find.text('Eligible provenance update; value unchanged'),
      findsOneWidget,
    );

    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
    );
    expect(apply.onPressed, isNotNull);
  });
}
