import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'automata_screen.dart';
import 'game_data.dart';
import 'game_level.dart' show kLayerConstraintErrors;
import 'level_select_screen.dart';
import 'login_screen.dart';
import 'persistence.dart';
import 'study_mode_screen.dart';
import 'widgets/app_theme.dart';

export 'automata_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catches malformed kAllLevels entries (see game_level.dart —
  // LayerConstraintValidator) as early as possible: tutorial levels sharing
  // a layer with something else, bosses mixed with regular levels, boss
  // layers with >2 bosses, or normal layers with >4 levels. This is an
  // assert (debug-only, stripped from release builds) so it costs nothing
  // in production, but it means a bad level definition fails loudly the
  // first time a contributor runs the app in debug mode instead of quietly
  // shipping a broken level-select layout.
  assert(() {
    final errors = kLayerConstraintErrors;
    if (errors.isNotEmpty) {
      throw StateError('Layer constraint violations:\n${errors.join('\n')}');
    }
    return true;
  }());

  final themeNotifier = await AppThemeNotifier.load();

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
      theme: buildMaterialTheme(c),
      home: AppGate(
        authService: authService,
        firebaseEnabled: firebaseEnabled,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AppGate — post-launch router. Handles auth-gating (waits for AuthService,
//  falls back to LoginScreen), lazily opens the session/progress stores once
//  signed in, then switches between Sandbox / Game / Study mode screens.
//  Sole consumer is MyApp above, so it lives here rather than its own file.
// ─────────────────────────────────────────────────────────────────────────────

enum _AppMode { none, sandbox, game, study }

class AppGate extends StatefulWidget {
  const AppGate({
    super.key,
    required this.authService,
    required this.firebaseEnabled,
  });

  final AuthService authService;
  final bool firebaseEnabled;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _authenticated = false;
  _AppMode _mode = _AppMode.none;
  AutomataSessionStore? _sessionStore;
  GameProgressStore? _progressStore;
  bool _loadingStores = false;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    await widget.authService.init();
    if (!mounted) return;
    setState(() {
      _authenticated = widget.authService.isSignedIn || widget.authService.isGuest;
    });
    if (_authenticated) await _initStores();
  }

  Future<void> _initStores() async {
    setState(() => _loadingStores = true);
    final session = widget.authService.isGuest
        ? await LocalSessionStore.open()
        : FirebaseSessionStore();
    final progress = await GameProgressStore.open();
    if (!mounted) return;
    setState(() {
      _sessionStore = session;
      _progressStore = progress;
      _loadingStores = false;
    });
  }

  Future<void> _handleAuthenticated() async {
    setState(() => _authenticated = true);
    await _initStores();
  }

  Future<void> _handleSignOut() async {
    await widget.authService.signOut();
    if (!mounted) return;
    setState(() {
      _authenticated = false;
      _mode = _AppMode.none;
      _sessionStore = null;
      _progressStore = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_authenticated) {
      return LoginScreen(
        authService: widget.authService,
        firebaseEnabled: widget.firebaseEnabled,
        onAuthenticated: _handleAuthenticated,
      );
    }

    if (_loadingStores || _sessionStore == null || _progressStore == null) {
      return Scaffold(
        backgroundColor: context.watch<AppThemeNotifier>().bg,
        body: Center(
          child: CircularProgressIndicator(
            color: context.watch<AppThemeNotifier>().accent,
          ),
        ),
      );
    }

    switch (_mode) {
      case _AppMode.none:
        return ModeSelectScreen(
          onSandbox: () => setState(() => _mode = _AppMode.sandbox),
          onGame: () => setState(() => _mode = _AppMode.game),
          onStudy: () => setState(() => _mode = _AppMode.study),
          onSignOut: _handleSignOut,
          isGuest: widget.authService.isGuest,
          progressStore: _progressStore!,
        );
      case _AppMode.sandbox:
        return AutomataScreen(
          sessionStore: _sessionStore!,
          isGuest: widget.authService.isGuest,
          userEmail: widget.authService.user?.email,
          onSignOut: _handleSignOut,
          onGoToGame: () => setState(() => _mode = _AppMode.game),
        );
      case _AppMode.study:
        return StudyModeScreen(
          progressStore: _progressStore!,
          onGoToSandbox: () => setState(() => _mode = _AppMode.sandbox),
          onGoToStudy: () => setState(() => _mode = _AppMode.study),
        );
      case _AppMode.game:
        return LevelSelectScreen(
          progressStore: _progressStore!,
          onGoToSandbox: () => setState(() => _mode = _AppMode.sandbox),
          onGoToStudy: () => setState(() => _mode = _AppMode.study),
        );
    }
  }
}