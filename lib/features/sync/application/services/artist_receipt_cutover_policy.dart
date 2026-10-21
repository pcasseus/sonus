/// Safety switch for SN-41 receipt-aware production composition.
///
/// This must remain false until concurrency and database verification
/// are complete and a separate cutover is explicitly approved.
abstract final class ArtistReceiptCutoverPolicy {
  static const bool enabled = false;
}
