/// BrainVault — App Entry Point
///
/// Sets up the Material 3 dark theme with a premium aesthetic,
/// configures Google Fonts, and launches the single-screen app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force dark status bar and navigation bar for immersive look
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const BrainVaultApp());
}

class BrainVaultApp extends StatelessWidget {
  const BrainVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrainVault',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  /// Build a premium dark Material 3 theme with Inter font family.
  ThemeData _buildTheme() {
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6C63FF),
        secondary: Color(0xFF4FC3F7),
        surface: Color(0xFF1A1A2E),
        error: Color(0xFFCF6679),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFFE8E8F0),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A0A0F),
    );

    // Apply Inter font via Google Fonts for premium typography
    return baseTheme.copyWith(
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
    );
  }
}
