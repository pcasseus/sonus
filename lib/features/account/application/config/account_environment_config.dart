class AccountEnvironmentConfig {
  const AccountEnvironmentConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
  });

  factory AccountEnvironmentConfig.fromEnvironment() {
    return const AccountEnvironmentConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    );
  }

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;

  bool get isSupabaseConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  bool get isGoogleConfigured => googleWebClientId.trim().isNotEmpty;

  bool get isFullyConfigured => isSupabaseConfigured && isGoogleConfigured;
}
