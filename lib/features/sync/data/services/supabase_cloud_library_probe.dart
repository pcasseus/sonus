import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_library_first_link_guard.dart';
import '../contracts/supabase_sync_contract.dart';
import '../gateways/supabase_cloud_archive_gateway.dart';

class SupabaseCloudLibraryProbe implements CloudLibraryProbe {
  const SupabaseCloudLibraryProbe({required this.client});

  final SupabaseClient client;

  @override
  Future<bool> hasLibrary(String userId) async {
    for (final table in [
      SupabaseSyncContract.songsTable,
      SupabaseSyncContract.artistsTable,
      SupabaseSyncContract.artworkAssetsTable,
    ]) {
      final rows = await client
          .from(table)
          .select(SupabaseSyncContract.idColumn)
          .eq(SupabaseSyncContract.userIdColumn, userId)
          .limit(1);
      if (rows.isNotEmpty) return true;
    }

    try {
      final rows = await client
          .from(SupabaseCloudArchiveGateway.table)
          .select('record_key')
          .eq('user_id', userId)
          .limit(1);
      return rows.isNotEmpty;
    } on PostgrestException catch (error) {
      // A server without the archive simply has nothing in it.
      if (error.code == 'PGRST205' || error.code == '42P01') return false;
      rethrow;
    }
  }
}

/// The choice to bring an account's cloud library onto this device.
/// Device-local, like other consents.
class SharedPreferencesCloudLibraryConsentStore
    implements CloudLibraryConsentStore {
  SharedPreferencesCloudLibraryConsentStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String keyFor(String userId) => 'sync.cloud_library_consent.$userId';

  @override
  Future<bool> hasConsent(String userId) async =>
      await _preferences.getBool(keyFor(userId)) ?? false;

  @override
  Future<void> grant(String userId) =>
      _preferences.setBool(keyFor(userId), true);
}
