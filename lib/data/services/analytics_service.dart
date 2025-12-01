import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight wrapper around PostHog to keep analytics calls consistent.
class AnalyticsService {
  AnalyticsService._internal();
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;

  static const String _apiKey =
      String.fromEnvironment('POSTHOG_API_KEY', defaultValue: '');
  static const String _host =
      String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://us.i.posthog.com');

  bool _isEnabled = false;
  String? _distinctId;

  Future<void> init() async {
    if (_apiKey.isEmpty) {
      debugPrint('[Analytics] PostHog disabled (POSTHOG_API_KEY missing)');
      return;
    }

    try {
      final config = PostHogConfig(_apiKey)
        ..host = _host
        ..flushAt = 1
        ..captureApplicationLifecycleEvents = true
        ..errorTrackingConfig.captureFlutterErrors = true
        ..errorTrackingConfig.capturePlatformDispatcherErrors = true;

      await Posthog().setup(config);

      _distinctId = await _getOrCreateDistinctId();
      await Posthog().identify(
        userId: _distinctId!,
        userProperties: const {
          'app': 'docker_manager',
        },
      );

      _isEnabled = true;
      await trackEvent('app_started');
    } catch (e) {
      _isEnabled = false;
      debugPrint('[Analytics] Failed to initialize PostHog: $e');
    }
  }

  Future<String> _getOrCreateDistinctId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('analytics_distinct_id');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString('analytics_distinct_id', id);
    return id;
  }

  Future<void> trackScreen(
    String screenName, {
    Map<String, Object?>? properties,
  }) async {
    if (!_isEnabled) return;
    try {
      final cleaned = _cleanProperties(properties);
      await Posthog().screen(
        screenName: screenName,
        properties: cleaned.isEmpty ? null : cleaned,
      );
    } catch (e) {
      debugPrint('[Analytics] screen($screenName) failed: $e');
    }
  }

  Future<void> trackEvent(
    String eventName, {
    Map<String, Object?>? properties,
  }) async {
    if (!_isEnabled) return;
    try {
      final cleaned = _cleanProperties(properties);
      await Posthog().capture(
        eventName: eventName,
        properties: cleaned.isEmpty ? null : cleaned,
      );
    } catch (e) {
      debugPrint('[Analytics] capture($eventName) failed: $e');
    }
  }

  Future<void> trackButton(
    String label, {
    String? location,
    Map<String, Object?>? properties,
  }) {
    return trackEvent(
      'ui.button_tap',
      properties: {
        'label': label,
        if (location != null) 'location': location,
        ..._cleanProperties(properties),
      },
    );
  }

  Future<void> trackException(
    String eventName,
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?>? properties,
  }) async {
    if (!_isEnabled) return;
    try {
      final cleaned = _cleanProperties(properties);
      await Posthog().captureException(
        error: error,
        stackTrace: stackTrace,
        properties: cleaned.isEmpty ? null : cleaned,
      );
      await trackEvent(
        eventName,
        properties: {
          'message': error.toString(),
          ...cleaned,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] captureException($eventName) failed: $e');
    }
  }

  Map<String, Object> _cleanProperties(Map<String, Object?>? properties) {
    final cleaned = <String, Object>{};
    if (properties == null) return cleaned;

    properties.forEach((key, value) {
      if (value == null) return;
      if (value is bool ||
          value is num ||
          value is String ||
          value is List ||
          value is Map<String, Object>) {
        cleaned[key] = value;
      } else {
        cleaned[key] = value.toString();
      }
    });
    return cleaned;
  }
}
