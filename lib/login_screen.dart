import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'game_data.dart';
import 'persistence.dart';
import 'widgets/app_theme.dart';

const _kError = Color(0xFFFF1744);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.firebaseEnabled,
    required this.onAuthenticated,
  });

  final AuthService authService;
  final bool firebaseEnabled;
  final VoidCallback onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey            = GlobalKey<FormState>();

  late final AnimationController _bgCtrl;

  bool _isRegistering = false;
  bool _busy          = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  // ── Auth actions ───────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_isRegistering) {
        await widget.authService.signUp(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await widget.authService.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      if (mounted) widget.onAuthenticated();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Authentication failed.');
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.authService.continueAsGuest();
      if (mounted) widget.onAuthenticated();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          // Animated grid background
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, _) => CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _GridPainter(
                animValue: _bgCtrl.value,
                gridColor: theme.gridLine,
                accentColor: theme.accent,
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(theme),
                        const SizedBox(height: 36),
                        if (!widget.firebaseEnabled) _buildFirebaseWarning(),
                        if (!widget.firebaseEnabled) const SizedBox(height: 20),
                        _buildEmailField(theme),
                        const SizedBox(height: 14),
                        _buildPasswordField(theme),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _buildError(),
                        ],
                        const SizedBox(height: 24),
                        _buildSignInButton(theme),
                        const SizedBox(height: 10),
                        _buildToggleRegisterButton(theme),
                        const SizedBox(height: 20),
                        _buildDivider(theme),
                        const SizedBox(height: 20),
                        _buildGuestButton(theme),
                        const SizedBox(height: 10),
                        _buildGuestNote(theme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppThemeNotifier theme) {
    return Column(
      children: [
        // Glowing title
        Text(
          'AUTOMATA',
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            color: theme.accent,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            shadows: [
              Shadow(color: theme.accent.withOpacity(0.6), blurRadius: 18),
              Shadow(color: theme.accent.withOpacity(0.3), blurRadius: 40),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'DESIGNER',
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            color: theme.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 18),
        Container(height: 1, color: theme.borderMid),
        const SizedBox(height: 16),
        Text(
          'Sign in to sync your graphs across devices,\nor continue as a guest.',
          textAlign: TextAlign.center,
          style: GoogleFonts.sourceCodePro(
            color: theme.textMid,
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildFirebaseWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1200),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4A3000), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD740), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Firebase is not configured on this build. '
              'Use Continue as Guest (data stays on this device). '
              'See FIREBASE_SETUP.md to enable accounts.',
              style: GoogleFonts.sourceCodePro(
                color: const Color(0xFFFFD740),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField(AppThemeNotifier theme) {
    return _StyledField(
      theme: theme,
      controller: _emailController,
      label: 'EMAIL',
      enabled: widget.firebaseEnabled && !_busy,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      validator: (v) {
        if (!widget.firebaseEnabled) return null;
        if (v == null || v.trim().isEmpty) return 'Enter your email';
        if (!v.contains('@')) return 'Enter a valid email';
        return null;
      },
    );
  }

  Widget _buildPasswordField(AppThemeNotifier theme) {
    return _StyledField(
      theme: theme,
      controller: _passwordController,
      label: 'PASSWORD',
      enabled: widget.firebaseEnabled && !_busy,
      obscureText: true,
      validator: (v) {
        if (!widget.firebaseEnabled) return null;
        if (v == null || v.length < 6) return 'Minimum 6 characters';
        return null;
      },
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kError.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kError.withOpacity(0.35)),
      ),
      child: Text(
        _error!,
        style: GoogleFonts.sourceCodePro(color: _kError, fontSize: 12),
      ),
    );
  }

  Widget _buildSignInButton(AppThemeNotifier theme) {
    final label = _busy
        ? 'PLEASE WAIT…'
        : _isRegistering
            ? 'CREATE ACCOUNT'
            : 'SIGN IN';

    return _GlowButton(
      onPressed: (!_busy && widget.firebaseEnabled) ? _submit : null,
      label: label,
      color: theme.accent,
    );
  }

  Widget _buildToggleRegisterButton(AppThemeNotifier theme) {
    return TextButton(
      onPressed: (!_busy && widget.firebaseEnabled)
          ? () => setState(() {
                _isRegistering = !_isRegistering;
                _error = null;
              })
          : null,
      style: TextButton.styleFrom(
        foregroundColor: theme.textDim,
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      child: Text(
        _isRegistering
            ? 'ALREADY HAVE AN ACCOUNT?  SIGN IN'
            : 'NEED AN ACCOUNT?  CREATE ONE',
        style: GoogleFonts.orbitron(
          fontSize: 8,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildDivider(AppThemeNotifier theme) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: theme.borderMid)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: GoogleFonts.orbitron(
              color: theme.textDim,
              fontSize: 9,
              letterSpacing: 3,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: theme.borderMid)),
      ],
    );
  }

  Widget _buildGuestButton(AppThemeNotifier theme) {
    return _GlowButton(
      onPressed: _busy ? null : _guest,
      label: 'CONTINUE AS GUEST',
      color: theme.accentGreen,
      icon: Icons.person_outline,
    );
  }

  Widget _buildGuestNote(AppThemeNotifier theme) {
    return Text(
      'Guest mode saves locally only and does not use Firebase.',
      textAlign: TextAlign.center,
      style: GoogleFonts.sourceCodePro(
        color: theme.textDim,
        fontSize: 10,
        letterSpacing: 0.3,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Styled text-field (dark with glowing focus border)
// ─────────────────────────────────────────────────────────────────────────────

class _StyledField extends StatelessWidget {
  const _StyledField({
    required this.theme,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.keyboardType,
    this.validator,
  });

  final AppThemeNotifier theme;
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool obscureText;
  final bool autocorrect;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      autocorrect: autocorrect,
      keyboardType: keyboardType,
      style: GoogleFonts.sourceCodePro(color: theme.textLight, fontSize: 14),
      cursorColor: theme.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.orbitron(color: theme.textDim, fontSize: 10, letterSpacing: 2),
        floatingLabelStyle: GoogleFonts.orbitron(color: theme.accent, fontSize: 10, letterSpacing: 2),
        filled: true,
        fillColor: theme.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.borderMid),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.borderMid),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kError, width: 1.5),
        ),
        errorStyle: GoogleFonts.sourceCodePro(color: _kError, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glowing CTA button
// ─────────────────────────────────────────────────────────────────────────────

class _GlowButton extends StatelessWidget {
  const _GlowButton({
    required this.label,
    required this.color,
    this.onPressed,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final enabled = onPressed != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: enabled
            ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 16, spreadRadius: 0)]
            : null,
      ),
      child: SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: icon != null
              ? Icon(icon, size: 16, color: enabled ? color : theme.textDim)
              : const SizedBox.shrink(),
          label: Text(
            label,
            style: GoogleFonts.orbitron(
              color: enabled ? color : theme.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: enabled ? color.withOpacity(0.08) : Colors.transparent,
            side: BorderSide(color: enabled ? color.withOpacity(0.6) : theme.borderMid, width: 1.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated dot-grid background (same style as level_select_screen)
// ─────────────────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final double animValue;
  final Color gridColor;
  final Color accentColor;

  const _GridPainter({
    required this.animValue,
    required this.gridColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Slow pulse of accent dots at grid intersections near center
    final cx = size.width / 2;
    final cy = size.height / 2;
    final pulse = (sin(animValue * 2 * pi) + 1) / 2; // 0..1

    final dotPaint = Paint()
      ..color = accentColor.withOpacity(0.04 + pulse * 0.04)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        final dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2));
        final fade = (1 - (dist / (size.width * 0.7)).clamp(0.0, 1.0));
        canvas.drawCircle(
          Offset(x, y),
          1.2 * fade,
          dotPaint..color = accentColor.withOpacity((0.08 + pulse * 0.06) * fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.animValue != animValue ||
      old.gridColor != gridColor ||
      old.accentColor != accentColor;
}
// ─────────────────────────────────────────────────────────────────────────────
//  ModeSelectScreen — landing page shown right after LoginScreen hands off
//  (sign-in / guest continue). Kept in this file since it's the natural next
//  step in the same pre-app entry flow, and shares the same visual language
//  (Orbitron title, dark theme, glow accents) as the login screen above.
// ─────────────────────────────────────────────────────────────────────────────

class ModeSelectScreen extends StatefulWidget {
  const ModeSelectScreen({
    super.key,
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
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen>
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
          builder: (_, _) {
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