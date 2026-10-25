import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/models/external_metadata_candidate.dart';
import '../../application/models/external_metadata_search_query.dart';
import '../../application/services/external_metadata_candidate_ranking_service.dart';
import '../../application/services/metadata_provider.dart';
import 'online_lookup_disclosure.dart';

class CoverArtAlbumSearchDialog extends StatefulWidget {
  const CoverArtAlbumSearchDialog({
    super.key,
    required this.provider,
    required this.query,
  });

  final MetadataProvider provider;
  final ExternalMetadataSearchQuery query;

  @override
  State<CoverArtAlbumSearchDialog> createState() =>
      _CoverArtAlbumSearchDialogState();
}

class _CoverArtAlbumSearchDialogState extends State<CoverArtAlbumSearchDialog> {
  List<ExternalMetadataCandidate> _results = const [];
  bool _loading = true;
  bool _hasError = false;
  bool _ambiguous = false;

  /// True while the online lookup disclosure waits for the user.
  bool _needsConsent = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    final consent = onlineLookupConsentOf(context);

    if (consent != null && !consent.isOnlineLookupAccepted) {
      setState(() {
        _needsConsent = true;
        _loading = false;
      });
      return;
    }

    setState(() {
      _needsConsent = false;
      _loading = true;
      _hasError = false;
      _ambiguous = false;
      _results = const [];
    });

    try {
      final results = await widget.provider.search(widget.query);

      if (!mounted) return;

      final albumCandidates = results
          .where(
            (candidate) =>
                candidate.provider ==
                    ExternalMetadataProviderKind.musicBrainz &&
                candidate.entityKind == ExternalMetadataEntityKind.album,
          )
          .toList(growable: false);

      final ranking = const ExternalMetadataCandidateRankingService().rank(
        query: widget.query,
        candidates: albumCandidates,
      );

      setState(() {
        _ambiguous = ranking.isAmbiguous;
        _results = ranking.candidates
            .map((entry) => entry.candidate)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('cover-art-album-search-dialog'),
      title: const Text('Find album artwork'),
      content: SizedBox(width: 520, height: 400, child: _buildContent()),
      actions: [
        if (_hasError && !_loading)
          TextButton(
            key: const ValueKey('cover-art-album-search-retry'),
            onPressed: _search,
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _acceptAndSearch() async {
    await onlineLookupConsentOf(context)?.acceptOnlineLookup();

    if (mounted) {
      await _search();
    }
  }

  Widget _buildContent() {
    if (_needsConsent) {
      return OnlineLookupDisclosure(onContinue: _acceptAndSearch);
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('cover-art-album-search-progress'),
        ),
      );
    }

    if (_hasError) {
      return const Center(
        child: Text(
          'Could not search MusicBrainz. Try again.',
          key: ValueKey('cover-art-album-search-error'),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'No matching albums found.',
          key: ValueKey('cover-art-album-search-empty'),
        ),
      );
    }

    return Column(
      children: [
        if (_ambiguous)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Several albums may match. Check the artist and release before choosing.',
              key: ValueKey('cover-art-album-search-ambiguous'),
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('cover-art-album-search-results'),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final candidate = _results[index];

              final artists = candidate.artistCredits
                  .map((credit) => credit.name)
                  .join(', ');

              final year = candidate.releaseDate?.year;

              final details = [
                if (artists.isNotEmpty) artists,
                if (year != null) '$year',
                if (candidate.primaryType != null) candidate.primaryType!,
              ].join(' • ');

              return ListTile(
                key: ValueKey(
                  'cover-art-album-result-${candidate.providerEntityId}',
                ),
                leading: const Icon(Icons.album_outlined),
                title: Text(candidate.displayName),
                subtitle: details.isEmpty ? null : Text(details),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop(candidate),
              );
            },
          ),
        ),
      ],
    );
  }
}
