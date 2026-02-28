import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import 'subscription_service.dart';

/// Handle background FCM messages (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('NotificationService: Background message: ${message.messageId}');
}

/// Singleton service wrapping Firebase Cloud Messaging for push notifications.
///
/// Handles FCM token management, token registration with the backend,
/// and displaying local notifications when Docker events arrive.
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();


  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;
  bool _permissionGranted = false;

  // Getters
  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;
  bool get permissionGranted => _permissionGranted;

  /// Initialize local notification channels only. Does NOT request
  /// notification permission — that is deferred to [requestPermissionAndToken]
  /// so users only see the prompt when they enable the feature.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Initialize local notifications plugin
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channel for Docker events
      const androidChannel = AndroidNotificationChannel(
        'docker_events',
        'Docker Events',
        description: 'Notifications for Docker container events',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('NotificationService: Failed to initialize: $e');
      _isInitialized = false;
    }
  }

  /// Request notification permission and obtain FCM token.
  /// Call this when the user explicitly enables notifications.
  Future<bool> requestPermissionAndToken() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized;

      if (!_permissionGranted) {
        debugPrint('NotificationService: Permission not granted');
        return false;
      }

      // Get FCM token
      _fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('NotificationService: FCM token: $_fcmToken');

      // Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('NotificationService: Permission request failed: $e');
      return false;
    }
  }

  /// Register the FCM token with the backend, associating it with
  /// the RevenueCat user ID.
  Future<bool> registerTokenWithBackend() async {
    final subscriptionService = SubscriptionService();

    if (_fcmToken == null) {
      debugPrint('NotificationService: No FCM token available');
      return false;
    }

    if (subscriptionService.appUserId == null) {
      debugPrint('NotificationService: No RevenueCat user ID available');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/register-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fcm_token': _fcmToken,
          'rc_user_id': subscriptionService.appUserId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('NotificationService: Token registered successfully');
        return true;
      } else {
        debugPrint(
            'NotificationService: Token registration failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('NotificationService: Token registration error: $e');
      return false;
    }
  }

  // --- Private handlers ---

  void _onTokenRefresh(String newToken) {
    debugPrint('NotificationService: Token refreshed');
    _fcmToken = newToken;

    // Re-register with backend if user is Pro
    final subscriptionService = SubscriptionService();
    if (subscriptionService.isPro) {
      registerTokenWithBackend();
    }

    notifyListeners();
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('NotificationService: Foreground message: ${message.messageId}');

    final notification = message.notification;
    if (notification != null) {
      _showLocalNotification(
        title: notification.title ?? 'Docker Event',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
      );
    } else if (message.data.isNotEmpty) {
      // Data-only message — parse Docker event
      final eventType = message.data['event_type'] ?? 'event';
      final containerName = message.data['container_name'] ?? 'Unknown';
      final serverName = message.data['server_name'] ?? 'Server';

      _showLocalNotification(
        title: '🐳 $serverName',
        body: 'Container "$containerName" — $eventType',
        payload: jsonEncode(message.data),
      );
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'docker_events',
      'Docker Events',
      channelDescription: 'Notifications for Docker container events',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint(
        'NotificationService: Notification tapped: ${response.payload}');
    // TODO: Navigate to the relevant container screen if desired
  }
}
