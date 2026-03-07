/// Centralized configuration for the Docker Manager app.
///
/// All environment-specific values live here so they can be
/// changed in one place before shipping.
///
/// Secrets and environment-specific values are injected at build time
/// via --dart-define flags (read from local.properties in CI).
/// Default values are production values, so local dev works without
/// any extra configuration.
class AppConfig {
  AppConfig._();

  // ⚠️ DEBUG ONLY: Set to true to force Pro status for testing.
  // MUST be false before shipping!
  static const bool debugForcePro = false;

  /// Backend API base URL.
  /// Injected via --dart-define=BACKEND_BASE_URL=...
  /// Defaults to production URL if not provided.
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://dm-prod.1110777.xyz/api',
  );
  
  /// Docker image for the dm-notifier container.
  static const String notifierImage = 'ghcr.io/thesobersobber/dm-notifier:latest';

  /// Container name for dm-notifier (also used as dedup key).
  static const String notifierContainerName = 'dm-notifier';

  /// RevenueCat API key.
  /// Injected via --dart-define=REVENUECAT_API_KEY=...
  /// Defaults to production key if not provided.
  static const String revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: 'wont_work',
  );

  /// RevenueCat entitlement ID for Pro.
  static const String proEntitlementId = 'Docker Manager Pro';
}
