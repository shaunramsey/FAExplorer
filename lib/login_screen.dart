// ─────────────────────────────────────────────────────────────────────────────
//  login_screen.dart
//
//  Two screens for the pre-app entry flow:
//    1. LoginScreen      — email/password sign-in, registration, and a
//                           "continue as guest" fallback for builds where
//                           Firebase hasn't been configured.
//    2. ModeSelectScreen  — the landing page shown immediately after
//                           LoginScreen hands off (kept in this file since
//                           it's the natural next step in the same entry
//                           flow and reuses the same dark/glow visual style).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math'; // sin/pow/sqrt/pi used by the animated grid background painter

import 'package:firebase_auth/firebase_auth.dart'; // FirebaseAuthException, caught specifically in _submit
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // Orbitron (headings/labels) + Source Code Pro (body/mono text)
import 'package:provider/provider.dart'; // context.watch<AppThemeNotifier>()

import 'game_data.dart'; // GameProgressStore, used by ModeSelectScreen for the completed-levels count
import 'persistence.dart'; // AuthService (sign in/up, guest continuation)
import 'widgets/app_theme.dart'; // AppThemeNotifier — supplies all the theme.* colors used below

// Shared "error" red used by both the inline field-validation borders and the
// top-level error banner, so every error indicator on this screen matches.
const _kError = Color(0xFFFF1744);

// ─────────────────────────────────────────────────────────────────────────────
//  LoginScreen
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.firebaseEnabled,
    required this.onAuthenticated,
  });

  // Handles the actual sign-in/sign-up/guest network calls; injected so the
  // screen itself stays free of Firebase wiring details.
  final AuthService authService;

  // False when this build has no Firebase config. When false, the email/
  // password path is disabled entirely and only "Continue as Guest" works
  // (see _buildEmailField/_buildPasswordField `enabled:` and
  // _buildSignInButton's onPressed gating below).
  final bool firebaseEnabled;

  // Fired once sign-in/sign-up/guest-continue succeeds, so the parent can
  // swap this screen out for the rest of the app.
  final VoidCallback onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // Backing controllers for the two form fields; read directly in _submit.
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  // Lets _submit call `.validate()` on the Form and trigger each field's
  // validator (see _buildEmailField/_buildPasswordField).
  final _formKey            = GlobalKey<FormState>();

  // Drives the slow animated grid/dot background (_GridPainter). Declared
  // `late final` because it's constructed in initState, not at field-init
  // time, since it needs `this` as the TickerProvider.
  late final AnimationController _bgCtrl;

  // Toggles the form between "sign in" and "create account" copy/behavior.
  bool _isRegistering = false;
  // True while an auth call is in flight; disables inputs/buttons and swaps
  // the submit button's label to "PLEASE WAIT…".
  bool _busy          = false;
  // Last error message to show under the password field, or null if none.
  String? _error;

  @override
  void initState() {
    super.initState();
    // 4-second looping animation, purely cosmetic (feeds `animValue` into
    // _GridPainter for the pulsing dot effect) — no gameplay/logic tie-in.
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    // Standard Flutter hygiene: release controllers this State owns so they
    // don't leak once the widget is removed from the tree.
    _emailController.dispose();
    _passwordController.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  // ── Auth actions ───────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // Runs every field's validator (see _buildEmailField/_buildPasswordField);
    // bail out silently if any of them fail — Flutter's Form already paints
    // the per-field error text, so nothing else to do here.
    if (!_formKey.currentState!.validate()) return;

    // Enter the busy state and clear any stale error from a previous attempt
    // before starting the new request.
    setState(() { _busy = true; _error = null; });
    try {
      // Route to sign-up or sign-in depending on which mode the toggle
      // button (_buildToggleRegisterButton) last put us in.
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
      // `mounted` guard: the async gap above means this State could have
      // been disposed (e.g. user navigated away) before the future
      // completed — calling the callback (or setState below) on a disposed
      // State would throw.
      if (mounted) widget.onAuthenticated();
    } on FirebaseAuthException catch (e) {
      // Firebase's own exception type carries a human-readable `message`;
      // fall back to a generic string on the rare chance it's null.
      setState(() => _error = e.message ?? 'Authentication failed.');
    } on StateError catch (e) {
      // Thrown by AuthService itself for non-Firebase-specific failure
      // modes (e.g. calling signIn when Firebase isn't configured).
      setState(() => _error = e.message);
    } catch (e) {
      // Catch-all so any other unexpected exception still surfaces to the
      // user instead of crashing silently.
      setState(() => _error = e.toString());
    } finally {
      // Always clear the busy flag, whether the call succeeded or failed,
      // but only if the widget is still around to receive the setState.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    // Same busy/error bookkeeping as _submit, but no form validation is
    // needed since guest mode doesn't read the email/password fields.
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
    // `watch` (not `read`) so the whole screen rebuilds and repaints in the
    // current theme's colors if the user changes appearance settings.
    final theme = context.watch<AppThemeNotifier>();
    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          // Animated grid background
          // Rebuilds every animation tick to feed the latest `_bgCtrl.value`
          // into the painter, driving the pulsing-dot effect.
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
          // SafeArea keeps the form clear of notches/status bars; Center +
          // SingleChildScrollView keeps it usable on short screens (e.g.
          // keyboard open) by allowing the column to scroll instead of
          // overflowing.
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  // Caps the form's width on wide/desktop windows so the
                  // fields don't stretch edge-to-edge.
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      // Stretch so children (fields, buttons, dividers) all
                      // take the full width of the constrained column.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(theme),
                        const SizedBox(height: 36),
                        // Only shown when this build has no Firebase config,
                        // to explain why the email/password fields below are
                        // disabled and guest mode is the only working path.
                        if (!widget.firebaseEnabled) _buildFirebaseWarning(),
                        if (!widget.firebaseEnabled) const SizedBox(height: 20),
                        _buildEmailField(theme),
                        const SizedBox(height: 14),
                        _buildPasswordField(theme),
                        // Error banner only takes up space (and only renders)
                        // once a request has actually failed.
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
        // Double Shadow stack (tight + wide blur) gives a layered neon-glow
        // look rather than a single flat drop shadow.
        Text(
          'AUTOMATA',
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            color: theme.accent,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            shadows: [
              Shadow(color: theme.accent.withValues(alpha: 0.6), blurRadius: 18),
              Shadow(color: theme.accent.withValues(alpha: 0.3), blurRadius: 40),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Subtitle sits directly under the title; dimmer color + wide
        // letter-spacing reads as a "kicker" label rather than a heading.
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
        // Thin full-width rule separating the branding block from the
        // explanatory copy below it.
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
    // Amber "no backend configured" notice — only ever shown when
    // widget.firebaseEnabled is false (see the `if` guarding it in build()).
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1200),                       // dark amber-tinted fill
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4A3000), width: 1), // matching amber border
      ),
      child: Row(
        // Start-aligned cross axis so the icon lines up with the first line
        // of (potentially multi-line) text rather than being vertically
        // centered against the whole paragraph.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD740), size: 16),
          const SizedBox(width: 10),
          // Expanded so the message wraps within the remaining width instead
          // of overflowing the Row horizontally.
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
      // Disabled whenever Firebase isn't configured (nothing to validate
      // against) or while a request is already in flight.
      enabled: widget.firebaseEnabled && !_busy,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      validator: (v) {
        // Skip validation entirely on Firebase-less builds — the field is
        // disabled and irrelevant to the (guest-only) submit flow there.
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
      obscureText: true, // masks input — this is the password field
      validator: (v) {
        if (!widget.firebaseEnabled) return null;
        // Matches Firebase Auth's own minimum password length so the field
        // fails fast client-side instead of round-tripping to the server.
        if (v == null || v.length < 6) return 'Minimum 6 characters';
        return null;
      },
    );
  }

  Widget _buildError() {
    // Tinted/bordered banner (not a SnackBar) so the error stays visible
    // in-place under the fields for as long as `_error` is non-null.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kError.withValues(alpha: 0.35)),
      ),
      child: Text(
        _error!, // safe: this widget is only built when _error != null (see build())
        style: GoogleFonts.sourceCodePro(color: _kError, fontSize: 12),
      ),
    );
  }

  Widget _buildSignInButton(AppThemeNotifier theme) {
    // Label reflects busy state first (takes priority over mode), then
    // whichever mode (_isRegistering) the toggle button last selected.
    final label = _busy
        ? 'PLEASE WAIT…'
        : _isRegistering
            ? 'CREATE ACCOUNT'
            : 'SIGN IN';

    return _GlowButton(
      // Disabled (onPressed: null) while busy or when Firebase isn't
      // configured, since there's nothing for this button to submit to.
      onPressed: (!_busy && widget.firebaseEnabled) ? _submit : null,
      label: label,
      color: theme.accent,
    );
  }

  Widget _buildToggleRegisterButton(AppThemeNotifier theme) {
    return TextButton(
      onPressed: (!_busy && widget.firebaseEnabled)
          ? () => setState(() {
                // Flip between sign-in/sign-up mode and drop any error from
                // whichever mode the user is leaving.
                _isRegistering = !_isRegistering;
                _error = null;
              })
          : null,
      style: TextButton.styleFrom(
        foregroundColor: theme.textDim,
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      child: Text(
        // Copy always points at the *other* mode — e.g. while in sign-in
        // mode it invites the user to create an account, and vice versa.
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
    // Classic "―――  OR  ―――" separator between the email/password form and
    // the guest-mode option below it.
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
    // Unlike the sign-in button, this one is never gated on
    // widget.firebaseEnabled — guest mode is meant to work regardless of
    // whether Firebase is configured, only busy-state disables it.
    return _GlowButton(
      onPressed: _busy ? null : _guest,
      label: 'CONTINUE AS GUEST',
      color: theme.accentGreen, // distinct accent color from the primary sign-in button
      icon: Icons.person_outline,
    );
  }

  Widget _buildGuestNote(AppThemeNotifier theme) {
    // Small print clarifying the local-only, no-Firebase nature of guest
    // mode, placed directly under the guest button.
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
  final String label; // floating/placeholder label, e.g. "EMAIL" or "PASSWORD"
  final bool enabled;
  final bool obscureText; // true for the password field, masks characters
  final bool autocorrect; // disabled for email (see _buildEmailField)
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
        // Style used when the label is inline (field empty, unfocused).
        labelStyle: GoogleFonts.orbitron(color: theme.textDim, fontSize: 10, letterSpacing: 2),
        // Style used once the label has floated up above the field
        // (focused or has content) — switches to the accent color to show
        // which field is active.
        floatingLabelStyle: GoogleFonts.orbitron(color: theme.accent, fontSize: 10, letterSpacing: 2),
        filled: true,
        fillColor: theme.bg,
        // Five border variants cover every combination of focus × validity:
        // default (unfocused, valid), enabled (same, explicit), focused
        // (valid + focused, accent glow), error (invalid, unfocused), and
        // focusedError (invalid + focused — still red, just thicker).
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
    this.onPressed, // null = disabled (button greys out, no glow, no tap)
    this.icon,
  });

  final String label;
  final Color color;      // accent color when enabled; falls back to theme.textDim when disabled
  final VoidCallback? onPressed;
  final IconData? icon;   // optional leading icon (e.g. person icon on the guest button)

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    // Enabled state is derived purely from whether a callback was supplied —
    // this is the single source of truth for every enabled/disabled visual
    // below (glow, icon color, label color, fill, border).
    final enabled = onPressed != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        // Soft outer glow only rendered while enabled; disabled buttons get
        // no shadow at all (flat/inert look).
        boxShadow: enabled
            ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 0)]
            : null,
      ),
      child: SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          // OutlinedButton.icon requires an icon widget; when none was
          // supplied, pass an empty SizedBox instead of omitting it so the
          // label-only buttons (e.g. sign-in) still lay out correctly.
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
            backgroundColor: enabled ? color.withValues(alpha: 0.08) : Colors.transparent,
            side: BorderSide(color: enabled ? color.withValues(alpha: 0.6) : theme.borderMid, width: 1.2),
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
  final double animValue;  // 0..1 looping value from LoginScreen's _bgCtrl, drives the pulse
  final Color gridColor;   // faint line color for the static grid
  final Color accentColor; // color of the pulsing dots at intersections

  const _GridPainter({
    required this.animValue,
    required this.gridColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Static grid lines ───────────────────────────────────────────────
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    const spacing = 40.0;
    // Vertical lines across the full width, one every `spacing` pixels.
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines across the full height, same spacing.
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Slow pulse of accent dots at grid intersections near center
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Remaps sin (-1..1) to a 0..1 pulse value so opacity math below never
    // goes negative.
    final pulse = (sin(animValue * 2 * pi) + 1) / 2; // 0..1

    final dotPaint = Paint()
      // Base alpha of 0.04, breathing up to 0.08 as `pulse` cycles — subtle
      // by design so it reads as ambient texture, not a distraction.
      ..color = accentColor.withValues(alpha: 0.04 + pulse * 0.04)
      ..style = PaintingStyle.fill;

    // One dot per grid intersection; each dot's own opacity additionally
    // fades out with distance from center (see `fade` below), so only the
    // intersections near the middle of the screen visibly pulse.
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        final dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2));
        // 1.0 at the exact center, fading linearly to 0 by the time `dist`
        // reaches 70% of the canvas width; clamped so it never goes negative
        // for points beyond that radius.
        final fade = (1 - (dist / (size.width * 0.7)).clamp(0.0, 1.0));
        canvas.drawCircle(
          Offset(x, y),
          1.2 * fade, // dot radius also shrinks with distance from center
          // Mutates and reuses `dotPaint` rather than allocating a new Paint
          // per dot — combines the pulse-driven base alpha with this dot's
          // own distance-based fade.
          dotPaint..color = accentColor.withValues(alpha: (0.08 + pulse * 0.06) * fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      // Only repaint when something that actually affects the drawing has
      // changed — avoids redundant repaints if this painter is rebuilt with
      // identical parameters.
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

  final VoidCallback onSandbox;             // navigate to the free-form sandbox designer
  final VoidCallback onGame;                // navigate to Game Mode (puzzle levels)
  final VoidCallback onStudy;                // navigate to Study Mode (lessons)
  final Future<void> Function() onSignOut;   // async so callers can await Firebase sign-out completing
  final bool isGuest;                        // shows the "GUEST MODE" label next to Sign Out when true
  final GameProgressStore progressStore;     // source of the completed-levels count shown on the Game card

  @override
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen>
    with TickerProviderStateMixin {
  // One-shot entrance animation (fade + slide-up) for the whole screen.
  late final AnimationController _entryCtrl;
  // Continuous back-and-forth pulse fed into the featured Game Mode card's
  // glow (see _ModeCard.pulseAnim / featured).
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward(); // plays once, from 0 to 1, immediately on screen entry
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true); // ping-pongs 0→1→0→1… indefinitely
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
    // Counts completions on either difficulty — matches the union that
    // unlock logic already uses, so this can't undercount Easy-only progress.
    final completed = widget.progressStore.loadCompletedLevelsAnyDifficulty().length;

    return Scaffold(
      backgroundColor: theme.bg,
      body: AnimatedBuilder(
        animation: _entryCtrl,
        builder: (ctx, _) {
          // Derive an eased fade curve from the linear controller so the
          // entrance feels like it decelerates into place rather than
          // moving at a constant rate.
          final fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
          return SafeArea(
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                // Starts slightly below (5% of the widget's own height) and
                // slides up into its final position as `fade` runs 0 → 1,
                // combined with the fade for a soft "rise in" entrance.
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
                          // Pushes the settings icon to the far right without
                          // needing a separate Align/mainAxisAlignment setup.
                          const Spacer(),
                          IconButton(
                            tooltip: 'Appearance & colors',
                            icon: Icon(Icons.palette_outlined, color: theme.textMid),
                            onPressed: () => showAppThemeSettings(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Same branding block styling as LoginScreen's header,
                      // just without the glow shadows (this screen already
                      // uses its own glow via the mode cards below).
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
                      // Spacer above/below the card stack vertically centers
                      // the three mode cards within whatever room is left
                      // between the title and the footer row.
                      const Spacer(),
                      _ModeCard(
                        icon: Icons.grid_view_rounded,
                        title: 'SANDBOX',
                        subtitle: 'Free-form automata designer.\nBuild, simulate, export.',
                        accent: theme.accentGreen, // distinct color from the other two cards
                        subtitleColor: theme.textMid,
                        pulseAnim: _pulseCtrl,
                        onTap: widget.onSandbox,
                      ),
                      const SizedBox(height: 20),
                      _ModeCard(
                        icon: Icons.hexagon_outlined,
                        title: 'GAME MODE',
                        // Dynamically reports progress and correctly
                        // pluralizes "level"/"levels" based on the count.
                        subtitle:
                            'Solve automata puzzles.\n$completed level${completed == 1 ? '' : 's'} completed.',
                        accent: theme.accent,
                        subtitleColor: theme.textMid,
                        pulseAnim: _pulseCtrl,
                        onTap: widget.onGame,
                        featured: true, // gives this card the stronger animated glow (see _ModeCardState)
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
                          // Only shown for guest sessions, to make the
                          // account state visible next to the sign-out
                          // control.
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
  final Animation<double> pulseAnim; // shared controller from ModeSelectScreen, drives the featured glow
  final VoidCallback onTap;
  final bool featured; // true only for the Game Mode card — gets a stronger, animated glow

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  // Tracks mouse hover (desktop/web) to brighten the border/glow — has no
  // effect on touch-only platforms since there's no hover event there.
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
            // Featured card: glow breathes continuously between 0.2 and 0.35
            // regardless of hover. Non-featured cards: glow is static per
            // hover state (0.1 idle, 0.3 on hover) and ignores the pulse.
            final glow = widget.featured
                ? (0.2 + widget.pulseAnim.value * 0.15)
                : (_hovered ? 0.3 : 0.1);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                  // Hover brightens and thickens the border slightly, giving
                  // tactile feedback even though the tap target is the whole
                  // card via the outer GestureDetector.
                  color: widget.accent.withValues(alpha: _hovered ? 0.9 : 0.4),
                  width: _hovered ? 1.5 : 1.0,
                ),
                borderRadius: BorderRadius.circular(16),
                color: widget.accent.withValues(alpha: 0.04), // faint accent-tinted fill
                boxShadow: [
                  BoxShadow(
                    color: widget.accent.withValues(alpha: glow),
                    // Featured card gets a wider blur and slight spread on
                    // top of its breathing alpha, making it visually pop
                    // out as the primary call-to-action among the three.
                    blurRadius: widget.featured ? 24 : 12,
                    spreadRadius: widget.featured ? 2 : 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Circular icon badge on the left.
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.accent.withValues(alpha: 0.1),
                      border: Border.all(color: widget.accent.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 24),
                  ),
                  const SizedBox(width: 20),
                  // Title + subtitle stack fills the remaining width between
                  // the icon badge and the trailing chevron.
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
                  // Trailing chevron signals "this card navigates somewhere"
                  // — purely decorative, the whole card is already tappable.
                  Icon(Icons.chevron_right, color: widget.accent.withValues(alpha: 0.5)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}