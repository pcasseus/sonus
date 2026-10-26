import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../domain/entities/artwork_crop.dart';
import '../../domain/models/crop_frame.dart';

/// What the crop editor returns.
sealed class ArtworkCropDecision {
  const ArtworkCropDecision();
}

/// Save the image cropped to [rect].
class ArtworkCropSave extends ArtworkCropDecision {
  const ArtworkCropSave(this.rect);

  final CropRect rect;
}

/// Put the full, uncropped original back.
class ArtworkCropReset extends ArtworkCropDecision {
  const ArtworkCropReset();
}

/// Opens the crop editor. Returns null when the user cancels.
Future<ArtworkCropDecision?> showArtworkCropEditor(
  BuildContext context, {
  required String imagePath,
  required ArtworkCropTarget target,
  CropRect? initialRect,
  bool canReset = false,
  String? previewName,
}) {
  return Navigator.of(context).push<ArtworkCropDecision>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ArtworkCropEditorPage(
        imagePath: imagePath,
        target: target,
        initialRect: initialRect,
        canReset: canReset,
        previewName: previewName,
      ),
    ),
  );
}

/// Crop, move and zoom an image at the shape it will be shown in (SN-45).
///
/// Covers are square, artist banners are wide with a preview of the lower
/// gradient and name placement, and portraits are square with a preview of
/// the circular frame. Dragging and pinching work, and every adjustment is
/// also available from the zoom slider, nudge buttons and arrow keys.
class ArtworkCropEditorPage extends StatefulWidget {
  const ArtworkCropEditorPage({
    super.key,
    required this.imagePath,
    required this.target,
    this.initialRect,
    this.canReset = false,
    this.previewName,
    this.imageProvider,
  });

  final String imagePath;
  final ArtworkCropTarget target;
  final CropRect? initialRect;

  /// Whether this reopens an earlier crop, so the full original can be
  /// restored.
  final bool canReset;

  /// The artist name to preview over a banner.
  final String? previewName;

  /// Overrides the image source (tests).
  final ImageProvider? imageProvider;

  /// Very large photos are decoded at most this wide for editing; the
  /// saved crop is still rendered from the original.
  static const int previewDecodeWidth = 2048;

  @override
  State<ArtworkCropEditorPage> createState() => _ArtworkCropEditorPageState();
}

class _ArtworkCropEditorPageState extends State<ArtworkCropEditorPage> {
  late final ImageProvider _provider =
      widget.imageProvider ??
      ResizeImage(
        FileImage(File(widget.imagePath)),
        width: ArtworkCropEditorPage.previewDecodeWidth,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );

  ImageStream? _stream;
  ImageStreamListener? _listener;
  CropFrame? _frame;
  bool _failed = false;

  // Pinch state: the zoom and frame when the gesture began.
  double _gestureStartZoom = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  void _resolve() {
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;

    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted || _frame != null) return;
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        setState(() {
          final initial = widget.initialRect;
          _frame = initial == null
              ? CropFrame.centered(
                  imageWidth: width,
                  imageHeight: height,
                  aspectRatio: widget.target.aspectRatio,
                )
              : CropFrame.fromRect(
                  imageWidth: width,
                  imageHeight: height,
                  aspectRatio: widget.target.aspectRatio,
                  rect: initial,
                );
        });
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );

    _removeListener();
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _removeListener() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  void _update(CropFrame Function(CropFrame frame) change) {
    final frame = _frame;
    if (frame == null) return;
    setState(() => _frame = change(frame));
  }

  String get _title => switch (widget.target) {
    ArtworkCropTarget.albumEdition => 'Crop cover',
    ArtworkCropTarget.artistBanner => 'Position banner',
    ArtworkCropTarget.artistPortrait => 'Position portrait',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final frame = _frame;

    return Scaffold(
      key: const ValueKey<String>('artwork-crop-editor'),
      appBar: AppBar(
        title: Text(_title),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              key: const ValueKey<String>('artwork-crop-save'),
              onPressed: frame == null
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(ArtworkCropSave(frame.toRect())),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This image could not be opened. Choose another one.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : frame == null
            ? const Center(child: CircularProgressIndicator())
            : CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      _update((f) => f.nudge(-0.05, 0)),
                  const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      _update((f) => f.nudge(0.05, 0)),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _update((f) => f.nudge(0, -0.05)),
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _update((f) => f.nudge(0, 0.05)),
                  const SingleActivator(LogicalKeyboardKey.equal): () =>
                      _update((f) => f.zoomTo(f.zoom * 1.15)),
                  const SingleActivator(LogicalKeyboardKey.minus): () =>
                      _update((f) => f.zoomTo(f.zoom / 1.15)),
                },
                child: Focus(
                  autofocus: true,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      tokens.metrics.pageGutter,
                      16,
                      tokens.metrics.pageGutter,
                      24,
                    ),
                    children: [
                      _viewport(context, frame),
                      const SizedBox(height: 16),
                      _controls(context, frame),
                      const SizedBox(height: 8),
                      Text(
                        'Drag to move and pinch to zoom, or use the controls. '
                        'The original image is kept.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _viewport(BuildContext context, CropFrame frame) {
    final colors = SonusTheme.of(context).colors;
    final circular = widget.target == ArtworkCropTarget.artistPortrait;

    return Semantics(
      label: '$_title preview. Use the controls below to move or zoom.',
      child: Center(
        child: ConstrainedBox(
          // A portrait or cover preview never needs the full width of a
          // tablet; a banner shows at the width it will be used at.
          constraints: BoxConstraints(
            maxWidth: widget.target == ArtworkCropTarget.artistBanner
                ? 720
                : 420,
          ),
          child: AspectRatio(
            aspectRatio: widget.target.aspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = constraints.maxWidth;
                final scale = viewportWidth / frame.width;

                return GestureDetector(
                  key: const ValueKey<String>('artwork-crop-viewport'),
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (_) => _gestureStartZoom = frame.zoom,
                  onScaleUpdate: (details) {
                    _update((current) {
                      var next = current.panBy(
                        details.focalPointDelta.dx,
                        details.focalPointDelta.dy,
                        viewportWidth: viewportWidth,
                      );
                      if (details.scale != 1) {
                        next = next.zoomTo(
                          _gestureStartZoom * details.scale,
                          focalX: (details.localFocalPoint.dx / viewportWidth)
                              .clamp(0.0, 1.0),
                          focalY:
                              (details.localFocalPoint.dy /
                                      constraints.maxHeight)
                                  .clamp(0.0, 1.0),
                        );
                      }
                      return next;
                    });
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(circular ? 0 : 12),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: -frame.left * scale,
                          top: -frame.top * scale,
                          width: frame.imageWidth * scale,
                          height: frame.imageHeight * scale,
                          child: Image(
                            image: _provider,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            excludeFromSemantics: true,
                          ),
                        ),
                        if (circular)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CircleMaskPainter(
                                color: colors.background.withValues(
                                  alpha: 0.72,
                                ),
                                ring: colors.accentPrimary,
                              ),
                            ),
                          ),
                        if (widget.target == ArtworkCropTarget.artistBanner)
                          Positioned.fill(
                            child: _BannerPreview(
                              background: colors.background,
                              name: widget.previewName,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, CropFrame frame) {
    IconButton nudge(
      String key,
      IconData icon,
      String label,
      double x,
      double y,
    ) => IconButton(
      key: ValueKey<String>('artwork-crop-$key'),
      tooltip: label,
      icon: Icon(icon),
      onPressed: () => _update((f) => f.nudge(x, y)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.zoom_out_rounded),
            Expanded(
              child: Slider(
                key: const ValueKey<String>('artwork-crop-zoom'),
                min: 1,
                max: CropFrame.maxZoom,
                value: frame.zoom,
                label: '${frame.zoom.toStringAsFixed(1)}x',
                semanticFormatterCallback: (value) =>
                    'Zoom ${value.toStringAsFixed(1)} times',
                onChanged: (value) => _update((f) => f.zoomTo(value)),
              ),
            ),
            const Icon(Icons.zoom_in_rounded),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            nudge('left', Icons.arrow_back_rounded, 'Move image left', 0.05, 0),
            nudge('up', Icons.arrow_upward_rounded, 'Move image up', 0, 0.05),
            nudge(
              'down',
              Icons.arrow_downward_rounded,
              'Move image down',
              0,
              -0.05,
            ),
            nudge(
              'right',
              Icons.arrow_forward_rounded,
              'Move image right',
              -0.05,
              0,
            ),
            TextButton.icon(
              key: const ValueKey<String>('artwork-crop-center'),
              onPressed: () => _update(
                (f) => CropFrame.centered(
                  imageWidth: f.imageWidth,
                  imageHeight: f.imageHeight,
                  aspectRatio: f.aspectRatio,
                ),
              ),
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('Center'),
            ),
          ],
        ),
        if (widget.canReset) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey<String>('artwork-crop-reset'),
            onPressed: () =>
                Navigator.of(context).pop(const ArtworkCropReset()),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Use the full original'),
          ),
        ],
      ],
    );
  }
}

/// Darkens everything outside the circular identity frame.
class _CircleMaskPainter extends CustomPainter {
  const _CircleMaskPainter({required this.color, required this.ring});

  final Color color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2,
    );
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(circle);
    canvas.drawPath(mask, Paint()..color = color);
    canvas.drawOval(
      circle.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_CircleMaskPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.ring != ring;
}

/// The lower fade into the page and where the artist's name will sit, so a
/// face can be kept clear of both.
class _BannerPreview extends StatelessWidget {
  const _BannerPreview({required this.background, required this.name});

  final Color background;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.45, 1],
            colors: [background.withValues(alpha: 0), background],
          ),
        ),
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              name ?? 'Artist name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                shadows: const [
                  ui.Shadow(blurRadius: 8, color: Color(0x66000000)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
