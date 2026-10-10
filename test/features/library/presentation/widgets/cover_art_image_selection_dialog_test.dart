import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/artwork/application/models/cover_art_archive_image.dart';
import 'package:sonus_next/features/library/presentation/widgets/cover_art_image_selection_dialog.dart';

const _releaseGroupId = '22222222-2222-4222-8222-222222222222';

const _frontImage = CoverArtArchiveImage(
  entity: CoverArtArchiveEntity.releaseGroup,
  entityId: _releaseGroupId,
  imageUrl: 'https://coverartarchive.org/front.jpg',
  thumbnailUrl: 'https://coverartarchive.org/front-250.jpg',
  front: true,
  back: false,
  approved: true,
);

const _backImage = CoverArtArchiveImage(
  entity: CoverArtArchiveEntity.releaseGroup,
  entityId: _releaseGroupId,
  imageUrl: 'https://coverartarchive.org/back.jpg',
  front: false,
  back: true,
);

void main() {
  testWidgets('displays artwork options and labels', (tester) async {
    await _showDialog(tester, [_frontImage, _backImage]);

    expect(
      find.byKey(const ValueKey('cover-art-image-results')),
      findsOneWidget,
    );
    expect(find.text('Artwork 1'), findsOneWidget);
    expect(find.text('Artwork 2'), findsOneWidget);
    expect(find.textContaining('Front cover'), findsOneWidget);
    expect(find.textContaining('Back cover'), findsOneWidget);
    expect(find.textContaining('Approved'), findsOneWidget);
    expect(find.text('Test Album'), findsOneWidget);
  });

  testWidgets('returns exactly the image selected', (tester) async {
    CoverArtArchiveImage? selected;

    await _showDialog(tester, [
      _frontImage,
      _backImage,
    ], onSelection: (image) => selected = image);

    await tester.tap(find.byKey(const ValueKey('cover-art-image-option-1')));
    await tester.pumpAndSettle();

    expect(selected, same(_backImage));
    expect(
      selected?.sourceReference,
      'coverartarchive:release-group:$_releaseGroupId',
    );
    expect(
      find.byKey(const ValueKey('cover-art-image-selection-dialog')),
      findsNothing,
    );
  });

  testWidgets('cancellation returns no image', (tester) async {
    CoverArtArchiveImage? selected;

    await _showDialog(tester, [
      _frontImage,
    ], onSelection: (image) => selected = image);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(
      find.byKey(const ValueKey('cover-art-image-selection-dialog')),
      findsNothing,
    );
  });

  testWidgets('shows an empty state', (tester) async {
    await _showDialog(tester, []);

    expect(find.byKey(const ValueKey('cover-art-image-empty')), findsOneWidget);
  });

  testWidgets('uses thumbnail URL when available', (tester) async {
    await _showDialog(tester, [_frontImage]);

    final preview = tester.widget<Image>(find.byType(Image).first);

    expect((preview.image as NetworkImage).url, _frontImage.thumbnailUrl);
  });

  testWidgets('falls back to full image URL without thumbnail', (tester) async {
    await _showDialog(tester, [_backImage]);

    final preview = tester.widget<Image>(find.byType(Image).first);

    expect((preview.image as NetworkImage).url, _backImage.imageUrl);
  });

  testWidgets('does not load preview from an untrusted HTTPS host', (
    tester,
  ) async {
    const unsafeImage = CoverArtArchiveImage(
      entity: CoverArtArchiveEntity.releaseGroup,
      entityId: _releaseGroupId,
      imageUrl: 'https://evil.example/full.jpg',
      thumbnailUrl: 'https://evil.example/thumb.jpg',
      front: true,
      back: false,
    );

    await _showDialog(tester, [unsafeImage]);

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}

Future<void> _showDialog(
  WidgetTester tester,
  List<CoverArtArchiveImage> images, {
  void Function(CoverArtArchiveImage?)? onSelection,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final image = await showDialog<CoverArtArchiveImage>(
                  context: context,
                  builder: (_) => CoverArtImageSelectionDialog(
                    images: images,
                    albumTitle: 'Test Album',
                  ),
                );

                onSelection?.call(image);
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
