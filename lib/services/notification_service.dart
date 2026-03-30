import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import 'user_service.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static String? _fcmToken;
  static bool _initialized = false;

  static String? get fcmToken => _fcmToken;

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
  /// Returns true if permission was granted and a token is available.
  static Future<bool> initialize() async {
    if (_initialized) return _fcmToken != null;
    _initialized = true;

    // Init flutter_local_notifications
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initSettings);

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
    _fcmToken = await _messaging.getToken();
    if (_fcmToken != null) await _registerDevice(_fcmToken!);

    // Token refresh — re-register device only, userSessions persists
    _messaging.onTokenRefresh.listen((newToken) async {
      _fcmToken = newToken;
      await _registerDevice(newToken);
    });

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    return _fcmToken != null;
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

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
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
    );
  }

  /// Call on sign-out so the next sign-in re-initializes.
  static void reset() {
    _initialized = false;
    _fcmToken = null;
  }
}
