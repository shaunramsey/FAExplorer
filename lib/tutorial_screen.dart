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

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'game_data.dart';
import 'game_level.dart';
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
enum TutorialIllustration {
  none,
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
}

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class TutorialScreen extends StatefulWidget {
  final GameLevel level;
  final GameProgressStore progressStore;
  final VoidCallback? onCompleted;

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
  late final PageController _pageCtrl;
  late final AnimationController _illustrationCtrl;
  late final AnimationController _slideEnterCtrl;
  int _currentPage = 0;

  List<TutorialSlide> get _slides => widget.level.tutorialSlides;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();

    _illustrationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _slideEnterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _illustrationCtrl.dispose();
    _slideEnterCtrl.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page >= _slides.length) return;
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    await widget.progressStore.markCompleted(widget.level.id);
    widget.onCompleted?.call();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
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
                        : theme.textDim.withOpacity(0.4),
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
                    color: theme.borderMid.withOpacity(0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Back button
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
                  Text(
                    '${_currentPage + 1} / ${_slides.length}',
                    style: GoogleFonts.sourceCodePro(
                      color: theme.textDim,
                      fontSize: 12,
                    ),
                  ),

                  const Spacer(),

                  // Next / Got it button
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Illustration
          if (slide.illustrationType != TutorialIllustration.none)
            AnimatedBuilder(
              animation: animCtrl,
              builder: (_, _) => Center(
                child: Container(
                  width: double.infinity,
                  height: 200,
                  margin: const EdgeInsets.only(bottom: 28),
                  decoration: BoxDecoration(
                    color: theme.border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accentColor.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
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

  Paint _circlePaint(Color c, {bool fill = false}) => Paint()
    ..color = c
    ..strokeWidth = 2.2
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;

  Paint _linePaint(Color c, {double w = 2.0}) => Paint()
    ..color = c
    ..strokeWidth = w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

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
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color,
      {double shorten = 22}) {
    final dir = (to - from);
    final dist = dir.distance;
    if (dist < 1) return;
    final unit = dir / dist;
    final start = from + unit * 22;
    final end = to - unit * shorten;
    canvas.drawLine(start, end, _linePaint(color, w: 2.2));
    // Arrowhead
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
      case TutorialIllustration.none:
        break;
    }
  }

  // ── addNode: pulsing tap → node appears ────────────────────────────────────
  void _paintAddNode(Canvas canvas, Size size, double cx, double cy) {
    // Blinking cursor / tap indicator
    final tapPhase = (progress * 2 * pi);
    final tapOpacity = (0.5 + 0.5 * sin(tapPhase)).clamp(0.0, 1.0);

    // Node fades in after "tap"
    final nodeProgress = ((progress * 2) % 1.0);
    final nodeOpacity = nodeProgress < 0.1
        ? (nodeProgress / 0.1).clamp(0.0, 1.0)
        : nodeProgress > 0.85
            ? ((1.0 - nodeProgress) / 0.15).clamp(0.0, 1.0)
            : 1.0;

    // Tap ripple
    final rippleRadius = 16 + nodeProgress * 30;
    canvas.drawCircle(
      Offset(cx, cy),
      rippleRadius,
      Paint()
        ..color = accentColor.withOpacity(tapOpacity * 0.3)
        ..style = PaintingStyle.fill,
    );

    // Node
    _drawNode(
      canvas,
      Offset(cx, cy),
      26,
      accentColor.withOpacity(nodeOpacity),
      bgColor.withOpacity(nodeOpacity),
      'q₀',
    );

    // "Double-tap" label
    _drawLabel(
      canvas,
      Offset(cx, cy + 55),
      'Double-tap on empty space to add a state',
      fontSize: 10,
      color: dimColor.withOpacity(0.85),
    );
  }

  // ── addTransition: node → node with animated arrow drawing ─────────────────
  void _paintAddTransition(Canvas canvas, Size size, double cx, double cy) {
    final left = Offset(cx - 70, cy);
    final right = Offset(cx + 70, cy);

    _drawNode(canvas, left, 24, dimColor, bgColor, 'A');
    _drawNode(canvas, right, 24, dimColor, bgColor, 'B');

    // Arrow animates from left to right
    final t = (progress * 1.5).clamp(0.0, 1.0);
    final arrowEnd = Offset(left.dx + (right.dx - left.dx) * t, cy);
    if (t > 0.05) {
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
      color: dimColor.withOpacity(0.85),
    );
  }

  // ── setAccepting: single tap on node → double ring ─────────────────────────
  void _paintSetAccepting(Canvas canvas, Size size, double cx, double cy) {
    final phase = (progress * 2 * pi);
    // Pulse: node bounces
    final scale = 1.0 + 0.06 * sin(phase);
    final r = 26.0 * scale;

    // Before → after transition at midpoint of animation
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
      canvas.drawCircle(
        Offset(cx, cy - 10),
        r + 6,
        Paint()
          ..color = accentColor.withOpacity(0.15 + 0.1 * sin(phase))
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
      color: dimColor.withOpacity(0.85),
    );
  }

  // ── startArrow: animating start arrow pointing at node ─────────────────────
  void _paintStartArrow(Canvas canvas, Size size, double cx, double cy) {
    final node = Offset(cx + 20, cy - 10);
    _drawNode(canvas, node, 26, accentColor, bgColor, 'q₀');

    // Arrow swings in from left
    final angle = -pi + (pi * 0.8) * (1 - (1 - progress) * (1 - progress));
    final arrowLen = 55.0;
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
      color: dimColor.withOpacity(0.85),
    );
  }

  // ── dfaVsNfa: two columns showing DFA (one path) vs NFA (forking paths) ────
  void _paintDfaVsNfa(Canvas canvas, Size size, double cx, double cy) {
    const Color dfaColor = Color(0xFF4FC3F7); // blue
    const Color nfaColor = Color(0xFFFFB74D); // amber

    // DFA side (left)
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

    final arrowOpacity = (0.5 + 0.5 * sin(progress * 2 * pi)).clamp(0.0, 1.0);

    _drawNode(canvas, n0, 20, nfaColor, bgColor, 'A');
    _drawNode(canvas, n1, 20, nfaColor.withOpacity(arrowOpacity), bgColor, 'B');
    _drawNode(canvas, n2, 20, nfaColor.withOpacity(arrowOpacity), bgColor, 'C');
    _drawArrow(canvas, n0, n1, nfaColor.withOpacity(arrowOpacity));
    _drawArrow(canvas, n0, n2, nfaColor.withOpacity(arrowOpacity));
    _drawLabel(canvas, Offset(cx * 1.37, cy - 55), 'a', color: nfaColor);
    _drawLabel(canvas, Offset(cx * 1.37, cy - 3), 'a', color: nfaColor);
    _drawLabel(canvas, Offset(cx * 1.37, cy + 24), 'NFA', color: nfaColor);

    // Divider
    canvas.drawLine(
      Offset(cx, cy - 80),
      Offset(cx, cy + 60),
      _linePaint(dimColor.withOpacity(0.25)),
    );
  }

  // ── epsilonTransition: ε-transition (free jump) ────────────────────────────
  void _paintEpsilon(Canvas canvas, Size size, double cx, double cy) {
    final left = Offset(cx - 70, cy);
    final right = Offset(cx + 70, cy);

    _drawNode(canvas, left, 24, dimColor, bgColor, 'A');
    _drawNode(canvas, right, 24, accentColor, bgColor, 'B', doubleRing: true);

    // Dashed arc for ε
    final path = Path()
      ..moveTo(left.dx + 24, cy)
      ..cubicTo(cx, cy - 50, cx, cy - 50, right.dx - 24, cy);

    final dashPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Animate dash offset
    final dashOffset = progress * 20;
    _drawDashedPath(canvas, path, dashPaint, dashLen: 8, gapLen: 5, offset: dashOffset);

    _drawLabel(canvas, Offset(cx, cy - 42), 'ε  (free jump)', color: accentColor);

    _drawLabel(
      canvas,
      Offset(cx, cy + 48),
      'No input consumed — machine can jump for free',
      fontSize: 10,
      color: dimColor.withOpacity(0.85),
    );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {required double dashLen, required double gapLen, double offset = 0}) {
    for (final metric in path.computeMetrics()) {
      double d = offset % (dashLen + gapLen);
      bool draw = d < dashLen;
      while (d < metric.length) {
        final next = (d + (draw ? dashLen : gapLen)).clamp(0.0, metric.length);
        if (draw) {
          canvas.drawPath(metric.extractPath(d, next), paint);
        }
        d = next;
        draw = !draw;
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

    canvas.drawRect(
      Rect.fromLTWH(stackLeft, stackBottom - cellH * 4, cellW, cellH * 4),
      Paint()
        ..color = dimColor.withOpacity(0.1)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(stackLeft, stackBottom - cellH * 4, cellW, cellH * 4),
      _linePaint(dimColor.withOpacity(0.4)),
    );

    // Number of items on stack oscillates
    final itemCount = (1 + (sin(progress * 2 * pi) * 1.5).abs().round()).clamp(1, 3);

    final stackColors = [
      accentColor,
      accentColor.withOpacity(0.7),
      accentColor.withOpacity(0.5),
    ];
    final stackLabels = ['a', 'a', 'Z'];

    for (int i = 0; i < itemCount; i++) {
      final top = stackBottom - (i + 1) * cellH;
      canvas.drawRect(
        Rect.fromLTWH(stackLeft + 2, top + 2, cellW - 4, cellH - 4),
        Paint()
          ..color = stackColors[i].withOpacity(0.3)
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
        color: dimColor.withOpacity(0.85), fontSize: 10);
  }

  // ── tmTape: animated read/write head scanning a tape ──────────────────────
  void _paintTmTape(Canvas canvas, Size size, double cx, double cy) {
    const cellW = 36.0;
    const cellH = 36.0;
    const cells = 5;
    final tapeLeft = cx - (cells / 2) * cellW;
    const tapeTop = 65.0;
    final symbols = ['a', 'a', 'b', 'X', '_'];

    // Animated head position (0→4)
    final headPos = ((progress * cells) % cells).floor();

    for (int i = 0; i < cells; i++) {
      final x = tapeLeft + i * cellW;
      final isHead = i == headPos;

      canvas.drawRect(
        Rect.fromLTWH(x, tapeTop, cellW, cellH),
        Paint()
          ..color = isHead
              ? accentColor.withOpacity(0.2)
              : dimColor.withOpacity(0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, tapeTop, cellW, cellH),
        _linePaint(
          isHead ? accentColor : dimColor.withOpacity(0.35),
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
        color: dimColor.withOpacity(0.85), fontSize: 10);
  }

  // ── deleteMode: state fades out with X ────────────────────────────────────
  void _paintDeleteMode(Canvas canvas, Size size, double cx, double cy) {
    final opacity = progress < 0.5
        ? 1.0
        : (1.0 - (progress - 0.5) * 2).clamp(0.0, 1.0);

    const Color deleteColor = Color(0xFFEF5350);

    _drawNode(canvas, Offset(cx, cy - 10), 28,
        deleteColor.withOpacity(opacity), bgColor.withOpacity(opacity), 'q₀');

    // X mark
    if (progress > 0.3) {
      final x = cx;
      final y = cy - 10;
      const r = 14.0;
      final xOpacity = ((progress - 0.3) / 0.2).clamp(0.0, 1.0);
      final xPaint = _linePaint(deleteColor.withOpacity(xOpacity * opacity), w: 3);
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
      color: dimColor.withOpacity(0.85),
    );
  }

  // ── checkAnswer: check button pulses green ─────────────────────────────────
  void _paintCheckAnswer(Canvas canvas, Size size, double cx, double cy) {
    final pulse = 0.5 + 0.5 * sin(progress * 2 * pi);
    const Color green = Color(0xFF66BB6A);

    // Button outline
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 10), width: 130, height: 44),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = green.withOpacity(0.15 + pulse * 0.1)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = green.withOpacity(0.6 + pulse * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Check icon
    final checkPaint = _linePaint(green, w: 3);
    canvas.drawLine(Offset(cx - 24, cy - 10), Offset(cx - 10, cy + 5), checkPaint);
    canvas.drawLine(Offset(cx - 10, cy + 5), Offset(cx + 22, cy - 22), checkPaint);

    // "Check" label
    _drawLabel(canvas, Offset(cx + 10, cy - 10), '   Check',
        color: green, fontSize: 15);

    _drawLabel(
      canvas,
      Offset(cx, cy + 42),
      'Tap "Check" to submit your automaton for grading',
      fontSize: 10,
      color: dimColor.withOpacity(0.85),
    );
  }

  @override
  bool shouldRepaint(_TutorialIllustrationPainter old) =>
      old.progress != progress;
}