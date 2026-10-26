import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/timed_http_client.dart';

import '../../data/repositories/supabase_account_repository.dart';
import '../../data/services/google_sign_in_auth_gateway.dart';
import '../../data/services/supabase_client_auth_gateway.dart';
import 'account_bootstrap_result.dart';
import 'account_environment_config.dart';

abstract final class AccountBootstrapper {
  static Future<AccountBootstrapResult> initialize(
    AccountEnvironmentConfig config,
  ) async {
    if (!config.isFullyConfigured) {
      return const AccountBootstrapResult(repository: null);
    }

    await Supabase.initialize(
      url: config.supabaseUrl.trim(),
      publishableKey: config.supabasePublishableKey.trim(),
      // Every auth, database and storage request finishes or times out, so
      // a stalled connection can never leave sync running forever.
      httpClient: TimedHttpClient(),
    );

    final googleAuthGateway = GoogleSignInAuthGateway(
      serverClientId: config.googleWebClientId,
    );

    final supabaseAuthGateway = SupabaseClientAuthGateway(
      client: Supabase.instance.client,
    );

    final repository = SupabaseAccountRepository(
      supabaseAuthGateway: supabaseAuthGateway,
      googleAuthGateway: googleAuthGateway,
    );

    return AccountBootstrapResult(repository: repository);
  }
}
