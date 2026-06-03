import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'game_gate.dart';
import 'auth/auth_service.dart';
import 'firebase_options.dart';

export 'automata_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Shared palette — mirrors level_select_screen.dart exactly so every screen
//  speaks the same visual language.
// ─────────────────────────────────────────────────────────────────────────────
const kBg          = Color(0xFF05080F);
const kGridLine    = Color(0xFF0D1620);
const kAccent      = Color(0xFF00E5FF);   // cyan highlight
const kAccentGreen = Color(0xFF1FD99A);   // edge-bright teal
const kTextDim     = Color(0xFF3A4A5E);
const kTextMid     = Color(0xFF6B7E96);
const kTextLight   = Color(0xFFCDD5E0);
const kSurface     = Color(0xFF0A0F18);
const kBorder      = Color(0xFF141E2A);
const kBorderMid   = Color(0xFF1A2535);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep status/nav bars transparent so the dark bg bleeds through.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  var firebaseEnabled = false;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseEnabled = true;
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
    }
  }

  final authService = AuthService(firebaseEnabled: firebaseEnabled);

  runApp(MyApp(
    authService: authService,
    firebaseEnabled: firebaseEnabled,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.authService,
    required this.firebaseEnabled,
  });

  final AuthService authService;
  final bool firebaseEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automata Designer',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: AppGate(
        authService: authService,
        firebaseEnabled: firebaseEnabled,
      ),
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData.dark();

    return base.copyWith(
      scaffoldBackgroundColor: kBg,
      canvasColor: kSurface,
      cardColor: kSurface,

      colorScheme: const ColorScheme.dark(
        primary:          kAccent,
        onPrimary:        kBg,
        secondary:        kAccentGreen,
        onSecondary:      kBg,
        surface:          kSurface,
        onSurface:        kTextLight,
        error:            Color(0xFFFF1744),
        onError:          kBg,
        outline:          kBorderMid,
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: kSurface,
        foregroundColor: kTextLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.orbitron(
          color: kAccent,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
        iconTheme: const IconThemeData(color: kTextMid),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // Drawer
      drawerTheme: const DrawerThemeData(
        backgroundColor: kSurface,
        surfaceTintColor: Colors.transparent,
      ),

      // Dividers
      dividerTheme: const DividerThemeData(color: kBorderMid, thickness: 1),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF080D14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kBorderMid),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kBorderMid),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
        labelStyle: GoogleFonts.orbitron(color: kTextMid, fontSize: 12, letterSpacing: 1),
        hintStyle: GoogleFonts.sourceCodePro(color: kTextDim, fontSize: 13),
        errorStyle: GoogleFonts.sourceCodePro(color: const Color(0xFFFF1744), fontSize: 11),
      ),

      // Filled / elevated buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kAccent.withOpacity(0.12),
          foregroundColor: kAccent,
          side: const BorderSide(color: kAccent, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: GoogleFonts.orbitron(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),

      // Outlined buttons
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kTextMid,
          side: const BorderSide(color: kBorderMid),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: GoogleFonts.orbitron(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      ),

      // Text buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kTextMid,
          textStyle: GoogleFonts.orbitron(fontSize: 10, letterSpacing: 1.5),
        ),
      ),

      // Floating action buttons
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: kSurface,
        foregroundColor: kTextLight,
        elevation: 4,
        highlightElevation: 8,
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: kSurface,
        labelStyle: GoogleFonts.orbitron(color: kTextMid, fontSize: 9, letterSpacing: 1.5),
        side: const BorderSide(color: kBorderMid),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // Progress indicators
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: kAccent,
        linearTrackColor: kGridLine,
      ),

      // Snackbars
      snackBarTheme: SnackBarThemeData(
        backgroundColor: kSurface,
        contentTextStyle: GoogleFonts.sourceCodePro(color: kTextLight, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: kBorderMid),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Bottom sheets
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),

      // Text theme — Orbitron for display, Source Code Pro for body/mono
      textTheme: GoogleFonts.orbitronTextTheme(base.textTheme).copyWith(
        bodyLarge:   GoogleFonts.sourceCodePro(color: kTextLight, fontSize: 14),
        bodyMedium:  GoogleFonts.sourceCodePro(color: kTextMid,   fontSize: 13),
        bodySmall:   GoogleFonts.sourceCodePro(color: kTextDim,   fontSize: 11),
        labelLarge:  GoogleFonts.orbitron(color: kTextLight, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700),
        labelMedium: GoogleFonts.orbitron(color: kTextMid,   fontSize: 10, letterSpacing: 1.2),
        labelSmall:  GoogleFonts.orbitron(color: kTextDim,   fontSize: 8,  letterSpacing: 1.0),
      ),
      primaryTextTheme: GoogleFonts.orbitronTextTheme(base.primaryTextTheme),

      // Icons
      iconTheme: const IconThemeData(color: kTextMid, size: 22),
      primaryIconTheme: const IconThemeData(color: kAccent),
    );
  }
}