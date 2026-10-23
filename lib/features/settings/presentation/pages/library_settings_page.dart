import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../import/application/services/import_review_service.dart';
import '../../../import/application/services/import_workflow_service.dart';
import '../../../import/presentation/pages/import_review_page.dart';
import '../../../import/presentation/pages/imports_page.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/application/services/album_profile_editing_service.dart';
import '../../application/controllers/library_overview_controller.dart';
import '../../application/services/library_overview_service.dart';
import '../widgets/settings/settings_section.dart';
import 'blacklisted_songs_page.dart';
import 'unavailable_songs_page.dart';

/// Library management in one place: a read-only summary and links to the
/// existing import, review, availability and blacklist tools.
class LibrarySettingsPage extends StatefulWidget {
  const LibrarySettingsPage({super.key});

  @override
  State<LibrarySettingsPage> createState() => _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends State<LibrarySettingsPage> {
  LibraryOverviewController? _controller;
  LibraryQueryRepository? _library;
  ImportWorkflowService? _imports;
  ImportReviewService? _reviews;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final library = context.watch<LibraryQueryRepository?>();
    final imports = context.watch<ImportWorkflowService?>();
    final reviews = context.watch<ImportReviewService?>();

    // The import services finish starting after the library; rebuild the
    // summary when any of them changes.
    if (identical(library, _library) &&
        identical(imports, _imports) &&
        identical(reviews, _reviews)) {
      return;
    }

    _library = library;
    _imports = imports;
    _reviews = reviews;

    _controller?.dispose();
    _controller = library == null
        ? null
        : LibraryOverviewController(
            service: LibraryOverviewService(
              library: library,
              imports: imports,
              reviews: reviews,
            ),
          );
    unawaited(_controller?.load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openReview() async {
    final reviews = _reviews;
    if (reviews == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImportReviewPage(
          service: reviews,
          userId: context.read<AccountController?>()?.user?.id,
          artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
          artworkFilePicker: context.read<ArtworkFilePicker?>(),
          albumProfileEditingService: context
              .read<AlbumProfileEditingService?>(),
        ),
      ),
    );

    if (mounted) unawaited(_controller?.load());
  }

  Future<void> _openAndRefresh(Widget page) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));

    if (mounted) unawaited(_controller?.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      key: const ValueKey<String>('library-settings-page'),
      appBar: AppBar(title: const Text('Library & Imports')),
      // The links always show: each destination handles its own
      // unavailable state. Only the summary needs the library.
      body: controller == null
          ? _buildBody(context, null)
          : ListenableBuilder(
              listenable: controller,
              builder: (context, _) => _buildBody(context, controller),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryOverviewController? controller,
  ) {
    final overview = controller?.overview;
    final pending = overview?.pendingReviewCount;
    final unavailable = overview?.unavailableSongs ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SummarySection(controller: controller),
        SettingsSection(
          title: 'Manage',
          footer:
              'Scanning a folder marks missing files as unavailable. It '
              'never deletes songs, history or metadata.',
          children: [
            SettingsNavTile(
              key: const ValueKey<String>('library-settings-imports'),
              icon: Icons.library_add_rounded,
              title: 'Import music',
              subtitle: overview?.importSourceCount == null
                  ? 'Add music and scan your folders for changes.'
                  : _count(overview!.importSourceCount!, 'music folder'),
              onTap: () => _openAndRefresh(const ImportsPage()),
            ),
            SettingsNavTile(
              key: const ValueKey<String>('library-settings-review'),
              icon: Icons.fact_check_outlined,
              title: 'Review imported metadata',
              subtitle: _reviews == null
                  ? 'Available once imports have started.'
                  : pending == null
                  ? 'Checking for songs to review…'
                  : pending == 0
                  ? 'Nothing needs review.'
                  : '${_count(pending, 'song')} need review.',
              onTap: _reviews == null ? null : _openReview,
            ),
            SettingsNavTile(
              key: const ValueKey<String>('library-settings-unavailable-songs'),
              icon: Icons.music_off_rounded,
              title: 'Unavailable songs',
              subtitle: overview == null
                  ? 'Songs whose audio file is missing on this device.'
                  : unavailable.isEmpty
                  ? 'Every song can be played on this device.'
                  : '${_count(unavailable.length, 'song')} cannot be played.',
              onTap: overview == null
                  ? null
                  : () => _openAndRefresh(
                      UnavailableSongsPage(songs: unavailable),
                    ),
            ),
            SettingsNavTile(
              key: const ValueKey<String>('settings-blacklisted-songs'),
              icon: Icons.block_rounded,
              title: 'Blacklisted songs',
              subtitle: overview == null
                  ? 'Review songs you have excluded from playback.'
                  : overview.blacklistedSongCount == 0
                  ? 'No songs are blacklisted.'
                  : '${_count(overview.blacklistedSongCount, 'song')} '
                        'excluded from playback.',
              onTap: () => _openAndRefresh(const BlacklistedSongsPage()),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.controller});

  final LibraryOverviewController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    if (controller == null) {
      return const SettingsSection(
        title: 'Your library',
        children: [
          ListTile(
            key: ValueKey<String>('library-settings-unavailable'),
            leading: Icon(Icons.hourglass_empty_rounded),
            title: Text('Your library is still opening.'),
          ),
        ],
      );
    }

    final overview = controller.overview;

    if (overview == null && controller.hasError) {
      return SettingsSection(
        title: 'Your library',
        children: [
          ListTile(
            key: const ValueKey<String>('library-settings-summary-error'),
            leading: const Icon(Icons.error_outline_rounded),
            title: const Text("Your library summary couldn't be loaded."),
            trailing: TextButton(
              onPressed: () => unawaited(controller.load()),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (overview == null) {
      return const SettingsSection(
        title: 'Your library',
        children: [
          ListTile(
            key: ValueKey<String>('library-settings-summary-loading'),
            leading: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Counting your library…'),
          ),
        ],
      );
    }

    return SettingsSection(
      key: const ValueKey<String>('library-settings-summary'),
      title: 'Your library',
      children: [
        ListTile(
          leading: const Icon(Icons.library_music_outlined),
          title: Text(
            '${_count(overview.songCount, 'song')} · '
            '${_count(overview.albumCount, 'album')} · '
            '${_count(overview.artistCount, 'artist')}',
            key: const ValueKey<String>('library-settings-counts'),
          ),
        ),
      ],
    );
  }
}

String _count(int value, String noun) =>
    value == 1 ? '1 $noun' : '$value ${noun}s';
