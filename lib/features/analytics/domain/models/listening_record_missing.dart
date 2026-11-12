/// A listening record (session, segment or qualified play) that was being
/// updated no longer exists.
///
/// Permanently deleting a song erases its listening history, including the
/// session open while it plays (App Update 1.2, BUG-11 hardening). The
/// listening tracker then forgets that session instead of retrying it
/// forever. A [StateError], as these updates have always reported.
class ListeningRecordMissing extends StateError {
  ListeningRecordMissing(super.message);
}
