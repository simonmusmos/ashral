import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Background messages are handled by the system tray automatically.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await UserService.instance.init();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.createNotificationChannel();
  runApp(const AshralApp());
}


class AshralApp extends StatefulWidget {
  const AshralApp({super.key});

  @override
  State<AshralApp> createState() => _AshralAppState();
}

class _AshralAppState extends State<AshralApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    NotificationService.navigatorKey = _navigatorKey;

    // App opened from a terminated state by tapping a notification
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) NotificationService.handleInitialMessage(message);
    });

    // App in background, user taps notification
    FirebaseMessaging.onMessageOpenedApp
        .listen(NotificationService.handleFcmTap);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ashral',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AshralTheme.build(),
      home: StreamBuilder(
        stream: AuthService.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  color: AppColors.textSecondary,
                  strokeWidth: 1.5,
                ),
              ),
            );
          }
          if (snapshot.hasData) return const HomeScreen();
          return const AuthScreen();
        },
      ),
    );
  }
}
