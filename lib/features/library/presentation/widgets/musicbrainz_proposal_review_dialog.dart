import 'package:flutter/material.dart';

import '../../application/models/external_metadata_proposal.dart';
import '../../domain/metadata/metadata_fields.dart';

class MusicBrainzProposalReviewDialog extends StatelessWidget {
  const MusicBrainzProposalReviewDialog({super.key, required this.proposal});

  final ExternalMetadataProposal proposal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('musicbrainz-proposal-review-dialog'),
      title: const Text('Review MusicBrainz metadata'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Preview only. No library changes have been made.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final field in proposal.fields) ...[
                _ProposalFieldRow(field: field),
                const SizedBox(height: 12),
              ],
              if (proposal.hasProtectedFields)
                const Text(
                  'Protected fields will not be replaced.',
                  key: ValueKey<String>('musicbrainz-proposal-protected-note'),
                ),
              if (proposal.requiresReview)
                const Text(
                  'Fields with unknown authority will remain unchanged.',
                  key: ValueKey<String>('musicbrainz-proposal-review-note'),
                ),
              const SizedBox(height: 8),
              Text(
                'Sonus will recheck metadata authority when applying. '
                'The final result may differ from this preview.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('musicbrainz-proposal-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('musicbrainz-proposal-apply'),
          onPressed: proposal.hasApplicableChanges
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Apply eligible changes'),
        ),
      ],
    );
  }
}

class _ProposalFieldRow extends StatelessWidget {
  const _ProposalFieldRow({required this.field});

  final ExternalMetadataProposalField field;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey<String>('musicbrainz-proposal-field-${field.fieldName}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _fieldLabel(field.fieldName),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text('Current: ${_displayValue(field.currentValue)}'),
            Text('Proposed: ${_displayValue(field.proposedValue)}'),
            const SizedBox(height: 8),
            Text(
              _statusLabel(field.status),
              key: ValueKey<String>(
                'musicbrainz-proposal-status-${field.fieldName}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fieldLabel(String fieldName) {
    if (fieldName == MetadataFields.artistName) {
      return 'Artist name';
    }
    if (fieldName == MetadataFields.songDuration) {
      return 'Duration';
    }
    if (fieldName == MetadataFields.albumTitle) {
      return 'Title';
    }
    return fieldName;
  }

  String _displayValue(Object? value) {
    if (value == null) {
      return 'Not available';
    }
    if (field.fieldName == MetadataFields.songDuration && value is int) {
      if (value <= 0) {
        return 'Unknown';
      }
      final minutes = value ~/ 60;
      final seconds = value % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    if (value is String && value.trim().isEmpty) {
      return 'Not available';
    }
    return value.toString();
  }

  String _statusLabel(ExternalMetadataProposalFieldStatus status) {
    return switch (status) {
      ExternalMetadataProposalFieldStatus.valueChange =>
        'Eligible value change',
      ExternalMetadataProposalFieldStatus.provenanceOnly =>
        'Eligible provenance update; value unchanged',
      ExternalMetadataProposalFieldStatus.unchanged => 'Already up to date',
      ExternalMetadataProposalFieldStatus.protected =>
        'Protected by existing metadata authority',
      ExternalMetadataProposalFieldStatus.reviewRequired =>
        'Unknown authority; manual review required',
      ExternalMetadataProposalFieldStatus.notProposed =>
        'No value proposed by MusicBrainz',
    };
  }
}
