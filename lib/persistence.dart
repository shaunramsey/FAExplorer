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

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  1. FIREBASE CONFIGURATION
// ═════════════════════════════════════════════════════════════════════════════

/// Set to true after running `flutterfire configure` and updating the values below.
const bool kFirebaseConfigured = true;

/// Firebase configuration for each platform.
///
/// Run from the project root:
///   dart pub global activate flutterfire_cli
///   flutterfire configure
/// Then set [kFirebaseConfigured] to true and paste the generated values here
/// (or replace this file with the generated `firebase_options.dart`).
class DefaultFirebaseOptions {
  static bool get isConfigured => kFirebaseConfigured;

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError(
        'Firebase is not configured. Set kFirebaseConfigured to true in '
        'lib/persistence.dart after running flutterfire configure.',
      );
    }
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCqTaOQbIk2Jf6MKnClw7RAfNAsmtWMH_Y',
    appId: '1:583188706903:web:a8c8dff725913ce3019512',
    messagingSenderId: '583188706903',
    projectId: 'toc-fa-ramsey',
    authDomain: 'toc-fa-ramsey.firebaseapp.com',
    storageBucket: 'toc-fa-ramsey.firebasestorage.app',
    measurementId: 'G-P1H2HB3M85',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.automataDesigner',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: 'YOUR_MACOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.automataDesigner',
  );

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

enum AuthMode { guest, account }

abstract final class AuthPreferenceKeys {
  static const authMode = 'auth_mode';
}

class AuthService {
  AuthService({
    required this.firebaseEnabled,
    FirebaseAuth? auth,
    SharedPreferences? prefs,
  })  : _auth = firebaseEnabled ? (auth ?? FirebaseAuth.instance) : null,
        _prefs = prefs;

  final bool firebaseEnabled;
  final FirebaseAuth? _auth;
  SharedPreferences? _prefs;

  AuthMode? _mode;
  User? _user;

  AuthMode? get mode => _mode;
  User? get user => _user;
  bool get isGuest => _mode == AuthMode.guest;
  bool get isSignedIn => _mode == AuthMode.account && _user != null;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final stored = _prefs!.getString(AuthPreferenceKeys.authMode);

    if (stored == AuthMode.guest.name) {
      _mode = AuthMode.guest;
      return;
    }

    if (stored == AuthMode.account.name && firebaseEnabled && _auth != null) {
      _user = _auth.currentUser;
      if (_user != null) {
        _mode = AuthMode.account;
        return;
      }
      await _prefs!.remove(AuthPreferenceKeys.authMode);
    }

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
    if (auth != null && auth.currentUser != null) {
      await auth.signOut();
    }
    _mode = AuthMode.guest;
    _user = null;
    await _prefs?.setString(AuthPreferenceKeys.authMode, AuthMode.guest.name);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final auth = _requireFirebase();
    final cred = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _user = cred.user;
    _mode = AuthMode.account;
    await _prefs?.setString(AuthPreferenceKeys.authMode, AuthMode.account.name);
  }

  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    final auth = _requireFirebase();
    final cred = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _user = cred.user;
    _mode = AuthMode.account;
    await _prefs?.setString(AuthPreferenceKeys.authMode, AuthMode.account.name);
  }

  Future<void> signOut() async {
    if (_auth != null && _user != null) {
      await _auth.signOut();
    }
    _mode = null;
    _user = null;
    await _prefs?.remove(AuthPreferenceKeys.authMode);
  }

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

enum SavedExportType { graph, blackBox }

class SavedExport {
  String name;
  String dsl;
  SavedExportType type;
  String blackBoxDescription;

  SavedExport({
    required this.name,
    required this.dsl,
    this.type = SavedExportType.graph,
    this.blackBoxDescription = '',
  });

  bool get isBlackBox => type == SavedExportType.blackBox;
}

/// Keys used in [SharedPreferences] for FAExplorer session data.
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

class PersistedSnapshot {
  final String? graphDsl;
  final List<SavedExport> savedExports;
  final bool showSimulator;
  final bool showHelpOverlay;
  final String simInput;
  final int simStep;
  /// Content for tapes 2, 3, … (index 0 = tape 2, index 1 = tape 3, …).
  /// Each string is the raw user input for that tape, tokenised the same way
  /// as [simInput].  Empty list means all extra tapes start blank.
  final List<String> additionalTapeInputs;

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

class PreferencesStore {
  PreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PreferencesStore> open() async {
    return PreferencesStore(await SharedPreferences.getInstance());
  }

  PersistedSnapshot load() {
    final exportsJson = _prefs.getString(PreferenceKeys.savedExports);
    return PersistedSnapshot(
      graphDsl: _prefs.getString(PreferenceKeys.graphDsl),
      savedExports: _decodeExports(exportsJson),
      showSimulator: _prefs.getBool(PreferenceKeys.showSimulator) ?? true,
      showHelpOverlay: _prefs.getBool(PreferenceKeys.showHelpOverlay) ?? false,
      simInput: _prefs.getString(PreferenceKeys.simInput) ?? '',
      simStep: _prefs.getInt(PreferenceKeys.simStep) ?? -1,
      additionalTapeInputs: _decodeTapeInputs(
        _prefs.getString(PreferenceKeys.additionalTapeInputs),
      ),
    );
  }

  Future<void> saveGraphDsl(String dsl) async {
    if (dsl.trim().isEmpty) {
      await _prefs.remove(PreferenceKeys.graphDsl);
    } else {
      await _prefs.setString(PreferenceKeys.graphDsl, dsl);
    }
  }

  Future<void> saveSavedExports(List<SavedExport> exports) async {
    final encoded = jsonEncode(
      exports
          .map(
            (e) => {
              'name': e.name,
              'dsl': e.dsl,
              'type': e.type.name,
              'blackBoxDescription': e.blackBoxDescription,
            },
          )
          .toList(),
    );
    await _prefs.setString(PreferenceKeys.savedExports, encoded);
  }

  Future<void> saveUi({
    bool? showSimulator,
    bool? showHelpOverlay,
  }) async {
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
    if (input.isEmpty) {
      await _prefs.remove(PreferenceKeys.simInput);
    } else {
      await _prefs.setString(PreferenceKeys.simInput, input);
    }
    await _prefs.setInt(PreferenceKeys.simStep, step);

    // Persist extra-tape inputs.  Remove the key entirely when all tapes are
    // blank so we don't store unnecessary noise for single-tape machines.
    final nonEmpty = additionalTapeInputs.map((s) => s).toList();
    final allBlank = nonEmpty.every((s) => s.isEmpty);
    if (allBlank) {
      await _prefs.remove(PreferenceKeys.additionalTapeInputs);
    } else {
      await _prefs.setString(
        PreferenceKeys.additionalTapeInputs,
        jsonEncode(nonEmpty),
      );
    }
  }

  Future<void> clearAll() async {
    await _prefs.remove(PreferenceKeys.graphDsl);
    await _prefs.remove(PreferenceKeys.savedExports);
    await _prefs.remove(PreferenceKeys.simInput);
    await _prefs.remove(PreferenceKeys.simStep);
    await _prefs.remove(PreferenceKeys.additionalTapeInputs);
  }

  static List<SavedExport> _decodeExports(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final result = <SavedExport>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          // Strict null checking with proper fallbacks
          final nameRaw = item['name'];
          final name = (nameRaw != null) ? nameRaw.toString().trim() : 'Export';

          final dslRaw = item['dsl'];
          final dsl = (dslRaw != null) ? dslRaw.toString() : '';

          final typeStr = item['type']?.toString().trim() ?? '';

          final descRaw = item['blackBoxDescription'];
          final desc = (descRaw != null) ? descRaw.toString() : '';

          result.add(SavedExport(
            name: name,
            dsl: dsl,
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
      return [];
    }
  }

  /// Decodes a JSON-encoded list of tape-input strings.
  /// Returns an empty list on any parse error so callers always get a safe value.
  static List<String> _decodeTapeInputs(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
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
abstract class AutomataSessionStore {
  Future<PersistedSnapshot> load();
  Future<void> save(PersistedSnapshot snapshot);
}

class LocalSessionStore implements AutomataSessionStore {
  LocalSessionStore(this._prefs);

  final PreferencesStore _prefs;

  static Future<LocalSessionStore> open() async {
    return LocalSessionStore(await PreferencesStore.open());
  }

  @override
  Future<PersistedSnapshot> load() async => _prefs.load();

  @override
  Future<void> save(PersistedSnapshot snapshot) async {
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
class FirebaseSessionStore implements AutomataSessionStore {
  FirebaseSessionStore({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('workspace').doc('main');
  }

  @override
  Future<PersistedSnapshot> load() async {
    final doc = _doc;
    if (doc == null) return const PersistedSnapshot();

    final snap = await doc.get();
    if (!snap.exists) return const PersistedSnapshot();

    final data = snap.data();
    if (data == null) return const PersistedSnapshot();

    return PersistedSnapshot(
      graphDsl: data['graphDsl'] as String?,
      savedExports: _decodeExports(data['savedExports']),
      showSimulator: data['showSimulator'] as bool? ?? true,
      showHelpOverlay: data['showHelpOverlay'] as bool? ?? false,
      simInput: data['simInput'] as String? ?? '',
      simStep: (data['simStep'] as num?)?.toInt() ?? -1,
      additionalTapeInputs: _decodeTapeInputs(data['additionalTapeInputs']),
    );
  }

  @override
  Future<void> save(PersistedSnapshot snapshot) async {
    final doc = _doc;
    if (doc == null) return;

    await doc.set(
      {
        'graphDsl': snapshot.graphDsl ?? '',
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
        'additionalTapeInputs': snapshot.additionalTapeInputs,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static List<SavedExport> _decodeExports(dynamic raw) {
    if (raw is! List) return [];
    return [
      for (final item in raw)
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

  static List<String> _decodeTapeInputs(dynamic raw) {
    if (raw is! List) return [];
    return [for (final item in raw) item?.toString() ?? ''];
  }
}