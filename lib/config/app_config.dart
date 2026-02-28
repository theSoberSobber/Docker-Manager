/// Centralized configuration for the Docker Manager app.
///
/// All environment-specific values live here so they can be
/// changed in one place before shipping.
class AppConfig {
  AppConfig._();

  // ⚠️ DEBUG ONLY: Set to true to force Pro status for testing.
  // MUST be false before shipping!
  static const bool debugForcePro = true;

  /// Backend API base URL.
  /// Change this to your production URL before shipping.
  static const String backendBaseUrl = 'https://dm-testing.1110777.xyz/api';

  /// Docker image for the dm-notifier container.
  static const String notifierImage = 'ghcr.io/thesobersobber/dm-notifier:latest';

  /// Container name for dm-notifier (also used as dedup key).
  static const String notifierContainerName = 'dm-notifier';

  /// RevenueCat API key.
  static const String revenueCatApiKey = 'test_SLzssVELfvHPiehzPsSCAPTHhfK';

  /// RevenueCat entitlement ID for Pro.
  static const String proEntitlementId = 'Docker Manager Pro';
}
