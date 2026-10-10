import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/models/external_metadata_candidate.dart';
import '../../application/models/external_metadata_candidate_ranking.dart';
import '../../application/models/external_metadata_proposal.dart';
import 'musicbrainz_proposal_review_dialog.dart';
import '../../application/services/external_metadata_candidate_ranking_service.dart';
import '../../application/models/external_metadata_search_query.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/metadata_provider.dart';

typedef MusicBrainzCandidateApplier =
    Future<ExternalMetadataApplicationResult> Function(
      ExternalMetadataCandidate candidate,
    );

typedef MusicBrainzCandidatePreviewer =
    Future<ExternalMetadataProposal> Function(
      ExternalMetadataCandidate candidate,
    );

typedef MusicBrainzReviewedCandidateApplier =
    Future<ExternalMetadataApplicationResult> Function(
      ExternalMetadataCandidate candidate,
      Set<String> confirmedFields,
    );

class MusicBrainzSearchSelection {
  const MusicBrainzSearchSelection({
    required this.candidate,
    required this.result,
  });

  final ExternalMetadataCandidate candidate;
  final ExternalMetadataApplicationResult result;
}

class MusicBrainzSearchDialog extends StatefulWidget {
  const MusicBrainzSearchDialog({
    super.key,
    required this.provider,
    required this.query,
    required this.applier,
    this.previewer,
    this.reviewedApplier,
    this.title = 'Search MusicBrainz',
  });

  final MetadataProvider provider;
  final ExternalMetadataSearchQuery query;
  final MusicBrainzCandidateApplier applier;
  final MusicBrainzCandidatePreviewer? previewer;
  final MusicBrainzReviewedCandidateApplier? reviewedApplier;
  final String title;

  @override
  State<MusicBrainzSearchDialog> createState() =>
      _MusicBrainzSearchDialogState();
}

class _MusicBrainzSearchDialogState extends State<MusicBrainzSearchDialog> {
  List<ExternalMetadataCandidate> _results = const [];
  ExternalMetadataCandidateRanking? _ranking;
  Object? _error;

  bool _isLoading = true;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _results = const [];
      _ranking = null;
    });

    try {
      final results = await widget.provider.search(widget.query);

      if (!mounted) {
        return;
      }

      final ranking = const ExternalMetadataCandidateRankingService().rank(
        query: widget.query,
        candidates: results,
      );

      setState(() {
        _ranking = ranking;
        _results = ranking.candidates
            .map((item) => item.candidate)
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _apply(ExternalMetadataCandidate candidate) async {
    if (_isApplying) {
      return;
    }

    setState(() {
      _isApplying = true;
    });

    try {
      ExternalMetadataApplicationResult result;

      if (widget.previewer == null) {
        final confirmed = await _confirmLegacy(candidate);

        if (!mounted || confirmed != true) {
          return;
        }

        result = await widget.applier(candidate);
      } else {
        final decision = await _confirmProposal(candidate);

        if (!mounted || decision == null) {
          return;
        }

        var automaticResult = const ExternalMetadataApplicationResult();

        if (decision.applyEligibleChanges) {
          automaticResult = await widget.applier(candidate);
        }

        var reviewedResult = const ExternalMetadataApplicationResult();

        if (decision.confirmedReviewFields.isNotEmpty) {
          final reviewedApplier = widget.reviewedApplier;

          if (reviewedApplier == null) {
            throw StateError(
              'Reviewed metadata applier is required to confirm fields.',
            );
          }

          reviewedResult = await reviewedApplier(
            candidate,
            decision.confirmedReviewFields,
          );
        }

        result = _mergeResults(
          automaticResult,
          reviewedResult,
          resolvedReviewFields: decision.confirmedReviewFields,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).pop(MusicBrainzSearchSelection(candidate: candidate, result: result));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey<String>('musicbrainz-apply-error'),
          content: Text('Could not review or apply MusicBrainz metadata.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  Future<MusicBrainzProposalReviewDecision?> _confirmProposal(
    ExternalMetadataCandidate candidate,
  ) async {
    final proposal = await widget.previewer!(candidate);

    if (!mounted) {
      return null;
    }

    return showDialog<MusicBrainzProposalReviewDecision>(
      context: context,
      builder: (_) => MusicBrainzProposalReviewDialog(
        proposal: proposal,
        canConfirmReview: widget.reviewedApplier != null,
      ),
    );
  }

  ExternalMetadataApplicationResult _mergeResults(
    ExternalMetadataApplicationResult automatic,
    ExternalMetadataApplicationResult reviewed, {
    required Set<String> resolvedReviewFields,
  }) {
    return ExternalMetadataApplicationResult(
      changedFields: {...automatic.changedFields, ...reviewed.changedFields},
      provenanceUpdatedFields: {
        ...automatic.provenanceUpdatedFields,
        ...reviewed.provenanceUpdatedFields,
      },
      protectedFields: {
        ...automatic.protectedFields,
        ...reviewed.protectedFields,
      },
      reviewRequiredFields: {
        ...automatic.reviewRequiredFields,
        ...reviewed.reviewRequiredFields,
      }..removeAll(resolvedReviewFields),
    );
  }

  Future<bool?> _confirmLegacy(ExternalMetadataCandidate candidate) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey<String>('musicbrainz-apply-confirmation-dialog'),
          title: const Text('Apply MusicBrainz metadata?'),
          content: Text(
            'Use "${candidate.displayName}" for this library item? '
            'Manual and confirmed fields will stay protected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('musicbrainz-apply-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('musicbrainz-search-dialog'),
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: _buildContent(),
        ),
      ),
      actions: [
        if (!_isLoading && _error != null)
          TextButton.icon(
            key: const ValueKey<String>('musicbrainz-retry-button'),
            onPressed: _isApplying ? null : _search,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        TextButton(
          onPressed: _isApplying ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(
            key: ValueKey<String>('musicbrainz-search-progress'),
          ),
        ),
      );
    }

    if (_error != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 42),
              SizedBox(height: 12),
              Text(
                'MusicBrainz could not be reached.',
                key: ValueKey<String>('musicbrainz-search-error'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No MusicBrainz matches found.',
            key: ValueKey<String>('musicbrainz-search-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_ranking?.isAmbiguous == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Card(
              key: const ValueKey<String>('musicbrainz-ambiguity-warning'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Multiple MusicBrainz candidates have similar '
                        'match quality. Review carefully before applying.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            key: const ValueKey<String>('musicbrainz-search-results'),
            shrinkWrap: true,
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final candidate = _results[index];
              final evaluation = _ranking!.candidates[index].evaluation;

              return ListTile(
                key: ValueKey<String>(
                  'musicbrainz-result-${candidate.providerEntityId}',
                ),
                enabled: !_isApplying,
                leading: const Icon(Icons.library_music_outlined),
                title: Text(candidate.displayName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_subtitle(candidate)),
                    const SizedBox(height: 4),
                    Text(
                      'Match quality: ${evaluation.score.round()}% '
                      '· Evidence coverage: ${evaluation.evidenceCoverage.round()}%',
                      key: ValueKey<String>(
                        'musicbrainz-evidence-${candidate.providerEntityId}',
                      ),
                    ),
                    if (evaluation.requiresCarefulReview)
                      Text(
                        !evaluation.comparable
                            ? 'Incompatible metadata type — review carefully'
                            : !evaluation.hasSufficientEvidence
                            ? 'Limited evidence — review carefully'
                            : 'Weak metadata match — review carefully',
                        key: ValueKey<String>(
                          'musicbrainz-evidence-warning-${candidate.providerEntityId}',
                        ),
                      ),
                  ],
                ),
                trailing: _isApplying
                    ? null
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _isApplying
                    ? null
                    : () {
                        unawaited(_apply(candidate));
                      },
              );
            },
          ),
        ),
      ],
    );
  }

  String _subtitle(ExternalMetadataCandidate candidate) {
    final parts = <String>[];

    if (candidate.artistCredits.isNotEmpty) {
      final credit = candidate.artistCredits
          .map((item) => '${item.name}${item.joinPhrase}')
          .join()
          .trim();

      if (credit.isNotEmpty) {
        parts.add(credit);
      }
    }

    final releaseTitle = candidate.releaseTitle?.trim();

    if (releaseTitle != null &&
        releaseTitle.isNotEmpty &&
        releaseTitle != candidate.displayName) {
      parts.add(releaseTitle);
    }

    final releaseDate = candidate.releaseDate;

    if (releaseDate != null) {
      parts.add('${releaseDate.year}');
    }

    final duration = candidate.durationSeconds;

    if (duration != null && duration > 0) {
      final minutes = duration ~/ 60;
      final seconds = duration % 60;

      parts.add('$minutes:${seconds.toString().padLeft(2, '0')}');
    }

    final type = candidate.primaryType?.trim();

    if (type != null && type.isNotEmpty) {
      parts.add(type);
    }

    if (parts.isEmpty) {
      return 'MusicBrainz';
    }

    return parts.join(' • ');
  }
}
