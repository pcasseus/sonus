import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../domain/entities/artwork_crop.dart';
import '../../domain/repositories/artwork_asset_repository.dart';
import '../../domain/repositories/artwork_crop_repository.dart';
import 'artwork_assignment_service.dart';
import 'artwork_crop_renderer.dart';

/// Where a crop editor opens: the image to show and, when the artwork was
/// cropped before, the saved rectangle.
class ArtworkCropSource {
  const ArtworkCropSource({required this.filePath, this.rect});

  final String filePath;
  final CropRect? rect;

  /// Whether this reopens an earlier crop (so Reset is available).
  bool get isRecropping => rect != null;
}

/// Crops covers and artist photos without losing the original (SN-45).
///
/// The cropped image is assigned through [ArtworkAssignmentService] like
/// any other artwork, with the same managed storage, provenance and sync
/// records. The original is kept as its own artwork asset and the crop
/// rectangle is remembered (device-local), so the crop can be moved again
/// or reset to the full original later.
class ArtworkCropService {
  ArtworkCropService({
    required this._assignment,
    required this._crops,
    required this._assets,
    required this._temporaryDirectory,
    ArtworkCropRender? render,
    DateTime Function()? now,
  }) : _render = render ?? ArtworkCropRenderer.render,
       _now = now ?? DateTime.now;

  final ArtworkAssignmentService _assignment;
  final ArtworkCropRepository _crops;
  final ArtworkAssetRepository _assets;
  final Future<Directory> Function() _temporaryDirectory;
  final ArtworkCropRender _render;
  final DateTime Function() _now;

  /// The remembered crop, if it still describes the assigned artwork.
  /// A crop whose output was replaced elsewhere (a new cover, an online
  /// lookup, sync) no longer applies.
  Future<ArtworkCrop?> currentCrop({
    required ArtworkCropTarget target,
    required String targetId,
    required String? currentArtworkId,
  }) async {
    final crop = await _crops.get(target, targetId);

    if (crop == null || crop.outputArtworkId != currentArtworkId) {
      return null;
    }

    return crop;
  }

  /// What "Reposition" opens: the original and its saved crop when there is
  /// one, otherwise the current artwork itself. Null when no image exists.
  Future<ArtworkCropSource?> repositionSource({
    required ArtworkCropTarget target,
    required String targetId,
    required String? currentArtworkId,
    required String? currentArtworkPath,
  }) async {
    final crop = await currentCrop(
      target: target,
      targetId: targetId,
      currentArtworkId: currentArtworkId,
    );

    if (crop != null) {
      final original = await _assets.getById(crop.sourceArtworkId);

      if (original != null && await File(original.filePath).exists()) {
        return ArtworkCropSource(filePath: original.filePath, rect: crop.rect);
      }
    }

    final current = currentArtworkPath?.trim();

    if (current == null || current.isEmpty || !await File(current).exists()) {
      return null;
    }

    return ArtworkCropSource(filePath: current);
  }

  /// Crops [sourcePath] to [rect] and assigns the result to the target.
  ///
  /// The original is stored (or reused, when Sonus already manages it)
  /// before anything is assigned. If the assignment fails, the target keeps
  /// its previous artwork and no crop is remembered.
  Future<void> apply({
    required ArtworkCropTarget target,
    required String targetId,
    required String sourcePath,
    required CropRect rect,
    String? userId,
  }) async {
    final original = await File(sourcePath).readAsBytes();
    final cropped = await _render(original, rect, target);
    final source = await _assignment.resolveArtworkAsset(filePath: sourcePath);

    final temporary = await _writeTemporary(cropped);

    try {
      final output = await _assign(target, targetId, temporary.path, userId);
      final timestamp = _now();
      final previous = await _crops.get(target, targetId);

      await _crops.save(
        ArtworkCrop(
          target: target,
          targetId: targetId,
          sourceArtworkId: source.id,
          outputArtworkId: output,
          rect: rect,
          createdAt: previous?.createdAt ?? timestamp,
          updatedAt: timestamp,
        ),
      );
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  /// Puts the full original back. Returns false when there is no crop to
  /// reset (or its original is gone), in which case nothing changes.
  Future<bool> reset({
    required ArtworkCropTarget target,
    required String targetId,
    required String? currentArtworkId,
    String? userId,
  }) async {
    final crop = await currentCrop(
      target: target,
      targetId: targetId,
      currentArtworkId: currentArtworkId,
    );

    if (crop == null) {
      return false;
    }

    final original = await _assets.getById(crop.sourceArtworkId);

    if (original == null || !await File(original.filePath).exists()) {
      return false;
    }

    await _assign(target, targetId, original.filePath, userId);
    await _crops.delete(target, targetId);
    return true;
  }

  /// Assigns [filePath] to the target and returns the assigned asset's ID.
  Future<String> _assign(
    ArtworkCropTarget target,
    String targetId,
    String filePath,
    String? userId,
  ) async {
    final asset = switch (target) {
      ArtworkCropTarget.albumEdition => await _assignment.assignAlbumEdition(
        albumEditionId: targetId,
        filePath: filePath,
      ),
      ArtworkCropTarget.artistBanner => await _assignment.assignArtistHeader(
        userId: userId,
        artistId: targetId,
        filePath: filePath,
      ),
      ArtworkCropTarget.artistPortrait =>
        await _assignment.assignArtistTopArtists(
          userId: userId,
          artistId: targetId,
          filePath: filePath,
        ),
    };
    return asset.id;
  }

  Future<File> _writeTemporary(Uint8List bytes) async {
    final directory = await _temporaryDirectory();
    final file = File(
      path.join(directory.path, 'sonus_crop_${const Uuid().v4()}.png'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
