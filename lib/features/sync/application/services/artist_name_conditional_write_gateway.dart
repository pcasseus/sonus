import 'cloud_conditional_write_result.dart';

/// Updates only an existing artist's name and canonical name.
/// Do not use to acknowledge a complete artist-record upload.
abstract interface class ArtistNameConditionalWriteGateway {
  Future<CloudConditionalWriteResult> updateArtistName({
    required String artistId,
    required int expectedServerRevision,
    required String name,
    required String canonicalName,
    required DateTime updatedAt,
  });
}
