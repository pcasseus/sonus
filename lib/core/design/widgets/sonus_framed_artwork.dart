import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// How an image of one shape is shown in a frame of another: filling it
/// when that trims only a little, otherwise whole, with room around it.
@immutable
class ArtworkFraming {
  const ArtworkFraming._(this.size, this.fills);

  /// The image's size in the frame, its own shape kept (never stretched).
  final Size size;

  /// Whether the image covers the whole frame; when false it is shown whole
  /// and the frame around it needs a fill.
  final bool fills;

  /// The most of the image a frame may trim to fill itself: 10%, so 5% at
  /// each side. More would cut off people at the edges of group and cast
  /// photographs.
  static const double defaultMaxCrop = 0.10;

  /// Frames an image of [imageAspect] (width over height) in [frame].
  factory ArtworkFraming.of({
    required double imageAspect,
    required Size frame,
    double maxCrop = defaultMaxCrop,
  }) {
    if (frame.isEmpty || !imageAspect.isFinite || imageAspect <= 0) {
      return ArtworkFraming._(frame, true);
    }
    final frameAspect = frame.width / frame.height;
    // The share of the image that filling the frame would trim.
    final trimmed = imageAspect > frameAspect
        ? 1 - frameAspect / imageAspect
        : 1 - imageAspect / frameAspect;
    if (trimmed <= maxCrop + 1e-9) {
      final cover = imageAspect > frameAspect
          ? Size(frame.height * imageAspect, frame.height)
          : Size(frame.width, frame.width / imageAspect);
      return ArtworkFraming._(cover, true);
    }
    final contain = imageAspect > frameAspect
        ? Size(frame.width, frame.width / imageAspect)
        : Size(frame.height * imageAspect, frame.height);
    return ArtworkFraming._(contain, false);
  }

  /// The share of the image's width or height trimmed at each side.
  double trimmedPerSide(Size frame) {
    final widthCut = size.width > frame.width
        ? (size.width - frame.width) / size.width / 2
        : 0.0;
    final heightCut = size.height > frame.height
        ? (size.height - frame.height) / size.height / 2
        : 0.0;
    return widthCut > heightCut ? widthCut : heightCut;
  }
}

/// Artwork in a frame of any shape, without cropping people away
/// (Roster portrait correction, after device QA): an image close to the
/// frame's shape fills it ([ArtworkFraming]); any other is shown whole,
/// centred, over a blurred copy of itself. The stored artwork is never
/// changed, and the image is decoded once for both layers.
class SonusFramedArtwork extends StatefulWidget {
  const SonusFramedArtwork({
    super.key,
    required this.image,
    required this.fill,
    required this.fallback,
    this.focus = const Alignment(0, -0.35),
    this.maxCrop = ArtworkFraming.defaultMaxCrop,
    this.blurSigma = 22,
  });

  final ImageProvider image;

  /// The frame's colour while the image loads, and under the blurred copy.
  final Color fill;

  /// Shown when the image cannot be loaded.
  final Widget fallback;

  /// Which part stays in view when the image is trimmed to fill: a little
  /// above centre, where faces usually are.
  final Alignment focus;

  final double maxCrop;
  final double blurSigma;

  @override
  State<SonusFramedArtwork> createState() => _SonusFramedArtworkState();
}

class _SonusFramedArtworkState extends State<SonusFramedArtwork> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: _onError,
  );
  double? _aspect;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(SonusFramedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _aspect = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final aspect = info.image.width / info.image.height;
    info.dispose();
    if (!mounted || aspect == _aspect) return;
    if (synchronousCall) {
      _aspect = aspect;
    } else {
      setState(() => _aspect = aspect);
    }
  }

  void _onError(Object error, StackTrace? stackTrace) {
    if (mounted) setState(() => _failed = true);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final aspect = _aspect;
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = constraints.biggest;
        if (aspect == null || !frame.isFinite) {
          return ColoredBox(
            key: const ValueKey<String>('framed-artwork-loading'),
            color: widget.fill,
          );
        }
        final framing = ArtworkFraming.of(
          imageAspect: aspect,
          frame: frame,
          maxCrop: widget.maxCrop,
        );
        final picture = Image(
          image: widget.image,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => widget.fallback,
        );
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: widget.fill),
              if (!framing.fills) ...[
                // The artwork-derived fill: the same image, blurred, under
                // a wash of the frame colour so the sharp image stands out.
                ImageFiltered(
                  key: const ValueKey<String>('framed-artwork-backdrop'),
                  imageFilter: ImageFilter.blur(
                    sigmaX: widget.blurSigma,
                    sigmaY: widget.blurSigma,
                    tileMode: TileMode.clamp,
                  ),
                  child: Image(
                    image: widget.image,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
                ColoredBox(color: widget.fill.withValues(alpha: 0.35)),
              ],
              OverflowBox(
                alignment: framing.fills ? widget.focus : Alignment.center,
                minWidth: framing.size.width,
                maxWidth: framing.size.width,
                minHeight: framing.size.height,
                maxHeight: framing.size.height,
                child: KeyedSubtree(
                  key: ValueKey<String>(
                    framing.fills
                        ? 'framed-artwork-filled'
                        : 'framed-artwork-whole',
                  ),
                  child: picture,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
