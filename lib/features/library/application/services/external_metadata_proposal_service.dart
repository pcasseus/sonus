import '../../domain/metadata/metadata_field_state.dart';
import '../../domain/metadata/metadata_fields.dart';
import '../../domain/repositories/album_repository.dart';
import '../../domain/repositories/artist_repository.dart';
import '../../domain/repositories/metadata_field_state_repository.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/metadata_authority_policy.dart';
import '../models/external_metadata_candidate.dart';
import '../models/external_metadata_proposal.dart';
import '../models/external_metadata_search_query.dart';

class ExternalMetadataProposalService {
  const ExternalMetadataProposalService({
    required this.artistRepository,
    required this.albumRepository,
    required this.songRepository,
    required this.metadataFieldStateRepository,
  });

  final ArtistRepository artistRepository;
  final AlbumRepository albumRepository;
  final SongRepository songRepository;
  final MetadataFieldStateRepository metadataFieldStateRepository;

  Future<ExternalMetadataProposal> previewArtist({
    required String artistId,
    required ExternalMetadataCandidate candidate,
  }) async {
    _requireCandidate(candidate, ExternalMetadataEntityKind.artist);

    final id = _requiredId(artistId);
    final artist = await artistRepository.getById(id);

    if (artist == null) {
      throw StateError('Artist not found: $id');
    }

    final field = await _previewField(
      entityType: MetadataEntityType.artist,
      entityId: artist.id,
      fieldName: MetadataFields.artistName,
      currentValue: artist.name,
      proposedValue: candidate.displayName.trim(),
      currentValuePresent: artist.name.trim().isNotEmpty,
      proposedValuePresent: candidate.displayName.trim().isNotEmpty,
      sourceReference: candidate.sourceReference,
    );

    return ExternalMetadataProposal(
      entityType: MetadataEntityType.artist,
      entityId: artist.id,
      candidate: candidate,
      fields: List.unmodifiable([field]),
    );
  }

  Future<ExternalMetadataProposal> previewAlbum({
    required String albumId,
    required ExternalMetadataCandidate candidate,
  }) async {
    _requireCandidate(candidate, ExternalMetadataEntityKind.album);

    final id = _requiredId(albumId);
    final album = await albumRepository.getById(id);

    if (album == null) {
      throw StateError('Album not found: $id');
    }

    final field = await _previewField(
      entityType: MetadataEntityType.album,
      entityId: album.id,
      fieldName: MetadataFields.albumTitle,
      currentValue: album.title,
      proposedValue: candidate.displayName.trim(),
      currentValuePresent: album.title.trim().isNotEmpty,
      proposedValuePresent: candidate.displayName.trim().isNotEmpty,
      sourceReference: candidate.sourceReference,
    );

    return ExternalMetadataProposal(
      entityType: MetadataEntityType.album,
      entityId: album.id,
      candidate: candidate,
      fields: List.unmodifiable([field]),
    );
  }

  Future<ExternalMetadataProposal> previewTrack({
    required String songId,
    required ExternalMetadataCandidate candidate,
  }) async {
    _requireCandidate(candidate, ExternalMetadataEntityKind.track);

    final id = _requiredId(songId);
    final song = await songRepository.getById(id);

    if (song == null) {
      throw StateError('Song not found: $id');
    }

    final fields = <ExternalMetadataProposalField>[
      await _previewField(
        entityType: MetadataEntityType.song,
        entityId: song.id,
        fieldName: MetadataFields.songTitle,
        currentValue: song.title,
        proposedValue: candidate.displayName.trim(),
        currentValuePresent: song.title.trim().isNotEmpty,
        proposedValuePresent: candidate.displayName.trim().isNotEmpty,
        sourceReference: candidate.sourceReference,
      ),
      await _previewField(
        entityType: MetadataEntityType.song,
        entityId: song.id,
        fieldName: MetadataFields.songDuration,
        currentValue: song.durationSeconds,
        proposedValue: candidate.durationSeconds,
        currentValuePresent: song.durationSeconds > 0,
        proposedValuePresent:
            candidate.durationSeconds != null && candidate.durationSeconds! > 0,
        sourceReference: candidate.sourceReference,
      ),
    ];

    return ExternalMetadataProposal(
      entityType: MetadataEntityType.song,
      entityId: song.id,
      candidate: candidate,
      fields: List.unmodifiable(fields),
    );
  }

  Future<ExternalMetadataProposalField> _previewField({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
    required Object currentValue,
    required Object? proposedValue,
    required bool currentValuePresent,
    required bool proposedValuePresent,
    required String sourceReference,
  }) async {
    if (!proposedValuePresent) {
      return ExternalMetadataProposalField(
        fieldName: fieldName,
        currentValue: currentValue,
        proposedValue: null,
        status: ExternalMetadataProposalFieldStatus.notProposed,
      );
    }

    final existing = await metadataFieldStateRepository.get(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
    );

    final decision = MetadataAuthorityPolicy.evaluateAutomaticReplacement(
      existingValuePresent: currentValuePresent,
      existing: existing,
      incomingAuthority: MetadataAuthority.external,
    );

    if (decision == MetadataReplacementDecision.rejectLowerAuthority) {
      return ExternalMetadataProposalField(
        fieldName: fieldName,
        currentValue: currentValue,
        proposedValue: proposedValue,
        status: ExternalMetadataProposalFieldStatus.protected,
        existingState: existing,
      );
    }

    if (decision == MetadataReplacementDecision.requireReviewUnknownAuthority) {
      return ExternalMetadataProposalField(
        fieldName: fieldName,
        currentValue: currentValue,
        proposedValue: proposedValue,
        status: ExternalMetadataProposalFieldStatus.reviewRequired,
        existingState: existing,
      );
    }

    if (currentValue != proposedValue) {
      return ExternalMetadataProposalField(
        fieldName: fieldName,
        currentValue: currentValue,
        proposedValue: proposedValue,
        status: ExternalMetadataProposalFieldStatus.valueChange,
        existingState: existing,
      );
    }

    final provenanceCurrent =
        existing != null &&
        existing.authority == MetadataAuthority.external &&
        existing.source == MetadataProvenanceSource.musicBrainz &&
        existing.sourceReference == sourceReference;

    return ExternalMetadataProposalField(
      fieldName: fieldName,
      currentValue: currentValue,
      proposedValue: proposedValue,
      status: provenanceCurrent
          ? ExternalMetadataProposalFieldStatus.unchanged
          : ExternalMetadataProposalFieldStatus.provenanceOnly,
      existingState: existing,
    );
  }

  static void _requireCandidate(
    ExternalMetadataCandidate candidate,
    ExternalMetadataEntityKind kind,
  ) {
    if (candidate.provider != ExternalMetadataProviderKind.musicBrainz ||
        candidate.entityKind != kind) {
      throw ArgumentError.value(
        candidate,
        'candidate',
        'Expected a MusicBrainz $kind candidate.',
      );
    }
  }

  static String _requiredId(String id) {
    final trimmed = id.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError.value(id, 'id', 'ID must not be blank.');
    }

    return trimmed;
  }
}
