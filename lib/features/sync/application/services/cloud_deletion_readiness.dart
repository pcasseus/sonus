/// Whether the cloud this app syncs with carries permanent deletion (App
/// Update 1.2; server migration 20261108000001). Provided by SyncScope;
/// read by the permanent-deletion flow, which stays blocked on a linked
/// device until this answers yes.
class CloudDeletionReadiness {
  const CloudDeletionReadiness(this._probe);

  final Future<bool> Function() _probe;

  Future<bool> isReady() => _probe();
}
