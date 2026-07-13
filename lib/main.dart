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

// Re-exported so other files can `import 'main.dart'` and get
// AutomataScreen (and whatever else automata_screen.dart exports)
// transitively, without needing to know its actual file path. Mostly a
// convenience for tests / tooling that import the app's entry point.
export 'automata_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  main.dart
//
//  App entry point. Responsibilities, in order:
//    1. Fail fast on malformed level data (kLayerConstraintErrors) before
//       any UI is shown.
//    2. Load the persisted theme.
//    3. Configure the OS status/navigation bar chrome to match that theme.
//    4. Initialize Firebase (optional — app still runs without it).
//    5. Build the AuthService and hand off to MyApp/AppGate, which own all
//       further navigation between Login -> Sandbox / Game / Study modes.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  // Required before calling any platform-channel APIs (Firebase, System
  // Chrome, SharedPreferences via AppThemeNotifier.load(), etc.) when
  // running ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Enforced in all builds so malformed level definitions cannot ship with a
  // broken level-select layout (previously this lived inside assert() and was
  // stripped from release builds).
  //
  // kLayerConstraintErrors is presumably a computed (not cached) top-level
  // getter/const in game_level.dart that validates the entire level graph
  // (e.g. checks that every level's declared "layer" is consistent with its
  // unlock-rule prerequisites) at load time. Failing this hard-throws and
  // therefore crashes app startup entirely — deliberate "fail loudly in
  // every build, including release" behavior per the comment, trading a
  // hard crash for the alternative of silently shipping a broken level
  // select screen.
  final layerErrors = kLayerConstraintErrors;
  if (layerErrors.isNotEmpty) {
    throw StateError('Layer constraint violations:\n${layerErrors.join('\n')}');
  }

  // Loads the user's previously-saved theme (light/dark/accent color, etc.)
  // from local storage. Awaited so the very first frame already renders in
  // the correct theme instead of flashing a default theme first.
  final themeNotifier = await AppThemeNotifier.load();

  // Paint the OS status bar / navigation bar to match the loaded theme
  // *before* the first frame, so there's no visible mismatch between the
  // app's background color and the system chrome around it on startup.
  // This mirrors (and is duplicated by) the SystemChrome call inside
  // MyApp.build() below — see the note over there about why both exist.
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: themeNotifier.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Firebase is optional: DefaultFirebaseOptions.isConfigured presumably
  // checks whether platform-specific Firebase config (google-services.json /
  // GoogleService-Info.plist equivalents baked into DefaultFirebaseOptions)
  // is actually present for this build, so the app can still be built and
  // run (in guest/local-only mode) without a Firebase project wired up.
  var firebaseEnabled = false;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseEnabled = true;
    } catch (e) {
      // Firebase failures (bad config, no network reaching the Firebase
      // backend at init time, etc.) are swallowed here rather than
      // rethrown — the app falls back to firebaseEnabled = false and
      // presumably degrades to guest/local-only auth. Only a debug-console
      // breadcrumb is left behind, so a real production failure here would
      // be invisible to users and easy to miss in release builds (debugPrint
      // is a no-op in release/profile unless a debugger's attached... in
      // practice `debugPrint` DOES still print in release; it's `debugPrint`
      // itself that can be overridden to silence, not stripped by default —
      // but there's still no user-facing signal that cloud sync/sign-in
      // won't work this session).
      debugPrint('Firebase initialization failed: $e');
    }
  }

  // AuthService is constructed with firebaseEnabled baked in up front so it
  // knows, for the lifetime of the app, whether Firebase-backed sign-in
  // (as opposed to guest mode) is even an option to offer.
  final authService = AuthService(firebaseEnabled: firebaseEnabled);

  runApp(
    // .value(...) (rather than the ChangeNotifierProvider(create: ...)
    // constructor) is used because themeNotifier was already constructed
    // above via the async AppThemeNotifier.load() — Provider's `.value`
    // constructor hands an already-built instance to the tree instead of
    // asking Provider to construct (and own the disposal of) one lazily.
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
    // context.watch subscribes MyApp to AppThemeNotifier, so MyApp (and
    // everything under it, since MaterialApp's `theme` is rebuilt too)
    // rebuilds any time the user changes the theme at runtime (e.g. toggles
    // light/dark from a settings screen elsewhere in the app).
    final themeNotifier = context.watch<AppThemeNotifier>();
    final c = themeNotifier.data;
    final light = c.isLightTheme;

    // Re-applies system chrome styling on every MyApp rebuild — i.e. every
    // time the theme changes at runtime, not just at startup. This is
    // effectively a duplicate of the SystemChrome call in main() above:
    // that one paints the correct chrome for the very first frame (before
    // MyApp has even been built once), and this one keeps it in sync for
    // every theme change afterward. Calling SystemChrome.setSystemUIOverlayStyle
    // as a *side effect inside build()* is slightly unconventional (build
    // methods are nominally supposed to be pure functions of state), but is
    // a common and harmless pattern for this specific platform-channel call
    // since it doesn't itself trigger a rebuild.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: c.bg,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
    return MaterialApp(
      title: 'Automata Designer',
      // Suppresses the little red-black "DEBUG" ribbon Flutter normally
      // draws in the top-right corner during debug builds — presumably
      // because it visually clashes with / obscures the app's own UI
      // chrome during development screenshots or demos.
      debugShowCheckedModeBanner: false,
      theme: buildMaterialTheme(c),
      // AppGate (below) is the actual router; MyApp itself only owns
      // top-level MaterialApp config (title, theme, debug banner).
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

/// The four top-level "screens" AppGate can be showing once a user is
/// authenticated. `none` is the mode-select landing screen; the other three
/// correspond 1:1 with the three main app experiences.
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
  // Whether the user has successfully authenticated (either a real
  // Firebase account, or has chosen "continue as guest" — see
  // _initializeAuth below, both count as "authenticated" for gating
  // purposes).
  bool _authenticated = false;

  // Which top-level screen is showing, once authenticated. Starts at
  // `none` (mode-select) every time the app launches / a user signs back
  // in — the app does not remember which mode you were last in across
  // sessions.
  _AppMode _mode = _AppMode.none;

  // These two stores are opened lazily (only once authenticated, since
  // which concrete store to use — local vs Firebase — depends on whether
  // the user is a guest) and are shared by reference with every child
  // screen that needs them (AutomataScreen, StudyModeScreen,
  // LevelSelectScreen all receive the *same* instances).
  AutomataSessionStore? _sessionStore;
  GameProgressStore? _progressStore;

  // True while _initStores() is running. Distinct from checking
  // `_sessionStore == null` alone so the loading spinner branch in build()
  // has an explicit flag rather than relying purely on null-checks (though
  // in practice both conditions are checked together — see build() below).
  bool _loadingStores = false;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  /// Waits for AuthService's own async init (e.g. restoring a previous
  /// Firebase session from disk / checking cached guest status), then
  /// decides whether the user is already authenticated from a prior
  /// session. If so, proceeds straight to opening the data stores without
  /// requiring the user to interact with LoginScreen at all.
  Future<void> _initializeAuth() async {
    await widget.authService.init();
    // `mounted` guard: this State could have been disposed while the
    // `await` above was in flight (e.g. hot-reload during development, or
    // — much less likely for the app's actual root widget — some other
    // teardown). Calling setState() on an unmounted State throws, hence
    // the guard.
    if (!mounted) return;
    setState(() {
      _authenticated = widget.authService.isSignedIn || widget.authService.isGuest;
    });
    if (_authenticated) await _initStores();
  }

  /// Opens the session store (local-file-backed for guests, Firebase-backed
  /// for signed-in users) and the game progress store. Called both from
  /// _initializeAuth (silent re-auth on cold start) and from
  /// _handleAuthenticated (explicit sign-in via LoginScreen).
  Future<void> _initStores() async {
    setState(() => _loadingStores = true);
    final session = widget.authService.isGuest
        ? await LocalSessionStore.open()
        // Note the asymmetry: LocalSessionStore.open() is awaited (implying
        // it does real async I/O — e.g. opening a local database/file —
        // before it's ready to use), whereas `FirebaseSessionStore()` is a
        // bare, un-awaited constructor call. This is presumably fine if
        // FirebaseSessionStore defers all of its actual async work
        // (reads/writes) to its individual methods rather than needing
        // anything ready at construction time — but it's worth confirming
        // that assumption holds (see persistence.dart) rather than taking
        // it for granted, since the two branches of this ternary otherwise
        // look like they should be symmetric.
        : FirebaseSessionStore();
    final progress = await GameProgressStore.open();
    if (!mounted) return;
    setState(() {
      _sessionStore = session;
      _progressStore = progress;
      _loadingStores = false;
    });
  }

  /// Callback passed down to LoginScreen; invoked once the user has
  /// completed sign-in (or chosen guest mode) there.
  Future<void> _handleAuthenticated() async {
    setState(() => _authenticated = true);
    await _initStores();
  }

  /// Signs out and resets AppGate back to its pre-auth state, dropping all
  /// references to the previous session's stores.
  ///
  /// NOTE (possible resource leak): `_sessionStore` / `_progressStore` are
  /// simply overwritten with `null` here rather than explicitly closed /
  /// disposed first. If either store type holds open resources (a
  /// SharedPreferences instance is fine to just drop, but a
  /// FirebaseSessionStore might hold open stream subscriptions / listeners
  /// against Firestore, or LocalSessionStore might hold an open file/db
  /// handle) those wouldn't be released until garbage collected rather than
  /// deterministically on sign-out. Worth confirming persistence.dart's
  /// store classes don't need an explicit `dispose()`/`close()` call.
  // RESOLVED (re: the leak note above): checked persistence.dart —
  // LocalSessionStore wraps SharedPreferences (a process-wide singleton with
  // no per-instance handle to release) and FirebaseSessionStore wraps the
  // FirebaseFirestore/FirebaseAuth singletons directly with no listeners/
  // subscriptions of its own. Neither type holds anything that needs
  // explicit disposal, so overwriting these fields with null on sign-out is
  // safe as written. Flagging as resolved rather than deleting the original
  // note so future changes to those store classes (e.g. adding a live
  // Firestore snapshot listener) know to revisit this assumption.
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
    // Gate 1: not authenticated at all -> show the login screen and wait
    // for onAuthenticated to fire.
    if (!_authenticated) {
      return LoginScreen(
        authService: widget.authService,
        firebaseEnabled: widget.firebaseEnabled,
        onAuthenticated: _handleAuthenticated,
      );
    }

    // Gate 2: authenticated, but the session/progress stores aren't ready
    // yet (either _initStores() is still running, or — belt and suspenders
    // — one of the store fields just happens to still be null for any
    // reason). Every screen past this point assumes non-null stores, so
    // this check has to cover both the explicit flag and the null values
    // to be safe against ordering bugs.
    if (_loadingStores || _sessionStore == null || _progressStore == null) {
      return Scaffold(
        backgroundColor: context.watch<AppThemeNotifier>().bg,
        body: Center(
          child: CircularProgressIndicator(
            // Two separate context.watch<AppThemeNotifier>() calls in this
            // one build — harmless (Provider de-dupes the lookup / the
            // second call is cheap), just slightly redundant; could be
            // hoisted into a single local `final theme = ...` at the top of
            // build() the way other files in this codebase do.
            color: context.watch<AppThemeNotifier>().accent,
          ),
        ),
      );
    }

    // Gate 3: fully ready — route to whichever top-level mode is active.
    // Every branch wires up all three `onGoTo*` callbacks so any screen can
    // jump directly to any other top-level mode (plus onGoToMenu, back to
    // `none`) without needing to pop back through `none` first.
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
          onGoToStudy: () => setState(() => _mode = _AppMode.study),
          onGoToMenu: () => setState(() => _mode = _AppMode.none),
        );
      case _AppMode.study:
        return StudyModeScreen(
          progressStore: _progressStore!,
          onGoToSandbox: () => setState(() => _mode = _AppMode.sandbox),
          onGoToStudy: () => setState(() => _mode = _AppMode.study),
          onGoToGame: () => setState(() => _mode = _AppMode.game),
          onGoToMenu: () => setState(() => _mode = _AppMode.none),
        );
      case _AppMode.game:
        return LevelSelectScreen(
          progressStore: _progressStore!,
          onGoToSandbox: () => setState(() => _mode = _AppMode.sandbox),
          onGoToStudy: () => setState(() => _mode = _AppMode.study),
          onGoToMenu: () => setState(() => _mode = _AppMode.none),
        );
      // No `default` branch: `switch` over an `enum` in Dart is checked for
      // exhaustiveness by the analyzer, so if `_AppMode` ever gains a new
      // value without a corresponding case being added here, this becomes
      // a compile-time (analysis) error rather than a silent runtime gap —
      // a good defensive property of using an enum + exhaustive switch for
      // this kind of router.
    }
  }
}