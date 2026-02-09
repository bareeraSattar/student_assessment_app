import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

// Firebase + FCM
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Local notifications (tray icons + foreground display)
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'home_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

// Global plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Background message handler (must be top-level)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Background message received: ${message.messageId}");

  // Show local notification in tray
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'assessment_channel_id',
    'Assessment Notifications',
    channelDescription: 'Notifications for assessments and feedback',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    playSound: true,
  );

  const NotificationDetails details = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    id: 0,
    title: message.notification?.title ?? 'New Notification',
    body: message.notification?.body ?? 'You have a new update',
    notificationDetails: details,
    payload: jsonEncode(message.data),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize local notifications
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
  );

  // Corrected parameter name for recent versions (^17+)
  await flutterLocalNotificationsPlugin.initialize(
    settings: initSettings,   // ← changed from initializationSettings → settings
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      print("Notification tapped - Payload: ${response.payload}");
      // Add navigation logic here later if needed
    },
  );

  // Set background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Foreground message handler (when app is open)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("Foreground message received: ${message.messageId}");

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'assessment_channel_id',
      'Assessment Notifications',
      channelDescription: 'Notifications for assessments',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    flutterLocalNotificationsPlugin.show(
      id: 0,
      title: message.notification?.title ?? 'New Assessment Update',
      body: message.notification?.body ?? 'Check your records',
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  });

  // App opened from notification tap
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print("App opened from notification tap: ${message.data}");
    // Add navigation here (e.g. to RecordsScreen)
  });

  // Check initial notification (killed state)
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print("Opened from killed state notification: ${initialMessage.data}");
  }

  // Initialize Hive
  final appDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDir.path);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _getInitialScreen() async {
    final savedUser = await AuthStorage.getSavedUser();

    // Request notification permission (non-blocking)
    try {
      final messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('User notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      print("FCM permission request failed: $e");
    }

    if (savedUser != null && savedUser.isNotEmpty) {
      return HomeScreen(userData: savedUser);
    }
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Assessment App',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF10B981),
          tertiary: const Color(0xFFF472B6),
          surface: Colors.white,
          surfaceTint: const Color(0xFFF3F4F6),
          background: const Color(0xFFFAFAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFC),
        cardTheme: CardThemeData(
          elevation: 1.5,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          color: Colors.white,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            minimumSize: const Size(0, 52),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return const Color(0xFF4F46E5);
              }
              return const Color(0xFF6366F1);
            }),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF818CF8),
          brightness: Brightness.dark,
          primary: const Color(0xFF818CF8),
          secondary: const Color(0xFF34D399),
          tertiary: const Color(0xFFF472B6),
          surface: const Color(0xFF111827),
          surfaceTint: const Color(0xFF1F2937),
          background: const Color(0xFF030712),
        ),
        scaffoldBackgroundColor: const Color(0xFF030712),
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          color: const Color(0xFF1F2937),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            minimumSize: const Size(0, 52),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return const Color(0xFF6366F1).withOpacity(0.9);
              }
              return const Color(0xFF818CF8);
            }),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: Colors.white,
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Colors.white),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFD1D5DB)),
          bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFD1D5DB)),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),

      themeMode: ThemeMode.system,

      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 80, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading app: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          }
          return snapshot.data ?? const LoginScreen();
        },
      ),

      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

// AuthStorage (unchanged)
class AuthStorage {
  static const String _userKey = 'current_user';

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_userKey);
    if (jsonString == null) return null;
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      print('Error parsing saved user: $e');
      return null;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }
}