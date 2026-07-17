// ─────────────────────────────────────────────────────────────────────────────
//  Tutorial Screen
//
//  Displays a series of animated slides for tutorial (non-puzzle) levels.
//  Each slide has:
//    • An animated SVG-style illustration (drawn in Flutter via CustomPaint)
//    • A headline
//    • Body text (supports bold runs using ** markers like mini-markdown)
//
//  Navigation: swipe left/right OR tap the prev/next buttons.
//  On the final slide the "Next" button becomes "Got it!" and pops the screen,
//  also marking the tutorial as completed in the progress store.
//
//  Usage (from level_select_screen or game_puzzle):
//
//    await Navigator.push(
//      context,
//      MaterialPageRoute(
//        builder: (_) => TutorialScreen(
//          level: level,
//          progressStore: progressStore,
//          onCompleted: _reload,
//        ),
//      ),
//    );
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math'; // pi, sin, cos, atan2 — all the illustration painters below are trig-driven
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // Orbitron (headline/UI chrome) + Source Code Pro (body text)
import 'package:provider/provider.dart'; // context.watch<AppThemeNotifier>()

import 'game_data.dart'; // GameProgressStore — records that this tutorial has been viewed
import 'game_level.dart'; // GameLevel — supplies the level's title + its list of TutorialSlides
import 'widgets/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Tutorial Slide model
// ─────────────────────────────────────────────────────────────────────────────

/// One page of a tutorial level.
///
/// [illustration] is a widget factory that receives an [Animation<double>]
/// (0→1, looping) so it can animate.  Pass [TutorialIllustrations.forType]
/// to get the built-in illustrations.
class TutorialSlide {
  const TutorialSlide({
    required this.headline,
    required this.body,
    this.illustrationType = TutorialIllustration.none,
  });

  /// Large text shown above the body.
  final String headline;

  /// Explanatory text.  Wrap text in **…** for bold.
  final String body;

  /// Which built-in illustration to animate.
  final TutorialIllustration illustrationType;
}

/// Identifies the built-in illustration to render on a slide.
// Each value below maps 1:1 to a `_paint*` method on
// _TutorialIllustrationPainter (see the switch in its `paint()` override).
enum TutorialIllustration {
  none, // no illustration box is shown for this slide at all
  addNode,
  addTransition,
  setAccepting,
  setStartArrow,
  dfaVsNfa,
  epsilonTransition,
  pdaStack,
  tmTape,
  deleteMode,
  checkAnswer,
  addSuperStates,
  stateElimination,
}

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class TutorialScreen extends StatefulWidget {
  final GameLevel level;                 // the level whose tutorialSlides are shown
  final GameProgressStore progressStore;  // where completion is recorded
  final VoidCallback? onCompleted;        // fired after markCompleted(), before popping

  const TutorialScreen({
    super.key,
    required this.level,
    required this.progressStore,
    this.onCompleted,
  });

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen>
    with TickerProviderStateMixin {
  // Drives the PageView of slides; used both for swipe gestures (built-in)
  // and for the explicit prev/next buttons (via _goTo/animateToPage).
  late final PageController _pageCtrl;

  // Looping animation fed into every illustration's CustomPainter as its
  // `progress` value (0→1, repeating) — one shared controller for all
  // slides rather than restarting per-slide, so switching pages doesn't
  // reset the illustration's animation phase back to 0.
  late final AnimationController _illustrationCtrl;

  // One-shot entrance animation. NOTE: this controller is created and
  // `forward()`-ed here, but nothing in this file's build() actually
  // consumes its value (no AnimatedBuilder/Tween references it) — it's
  // effectively unused at the moment; disposed correctly regardless.
  late final AnimationController _slideEnterCtrl;

  int _currentPage = 0; // synced from PageView's onPageChanged; drives the dot indicator, back/next buttons, and progress label

  // Convenience accessor so the rest of the class can just say `_slides`
  // instead of `widget.level.tutorialSlides` everywhere.
  List<TutorialSlide> get _slides => widget.level.tutorialSlides;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();

    _illustrationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(); // loops forever for as long as this screen is alive

    _slideEnterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward(); // plays once; see note above — not currently wired to any visual
  }

  @override
  void dispose() {
    // Standard cleanup: release every controller this State created.
    _pageCtrl.dispose();
    _illustrationCtrl.dispose();
    _slideEnterCtrl.dispose();
    super.dispose();
  }

  /// Animates the PageView to [page], if it's a valid index.
  void _goTo(int page) {
    if (page < 0 || page >= _slides.length) return; // no-op past either end (also guards the Back/Next buttons' disabled states)
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  /// Called from the final slide's "GOT IT!" button: records completion,
  /// notifies the caller, then pops this screen off the navigation stack.
  Future<void> _finish() async {
    await widget.progressStore.markCompleted(widget.level.id);
    widget.onCompleted?.call();
    // `mounted` guard: the await above is an async gap, so this State could
    // have been disposed in the meantime (e.g. the user backed out some
    // other way) — popping a disposed State's context would throw.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    // Tutorial-specific accent color (distinct from e.g. puzzle-level tags),
    // used throughout this screen's chrome and passed down into every
    // illustration painter.
    final accentColor = theme.tagColor('tutorial');
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(
        backgroundColor: theme.bg,
        elevation: 0,
        leading: BackButton(
          color: theme.textMid,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.school_outlined, color: accentColor, size: 18),
            const SizedBox(width: 8),
            Text(
              widget.level.title.toUpperCase(),
              style: GoogleFonts.orbitron(
                color: theme.textLight,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: [
          // Dot indicator in the top-right
          // One dot per slide; the active slide's dot is wider (18px vs 6px)
          // and lit with the accent color, giving a "pill" look rather than
          // a plain row of identical dots.
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              children: List.generate(_slides.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? accentColor
                        : theme.textDim.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Slide area ──────────────────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _slides.length,
              // Keeps `_currentPage` (and therefore the dot indicator,
              // back/next buttons, and "GOT IT!" swap) in sync whenever the
              // user swipes — not just when they use the buttons.
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (ctx, i) => _SlidePage(
                slide: _slides[i],
                animCtrl: _illustrationCtrl,
                accentColor: accentColor,
                theme: theme,
              ),
            ),
          ),

          // ── Bottom nav bar ──────────────────────────────────────────────
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: theme.bg,
                border: Border(
                  top: BorderSide(
                    color: theme.borderMid.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Back button
                  // Faded to fully transparent (rather than removed) on the
                  // first slide, so the layout doesn't jump when it
                  // reappears — onPressed is also nulled in lockstep so it
                  // can't be tapped while invisible.
                  AnimatedOpacity(
                    opacity: _currentPage > 0 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: OutlinedButton.icon(
                      onPressed: _currentPage > 0
                          ? () => _goTo(_currentPage - 1)
                          : null,
                      icon: Icon(Icons.arrow_back_ios_new,
                          size: 14, color: theme.textMid),
                      label: Text('BACK',
                          style: GoogleFonts.orbitron(
                              fontSize: 11,
                              color: theme.textMid,
                              letterSpacing: 1.5)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.borderMid),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Progress label
                  // e.g. "3 / 7" — 1-based for display, since _currentPage is 0-based.
                  Text(
                    '${_currentPage + 1} / ${_slides.length}',
                    style: GoogleFonts.sourceCodePro(
                      color: theme.textDim,
                      fontSize: 12,
                    ),
                  ),

                  const Spacer(),

                  // Next / Got it button
                  // Same button doubles as both actions: on every slide but
                  // the last it advances the PageView; on the last slide it
                  // instead calls _finish() to record completion and pop.
                  FilledButton.icon(
                    onPressed: isLast ? _finish : () => _goTo(_currentPage + 1),
                    icon: Icon(
                      isLast ? Icons.check_circle_outline : Icons.arrow_forward_ios,
                      size: 15,
                    ),
                    label: Text(
                      isLast ? 'GOT IT!' : 'NEXT',
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      // Green "success" color on the final slide, versus the
                      // tutorial's normal accent everywhere else — visually
                      // signals "this button finishes the tutorial" rather
                      // than "this button just goes to the next slide".
                      backgroundColor: isLast
                          ? theme.accentGreen
                          : accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single slide page
// ─────────────────────────────────────────────────────────────────────────────

/// Renders one [TutorialSlide]: optional illustration box, headline, and
/// body text. Stateless — all animation state lives in the shared
/// [animCtrl] passed down from _TutorialScreenState.
class _SlidePage extends StatelessWidget {
  final TutorialSlide slide;
  final AnimationController animCtrl;
  final Color accentColor;
  final AppThemeNotifier theme;

  const _SlidePage({
    required this.slide,
    required this.animCtrl,
    required this.accentColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Scrollable so slides with long body text (or on short/landscape
    // screens) don't overflow rather than clip.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Illustration
          // Slides with TutorialIllustration.none skip this box entirely
          // (no empty placeholder), so text-only slides don't waste space.
          if (slide.illustrationType != TutorialIllustration.none)
            AnimatedBuilder(
              // Rebuilds every tick of the shared looping controller so the
              // CustomPainter below always repaints with the latest
              // `animCtrl.value` as its `progress`.
              animation: animCtrl,
              builder: (_, _) => Center(
                child: Container(
                  width: double.infinity,
                  height: 200,
                  margin: const EdgeInsets.only(bottom: 28),
                  decoration: BoxDecoration(
                    color: theme.border.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    // Clips the CustomPaint's square corners to match the
                    // container's own rounded corners (radius 1px smaller
                    // than the container's so the clip sits just inside the
                    // border stroke rather than cutting into it).
                    borderRadius: BorderRadius.circular(15),
                    child: CustomPaint(
                      painter: _TutorialIllustrationPainter(
                        type: slide.illustrationType,
                        progress: animCtrl.value,
                        accentColor: accentColor,
                        bgColor: theme.bg,
                        textColor: theme.textLight,
                        dimColor: theme.textDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Headline
          Text(
            slide.headline,
            style: GoogleFonts.orbitron(
              color: accentColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 16),

          // Body — supports **bold** via inline rich text
          _RichBody(text: slide.body, theme: theme),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mini-markdown body renderer  (**bold** → bold span)
// ─────────────────────────────────────────────────────────────────────────────

/// Renders [text] as a single Text.rich, turning every other `**`-delimited
/// segment into bold. Only supports this one marker — no italics, links,
/// etc. — by design, since tutorial body copy only ever needs to emphasize
/// a word or two.
class _RichBody extends StatelessWidget {
  final String text;
  final AppThemeNotifier theme;

  const _RichBody({required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final normal = GoogleFonts.sourceCodePro(
      color: theme.textLight,
      fontSize: 15,
      height: 1.7,
    );
    final bold = GoogleFonts.sourceCodePro(
      color: theme.textLight,
      fontSize: 15,
      height: 1.7,
      fontWeight: FontWeight.w700,
    );

    // Split by ** markers
    // Splitting on the marker itself means the text alternates: the
    // segments at even indices (0, 2, 4, …) are plain text *outside* any
    // "**", and odd indices are the text that was *between* a pair of
    // "**" markers — i.e. exactly the parts that should be bold. This only
    // works cleanly when "**" markers are properly paired in the source
    // text; an unpaired "**" would just shift which segments end up bold.
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(text: parts[i], style: i.isEven ? normal : bold));
    }

    return Text.rich(TextSpan(children: spans));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tutorial illustration painter
//
//  Each case draws an animated diagram that shows the concept being explained.
// ─────────────────────────────────────────────────────────────────────────────

/// Paints one of the built-in tutorial illustrations, selected by [type].
/// All the illustrations are drawn procedurally with Canvas primitives
/// (circles, lines, paths, TextPainter) rather than image assets, so they
/// can smoothly animate against the single looping `progress` value (0→1,
/// supplied by the shared AnimationController in _SlidePage) and always
/// match the current theme's colors.
class _TutorialIllustrationPainter extends CustomPainter {
  final TutorialIllustration type;
  final double progress; // 0→1 looping
  final Color accentColor;
  final Color bgColor;
  final Color textColor;
  final Color dimColor;

  const _TutorialIllustrationPainter({
    required this.type,
    required this.progress,
    required this.accentColor,
    required this.bgColor,
    required this.textColor,
    required this.dimColor,
  });

  // ── Common helpers ──────────────────────────────────────────────────────────

  /// Paint for a node's outline circle, or its filled background disc when
  /// [fill] is true.
  Paint _circlePaint(Color c, {bool fill = false}) => Paint()
    ..color = c
    ..strokeWidth = 2.2
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;

  /// Paint for a plain stroked line/arc, with rounded end caps so short
  /// dashes and arrow shafts don't look clipped-off square.
  Paint _linePaint(Color c, {double w = 2.0}) => Paint()
    ..color = c
    ..strokeWidth = w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Draws one automaton state: filled circle, outline, optional inner ring
  /// (accepting-state double-circle), and a centered text label.
  void _drawNode(Canvas canvas, Offset center, double r, Color border,
      Color bg, String label, {bool doubleRing = false}) {
    canvas.drawCircle(center, r, _circlePaint(bg, fill: true));
    canvas.drawCircle(center, r, _circlePaint(border));
    if (doubleRing) {
      canvas.drawCircle(center, r - 5, _circlePaint(border));
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Centers the laid-out text on `center` by offsetting by half its
    // measured width/height.
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Draws a straight arrow from just outside [from]'s node circle to just
  /// outside [to]'s, with a filled triangular arrowhead at the end.
  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color,
      {double shorten = 22}) {
    final dir = (to - from);
    final dist = dir.distance;
    if (dist < 1) return; // coincident points: nothing sensible to draw
    final unit = dir / dist;
    // Both ends are pulled in along the direction vector — `start` by a
    // fixed 22px (roughly a node's radius, so the shaft doesn't start
    // inside the source node), `end` by the caller-supplied `shorten`
    // (defaults to the same 22px, but callers mid-animation can pass 0 to
    // let the arrow's tip travel all the way to `to` while it's still
    // "growing" — see _paintAddTransition).
    final start = from + unit * 22;
    final end = to - unit * shorten;
    canvas.drawLine(start, end, _linePaint(color, w: 2.2));
    // Arrowhead
    // Small filled triangle at `end`, built from two points offset
    // perpendicular ("wing") and back along the shaft ("len") from the tip,
    // rotated to match the shaft's actual angle via atan2/cos/sin so it
    // always points the right way regardless of `from`/`to` orientation.
    const len = 10.0;
    const wing = 6.0;
    final angle = atan2(dir.dy, dir.dx);
    final tip = end;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
            tip.dx - len * cos(angle) + wing * sin(angle),
            tip.dy - len * sin(angle) - wing * cos(angle))
        ..lineTo(
            tip.dx - len * cos(angle) - wing * sin(angle),
            tip.dy - len * sin(angle) + wing * cos(angle))
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  /// Draws [text] centered at [pos] — used for both transition-symbol
  /// labels (small, near a line) and the descriptive caption under each
  /// illustration (via the `fontSize`/`color` overrides callers pass).
  void _drawLabel(Canvas canvas, Offset pos, String text,
      {double fontSize = 11, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? dimColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  // ── Illustration cases ──────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Dispatches to exactly one `_paint*` method per illustration type;
    // `none` (no illustration box rendered at all — see _SlidePage) simply
    // has nothing to draw.
    switch (type) {
      case TutorialIllustration.addNode:
        _paintAddNode(canvas, size, cx, cy);
        break;
      case TutorialIllustration.addTransition:
        _paintAddTransition(canvas, size, cx, cy);
        break;
      case TutorialIllustration.setAccepting:
        _paintSetAccepting(canvas, size, cx, cy);
        break;
      case TutorialIllustration.setStartArrow:
        _paintStartArrow(canvas, size, cx, cy);
        break;
      case TutorialIllustration.dfaVsNfa:
        _paintDfaVsNfa(canvas, size, cx, cy);
        break;
      case TutorialIllustration.epsilonTransition:
        _paintEpsilon(canvas, size, cx, cy);
        break;
      case TutorialIllustration.pdaStack:
        _paintPdaStack(canvas, size, cx, cy);
        break;
      case TutorialIllustration.tmTape:
        _paintTmTape(canvas, size, cx, cy);
        break;
      case TutorialIllustration.deleteMode:
        _paintDeleteMode(canvas, size, cx, cy);
        break;
      case TutorialIllustration.checkAnswer:
        _paintCheckAnswer(canvas, size, cx, cy);
        break;
      case TutorialIllustration.addSuperStates:
        _paintAddSuperStates(canvas, size, cx, cy);
        break;
      case TutorialIllustration.stateElimination:
        _paintStateElimination(canvas, size, cx, cy);
        break;
      case TutorialIllustration.none:
        break;
    }
  }

  // ── addNode: pulsing tap → node appears ────────────────────────────────────
  void _paintAddNode(Canvas canvas, Size size, double cx, double cy) {
    // Blinking cursor / tap indicator
    // Continuous sine pulse (independent of the node's own fade cycle
    // below) driving the ripple's opacity, so the "tap here" cue keeps
    // blinking throughout the loop.
    final tapPhase = (progress * 2 * pi);
    final tapOpacity = (0.5 + 0.5 * sin(tapPhase)).clamp(0.0, 1.0);

    // Node fades in after "tap"
    // `progress * 2 % 1.0` runs this sub-cycle twice as fast as the overall
    // loop, so the "tap → node appears → node disappears" beat repeats
    // twice per full `progress` cycle. Within one sub-cycle: fade in over
    // the first 10%, hold fully visible through 85%, then fade out over the
    // final 15% — a fast in/slow hold/fast out envelope.
    final nodeProgress = ((progress * 2) % 1.0);
    final nodeOpacity = nodeProgress < 0.1
        ? (nodeProgress / 0.1).clamp(0.0, 1.0)
        : nodeProgress > 0.85
            ? ((1.0 - nodeProgress) / 0.15).clamp(0.0, 1.0)
            : 1.0;

    // Tap ripple
    // Expands outward from 16px to 46px over each sub-cycle, tied to the
    // same `nodeProgress` clock as the node's own fade.
    final rippleRadius = 16 + nodeProgress * 30;
    canvas.drawCircle(
      Offset(cx, cy),
      rippleRadius,
      Paint()
        ..color = accentColor.withValues(alpha: tapOpacity * 0.3)
        ..style = PaintingStyle.fill,
    );

    // Node
    _drawNode(
      canvas,
      Offset(cx, cy),
      26,
      accentColor.withValues(alpha: nodeOpacity),
      bgColor.withValues(alpha: nodeOpacity),
      'q₀',
    );

    // "Double-tap" label
    _drawLabel(
      canvas,
      Offset(cx, cy + 55),
      'Double-tap on empty space to add a state',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  // ── addTransition: node → node with animated arrow drawing ─────────────────
  void _paintAddTransition(Canvas canvas, Size size, double cx, double cy) {
    final left = Offset(cx - 70, cy);
    final right = Offset(cx + 70, cy);

    _drawNode(canvas, left, 24, dimColor, bgColor, 'A');
    _drawNode(canvas, right, 24, dimColor, bgColor, 'B');

    // Arrow animates from left to right
    // `t` reaches 1.0 at 2/3 of the way through the loop (progress ≈ 0.667)
    // and then holds there for the remainder, so the "fully drawn" state
    // (with its label) is visible for the last third of each cycle before
    // looping back to a freshly-retracted arrow.
    final t = (progress * 1.5).clamp(0.0, 1.0);
    final arrowEnd = Offset(left.dx + (right.dx - left.dx) * t, cy);
    if (t > 0.05) {
      // While still growing (t < 1.0), pass shorten: 0 so the drawn tip
      // actually reaches `arrowEnd` instead of stopping short as if
      // approaching a node it hasn't reached yet; once fully grown, revert
      // to the normal 22px pull-back so the arrowhead sits just outside B's
      // circle rather than overlapping it.
      _drawArrow(canvas, left, arrowEnd, accentColor,
          shorten: t >= 1.0 ? 22 : 0);
    }

    // Label appears when arrow fully drawn
    if (t >= 1.0) {
      _drawLabel(canvas, Offset(cx, cy - 22), 'a', color: accentColor);
    }

    _drawLabel(
      canvas,
      Offset(cx, cy + 55),
      'Hold Shift + drag between states to draw a transition',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  // ── setAccepting: single tap on node → double ring ─────────────────────────
  void _paintSetAccepting(Canvas canvas, Size size, double cx, double cy) {
    final phase = (progress * 2 * pi);
    // Pulse: node bounces
    // Radius gently oscillates ±6% around 26px throughout the whole loop,
    // whether or not the node is currently "accepting" — a continuous
    // idle-breathing effect layered under the before/after state change.
    final scale = 1.0 + 0.06 * sin(phase);
    final r = 26.0 * scale;

    // Before → after transition at midpoint of animation
    // First half of the loop shows the plain (non-accepting) state; second
    // half shows it after the toggle — a hard cut, not a cross-fade.
    final isAccepting = progress > 0.5;

    _drawNode(
      canvas,
      Offset(cx, cy - 10),
      r,
      isAccepting ? accentColor : dimColor,
      bgColor,
      'q₁',
      doubleRing: isAccepting,
    );

    if (isAccepting) {
      // Glow
      // Soft halo just outside the node, itself pulsing in sync with
      // `phase` so the glow and the bounce read as one coordinated pulse.
      canvas.drawCircle(
        Offset(cx, cy - 10),
        r + 6,
        Paint()
          ..color = accentColor.withValues(alpha: 0.15 + 0.1 * sin(phase))
          ..style = PaintingStyle.fill,
      );
    }

    _drawLabel(
      canvas,
      Offset(cx, cy + 50),
      isAccepting
          ? 'Double ring = accepting state ✓'
          : 'Tap a state then toggle "Accept" to mark it',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  // ── startArrow: animating start arrow pointing at node ─────────────────────
  void _paintStartArrow(Canvas canvas, Size size, double cx, double cy) {
    final node = Offset(cx + 20, cy - 10);
    _drawNode(canvas, node, 26, accentColor, bgColor, 'q₀');

    // Arrow swings in from left
    // `(1 - (1-progress)^2)` is a standard ease-out curve (fast start,
    // slowing as it approaches 1) mapped onto an 0.8π sweep, starting at
    // angle -π (arrow pointing in from directly left) and swinging toward
    // roughly -0.2π (down and to the left) as `progress` runs 0→1.
    final angle = -pi + (pi * 0.8) * (1 - (1 - progress) * (1 - progress));
    final arrowLen = 55.0;
    // Arrow's tail sits out along `angle` from the node, at a distance of
    // the shaft length plus the node's own radius (26) so it starts clear
    // of the node's edge.
    final arrowStart = Offset(
      node.dx + cos(angle) * (arrowLen + 26),
      node.dy + sin(angle) * (arrowLen + 26),
    );

    _drawArrow(canvas, arrowStart, node, accentColor);

    _drawLabel(
      canvas,
      Offset(cx, cy + 52),
      'Drag the start arrow to set the initial state',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  // ── dfaVsNfa: two columns showing DFA (one path) vs NFA (forking paths) ────
  void _paintDfaVsNfa(Canvas canvas, Size size, double cx, double cy) {
    const Color dfaColor = Color(0xFF4FC3F7); // blue
    const Color nfaColor = Color(0xFFFFB74D); // amber

    // DFA side (left)
    // Positions are expressed as fractions of `cx` (half the canvas width)
    // rather than `size.width` directly — since cx == size.width / 2, e.g.
    // `cx * 0.35` places this node at 17.5% of the full width.
    final d0 = Offset(cx * 0.35, cy - 20);
    final d1 = Offset(cx * 0.80, cy - 20);
    _drawNode(canvas, d0, 20, dfaColor, bgColor, 'A');
    _drawNode(canvas, d1, 20, dfaColor, bgColor, 'B');
    _drawArrow(canvas, d0, d1, dfaColor);
    _drawLabel(canvas, Offset(cx * 0.58, cy - 45), 'a', color: dfaColor);
    _drawLabel(canvas, Offset(cx * 0.58, cy + 10), 'DFA', color: dfaColor);

    // NFA side (right): one input, two possible next states
    final n0 = Offset(cx * 1.2, cy - 20);
    final n1 = Offset(cx * 1.55, cy - 45);
    final n2 = Offset(cx * 1.55, cy + 5);

    // Both NFA branches blink together (rather than independently) to read
    // as "either path is simultaneously possible", emphasizing the
    // nondeterminism the illustration is explaining.
    final arrowOpacity = (0.5 + 0.5 * sin(progress * 2 * pi)).clamp(0.0, 1.0);

    _drawNode(canvas, n0, 20, nfaColor, bgColor, 'A');
    _drawNode(canvas, n1, 20, nfaColor.withValues(alpha: arrowOpacity), bgColor, 'B');
    _drawNode(canvas, n2, 20, nfaColor.withValues(alpha: arrowOpacity), bgColor, 'C');
    _drawArrow(canvas, n0, n1, nfaColor.withValues(alpha: arrowOpacity));
    _drawArrow(canvas, n0, n2, nfaColor.withValues(alpha: arrowOpacity));
    _drawLabel(canvas, Offset(cx * 1.37, cy - 55), 'a', color: nfaColor);
    _drawLabel(canvas, Offset(cx * 1.37, cy - 3), 'a', color: nfaColor);
    _drawLabel(canvas, Offset(cx * 1.37, cy + 24), 'NFA', color: nfaColor);

    // Divider
    // Faint vertical rule separating the DFA and NFA halves of the illustration.
    canvas.drawLine(
      Offset(cx, cy - 80),
      Offset(cx, cy + 60),
      _linePaint(dimColor.withValues(alpha: 0.25)),
    );
  }

  // ── epsilonTransition: ~-transition (free jump) ────────────────────────────
  void _paintEpsilon(Canvas canvas, Size size, double cx, double cy) {
    final left = Offset(cx - 70, cy);
    final right = Offset(cx + 70, cy);

    _drawNode(canvas, left, 24, dimColor, bgColor, 'A');
    _drawNode(canvas, right, 24, accentColor, bgColor, 'B', doubleRing: true);

    // Dashed arc for ~
    // A single cubic Bezier bowing upward between the two nodes (both
    // control points sit at the same point above the midpoint, giving a
    // smooth symmetric arc rather than an S-curve).
    final path = Path()
      ..moveTo(left.dx + 24, cy)
      ..cubicTo(cx, cy - 50, cx, cy - 50, right.dx - 24, cy);

    final dashPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Animate dash offset
    // Scrolling the dash pattern along the arc gives the epsilon-transition
    // a "flowing"/marching-ants look, reinforcing that it's a free,
    // ongoing jump rather than a static line.
    final dashOffset = progress * 20;
    _drawDashedPath(canvas, path, dashPaint, dashLen: 8, gapLen: 5, offset: dashOffset);

    _drawLabel(canvas, Offset(cx, cy - 42), '~  (free jump)', color: accentColor);

    _drawLabel(
      canvas,
      Offset(cx, cy + 48),
      'No input consumed — machine can jump for free',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  /// Strokes [path] as a dash-gap-dash-gap… pattern instead of solid,
  /// scrolling the whole pattern along the path by [offset] px (used to
  /// animate a "marching ants" effect — see _paintEpsilon/_paintAddSuperStates).
  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {required double dashLen, required double gapLen, double offset = 0}) {
    // A Path can be made of multiple disjoint contours (e.g. moveTo called
    // more than once); computeMetrics() yields one PathMetric per contour,
    // and each is dashed independently.
    for (final metric in path.computeMetrics()) {
      // `offset % (dashLen + gapLen)` wraps the scroll position back into a
      // single dash+gap period, and `draw` starts true/false depending on
      // whether that wrapped position falls within the dash portion — this
      // is what makes the pattern appear to continuously scroll as `offset`
      // increases across frames, rather than always restarting at a dash.
      double d = offset % (dashLen + gapLen);
      bool draw = d < dashLen;
      while (d < metric.length) {
        final next = (d + (draw ? dashLen : gapLen)).clamp(0.0, metric.length);
        if (draw) {
          // extractPath(d, next) pulls out just this sub-segment of the
          // contour so only the "dash" portions actually get painted; gaps
          // are skipped by simply not drawing anything for that span.
          canvas.drawPath(metric.extractPath(d, next), paint);
        }
        d = next;
        draw = !draw; // alternate dash/gap for the next segment
      }
    }
  }

  // ── pdaStack: animated stack push/pop ──────────────────────────────────────
  void _paintPdaStack(Canvas canvas, Size size, double cx, double cy) {
    // Stack box
    final stackLeft = cx - 25;
    const stackBottom = 150.0;
    const cellH = 28.0;
    const cellW = 50.0;

    // Outer container: a faint 4-cell-tall box representing the stack's
    // maximum drawn capacity (not a hard limit on the real PDA stack, just
    // how many cells this illustration has room to show).
    canvas.drawRect(
      Rect.fromLTWH(stackLeft, stackBottom - cellH * 4, cellW, cellH * 4),
      Paint()
        ..color = dimColor.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(stackLeft, stackBottom - cellH * 4, cellW, cellH * 4),
      _linePaint(dimColor.withValues(alpha: 0.4)),
    );

    // Number of items on stack oscillates
    // `sin(progress * 2π)` swings between -1 and 1; scaling by 1.5 and
    // taking abs() gives a 0..1.5 wave, rounding yields 0, 1, or 2, and the
    // final clamp(1, 3) floors it at 1 (so the stack is never shown fully
    // empty) while still allowing the underlying value up to 3 in principle.
    final itemCount = (1 + (sin(progress * 2 * pi) * 1.5).abs().round()).clamp(1, 3);

    // Colors/labels fade and change per depth, so the bottom-most visible
    // item (index 0, drawn last/on top per the loop below) reads as the
    // most prominent — reinforcing "top of stack" as the active element.
    final stackColors = [
      accentColor,
      accentColor.withValues(alpha: 0.7),
      accentColor.withValues(alpha: 0.5),
    ];
    final stackLabels = ['a', 'a', 'Z']; // 'Z' = conventional bottom-of-stack marker

    for (int i = 0; i < itemCount; i++) {
      final top = stackBottom - (i + 1) * cellH; // stacks upward from the bottom of the box
      canvas.drawRect(
        Rect.fromLTWH(stackLeft + 2, top + 2, cellW - 4, cellH - 4),
        Paint()
          ..color = stackColors[i].withValues(alpha: 0.3)
          ..style = PaintingStyle.fill,
      );
      _drawLabel(
        canvas,
        Offset(stackLeft + cellW / 2, top + cellH / 2),
        stackLabels[i],
        color: stackColors[i],
        fontSize: 13,
      );
    }

    // Labels
    _drawLabel(canvas, Offset(stackLeft + cellW / 2, stackBottom - cellH * 4 - 14), 'STACK',
        color: dimColor, fontSize: 10);
    _drawLabel(canvas, Offset(cx, stackBottom + 20),
        'PDA adds a stack — push/pop symbols to count',
        color: dimColor.withValues(alpha: 0.85), fontSize: 10);
  }

  // ── tmTape: animated read/write head scanning a tape ──────────────────────
  void _paintTmTape(Canvas canvas, Size size, double cx, double cy) {
    const cellW = 36.0;
    const cellH = 36.0;
    const cells = 5;
    final tapeLeft = cx - (cells / 2) * cellW; // centers the 5-cell tape horizontally
    const tapeTop = 65.0;
    final symbols = ['a', 'a', 'b', 'X', '_']; // '_' conventionally denotes a blank tape cell

    // Animated head position (0→4)
    // Sweeps the head across all 5 cells once per full `progress` loop,
    // then wraps back to cell 0 (`% cells`) rather than bouncing back and forth.
    final headPos = ((progress * cells) % cells).floor();

    for (int i = 0; i < cells; i++) {
      final x = tapeLeft + i * cellW;
      final isHead = i == headPos;

      canvas.drawRect(
        Rect.fromLTWH(x, tapeTop, cellW, cellH),
        Paint()
          ..color = isHead
              ? accentColor.withValues(alpha: 0.2)
              : dimColor.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, tapeTop, cellW, cellH),
        _linePaint(
          isHead ? accentColor : dimColor.withValues(alpha: 0.35),
          w: isHead ? 2 : 1,
        ),
      );

      _drawLabel(
        canvas,
        Offset(x + cellW / 2, tapeTop + cellH / 2),
        symbols[i],
        color: isHead ? accentColor : textColor,
        fontSize: 15,
      );
    }

    // Read/write head indicator (triangle above)
    // Small downward-pointing triangle hovering above whichever cell is
    // currently the head, tracking `headPos` each frame.
    final headX = tapeLeft + headPos * cellW + cellW / 2;
    canvas.drawPath(
      Path()
        ..moveTo(headX, tapeTop - 6)
        ..lineTo(headX - 8, tapeTop - 20)
        ..lineTo(headX + 8, tapeTop - 20)
        ..close(),
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill,
    );
    _drawLabel(canvas, Offset(headX, tapeTop - 30), 'HEAD', color: accentColor, fontSize: 9);

    _drawLabel(canvas, Offset(cx, tapeTop + cellH + 20),
        'TM reads and writes a tape, moving left or right',
        color: dimColor.withValues(alpha: 0.85), fontSize: 10);
  }

  // ── deleteMode: state fades out with X ────────────────────────────────────
  void _paintDeleteMode(Canvas canvas, Size size, double cx, double cy) {
    // Node stays fully opaque through the first half of the loop, then
    // fades to nothing over the second half — the "deletion" itself.
    final opacity = progress < 0.5
        ? 1.0
        : (1.0 - (progress - 0.5) * 2).clamp(0.0, 1.0);

    const Color deleteColor = Color(0xFFEF5350);

    _drawNode(canvas, Offset(cx, cy - 10), 28,
        deleteColor.withValues(alpha: opacity), bgColor.withValues(alpha: opacity), 'q₀');

    // X mark
    // Appears partway through the fade (after 30% progress) and itself
    // fades in quickly over the next 20%, then continues to fade out
    // alongside the node (`* opacity`) so it never outlives the state
    // it's marking for deletion.
    if (progress > 0.3) {
      final x = cx;
      final y = cy - 10;
      const r = 14.0;
      final xOpacity = ((progress - 0.3) / 0.2).clamp(0.0, 1.0);
      final xPaint = _linePaint(deleteColor.withValues(alpha: xOpacity * opacity), w: 3);
      canvas.drawLine(
          Offset(x - r, y - r), Offset(x + r, y + r), xPaint);
      canvas.drawLine(
          Offset(x + r, y - r), Offset(x - r, y + r), xPaint);
    }

    _drawLabel(
      canvas,
      Offset(cx, cy + 46),
      'Use the trash-can toolbar button to enter delete mode',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  // ── checkAnswer: check button pulses green ─────────────────────────────────
  void _paintCheckAnswer(Canvas canvas, Size size, double cx, double cy) {
    final pulse = 0.5 + 0.5 * sin(progress * 2 * pi);
    const Color green = Color(0xFF66BB6A);

    // Button outline
    // Draws a mock "Check" button (rounded rect + checkmark glyph) that
    // gently pulses in fill/border opacity, inviting the eye toward it the
    // same way a real UI highlight might.
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 10), width: 130, height: 44),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = green.withValues(alpha: 0.15 + pulse * 0.1)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = green.withValues(alpha: 0.6 + pulse * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Check icon
    // A hand-drawn checkmark: short down-stroke then long up-stroke,
    // positioned to sit just left of the "Check" label below.
    final checkPaint = _linePaint(green, w: 3);
    canvas.drawLine(Offset(cx - 24, cy - 10), Offset(cx - 10, cy + 5), checkPaint);
    canvas.drawLine(Offset(cx - 10, cy + 5), Offset(cx + 22, cy - 22), checkPaint);

    // "Check" label
    // Leading spaces in the label text nudge it rightward so it doesn't
    // overlap the checkmark glyph drawn just to its left.
    _drawLabel(canvas, Offset(cx + 10, cy - 10), '   Check',
        color: green, fontSize: 15);

    _drawLabel(
      canvas,
      Offset(cx, cy + 42),
      'Tap "Check" to submit your automaton for grading',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  // ── addSuperStates: super-start & super-accept fade in around a DFA ───────
  //
  //  Illustrates step 1 of DFA→regex state elimination: before removing any
  //  state you first wrap the automaton with a fresh super-start S (~ into
  //  the old start) and a fresh super-accept F (~ out of the old accept
  //  state). Only S and F keep their start/accept status from then on, which
  //  frees every other state — including the old accept state — to be
  //  eliminated in step 2.
  void _paintAddSuperStates(Canvas canvas, Size size, double cx, double cy) {
    final q0 = Offset(cx - 35, cy - 5);
    final q1 = Offset(cx + 35, cy - 5);
    final superStart = Offset(cx - 95, cy - 5);
    final superAccept = Offset(cx + 95, cy - 5);

    // Original DFA edge.
    _drawArrow(canvas, q0, q1, dimColor);
    _drawLabel(canvas, Offset(cx, cy - 28), 'a', color: dimColor);

    // Two separate phase windows (both length 0.35, staggered so the
    // super-start appears first and the super-accept follows) drive when S
    // and F each fade in, each clamped to 0..1 so they hold steady once
    // fully visible.
    final startT = ((progress - 0.15) / 0.35).clamp(0.0, 1.0);
    final acceptT = ((progress - 0.55) / 0.35).clamp(0.0, 1.0);

    // q1 hands its acceptance off to the super-accept once F appears.
    // Once acceptT passes the halfway point of its own fade-in, q1's double
    // ring is dropped — visually "handing off" accepting status to F, which
    // only gets its own double ring right as q1 loses it (see the
    // `doubleRing: acceptT > 0.5` below).
    final q1Accepting = acceptT < 0.5;

    _drawNode(canvas, q0, 20, accentColor, bgColor, 'q0');
    _drawNode(canvas, q1, 20, q1Accepting ? accentColor : dimColor, bgColor,
        'q1', doubleRing: q1Accepting);

    if (startT > 0.0) {
      _drawNode(
        canvas,
        superStart,
        16,
        accentColor.withValues(alpha: startT),
        bgColor.withValues(alpha: startT),
        'S',
      );

      // Start arrow into S — S is now the start state, so it needs the same
      // "arrow from nowhere" marker every start state gets.
      // Small filled triangle + short shaft, hand-built here rather than
      // reusing _drawArrow since this represents the *start* marker (which
      // has no source node) rather than a transition between two states.
      final tickColor = accentColor.withValues(alpha: startT);
      final tickTip = Offset(superStart.dx - 16, superStart.dy);
      final tickTail = Offset(superStart.dx - 34, superStart.dy);
      canvas.drawLine(tickTail, tickTip, _linePaint(tickColor, w: 2.2));
      const tickLen = 8.0;
      const tickWing = 5.0;
      canvas.drawPath(
        Path()
          ..moveTo(tickTip.dx, tickTip.dy)
          ..lineTo(tickTip.dx - tickLen, tickTip.dy - tickWing)
          ..lineTo(tickTip.dx - tickLen, tickTip.dy + tickWing)
          ..close(),
        Paint()
          ..color = tickColor
          ..style = PaintingStyle.fill,
      );

      // Dashed ~-edge from S into the old start state q0, scrolling in sync
      // with the overall `progress` clock (same marching-ants technique as
      // _paintEpsilon).
      _drawDashedPath(
        canvas,
        Path()
          ..moveTo(superStart.dx + 16, superStart.dy)
          ..lineTo(q0.dx - 20, q0.dy),
        Paint()
          ..color = accentColor.withValues(alpha: startT * 0.9)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
        dashLen: 6,
        gapLen: 4,
        offset: progress * 24,
      );
      if (startT > 0.4) {
        _drawLabel(
          canvas,
          Offset((superStart.dx + q0.dx) / 2, superStart.dy - 16),
          '~',
          color: accentColor.withValues(alpha: startT),
        );
      }
    }

    if (acceptT > 0.0) {
      _drawNode(
        canvas,
        superAccept,
        16,
        accentColor.withValues(alpha: acceptT),
        bgColor.withValues(alpha: acceptT),
        'F',
        doubleRing: acceptT > 0.5, // gains its double ring right as q1 loses its own (see q1Accepting above)
      );
      // Dashed ~-edge from the old accept state q1 out to the new
      // super-accept F, mirroring the S/~/q0 edge above.
      _drawDashedPath(
        canvas,
        Path()
          ..moveTo(q1.dx + 20, q1.dy)
          ..lineTo(superAccept.dx - 16, superAccept.dy),
        Paint()
          ..color = accentColor.withValues(alpha: acceptT * 0.9)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
        dashLen: 6,
        gapLen: 4,
        offset: progress * 24,
      );
      if (acceptT > 0.4) {
        _drawLabel(
          canvas,
          Offset((q1.dx + superAccept.dx) / 2, superAccept.dy - 16),
          '~',
          color: accentColor.withValues(alpha: acceptT),
        );
      }
    }

    _drawLabel(
      canvas,
      Offset(cx, cy + 55),
      'Add a super-start S and super-accept F, linked by ~-edges',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  // ── stateElimination: remove an inner state, merge into one regex edge ────
  //
  //  Illustrates step 2: to eliminate B, fold its incoming edge (A→B),
  //  self-loop (B→B), and outgoing edge (B→C) into a single new A→C edge
  //  labelled with the combined regex. Repeating this for every remaining
  //  inner state leaves just the super-start/super-accept edge — that
  //  label is the answer.
  void _paintStateElimination(Canvas canvas, Size size, double cx, double cy) {
    final a = Offset(cx - 90, cy - 10);
    final b = Offset(cx, cy - 10);
    final c = Offset(cx + 90, cy - 10);

    // Phase timing: B and its edges fade out, then a merged A→C edge fades in.
    final removeT = ((progress - 0.35) / 0.25).clamp(0.0, 1.0);
    final mergeT = ((progress - 0.55) / 0.35).clamp(0.0, 1.0);
    final bOpacity = 1.0 - removeT; // B (and everything attached to it) fades in lockstep with removeT rising

    _drawNode(canvas, a, 22, accentColor, bgColor, 'A');
    _drawNode(canvas, c, 22, accentColor, bgColor, 'C', doubleRing: true);

    if (bOpacity > 0.01) {
      _drawNode(canvas, b, 20, dimColor.withValues(alpha: bOpacity),
          bgColor.withValues(alpha: bOpacity), 'B');

      _drawArrow(canvas, a, b, dimColor.withValues(alpha: bOpacity));
      _drawLabel(canvas, Offset((a.dx + b.dx) / 2, cy - 34), 'a',
          color: dimColor.withValues(alpha: bOpacity));

      _drawArrow(canvas, b, c, dimColor.withValues(alpha: bOpacity));
      _drawLabel(canvas, Offset((b.dx + c.dx) / 2, cy - 34), 'c',
          color: dimColor.withValues(alpha: bOpacity));

      // Self-loop on B: a true circle tangent to the node's top edge, with
      // a small gap facing straight down into B and an arrowhead at that
      // gap — so it reads as "leaves B, loops around, re-enters B" instead
      // of a disconnected floating oval.
      const loopRadius = 16.0;
      final loopCenter = Offset(b.dx, b.dy - 20 - loopRadius);
      const gapAngle = 0.55;
      // Starting the sweep at the bottom of the circle (π/2, since
      // Flutter's angle convention has positive angles sweeping clockwise
      // from the positive x-axis) plus gapAngle, and sweeping almost all
      // the way around (2π minus the gap on both sides), leaves the small
      // gap centered at the bottom — directly facing B.
      final loopStart = pi / 2 + gapAngle;
      final loopSweep = 2 * pi - gapAngle * 2;
      canvas.drawArc(
        Rect.fromCircle(center: loopCenter, radius: loopRadius),
        loopStart,
        loopSweep,
        false, // don't connect the arc back to the circle's center (useCenter)
        _linePaint(dimColor.withValues(alpha: bOpacity)),
      );

      // Arrowhead pointing straight down into B, centred in the gap.
      final loopTip = Offset(loopCenter.dx, loopCenter.dy + loopRadius);
      const tipLen = 8.0;
      const tipWing = 5.0;
      canvas.drawPath(
        Path()
          ..moveTo(loopTip.dx, loopTip.dy)
          ..lineTo(loopTip.dx - tipWing, loopTip.dy - tipLen)
          ..lineTo(loopTip.dx + tipWing, loopTip.dy - tipLen)
          ..close(),
        Paint()
          ..color = dimColor.withValues(alpha: bOpacity)
          ..style = PaintingStyle.fill,
      );

      _drawLabel(
        canvas,
        Offset(loopCenter.dx, loopCenter.dy - loopRadius - 12),
        'b',
        color: dimColor.withValues(alpha: bOpacity),
        fontSize: 10,
      );

      // X mark once removal begins.
      // Fades in over the first 30% of the removal window, additionally
      // scaled by bOpacity so the X never appears more solid than the B
      // node it's marking (both reach zero together as B fully disappears).
      if (removeT > 0.15) {
        final xOpacity = ((removeT - 0.15) / 0.3).clamp(0.0, 1.0) * bOpacity;
        final xPaint = _linePaint(
            const Color(0xFFEF5350).withValues(alpha: xOpacity), w: 3);
        const r = 13.0;
        canvas.drawLine(
            Offset(b.dx - r, b.dy - r), Offset(b.dx + r, b.dy + r), xPaint);
        canvas.drawLine(
            Offset(b.dx + r, b.dy - r), Offset(b.dx - r, b.dy + r), xPaint);
      }
    }

    // New direct A → C edge with the merged regex label, curving underneath.
    if (mergeT > 0.0) {
      // Endpoints sit just below-and-outward from A and C's circles (rather
      // than their exact centres), and the curve bows downward through a
      // control point below the midpoint — keeping this new edge visually
      // distinct from (and passing under) the original A-B-C edges above.
      final p0 = Offset(a.dx + 14, a.dy + 16);
      final p2 = Offset(c.dx - 14, c.dy + 16);
      final control = Offset(cx, cy + 50);

      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..quadraticBezierTo(control.dx, control.dy, p2.dx, p2.dy);
      canvas.drawPath(
          path, _linePaint(accentColor.withValues(alpha: mergeT), w: 2.2));

      // Arrowhead, aligned to the curve's tangent at its end point.
      // For a quadratic Bezier, the tangent direction at the very end point
      // is exactly the direction from the control point to that end point —
      // hence using `control` (not `p0`) as the "from" reference for the
      // angle, rather than reusing the generic straight-line _drawArrow.
      final angle = atan2(p2.dy - control.dy, p2.dx - control.dx);
      const len = 10.0;
      const wing = 6.0;
      canvas.drawPath(
        Path()
          ..moveTo(p2.dx, p2.dy)
          ..lineTo(p2.dx - len * cos(angle) + wing * sin(angle),
              p2.dy - len * sin(angle) - wing * cos(angle))
          ..lineTo(p2.dx - len * cos(angle) - wing * sin(angle),
              p2.dy - len * sin(angle) + wing * cos(angle))
          ..close(),
        Paint()
          ..color = accentColor.withValues(alpha: mergeT)
          ..style = PaintingStyle.fill,
      );

      _drawLabel(canvas, Offset(cx, cy + 66), 'ab*c',
          color: accentColor.withValues(alpha: mergeT), fontSize: 13);
    }

    _drawLabel(
      canvas,
      Offset(cx, cy + 85),
      'Eliminate B — merge its in/out/self-loop edges into one label',
      fontSize: 10,
      color: dimColor.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_TutorialIllustrationPainter old) =>
      // `progress` (fed a fresh AnimationController value every tick) is the
      // only field that ever actually changes between rebuilds of this
      // painter, so it's the only one worth comparing.
      old.progress != progress;
}