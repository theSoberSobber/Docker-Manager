import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../../config/app_config.dart';

/// Singleton service wrapping RevenueCat for subscription management.
///
/// Provides accountless Pro subscription handling. Cross-device
/// portability is achieved via "Restore Purchases" (tied to the
/// user's Play Store or Apple ID account).
class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  bool _isInitialized = false;
  bool _isPro = false;
  String? _appUserId;

  // Getters
  bool get isPro => AppConfig.debugForcePro || _isPro;
  bool get isInitialized => _isInitialized;
  String? get appUserId => _appUserId;

  /// Initialize RevenueCat SDK. Call once at app startup.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await Purchases.setLogLevel(LogLevel.debug);

      final configuration = PurchasesConfiguration(AppConfig.revenueCatApiKey);
      await Purchases.configure(configuration);

      // Listen for customer info changes (subscription status updates)
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

      // Get initial status
      final customerInfo = await Purchases.getCustomerInfo();
      _updateProStatus(customerInfo);

      _appUserId = await Purchases.appUserID;
      _isInitialized = true;

      notifyListeners();
    } catch (e) {
      debugPrint('SubscriptionService: Failed to initialize RevenueCat: $e');
      _isInitialized = false;
    }
  }

  /// Show the RevenueCat Paywall to purchase Pro.
  /// Returns true if the user ended up with an active Pro entitlement.
  Future<bool> showPaywall(BuildContext context) async {
    try {
      final paywallResult = await RevenueCatUI.presentPaywallIfNeeded(
        AppConfig.proEntitlementId,
      );

      debugPrint('SubscriptionService: Paywall result: $paywallResult');

      // Refresh status after paywall closes
      await refreshStatus();
      return _isPro;
    } catch (e) {
      debugPrint('SubscriptionService: Paywall error: $e');
      return false;
    }
  }

  /// Show the RevenueCat Customer Center for managing subscriptions.
  Future<void> showCustomerCenter(BuildContext context) async {
    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
      debugPrint('SubscriptionService: Customer Center error: $e');
    }
  }

  /// Restore previous purchases (cross-device portability).
  /// Returns true if Pro was restored.
  Future<bool> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updateProStatus(customerInfo);
      notifyListeners();
      return _isPro;
    } catch (e) {
      debugPrint('SubscriptionService: Restore failed: $e');
      return false;
    }
  }

  /// Check current subscription status (force refresh from server).
  Future<void> refreshStatus() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      _updateProStatus(customerInfo);
      notifyListeners();
    } catch (e) {
      debugPrint('SubscriptionService: Failed to refresh status: $e');
    }
  }

  // --- Private helpers ---

  void _onCustomerInfoUpdated(CustomerInfo customerInfo) {
    _updateProStatus(customerInfo);
    notifyListeners();
  }

  void _updateProStatus(CustomerInfo customerInfo) {
    _isPro = customerInfo.entitlements.active.containsKey(AppConfig.proEntitlementId);
    _appUserId = customerInfo.originalAppUserId;
  }
}
