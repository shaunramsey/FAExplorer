import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'widgets/app_theme.dart';
import 'game_gate.dart';
import 'auth/auth_service.dart';
import 'firebase_options.dart';

export 'automata_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeNotifier = await AppThemeNotifier.load();

  // Keep status/nav bars transparent so the dark bg bleeds through.
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: themeNotifier.bg,
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

  runApp(
    ChangeNotifierProvider<AppThemeNotifier>.value(
      value: themeNotifier,
      child: MyApp(
        authService: authService,
        firebaseEnabled: firebaseEnabled,
      ),
    ),
  );
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
    final themeNotifier = context.watch<AppThemeNotifier>();
    final c = themeNotifier.data;
    final light = c.isLightTheme;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: c.bg,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
    return MaterialApp(
      title: 'Automata Designer',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(c),
      home: AppGate(
        authService: authService,
        firebaseEnabled: firebaseEnabled,
      ),
    );
  }

  static ThemeData _buildTheme(AppThemeData c) {
    final base = c.isLightTheme ? ThemeData.light() : ThemeData.dark();

    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.surface,
      cardColor: c.surface,

      colorScheme: (c.isLightTheme ? ColorScheme.light : ColorScheme.dark)(
        primary:          c.accent,
        onPrimary:        c.bg,
        secondary:        c.accentGreen,
        onSecondary:      c.bg,
        surface:          c.surface,
        onSurface:        c.textLight,
        error:            c.error,
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
        systemOverlayStyle: c.isLightTheme
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
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
        fillColor: c.surface,
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
        errorStyle: GoogleFonts.sourceCodePro(color: c.error, fontSize: 11),
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