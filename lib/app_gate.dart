import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth/auth_mode.dart';
import 'auth/auth_service.dart';
import 'automata_screen.dart';
import 'data/automata_session_store.dart';
import 'data/firebase_session_store.dart';
import 'login_screen.dart';

// Palette shared with level_select_screen.dart / main.dart
const _kBg      = Color(0xFF05080F);
const _kAccent  = Color(0xFF00E5FF);
const _kTextDim = Color(0xFF3A4A5E);

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

class _AppGateState extends State<AppGate> with SingleTickerProviderStateMixin {
  bool _loading = true;
  AutomataSessionStore? _sessionStore;

  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _bootstrap();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await widget.authService.init();
    await _openSessionStore();
    if (mounted) setState(() => _loading = false);
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
      return _LoadingScreen(spinCtrl: _spinCtrl);
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

// ─────────────────────────────────────────────────────────────────────────────
//  Loading screen — styled to match the dark palette
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.spinCtrl});

  final AnimationController spinCtrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Spinning accent ring
            AnimatedBuilder(
              animation: spinCtrl,
              builder: (_, __) => Transform.rotate(
                angle: spinCtrl.value * 2 * 3.14159,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _kAccent.withOpacity(0.15),
                      width: 2,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'INITIALISING',
              style: GoogleFonts.orbitron(
                color: _kTextDim,
                fontSize: 10,
                letterSpacing: 4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}