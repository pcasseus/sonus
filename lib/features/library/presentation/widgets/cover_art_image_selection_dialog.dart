import 'package:flutter/material.dart';

import '../../../artwork/application/models/cover_art_archive_image.dart';
import '../../../artwork/application/services/cover_art_archive_uri_policy.dart';

class CoverArtImageSelectionDialog extends StatelessWidget {
  const CoverArtImageSelectionDialog({
    super.key,
    required this.images,
    required this.albumTitle,
  });

  final List<CoverArtArchiveImage> images;
  final String albumTitle;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('cover-art-image-selection-dialog'),
      title: const Text('Choose album artwork'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              albumTitle,
              key: const ValueKey<String>('cover-art-image-album-title'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: images.isEmpty
                  ? const Center(
                      child: Text(
                        'No artwork is available for this album.',
                        key: ValueKey<String>('cover-art-image-empty'),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey<String>('cover-art-image-results'),
                      itemCount: images.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final image = images[index];
                        final rawPreviewUrl =
                            image.thumbnailUrl ?? image.imageUrl;
                        final previewUrl =
                            CoverArtArchiveUriPolicy.isTrustedString(
                              rawPreviewUrl,
                            )
                            ? rawPreviewUrl
                            : null;

                        final labels = <String>[
                          if (image.front) 'Front cover',
                          if (image.back) 'Back cover',
                          ...image.types.where(
                            (type) =>
                                type.isNotEmpty &&
                                type != 'Front' &&
                                type != 'Back',
                          ),
                          if (image.approved) 'Approved',
                        ];

                        return ListTile(
                          key: ValueKey<String>(
                            'cover-art-image-option-$index',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          leading: SizedBox(
                            width: 72,
                            height: 72,
                            child: previewUrl == null
                                ? const Icon(Icons.broken_image_outlined)
                                : Image.network(
                                    previewUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                          ),
                          title: Text('Artwork ${index + 1}'),
                          subtitle: Text(
                            labels.isEmpty
                                ? 'Cover Art Archive'
                                : labels.join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(image),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
