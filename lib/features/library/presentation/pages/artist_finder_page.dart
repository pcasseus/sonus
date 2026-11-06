import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../application/models/library_artist.dart';
import '../models/artist_library_statistics.dart';
import '../models/artist_roster_view.dart';
import '../widgets/film_reel/artist_film_reel.dart';

/// The Artist Finder (Roster layout correction): a page of its own for
/// finding an artist by name, opened from the Artist Roster's and the Film
/// Reel's search icons. It owns the keyboard, so the Roster's layout never
/// has to make room for one: the field stays at the top, and the matches
/// scroll in whatever space the keyboard leaves.
///
/// Choosing an artist closes the Finder and returns them (null when the
/// Finder is closed without a choice).
class ArtistFinderPage extends StatefulWidget {
  const ArtistFinderPage({
    super.key,
    required this.artists,
    required this.statistics,
    required this.statisticsLoaded,
    this.sort = ArtistStatisticsSort.qualifiedStreams,
    this.selectedArtistId,
  });

  /// The Library's listed artists.
  final List<LibraryArtist> artists;
  final ArtistLibraryStatisticsSnapshot statistics;
  final bool statisticsLoaded;

  /// The Roster's order, which the matches follow.
  final ArtistStatisticsSort sort;

  /// The artist being previewed, marked in the list.
  final String? selectedArtistId;

  /// Opens the Finder and returns the chosen artist (null when closed
  /// without one).
  static Future<LibraryArtist?> open(
    BuildContext context, {
    required List<LibraryArtist> artists,
    required ArtistLibraryStatisticsSnapshot statistics,
    required bool statisticsLoaded,
    ArtistStatisticsSort sort = ArtistStatisticsSort.qualifiedStreams,
    String? selectedArtistId,
  }) {
    return Navigator.of(context).push<LibraryArtist>(
      MaterialPageRoute<LibraryArtist>(
        builder: (_) => ArtistFinderPage(
          artists: artists,
          statistics: statistics,
          statisticsLoaded: statisticsLoaded,
          sort: sort,
          selectedArtistId: selectedArtistId,
        ),
      ),
    );
  }

  @override
  State<ArtistFinderPage> createState() => _ArtistFinderPageState();
}

class _ArtistFinderPageState extends State<ArtistFinderPage> {
  final TextEditingController _field = TextEditingController();
  String _query = '';
  ArtistRosterView? _view;
  String? _viewQuery;

  ArtistRosterView get _matches {
    if (_view == null || _viewQuery != _query) {
      _view = ArtistRosterView(
        artists: widget.artists,
        statistics: widget.statistics,
        sort: widget.sort,
        query: _query,
      );
      _viewQuery = _query;
    }
    return _view!;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _setQuery(String query) => setState(() => _query = query);

  void _clear() {
    _field.clear();
    _setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);
    final matches = _matches;
    final hasQuery = _query.trim().isNotEmpty;

    return Scaffold(
      key: const ValueKey<String>('artist-finder-page'),
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const ValueKey<String>('artist-finder-field'),
          controller: _field,
          autofocus: true,
          onChanged: _setQuery,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.titleMedium?.copyWith(
            color: tokens.colors.textPrimary,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Find an artist',
            hintStyle: theme.textTheme.titleMedium?.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              key: const ValueKey<String>('artist-finder-clear'),
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded),
              onPressed: _clear,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                matches.isEmpty
                    ? 'No artists match "${_query.trim()}"'
                    : hasQuery
                    ? sonusCount(
                        matches.artists.length,
                        'match',
                        plural: 'matches',
                      )
                    : sonusCount(matches.artists.length, 'artist'),
                key: ValueKey<String>(
                  matches.isEmpty
                      ? 'artist-finder-no-results'
                      : 'artist-finder-count',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const ValueKey<String>('artist-finder-results'),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: matches.artists.length,
              itemBuilder: (context, index) {
                final artist = matches.artists[index];
                return _FinderRow(
                  key: ValueKey<String>('artist-finder-${artist.artistId}'),
                  artist: artist,
                  stats: widget.statistics[artist.artistId],
                  loaded: widget.statisticsLoaded,
                  selected: artist.artistId == widget.selectedArtistId,
                  onTap: () => Navigator.of(context).pop(artist),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FinderRow extends StatelessWidget {
  const _FinderRow({
    super.key,
    required this.artist,
    required this.stats,
    required this.loaded,
    required this.selected,
    required this.onTap,
  });

  final LibraryArtist artist;
  final ArtistLibraryStatistics? stats;
  final bool loaded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final rank = stats?.rank;
    final streams = stats?.qualifiedStreams ?? 0;
    final standing = !loaded
        ? null
        : rank == null
        ? 'Unranked'
        : '#$rank · ${sonusCount(streams, 'stream')}';

    return Semantics(
      selected: selected,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        minVerticalPadding: 8,
        leading: _Thumbnail(artist: artist),
        title: Text(artist.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: standing == null ? null : Text(standing),
        trailing: selected
            ? Icon(
                Icons.check_rounded,
                color: tokens.colors.accentPrimary,
                semanticLabel: 'Previewing',
              )
            : null,
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.artist});

  final LibraryArtist artist;

  static const double _width = 44;
  static const double _height = 52;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final path = ArtistFilmReel.portraitPath(artist);
    final initials = Center(
      child: Text(
        artist.name.trim().isEmpty
            ? '?'
            : artist.name.trim().substring(0, 1).toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: tokens.colors.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: _width,
          height: _height,
          child: ColoredBox(
            color: tokens.colors.raisedSurface,
            child: path == null
                ? initials
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.35),
                    cacheWidth:
                        (_width * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => initials,
                  ),
          ),
        ),
      ),
    );
  }
}
