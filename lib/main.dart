import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart' show appEnvironment;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  runApp(CompleatApp(isLoggedIn: token != null));
}

class CompleatApp extends StatelessWidget {
  final bool isLoggedIn;
  const CompleatApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    // Test identity: driven ONLY by the existing --dart-define=APP_ENV (qa
    // flavor build sets APP_ENV=test). Committed default is 'prod' -> blue
    // theme, no ribbon; the red look cannot ship to live by accident.
    final bool isTestEnv = appEnvironment == 'test';
    return MaterialApp(
      title: 'Com-Pleat IMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor:
                isTestEnv ? const Color(0xFFB91C1C) : const Color(0xFF1a73e8)),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18),
          bodyMedium: TextStyle(fontSize: 16),
        ),
      ),
      builder: (context, child) {
        if (!isTestEnv || child == null) return child ?? const SizedBox();
        // Corner ribbon on EVERY screen (same mechanism as Flutter's own
        // debug banner). Directionality is needed because the builder sits
        // above the Navigator's Localizations.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Banner(
            message: 'TEST',
            location: BannerLocation.topEnd,
            color: const Color(0xFFB91C1C),
            child: child,
          ),
        );
      },
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
