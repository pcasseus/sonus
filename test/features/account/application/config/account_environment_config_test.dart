import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/account/application/config/account_bootstrap_result.dart';
import 'package:sonus_next/features/account/application/config/account_environment_config.dart';

void main() {
  group('AccountEnvironmentConfig', () {
    test('reports fully configured when all values are present', () {
      const config = AccountEnvironmentConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'publishable-key',
        googleWebClientId: 'google-client-id',
      );

      expect(config.isSupabaseConfigured, isTrue);
      expect(config.isGoogleConfigured, isTrue);
      expect(config.isFullyConfigured, isTrue);
    });

    test('reports Supabase as unconfigured when URL is blank', () {
      const config = AccountEnvironmentConfig(
        supabaseUrl: '   ',
        supabasePublishableKey: 'publishable-key',
        googleWebClientId: 'google-client-id',
      );

      expect(config.isSupabaseConfigured, isFalse);
      expect(config.isFullyConfigured, isFalse);
    });

    test('reports Supabase as unconfigured when publishable key is blank', () {
      const config = AccountEnvironmentConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: '   ',
        googleWebClientId: 'google-client-id',
      );

      expect(config.isSupabaseConfigured, isFalse);
      expect(config.isFullyConfigured, isFalse);
    });

    test('reports Google as unconfigured when client ID is blank', () {
      const config = AccountEnvironmentConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'publishable-key',
        googleWebClientId: '   ',
      );

      expect(config.isGoogleConfigured, isFalse);
      expect(config.isFullyConfigured, isFalse);
    });
  });

  group('AccountBootstrapResult', () {
    test('reports unavailable when repository is null', () {
      const result = AccountBootstrapResult(repository: null);

      expect(result.isAvailable, isFalse);
    });
  });
}
