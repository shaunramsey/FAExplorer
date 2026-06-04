import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/app_theme.dart';
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
const kTextDim     = Color(0xFF8A9BB0);
const kTextMid     = Color(0xFFB0BDCC);
const kTextLight   = Color(0xFFE8ECF0);
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

  final authService   = AuthService(firebaseEnabled: firebaseEnabled);
  final themeNotifier = await AppThemeNotifier.load();

  runApp(MyApp(
    authService: authService,
    firebaseEnabled: firebaseEnabled,
    themeNotifier: themeNotifier,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.authService,
    required this.firebaseEnabled,
    required this.themeNotifier,
  });

  final AuthService authService;
  final bool firebaseEnabled;
  final AppThemeNotifier themeNotifier;

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      notifier: themeNotifier,
      child: ListenableBuilder(
        listenable: themeNotifier,
        builder: (context, _) => MaterialApp(
          title: 'Automata Designer',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(themeNotifier.data),
          home: AppGate(
            authService: authService,
            firebaseEnabled: firebaseEnabled,
          ),
        ),
      ),
    );
  }

  ThemeData _buildTheme(AppThemeData c) {
    final base = ThemeData.dark();

    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.surface,
      cardColor: c.surface,

      colorScheme: ColorScheme.dark(
        primary:          c.accent,
        onPrimary:        c.bg,
        secondary:        c.accentGreen,
        onSecondary:      c.bg,
        surface:          c.surface,
        onSurface:        c.textLight,
        error:            const Color(0xFFFF1744),
        onError:          c.bg,
        outline:          c.borderMid,
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.orbitron(
          color: c.accent,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
        iconTheme: IconThemeData(color: c.textMid),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // Drawer
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),

      // Dividers
      dividerTheme: DividerThemeData(color: c.borderMid, thickness: 1),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF080D14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.borderMid),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.borderMid),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        labelStyle: GoogleFonts.orbitron(color: c.textMid, fontSize: 12, letterSpacing: 1),
        hintStyle: GoogleFonts.sourceCodePro(color: c.textDim, fontSize: 13),
        errorStyle: GoogleFonts.sourceCodePro(color: const Color(0xFFFF1744), fontSize: 11),
      ),

      // Filled / elevated buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent.withOpacity(0.12),
          foregroundColor: c.accent,
          side: BorderSide(color: c.accent, width: 1),
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
          foregroundColor: c.textMid,
          side: BorderSide(color: c.borderMid),
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
          foregroundColor: c.textMid,
          textStyle: GoogleFonts.orbitron(fontSize: 10, letterSpacing: 1.5),
        ),
      ),

      // Floating action buttons
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.surface,
        foregroundColor: c.textLight,
        elevation: 4,
        highlightElevation: 8,
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        labelStyle: GoogleFonts.orbitron(color: c.textMid, fontSize: 9, letterSpacing: 1.5),
        side: BorderSide(color: c.borderMid),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // Progress indicators
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.gridLine,
      ),

      // Snackbars
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surface,
        contentTextStyle: GoogleFonts.sourceCodePro(color: c.textLight, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: c.borderMid),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Bottom sheets
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),

      // Text theme
      textTheme: GoogleFonts.orbitronTextTheme(base.textTheme).copyWith(
        bodyLarge:   GoogleFonts.sourceCodePro(color: c.textLight, fontSize: 14),
        bodyMedium:  GoogleFonts.sourceCodePro(color: c.textMid,   fontSize: 13),
        bodySmall:   GoogleFonts.sourceCodePro(color: c.textDim,   fontSize: 11),
        labelLarge:  GoogleFonts.orbitron(color: c.textLight, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700),
        labelMedium: GoogleFonts.orbitron(color: c.textMid,   fontSize: 10, letterSpacing: 1.2),
        labelSmall:  GoogleFonts.orbitron(color: c.textDim,   fontSize: 8,  letterSpacing: 1.0),
      ),
      primaryTextTheme: GoogleFonts.orbitronTextTheme(base.primaryTextTheme),

      // Icons
      iconTheme: IconThemeData(color: c.textMid, size: 22),
      primaryIconTheme: IconThemeData(color: c.accent),
    );
  }
}