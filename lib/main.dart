import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';

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

ThemeData _buildTheme() {
  const background = Color(0xFF090909);
  const surface = Color(0xFF111111);
  const border = Color(0xFF222222);
  const textPrimary = Color(0xFFF2F2F2);
  const textSecondary = Color(0xFF5C5C5C);

  final jakartaBase =
      GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: textPrimary,
      onPrimary: background,
      surface: surface,
      onSurface: textPrimary,
      outline: border,
      error: Color(0xFFEF4444),
      onError: textPrimary,
    ),
    textTheme: jakartaBase.copyWith(
      bodyMedium: jakartaBase.bodyMedium?.copyWith(color: textSecondary),
      bodySmall: jakartaBase.bodySmall?.copyWith(color: textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF3A3A3A), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: textPrimary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      errorStyle: GoogleFonts.plusJakartaSans(
          color: const Color(0xFFEF4444), fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: textPrimary,
        foregroundColor: background,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: border),
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(color: textSecondary),
    ),
  );
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
      theme: _buildTheme(),
      home: StreamBuilder(
        stream: AuthService.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFF2F2F2),
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
