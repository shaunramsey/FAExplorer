// ─────────────────────────────────────────────────────────────────────────────
//  persistence.dart
//
//  All account / storage plumbing for the app, in one place:
//    1. Firebase configuration      (DefaultFirebaseOptions)
//    2. Authentication              (AuthService, AuthMode)
//    3. Local key/value storage     (PreferencesStore, SavedExport, PersistedSnapshot)
//    4. Workspace session storage   (AutomataSessionStore + Local/Firebase impls)
//
//  Game progress lives separately in game_data.dart; level content lives in
//  game_level.dart.
// ─────────────────────────────────────────────────────────────────────────────

// dart:convert supplies jsonEncode/jsonDecode, used to serialize SavedExport
// lists and the additionalTapeInputs list into a single String for storage
// in SharedPreferences (which only stores primitives, not nested objects).
import 'dart:convert';

// Firestore client — only exercised by FirebaseSessionStore (section 4) for
// reading/writing the per-user workspace document.
import 'package:cloud_firestore/cloud_firestore.dart';
// Firebase's auth client — provides FirebaseAuth (sign in/up/out, current
// user) and the User type used throughout AuthService (section 2).
import 'package:firebase_auth/firebase_auth.dart';
// Only FirebaseOptions is needed from firebase_core — the per-platform
// config bundle handed to Firebase.initializeApp() elsewhere in the app.
// `show` keeps the import narrow so nothing else from this package leaks in.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
// Platform-detection helpers used only inside DefaultFirebaseOptions to pick
// the right FirebaseOptions constant for the running platform:
//   kIsWeb              - true when compiled to run in a browser
//   defaultTargetPlatform - enum value (android/iOS/macOS/windows/...) for
//                            native builds
//   TargetPlatform        - the enum type itself, used in the switch below
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
// SharedPreferences — the underlying local key/value store wrapped by
// PreferencesStore (section 3) and used directly by AuthService for
// persisting which auth mode (guest/account) is active.
import 'package:shared_preferences/shared_preferences.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  1. FIREBASE CONFIGURATION
// ═════════════════════════════════════════════════════════════════════════════

/// Set to true after running `flutterfire configure` and updating the values below.
// Global on/off switch for all Firebase-backed behaviour in the app
// (FirebaseAuth account sign-in, FirebaseSessionStore). When false,
// DefaultFirebaseOptions.currentPlatform throws instead of returning
// options, and callers elsewhere in the app are expected to check
// DefaultFirebaseOptions.isConfigured before touching Firebase at all.
const bool kFirebaseConfigured = true;

/// Firebase configuration for each platform.
///
/// Run from the project root:
///   dart pub global activate flutterfire_cli
///   flutterfire configure
/// Then set [kFirebaseConfigured] to true and paste the generated values here
/// (or replace this file with the generated `firebase_options.dart`).
// Mirrors the shape of the file flutterfire_cli normally generates
// (firebase_options.dart), just hand-rolled here so it lives alongside the
// rest of the app's persistence code instead of as a separate generated file.
class DefaultFirebaseOptions {
  // Simple passthrough so callers can check configuration status without
  // reaching for the private constant directly, e.g.
  // `if (DefaultFirebaseOptions.isConfigured) { ... }`.
  static bool get isConfigured => kFirebaseConfigured;

  // The single entry point callers use (typically passed straight into
  // Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)).
  // Resolves to the correct per-platform FirebaseOptions constant below.
  static FirebaseOptions get currentPlatform {
    // Fail loudly and immediately if Firebase hasn't actually been set up —
    // better than silently returning placeholder "YOUR_..." credentials
    // that would fail obscurely later inside the Firebase SDK.
    if (!isConfigured) {
      throw StateError(
        'Firebase is not configured. Set kFirebaseConfigured to true in '
        'lib/persistence.dart after running flutterfire configure.',
      );
    }
    // Web has its own branch outside the switch because kIsWeb is a
    // separate flag from defaultTargetPlatform — a Flutter web build still
    // reports an underlying TargetPlatform (e.g. android/iOS emulation of
    // the browser's OS), so checking kIsWeb first avoids misrouting web
    // builds into a native-platform case below.
    if (kIsWeb) return web;
    // Native platforms: dispatch on the OS Flutter detects at runtime.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      // Any platform without a dedicated FirebaseOptions constant below
      // (e.g. Linux, Fuchsia) — rather than guessing, fail explicitly so
      // it's obvious Firebase needs platform-specific setup there too.
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Real, working credentials for the web target — these are the actual
  // values pasted in after running `flutterfire configure` for this
  // project (project id: toc-fa-ramsey). Firebase web API keys are not
  // secret in the way a server API key would be; they identify the
  // project, with access still governed by Firebase security rules.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCqTaOQbIk2Jf6MKnClw7RAfNAsmtWMH_Y',
    appId: '1:583188706903:web:a8c8dff725913ce3019512',
    messagingSenderId: '583188706903',
    projectId: 'toc-fa-ramsey',
    authDomain: 'toc-fa-ramsey.firebaseapp.com',
    storageBucket: 'toc-fa-ramsey.firebasestorage.app',
    measurementId: 'G-P1H2HB3M85',
  );

  // Placeholder credentials — android/ios/macos/windows have never had
  // `flutterfire configure` run for them, so these are still the
  // "YOUR_..." template values. Any attempt to actually run the app on
  // these platforms with kFirebaseConfigured = true would fail inside the
  // Firebase SDK when it rejects these fake values.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  // iOS additionally requires iosBundleId (the app's bundle identifier),
  // which the android block above doesn't need.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.automataDesigner',
  );

  // macOS shares iOS's Apple-platform shape (also needs iosBundleId, since
  // macOS Firebase config reuses the same bundle-id field as iOS).
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: 'YOUR_MACOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.automataDesigner',
  );

  // Windows, like android, has no bundle-id-style field.
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'YOUR_WINDOWS_API_KEY',
    appId: 'YOUR_WINDOWS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  2. AUTHENTICATION
// ═════════════════════════════════════════════════════════════════════════════

// The two ways a session can be "logged in" from the app's point of view:
// browsing without an account at all, or authenticated via Firebase.
enum AuthMode { guest, account }

// `abstract final class` with only static members = a namespaced constant
// holder that can never be instantiated or subclassed (Dart's idiom for a
// lightweight "keys" bag, avoiding a bare top-level `const String` that
// would pollute the library's namespace).
abstract final class AuthPreferenceKeys {
  // The single SharedPreferences key this file uses to remember which
  // AuthMode was last active, so app restarts can restore it (see
  // AuthService.init below).
  static const authMode = 'auth_mode';
}

// Owns the app's current authentication state (guest vs signed-in account)
// and is the single place that talks to FirebaseAuth + persists the choice
// so it survives app restarts.
class AuthService {
  AuthService({
    required this.firebaseEnabled,
    FirebaseAuth? auth,
    SharedPreferences? prefs,
  })  // Only actually construct/require a FirebaseAuth instance when
        // Firebase is enabled for this build; otherwise _auth stays null so
        // every Firebase-touching code path below can branch on it safely.
        // `auth ?? FirebaseAuth.instance` lets tests inject a fake
        // FirebaseAuth while production code just uses the real singleton.
      : _auth = firebaseEnabled ? (auth ?? FirebaseAuth.instance) : null,
        // Similarly, allow tests to inject a SharedPreferences instance;
        // production code leaves this null and lazily fetches the real
        // instance inside init() (SharedPreferences.getInstance() is async,
        // so it can't be done directly in this sync constructor).
        _prefs = prefs;

  // Whether this build/session has Firebase configured at all — gates
  // every method below that would otherwise touch _auth.
  final bool firebaseEnabled;
  // Nullable: null whenever firebaseEnabled is false, since there's nothing
  // to construct a FirebaseAuth instance from/for in that case.
  final FirebaseAuth? _auth;
  // Not `final` — unlike _auth, this can be assigned later inside init()
  // via `_prefs ??= ...` once the async SharedPreferences.getInstance()
  // call resolves.
  SharedPreferences? _prefs;

  // In-memory view of the current session; null before init() runs or
  // after signOut(). Kept alongside (not derived purely from) SharedPreferences
  // so reads of `mode`/`user` don't need to be async.
  AuthMode? _mode;
  User? _user;

  // Read-only public views of the private in-memory state above.
  AuthMode? get mode => _mode;
  User? get user => _user;
  // Convenience booleans callers use for UI branching instead of comparing
  // `mode` directly.
  bool get isGuest => _mode == AuthMode.guest;
  // Signed in requires BOTH that the stored mode says "account" AND that a
  // concrete User object is actually present — protects against a stale
  // "account" mode surviving without a matching Firebase user (see the
  // stale-account handling inside init() below).
  bool get isSignedIn => _mode == AuthMode.account && _user != null;

  // Called once at app startup to restore whatever auth state was active
  // last time the app ran. See the BUG note on continueAsGuest() below for
  // an important caveat about *when* this is safe to rely on having
  // finished.
  Future<void> init() async {
    // Lazily fetch the real SharedPreferences instance the first time
    // init() runs, unless a test already injected one via the constructor
    // (in which case `??=` is a no-op).
    _prefs ??= await SharedPreferences.getInstance();
    // Read back whichever AuthMode.name string ('guest' or 'account') was
    // written by a previous continueAsGuest()/signIn()/signUp() call, if
    // any (null if nothing was ever stored, e.g. first launch).
    final stored = _prefs!.getString(AuthPreferenceKeys.authMode);

    // Guest mode requires no further verification — there's no external
    // system of record to check it against, so restore it immediately.
    if (stored == AuthMode.guest.name) {
      _mode = AuthMode.guest;
      return;
    }

    // Stored mode claims "account" — but only trust that if Firebase is
    // actually enabled/available AND FirebaseAuth still has a live current
    // user (e.g. its own persisted session). This guards against a stale
    // preference outliving an external Firebase sign-out.
    if (stored == AuthMode.account.name && firebaseEnabled && _auth != null) {
      _user = _auth.currentUser;
      if (_user != null) {
        _mode = AuthMode.account;
        return;
      }
      // Stored "account" mode but Firebase has no current user (e.g. the
      // user was signed out of Firebase by some other means, or the token
      // expired) — clean up the now-stale preference rather than leaving
      // it around to cause the same dead-end check on every future launch.
      await _prefs!.remove(AuthPreferenceKeys.authMode);
    }

    // Fallback for every other case: nothing was stored, Firebase isn't
    // enabled, or the stale-account cleanup above just ran. Leaves the
    // user logged out / at the login screen.
    _mode = null;
    _user = null;
  }

  // BUG (race condition): _prefs is only guaranteed non-null *after* init()
  // has completed (it's assigned via `_prefs ??= await SharedPreferences
  // .getInstance()` inside init()). But init() is kicked off from
  // AppGate._initializeAuth() WITHOUT gating the UI on it — LoginScreen is
  // shown immediately on the very first frame (_authenticated starts false)
  // and initState() calls _initializeAuth() without awaiting before the
  // first build(). If the user taps "Continue as guest" (or Sign in/Sign
  // up below) fast enough that this method runs before init()'s
  // `SharedPreferences.getInstance()` future resolves, `_prefs` is still
  // null here. `_prefs?.setString(...)` then silently no-ops (null-aware
  // operator swallows it — no exception, no signal of any kind) instead of
  // persisting the auth mode. In-memory state (_mode/_user) still updates
  // correctly for the current session, so the bug is invisible until the
  // next cold start: init() reads AuthPreferenceKeys.authMode, finds
  // nothing was ever written, and the user is dropped back to the login
  // screen despite having "signed in" successfully last time. Same failure
  // mode applies to signIn(), signUp(), and signOut() below, all of which
  // use the same `_prefs?.` pattern.
  Future<void> continueAsGuest() async {
    final auth = _auth;
    // If a Firebase user happens to be signed in already (e.g. the user
    // backed out of a sign-in flow partway, or switched from a previous
    // account session), sign them out of Firebase first so "guest" mode
    // genuinely has no authenticated user attached.
    if (auth != null && auth.currentUser != null) {
      await auth.signOut();
    }
    _mode = AuthMode.guest;
    _user = null;
    // Persist the choice so init() restores guest mode on next launch. See
    // BUG note above: this can silently no-op if _prefs isn't ready yet.
    await _prefs?.setString(AuthPreferenceKeys.authMode, AuthMode.guest.name);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    // Throws a clear StateError if Firebase isn't enabled/configured,
    // rather than letting a null-check failure surface deeper in the
    // FirebaseAuth SDK.
    final auth = _requireFirebase();
    // `email.trim()` guards against leading/trailing whitespace a user
    // might paste in; password is intentionally NOT trimmed since
    // whitespace could be a deliberate part of the password.
    final cred = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _user = cred.user;
    _mode = AuthMode.account;
    // Same persistence caveat as continueAsGuest() above.
    await _prefs?.setString(AuthPreferenceKeys.authMode, AuthMode.account.name);
  }

  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    final auth = _requireFirebase();
    // Mirrors signIn() above but creates a brand-new Firebase account
    // instead of authenticating an existing one.
    final cred = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _user = cred.user;
    _mode = AuthMode.account;
    await _prefs?.setString(AuthPreferenceKeys.authMode, AuthMode.account.name);
  }

  Future<void> signOut() async {
    // Only bother calling Firebase's signOut() if there's actually a
    // Firebase-backed user to sign out of (guests were never signed in to
    // begin with, so calling this unconditionally would be a harmless but
    // pointless network call).
    if (_auth != null && _user != null) {
      await _auth.signOut();
    }
    _mode = null;
    _user = null;
    // Clear the persisted mode entirely (rather than writing some "signed
    // out" sentinel value) so init() on next launch finds nothing stored
    // and falls through to the logged-out default.
    await _prefs?.remove(AuthPreferenceKeys.authMode);
  }

  // Shared guard used by signIn()/signUp(): returns a usable FirebaseAuth
  // instance or throws, so callers don't each have to repeat the
  // null/enabled check.
  FirebaseAuth _requireFirebase() {
    final auth = _auth;
    if (!firebaseEnabled || auth == null) {
      throw StateError(
        'Firebase is not configured. Use Continue as Guest or run flutterfire configure.',
      );
    }
    return auth;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  3. LOCAL PREFERENCES  (sandbox workspace: graph DSL, exports, sim/UI state)
// ═════════════════════════════════════════════════════════════════════════════

// Distinguishes a normal automaton/graph export from a "black box" export
// (a component whose internals are hidden, described only in prose via
// blackBoxDescription below).
enum SavedExportType { graph, blackBox }

// A single user-saved export from the workspace (e.g. a named DFA/PDA/TM
// definition the user chose to keep). Mutable (non-final fields) so callers
// can rename/edit an export in place rather than always constructing a new
// instance.
class SavedExport {
  String name;
  // The exported automaton, encoded in the app's own DSL text format.
  String dsl;
  SavedExportType type;
  // Only meaningful when type == SavedExportType.blackBox; empty string
  // otherwise. Free-text description of what the hidden component does.
  String blackBoxDescription;

  SavedExport({
    required this.name,
    required this.dsl,
    // Defaults to a plain graph export unless the caller says otherwise.
    this.type = SavedExportType.graph,
    this.blackBoxDescription = '',
  });

  // Convenience getter mirroring the isSignedIn-style booleans in
  // AuthService above — lets callers write `export.isBlackBox` instead of
  // `export.type == SavedExportType.blackBox`.
  bool get isBlackBox => type == SavedExportType.blackBox;
}

/// Keys used in [SharedPreferences] for FAExplorer session data.
// Same "abstract final class as a namespaced constants bag" pattern as
// AuthPreferenceKeys above, this time for all the sandbox-workspace keys.
abstract final class PreferenceKeys {
  static const graphDsl = 'graph_dsl';
  static const savedExports = 'saved_exports';
  static const showSimulator = 'show_simulator';
  static const showHelpOverlay = 'show_help_overlay';
  static const simInput = 'sim_input';
  static const simStep = 'sim_step';
  /// JSON-encoded list of strings: content for tapes 2, 3, … (index 0 = tape 2).
  static const additionalTapeInputs = 'additional_tape_inputs';
}

// Immutable snapshot of everything PreferencesStore/AutomataSessionStore
// load and save — the single value object both the local (SharedPreferences)
// and remote (Firestore) backends read into and write out of, so the rest
// of the app doesn't need to know or care which backend is active.
class PersistedSnapshot {
  // Nullable (unlike the other fields, which have concrete defaults) so
  // callers can distinguish "no graph was ever saved" (null) from "an
  // empty graph was explicitly saved" if that distinction ever matters;
  // in practice see PreferencesStore.saveGraphDsl below, which currently
  // collapses blank/whitespace-only DSL to "remove the key" (i.e. null on
  // next load).
  final String? graphDsl;
  final List<SavedExport> savedExports;
  final bool showSimulator;
  final bool showHelpOverlay;
  final String simInput;
  // -1 is the sentinel for "no simulation step in progress" (as opposed to
  // 0, which is a legitimate first step).
  final int simStep;
  /// Content for tapes 2, 3, … (index 0 = tape 2, index 1 = tape 3, …).
  /// Each string is the raw user input for that tape, tokenised the same way
  /// as [simInput].  Empty list means all extra tapes start blank.
  final List<String> additionalTapeInputs;

  // All fields have sensible empty/default values, so an empty
  // `PersistedSnapshot()` represents "nothing saved yet" and is used as the
  // fallback return value throughout this file whenever a load fails or
  // finds nothing.
  const PersistedSnapshot({
    this.graphDsl,
    this.savedExports = const [],
    this.showSimulator = true,
    this.showHelpOverlay = false,
    this.simInput = '',
    this.simStep = -1,
    this.additionalTapeInputs = const [],
  });
}

// Thin, synchronous-where-possible wrapper around SharedPreferences for the
// sandbox workspace's own data (as opposed to AuthService's auth-mode key,
// which is a separate concern even though it uses the same underlying
// SharedPreferences storage).
class PreferencesStore {
  PreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  // Async factory (SharedPreferences.getInstance() is itself async) mirrors
  // AuthService's constructor-injection pattern, but here _prefs is
  // required and final rather than lazily filled in later — this store is
  // only ever constructed once the instance is already available.
  static Future<PreferencesStore> open() async {
    return PreferencesStore(await SharedPreferences.getInstance());
  }

  // Synchronous — SharedPreferences reads are synchronous once the
  // instance exists, so unlike AutomataSessionStore.load() below this
  // doesn't need to be a Future.
  PersistedSnapshot load() {
    // Fetch the raw JSON string once so both the null-check and the decode
    // call below share the same read.
    final exportsJson = _prefs.getString(PreferenceKeys.savedExports);
    return PersistedSnapshot(
      // Passed through as-is (nullable) — see the PersistedSnapshot.graphDsl
      // doc comment above for why null is preserved rather than defaulted
      // to ''.
      graphDsl: _prefs.getString(PreferenceKeys.graphDsl),
      savedExports: _decodeExports(exportsJson),
      // getBool returns null if the key was never set (e.g. first launch),
      // so `?? true`/`?? false` supply the PersistedSnapshot defaults.
      showSimulator: _prefs.getBool(PreferenceKeys.showSimulator) ?? true,
      showHelpOverlay: _prefs.getBool(PreferenceKeys.showHelpOverlay) ?? false,
      simInput: _prefs.getString(PreferenceKeys.simInput) ?? '',
      // -1 matches the PersistedSnapshot.simStep sentinel for "no step in
      // progress".
      simStep: _prefs.getInt(PreferenceKeys.simStep) ?? -1,
      additionalTapeInputs: _decodeTapeInputs(
        _prefs.getString(PreferenceKeys.additionalTapeInputs),
      ),
    );
  }

  Future<void> saveGraphDsl(String dsl) async {
    // Treat whitespace-only DSL the same as genuinely empty — removing the
    // key entirely (rather than storing an empty/blank string) keeps
    // "nothing saved" detectable via the null check in load() above and
    // avoids storing meaningless whitespace.
    if (dsl.trim().isEmpty) {
      await _prefs.remove(PreferenceKeys.graphDsl);
    } else {
      await _prefs.setString(PreferenceKeys.graphDsl, dsl);
    }
  }

  Future<void> saveSavedExports(List<SavedExport> exports) async {
    // SharedPreferences has no native support for lists of objects, so the
    // whole list is serialized to a single JSON string: each SavedExport
    // becomes a plain Map with primitive values, then the outer List<Map>
    // is JSON-encoded as one blob.
    final encoded = jsonEncode(
      exports
          .map(
            (e) => {
              'name': e.name,
              'dsl': e.dsl,
              // Store the enum's *name* string ('graph'/'blackBox') rather
              // than its index, so the encoding survives reordering the
              // enum's declared values in future code changes.
              'type': e.type.name,
              'blackBoxDescription': e.blackBoxDescription,
            },
          )
          .toList(),
    );
    // Unlike saveGraphDsl above, an empty exports list is still written
    // (as the JSON string "[]") rather than removing the key — this method
    // has no equivalent early-return branch.
    await _prefs.setString(PreferenceKeys.savedExports, encoded);
  }

  Future<void> saveUi({
    bool? showSimulator,
    bool? showHelpOverlay,
  }) async {
    // Both parameters are optional and independently nullable so callers
    // can update just one flag without needing to know/pass the other's
    // current value.
    if (showSimulator != null) {
      await _prefs.setBool(PreferenceKeys.showSimulator, showSimulator);
    }
    if (showHelpOverlay != null) {
      await _prefs.setBool(PreferenceKeys.showHelpOverlay, showHelpOverlay);
    }
  }

  Future<void> saveSimulator({
    required String input,
    required int step,
    List<String> additionalTapeInputs = const [],
  }) async {
    // Same "empty means remove the key" treatment as saveGraphDsl above,
    // so a blank tape-1 input doesn't linger as a stored empty string.
    if (input.isEmpty) {
      await _prefs.remove(PreferenceKeys.simInput);
    } else {
      await _prefs.setString(PreferenceKeys.simInput, input);
    }
    // step has no "empty" concept (it's an int, and -1 is itself a
    // meaningful sentinel), so it's always written unconditionally, unlike
    // input above.
    await _prefs.setInt(PreferenceKeys.simStep, step);

    // Persist extra-tape inputs.  Remove the key entirely when all tapes are
    // blank so we don't store unnecessary noise for single-tape machines.
    // `.map((s) => s)` here is a no-op copy (identity map) — it doesn't
    // transform anything, just materializes a fresh List from whatever
    // iterable was passed in.
    final nonEmpty = additionalTapeInputs.map((s) => s).toList();
    // True for both "no extra tapes at all" (empty list -> every() on an
    // empty iterable is vacuously true) and "extra tapes exist but every
    // one of them is an empty string".
    final allBlank = nonEmpty.every((s) => s.isEmpty);
    if (allBlank) {
      await _prefs.remove(PreferenceKeys.additionalTapeInputs);
    } else {
      // Only extra tapes need JSON encoding (a List<String>, unlike the
      // single simInput string above) since SharedPreferences can't store
      // a List directly alongside these other scalar keys.
      await _prefs.setString(
        PreferenceKeys.additionalTapeInputs,
        jsonEncode(nonEmpty),
      );
    }
  }

  Future<void> clearAll() async {
    // Wipes every key this store owns, restoring a fresh/first-launch
    // state. Deliberately does NOT touch AuthPreferenceKeys.authMode —
    // that's AuthService's key, a separate concern (e.g. signing out
    // shouldn't be conflated with clearing the sandbox workspace, and vice
    // versa).
    await _prefs.remove(PreferenceKeys.graphDsl);
    await _prefs.remove(PreferenceKeys.savedExports);
    await _prefs.remove(PreferenceKeys.simInput);
    await _prefs.remove(PreferenceKeys.simStep);
    await _prefs.remove(PreferenceKeys.additionalTapeInputs);
  }

  // Decodes the JSON blob written by saveSavedExports() back into
  // SavedExport objects. Defensive at two nested levels (see the two
  // try/catch blocks) because this reads user-controlled, previously
  // persisted data that could in principle be corrupted (e.g. a crash
  // mid-write, or a future schema change reading an older format).
  static List<SavedExport> _decodeExports(String? raw) {
    // No key stored yet, or stored as an empty string — both mean "no
    // saved exports", not an error.
    if (raw == null || raw.isEmpty) return [];
    try {
      // Outer try/catch: guards the jsonDecode call itself and the cast to
      // List<dynamic> — if `raw` isn't valid JSON, or isn't a JSON array
      // at the top level, this catches it and falls through to returning
      // an empty list below rather than crashing the whole load().
      final list = jsonDecode(raw) as List<dynamic>;
      final result = <SavedExport>[];
      for (final item in list) {
        // Skip (rather than error on) any array entry that isn't even a
        // Map — e.g. if the array somehow contains a stray string or
        // number.
        if (item is! Map) continue;
        try {
          // Inner try/catch: guards each individual entry's field
          // extraction, so ONE corrupt/malformed export doesn't take down
          // every other valid export in the same saved list (see the
          // catch below, which skips just this entry and continues the
          // loop).

          // Strict null checking with proper fallbacks
          final nameRaw = item['name'];
          // toString().trim() handles both "field present but not a
          // String" (e.g. accidentally stored as a number) and stray
          // whitespace; falls back to a generic label if the field is
          // missing entirely.
          final name = (nameRaw != null) ? nameRaw.toString().trim() : 'Export';

          final dslRaw = item['dsl'];
          final dsl = (dslRaw != null) ? dslRaw.toString() : '';

          // ?.toString() short-circuits to null (not a "null" string) if
          // 'type' is absent; ?? '' then supplies a default that won't
          // match either enum name below, landing on SavedExportType.graph
          // via the ternary's false branch.
          final typeStr = item['type']?.toString().trim() ?? '';

          final descRaw = item['blackBoxDescription'];
          final desc = (descRaw != null) ? descRaw.toString() : '';

          result.add(SavedExport(
            name: name,
            dsl: dsl,
            // Only recognizes the exact stored enum-name string; anything
            // else (missing field, typo, future/unknown type value)
            // safely defaults to a plain graph export instead of throwing.
            type: typeStr == SavedExportType.blackBox.name
                ? SavedExportType.blackBox
                : SavedExportType.graph,
            blackBoxDescription: desc,
          ));
        } catch (_) {
          // Skip individual corrupt entries rather than aborting the whole list.
        }
      }
      return result;
    } catch (_) {
      // Whole blob failed to parse as JSON/a List at all — treat it the
      // same as "nothing saved" rather than propagating the exception up
      // into load().
      return [];
    }
  }

  /// Decodes a JSON-encoded list of tape-input strings.
  /// Returns an empty list on any parse error so callers always get a safe value.
  static List<String> _decodeTapeInputs(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      // `item?.toString() ?? ''` tolerates a null entry inside the decoded
      // list (turning it into an empty-string tape rather than crashing or
      // propagating a null into a List<String>).
      return [for (final item in list) item?.toString() ?? ''];
    } catch (_) {
      return [];
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  4. WORKSPACE SESSION STORAGE  (local SharedPreferences vs. Firestore)
// ═════════════════════════════════════════════════════════════════════════════

/// Loads and saves automata workspace data (graph, exports, simulator, UI).
// Common interface so the rest of the app can load/save a workspace without
// caring whether the active backend is local-only (guest mode) or synced to
// Firestore (signed-in account mode) — see LocalSessionStore and
// FirebaseSessionStore below, the two concrete implementations.
abstract class AutomataSessionStore {
  Future<PersistedSnapshot> load();
  Future<void> save(PersistedSnapshot snapshot);
}

// The guest-mode / offline backend: everything routes straight through to
// the SharedPreferences-backed PreferencesStore from section 3.
class LocalSessionStore implements AutomataSessionStore {
  LocalSessionStore(this._prefs);

  final PreferencesStore _prefs;

  // Convenience factory that also opens the underlying PreferencesStore,
  // so callers don't need to sequence two separate async setup calls.
  static Future<LocalSessionStore> open() async {
    return LocalSessionStore(await PreferencesStore.open());
  }

  @override
  // PreferencesStore.load() is itself synchronous, but this override still
  // returns a Future to satisfy the shared AutomataSessionStore interface
  // (which must also accommodate FirebaseSessionStore's genuinely async
  // load() below).
  Future<PersistedSnapshot> load() async => _prefs.load();

  @override
  Future<void> save(PersistedSnapshot snapshot) async {
    // Splits the single PersistedSnapshot back out into PreferencesStore's
    // separate save* calls (the inverse of how load() reassembles them
    // into one object). `graphDsl ?? ''` supplies a value since
    // saveGraphDsl expects a non-nullable String (it does its own
    // trim-to-empty-means-remove check internally).
    await _prefs.saveGraphDsl(snapshot.graphDsl ?? '');
    await _prefs.saveSavedExports(snapshot.savedExports);
    await _prefs.saveUi(
      showSimulator: snapshot.showSimulator,
      showHelpOverlay: snapshot.showHelpOverlay,
    );
    await _prefs.saveSimulator(
      input: snapshot.simInput,
      step: snapshot.simStep,
      additionalTapeInputs: snapshot.additionalTapeInputs,
    );
  }
}

/// Persists workspace data under `users/{uid}/workspace/main` in Firestore.
// The signed-in-account backend: unlike LocalSessionStore, all fields live
// together in a single Firestore document rather than several separate
// SharedPreferences keys.
class FirebaseSessionStore implements AutomataSessionStore {
  FirebaseSessionStore({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  // Same test-injection pattern as AuthService's constructor: allow a
        // fake Firestore/FirebaseAuth to be passed in for tests, defaulting
        // to the real singletons in production. Unlike AuthService's
        // _prefs, both fields here are `final` and always get a concrete
        // (non-null) value immediately — there's no async instance-lookup
        // step comparable to SharedPreferences.getInstance() needed here.
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // Resolves the current user's workspace document reference, or null if
  // nobody is signed in. Recomputed on every access (not cached) so it
  // always reflects whichever user is *currently* signed in, in case the
  // signed-in user changes between calls.
  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    // Fixed path shape: users/{uid}/workspace/main — one workspace
    // document per user, always named "main" (no support for multiple
    // named workspaces per account).
    return _firestore.collection('users').doc(uid).collection('workspace').doc('main');
  }

  @override
  Future<PersistedSnapshot> load() async {
    final doc = _doc;
    // No signed-in user — nothing to load, so return the same "empty"
    // default PersistedSnapshot() used elsewhere in this file for
    // first-launch/no-data states.
    if (doc == null) return const PersistedSnapshot();

    final snap = await doc.get();
    // Document has never been written for this user (e.g. brand-new
    // account) — same empty-default fallback.
    if (!snap.exists) return const PersistedSnapshot();

    final data = snap.data();
    // Defensive: snap.exists true but data() still null shouldn't normally
    // happen, but guarded anyway rather than risking a null-dereference
    // below.
    if (data == null) return const PersistedSnapshot();

    return PersistedSnapshot(
      // Cast rather than toString()-coerce here, unlike
      // PreferencesStore._decodeExports above — Firestore preserves typed
      // fields natively (no JSON-string round-trip needed for scalars), so
      // a straightforward `as String?` is enough.
      graphDsl: data['graphDsl'] as String?,
      savedExports: _decodeExports(data['savedExports']),
      showSimulator: data['showSimulator'] as bool? ?? true,
      showHelpOverlay: data['showHelpOverlay'] as bool? ?? false,
      simInput: data['simInput'] as String? ?? '',
      // Firestore numbers can come back as int or double depending on how
      // they were written, so cast to `num?` first and use `.toInt()`
      // rather than casting directly to `int?` (which could throw if
      // Firestore happens to return a double).
      simStep: (data['simStep'] as num?)?.toInt() ?? -1,
      additionalTapeInputs: _decodeTapeInputs(data['additionalTapeInputs']),
    );
  }

  @override
  Future<void> save(PersistedSnapshot snapshot) async {
    final doc = _doc;
    // No signed-in user to save under — silently do nothing rather than
    // throwing, mirroring how the getter itself just returns null instead
    // of erroring.
    if (doc == null) return;

    await doc.set(
      {
        'graphDsl': snapshot.graphDsl ?? '',
        // Unlike PreferencesStore.saveSavedExports, this writes the export
        // list as a native Firestore array of maps directly — no
        // jsonEncode needed, since Firestore documents support nested
        // structures natively (that JSON round-trip is only necessary for
        // SharedPreferences' flat string-only storage).
        'savedExports': snapshot.savedExports
            .map(
              (e) => {
                'name': e.name,
                'dsl': e.dsl,
                'type': e.type.name,
                'blackBoxDescription': e.blackBoxDescription,
              },
            )
            .toList(),
        'showSimulator': snapshot.showSimulator,
        'showHelpOverlay': snapshot.showHelpOverlay,
        'simInput': snapshot.simInput,
        'simStep': snapshot.simStep,
        // Also stored as a native array (List<String>) rather than a JSON
        // string, same reasoning as savedExports above.
        'additionalTapeInputs': snapshot.additionalTapeInputs,
        // Server-assigned write timestamp — useful for auditing/debugging
        // and potential future conflict resolution, though nothing in this
        // file currently reads it back.
        'updatedAt': FieldValue.serverTimestamp(),
      },
      // merge: true makes this a partial update rather than a full
      // document replace — any field NOT included in this map (there
      // currently are none, since every PersistedSnapshot field is
      // written) would otherwise be left untouched rather than deleted.
      SetOptions(merge: true),
    );
  }

  // Firestore-specific counterpart to PreferencesStore._decodeExports
  // above. Notably simpler: no try/catch needed because Firestore data is
  // already structured (not a JSON string that could fail to parse) — the
  // only defensiveness needed is against unexpected/missing field types
  // within an already-valid document.
  static List<SavedExport> _decodeExports(dynamic raw) {
    // Firestore field might be entirely absent (raw == null) or, in
    // theory, some other type if the schema was ever different — either
    // way, anything that isn't a List is treated as "no exports".
    if (raw is! List) return [];
    return [
      for (final item in raw)
        // Skip non-Map entries the same way the SharedPreferences decoder
        // does, just without needing the outer try/catch since we're not
        // parsing raw JSON text here.
        if (item is Map)
          SavedExport(
            name: item['name']?.toString() ?? 'Export',
            dsl: item['dsl']?.toString() ?? '',
            type: item['type']?.toString() == SavedExportType.blackBox.name
                ? SavedExportType.blackBox
                : SavedExportType.graph,
            blackBoxDescription: item['blackBoxDescription']?.toString() ?? '',
          ),
    ];
  }

  // Firestore-specific counterpart to
  // PreferencesStore._decodeTapeInputs — same simplification as
  // _decodeExports above (no JSON parsing needed, just type-guarding an
  // already-structured value).
  static List<String> _decodeTapeInputs(dynamic raw) {
    if (raw is! List) return [];
    return [for (final item in raw) item?.toString() ?? ''];
  }
}