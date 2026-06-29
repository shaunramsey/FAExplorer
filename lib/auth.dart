import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
