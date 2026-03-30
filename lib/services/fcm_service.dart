import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> saveFcmToken(String uid) async {
    try {
      await requestPermission();
      final token = await _getFcmToken();
      if (token == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Refresh token listener
      _messaging.onTokenRefresh.listen((newToken) async {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {
            'fcmToken': newToken,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('FcmService: failed to save token — $e');
    }
  }

  static Future<String?> _getFcmToken() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      const attempts = 10;
      for (var i = 0; i < attempts; i++) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          return _messaging.getToken();
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      debugPrint(
        'FcmService: APNS token not available yet; skipping initial FCM token fetch.',
      );
      return null;
    }

    return _messaging.getToken();
  }
}
