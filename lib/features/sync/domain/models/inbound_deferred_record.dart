import 'sync_data_contract.dart';

/// Why a verified cloud revision could not yet be applied locally.
enum InboundDeferralReason {
  /// The artwork bytes exist only in cloud Storage.
  artworkDownloadRequired,

  /// The cloud row is a tombstone for an entity that still exists locally.
  tombstoneRequiresLocalDeletion,

  /// The record references artwork that is not available locally.
  missingLocalArtwork,

  /// A required parent row (artist, album or edition) is not held locally.
  missingLocalParent,

  /// A required parent has an outstanding deferred revision.
  parentDeferred,

  /// A pending local mutation for the same entity must not be overwritten.
  pendingLocalMutation,

  /// An artist write or dependency journal awaits cloud verification.
  unresolvedArtistJournal,
}

/// A durable replay obligation for a cloud revision the inbound cursor
/// has passed without applying.
///
/// No revision baseline is recorded for a deferred revision, so a later
/// replay is still treated as newer than local state.
class InboundDeferredRecord {
  const InboundDeferredRecord({
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.serverRevision,
    required this.serverUpdatedAt,
    required this.reason,
    required this.deferredAt,
  });

  final String userId;
  final CloudDataEntity entityType;
  final String entityId;
  final int serverRevision;
  final DateTime serverUpdatedAt;
  final InboundDeferralReason reason;
  final DateTime deferredAt;
}
