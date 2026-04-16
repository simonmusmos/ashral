import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../screens/session_screen.dart';
import 'user_service.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static String? _fcmToken;
  static bool _initialized = false;
  static GlobalKey<NavigatorState>? _navigatorKey;

  static String? get fcmToken => _fcmToken;

  static set navigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Creates the Android notification channel. Call once in main() before runApp.
  static Future<void> createNotificationChannel() async {
    if (!Platform.isAndroid) return;
    const channel = AndroidNotificationChannel(
      kNotificationChannelId,
      kNotificationChannelName,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Requests permission, fetches the FCM token, registers the device with
  /// the backend, and sets up foreground + token-refresh listeners.
  ///
  /// Returns true if notification permission was granted.
  static Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = true;

    // Init flutter_local_notifications with tap callback
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return false;

    // Get token + register device
    _fcmToken = await _getFcmToken();
    if (_fcmToken != null) await _registerDevice(_fcmToken!);

    // Token refresh — re-register device only, userSessions persists
    _messaging.onTokenRefresh.listen((newToken) async {
      _fcmToken = newToken;
      await _registerDevice(newToken);
    });

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    return true;
  }

  /// Call when the app is opened from a terminated state via notification tap.
  static void handleInitialMessage(RemoteMessage message) {
    final sessionId = message.data['sessionId'] as String?;
    if (sessionId != null && sessionId.isNotEmpty) {
      // Delay until the navigator is ready after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToSession(sessionId);
      });
    }
  }

  /// Call when the app is in the background and the user taps a notification.
  static void handleFcmTap(RemoteMessage message) {
    final sessionId = message.data['sessionId'] as String?;
    if (sessionId != null && sessionId.isNotEmpty) {
      _navigateToSession(sessionId);
    }
  }

  static void _onLocalNotificationTap(NotificationResponse response) {
    final sessionId = response.payload;
    if (sessionId != null && sessionId.isNotEmpty) {
      _navigateToSession(sessionId);
    }
  }

  static void _navigateToSession(String sessionId) {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => SessionScreen(sessionId: sessionId),
    ));
  }

  static Future<String?> _getFcmToken() async {
    if (!kIsWeb && Platform.isIOS) {
      const attempts = 10;
      for (var i = 0; i < attempts; i++) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          return _messaging.getToken();
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      debugPrint(
        'NotificationService: APNS token not available yet; skipping initial FCM token fetch.',
      );
      return null;
    }

    return _messaging.getToken();
  }

  static Future<void> _registerDevice(String token) async {
    try {
      final userId = UserService.instance.userId;
      final response = await http.post(
        Uri.parse('$kBackendUrl/users/$userId/devices'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fcmToken': token}),
      );
      debugPrint(
          'NotificationService: device registered — ${response.statusCode}');
    } catch (e) {
      debugPrint('NotificationService: device registration failed — $e');
    }
  }

  static Future<void> _showForegroundNotification(
      RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final sessionId = message.data['sessionId'] as String?;
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kNotificationChannelId,
          kNotificationChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: sessionId,
    );
  }

  /// Call on sign-out so the next sign-in re-initializes.
  static void reset() {
    _initialized = false;
    _fcmToken = null;
  }
}
