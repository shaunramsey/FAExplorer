import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'auth.dart';
import 'automata_screen.dart';
import 'game_progress_store.dart';
import 'level_select_screen.dart';
import 'login_screen.dart';
import 'session_store.dart';
import 'study_mode_screen.dart';
import 'widgets/app_theme.dart';
import 'widgets/app_theme_settings.dart';

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
        return _ModeSelectScreen(
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

class _ModeSelectScreen extends StatefulWidget {
  const _ModeSelectScreen({
    required this.onSandbox,
    required this.onGame,
    required this.onStudy,
    required this.onSignOut,
    required this.isGuest,
    required this.progressStore,
  });

  final VoidCallback onSandbox;
  final VoidCallback onGame;
  final VoidCallback onStudy;
  final Future<void> Function() onSignOut;
  final bool isGuest;
  final GameProgressStore progressStore;

  @override
  State<_ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<_ModeSelectScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final completed = widget.progressStore.loadCompletedLevels().length;

    return Scaffold(
      backgroundColor: theme.bg,
      body: AnimatedBuilder(
        animation: _entryCtrl,
        builder: (ctx, _) {
          final fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
          return SafeArea(
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(fade),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          const Spacer(),
                          IconButton(
                            tooltip: 'Appearance & colors',
                            icon: Icon(Icons.palette_outlined, color: theme.textMid),
                            onPressed: () => showAppThemeSettings(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AUTOMATA',
                        style: GoogleFonts.orbitron(
                          color: theme.accent,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DESIGNER',
                        style: GoogleFonts.orbitron(
                          color: theme.accent,
                          fontSize: 18,
                          letterSpacing: 12,
                        ),
                      ),
                      const Spacer(),
                      _ModeCard(
                        icon: Icons.grid_view_rounded,
                        title: 'SANDBOX',
                        subtitle: 'Free-form automata designer.\nBuild, simulate, export.',
                        accent: theme.accentGreen,
                        subtitleColor: theme.textMid,
                        pulseAnim: _pulseCtrl,
                        onTap: widget.onSandbox,
                      ),
                      const SizedBox(height: 20),
                      _ModeCard(
                        icon: Icons.hexagon_outlined,
                        title: 'GAME MODE',
                        subtitle:
                            'Solve automata puzzles.\n$completed level${completed == 1 ? '' : 's'} completed.',
                        accent: theme.accent,
                        subtitleColor: theme.textMid,
                        pulseAnim: _pulseCtrl,
                        onTap: widget.onGame,
                        featured: true,
                      ),
                      const SizedBox(height: 20),
                      _ModeCard(
                        icon: Icons.menu_book_rounded,
                        title: 'STUDY MODE',
                        subtitle: 'Learn automata theory.\nInteractive lessons & examples.',
                        accent: theme.accent,
                        subtitleColor: theme.textMid,
                        pulseAnim: _pulseCtrl,
                        onTap: widget.onStudy,
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.isGuest)
                            Text(
                              'GUEST MODE  •  ',
                              style: GoogleFonts.orbitron(
                                color: theme.textDim,
                                fontSize: 11,
                                letterSpacing: 1,
                              ),
                            ),
                          TextButton(
                            onPressed: widget.onSignOut,
                            child: Text(
                              'SIGN OUT',
                              style: GoogleFonts.orbitron(
                                color: theme.textDim,
                                fontSize: 11,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.subtitleColor,
    required this.pulseAnim,
    required this.onTap,
    this.featured = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color subtitleColor;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;
  final bool featured;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: widget.pulseAnim,
          builder: (_, __) {
            final glow = widget.featured
                ? (0.2 + widget.pulseAnim.value * 0.15)
                : (_hovered ? 0.3 : 0.1);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.accent.withOpacity(_hovered ? 0.9 : 0.4),
                  width: _hovered ? 1.5 : 1.0,
                ),
                borderRadius: BorderRadius.circular(16),
                color: widget.accent.withOpacity(0.04),
                boxShadow: [
                  BoxShadow(
                    color: widget.accent.withOpacity(glow),
                    blurRadius: widget.featured ? 24 : 12,
                    spreadRadius: widget.featured ? 2 : 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.accent.withOpacity(0.1),
                      border: Border.all(color: widget.accent.withOpacity(0.5), width: 1.5),
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 24),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.orbitron(
                            color: widget.accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: GoogleFonts.sourceCodePro(
                            color: widget.subtitleColor,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: widget.accent.withOpacity(0.5)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
