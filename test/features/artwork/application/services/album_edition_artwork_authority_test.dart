import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/application/services/album_edition_artwork_authority.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/domain/services/metadata_authority_policy.dart';

void main() {
  MetadataFieldState state(MetadataAuthority authority) {
    return MetadataFieldState(
      entityType: MetadataEntityType.albumEdition,
      entityId: 'edition_1',
      fieldName: MetadataFields.editionArtwork,
      authority: authority,
      source: MetadataProvenanceSource.user,
      updatedAt: DateTime.utc(2026, 10, 9),
    );
  }

  test('accepts automatically sourced artwork when edition is empty', () {
    expect(
      AlbumEditionArtworkAuthority.evaluateAutomatic(
        currentArtworkId: null,
        currentState: null,
      ),
      MetadataReplacementDecision.accept,
    );
  });

  test('accepts replacement of inferred and imported artwork', () {
    for (final authority in [
      MetadataAuthority.inferred,
      MetadataAuthority.imported,
    ]) {
      expect(
        AlbumEditionArtworkAuthority.evaluateAutomatic(
          currentArtworkId: 'existing',
          currentState: state(authority),
        ),
        MetadataReplacementDecision.accept,
      );
    }
  });

  test('accepts replacement of existing external artwork', () {
    expect(
      AlbumEditionArtworkAuthority.evaluateAutomatic(
        currentArtworkId: 'existing',
        currentState: state(MetadataAuthority.external),
      ),
      MetadataReplacementDecision.accept,
    );
  });

  test('protects confirmed and manually selected artwork', () {
    for (final authority in [
      MetadataAuthority.confirmed,
      MetadataAuthority.manual,
    ]) {
      expect(
        AlbumEditionArtworkAuthority.evaluateAutomatic(
          currentArtworkId: 'existing',
          currentState: state(authority),
        ),
        MetadataReplacementDecision.rejectLowerAuthority,
      );
    }
  });

  test('requires review when existing artwork has unknown authority', () {
    expect(
      AlbumEditionArtworkAuthority.evaluateAutomatic(
        currentArtworkId: 'existing',
        currentState: null,
      ),
      MetadataReplacementDecision.requireReviewUnknownAuthority,
    );
  });

  test('protects an intentional manual artwork clear', () {
    expect(
      AlbumEditionArtworkAuthority.evaluateAutomatic(
        currentArtworkId: null,
        currentState: state(MetadataAuthority.manual),
      ),
      MetadataReplacementDecision.rejectLowerAuthority,
    );
  });

  test('allows an empty edition with prior external authority', () {
    expect(
      AlbumEditionArtworkAuthority.evaluateAutomatic(
        currentArtworkId: null,
        currentState: state(MetadataAuthority.external),
      ),
      MetadataReplacementDecision.accept,
    );
  });
}
