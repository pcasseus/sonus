import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../artwork/data/services/cover_art_archive/cover_art_image_validator.dart';
import '../../../artwork/data/services/file_system_artwork_managed_storage.dart';
import '../../application/services/cloud_artwork_recovery_service.dart';
import '../../data/services/supabase_cloud_artwork_storage.dart';

/// Production composition of cloud artwork recovery used by SyncScope.
///
/// Downloads land in the same managed artwork storage as user imports and
/// pass the same image validation. Only the directory providers may be
/// replaced, so tests can run the exact production chain.
CloudArtworkRecoveryService createCloudArtworkRecovery({
  required SupabaseClient client,
  ArtworkDownloadDirectory? downloadDirectory,
  ArtworkStorageDirectoryProvider? managedArtworkDirectory,
}) {
  return CloudArtworkRecoveryService(
    cloudArtworkStorage: SupabaseCloudArtworkStorage(client: client),
    managedStorage: FileSystemArtworkManagedStorage(
      applicationSupportDirectoryProvider: managedArtworkDirectory,
    ),
    validateImage: const CoverArtImageValidator(
      maximumBytes: CloudArtworkRecoveryService.defaultMaxBytes,
    ).validate,
    downloadDirectory:
        downloadDirectory ?? () async => (await getTemporaryDirectory()).path,
  );
}
