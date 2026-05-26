import 'package:flutter/material.dart';

import 'auth/auth_mode.dart';
import 'auth/auth_service.dart';
import 'automata_screen.dart';
import 'data/automata_session_store.dart';
import 'data/firebase_session_store.dart';
import 'login_screen.dart';

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
  bool _loading = true;
  AutomataSessionStore? _sessionStore;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await widget.authService.init();
    await _openSessionStore();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openSessionStore() async {
    if (widget.authService.isSignedIn) {
      _sessionStore = FirebaseSessionStore();
    } else if (widget.authService.isGuest) {
      _sessionStore = await LocalSessionStore.open();
    } else {
      _sessionStore = null;
    }
  }

  Future<void> _onAuthenticated() async {
    setState(() => _loading = true);
    await _openSessionStore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signOut() async {
    setState(() => _loading = true);
    await widget.authService.signOut();
    _sessionStore = null;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final mode = widget.authService.mode;
    if (mode == null || _sessionStore == null) {
      return LoginScreen(
        authService: widget.authService,
        firebaseEnabled: widget.firebaseEnabled,
        onAuthenticated: _onAuthenticated,
      );
    }

    return AutomataScreen(
      sessionStore: _sessionStore!,
      isGuest: mode == AuthMode.guest,
      userEmail: widget.authService.user?.email,
      onSignOut: _signOut,
    );
  }
}
