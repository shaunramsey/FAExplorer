// ─────────────────────────────────────────────────────────────────────────────
//  Level Select Screen — neural-network visual layout
//
//  Nodes = game levels.
//  Edges = unlock dependency arrows drawn between nodes.
//  Completed nodes glow; locked nodes are dimmed.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'game_level.dart';
import 'game_progress_store.dart';
import 'game_puzzle.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Colour palette
// ─────────────────────────────────────────────────────────────────────────────

const _kBg = Color(0xFF07080F);
const _kEdgeColor = Color(0xFF1A2535);
const _kEdgeUnlocked = Color(0xFF1E6B55);
const _kTextDim = Color(0xFF4A5568);
const _kTextLight = Color(0xFFCDD5E0);

// ─────────────────────────────────────────────────────────────────────────────
//  Level Select Screen
// ─────────────────────────────────────────────────────────────────────────────

class LevelSelectScreen extends StatefulWidget {
  final GameProgressStore progressStore;
  final VoidCallback onGoToSandbox;

  const LevelSelectScreen({
    super.key,
    required this.progressStore,
    required this.onGoToSandbox,
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _entryCtrl;

  Set<String> _completed = {};

  @override
  void initState() {
    super.initState();
    _completed = widget.progressStore.loadCompletedLevels();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _completed = widget.progressStore.loadCompletedLevels();
    });
  }

  bool _isUnlocked(GameLevel level) =>
      level.unlockRule.isSatisfied(_completed);

  bool _isCompleted(String id) => _completed.contains(id);

  void _onNodeTap(GameLevel level) {
    if (!_isUnlocked(level)) {
      _showLockedDialog(level);
      return;
    }
    _openLevel(level);
  }

  void _showLockedDialog(GameLevel level) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E2A3A), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: Color(0xFF4A5568), size: 40),
              const SizedBox(height: 16),
              Text(
                level.title,
                style: GoogleFonts.orbitron(
                  color: _kTextLight,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                level.unlockRule.describe(),
                style: GoogleFonts.sourceCodePro(
                  color: const Color(0xFF718096),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.orbitron(color: levelTagColor(level.tag)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLevel(GameLevel level) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GamePuzzleScreen(
          level: level,
          progressStore: widget.progressStore,
          onCompleted: _reload,
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // ── Animated scan-line ──────────────────────────────────────────
          AnimatedBuilder(
            animation: _scanCtrl,
            builder: (ctx, _) {
              final h = MediaQuery.of(ctx).size.height;
              return Positioned(
                top: _scanCtrl.value * h - 2,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        const Color(0xFF00E5FF).withOpacity(0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // ── Neural network canvas ───────────────────────────────────────
          LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              return AnimatedBuilder(
                animation: Listenable.merge([_pulseCtrl, _entryCtrl]),
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(w, h),
                    painter: _NeuralNetPainter(
                      levels: kAllLevels,
                      completed: _completed,
                      isUnlocked: _isUnlocked,
                      pulseValue: _pulseCtrl.value,
                      entryValue: CurvedAnimation(
                        parent: _entryCtrl,
                        curve: Curves.easeOut,
                      ).value,
                    ),
                  );
                },
              );
            },
          ),

          // ── Tappable node overlays ─────────────────────────────────────
          LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final usableH = h - 80; // leave top bar space
              final topPad = 80.0;

              return Stack(
                children: kAllLevels.map((level) {
                  final cx = level.x * w;
                  final cy = topPad + level.y * usableH;
                  final unlocked = _isUnlocked(level);
                  final completed = _isCompleted(level.id);
                  const r = 36.0;

                  return Positioned(
                    left: cx - r,
                    top: cy - r,
                    width: r * 2,
                    height: r * 2,
                    child: GestureDetector(
                      onTap: () => _onNodeTap(level),
                      child: Tooltip(
                        message: level.title,
                        preferBelow: false,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                          ),
                          child: Center(
                            child: _NodeBadge(
                              level: level,
                              unlocked: unlocked,
                              completed: completed,
                              pulseAnim: _pulseCtrl,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          // ── Top bar ────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'AUTOMATA',
                    style: GoogleFonts.orbitron(
                      color: const Color(0xFF00E5FF),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const Spacer(),
                  // Progress indicator
                  AnimatedBuilder(
                    animation: _entryCtrl,
                    builder: (_, __) {
                      final done = _completed.length;
                      final total = kAllLevels.length;
                      return Row(
                        children: [
                          Text(
                            '$done / $total',
                            style: GoogleFonts.orbitron(
                              color: _kTextLight,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: total > 0 ? done / total : 0,
                                backgroundColor: const Color(0xFF1A2535),
                                valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFF00E5FF)),
                                minHeight: 6,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  // Sandbox button
                  GestureDetector(
                    onTap: widget.onGoToSandbox,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0xFF1E2A3A), width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'SANDBOX',
                        style: GoogleFonts.orbitron(
                          color: _kTextDim,
                          fontSize: 11,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Legend ────────────────────────────────────────────────────
          Positioned(
            bottom: 24,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in {
                  'intro': 'Introduction',
                  'dfa': 'DFA',
                  'nfa': 'NFA',
                  'boss': 'Boss',
                  'custom': 'Puzzle',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: levelTagColor(entry.key),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.value,
                          style: GoogleFonts.sourceCodePro(
                            color: _kTextDim,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Node Badge widget
// ─────────────────────────────────────────────────────────────────────────────

class _NodeBadge extends StatelessWidget {
  final GameLevel level;
  final bool unlocked;
  final bool completed;
  final Animation<double> pulseAnim;

  const _NodeBadge({
    required this.level,
    required this.unlocked,
    required this.completed,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final tagColor = levelTagColor(level.tag);
    final baseColor = unlocked ? tagColor : const Color(0xFF1E2A3A);
    final glowOpacity = completed
        ? 0.5 + pulseAnim.value * 0.4
        : unlocked
            ? 0.15 + pulseAnim.value * 0.15
            : 0.0;

    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) {
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed
                ? baseColor.withOpacity(0.2)
                : unlocked
                    ? baseColor.withOpacity(0.1)
                    : const Color(0xFF0D1117),
            border: Border.all(
              color: baseColor.withOpacity(unlocked ? 0.8 : 0.3),
              width: completed ? 2.5 : 1.5,
            ),
            boxShadow: glowOpacity > 0
                ? [
                    BoxShadow(
                      color: tagColor.withOpacity(glowOpacity),
                      blurRadius: completed ? 18 : 8,
                      spreadRadius: completed ? 3 : 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: completed
                ? Icon(Icons.check, color: tagColor, size: 22)
                : unlocked
                    ? Text(
                        level.tag == 'boss' ? '★' : '●',
                        style: TextStyle(
                          color: tagColor.withOpacity(0.9),
                          fontSize: level.tag == 'boss' ? 20 : 14,
                        ),
                      )
                    : const Icon(Icons.lock,
                        color: Color(0xFF2D3748), size: 16),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Neural Network CustomPainter
//  — draws edges + background node rings
// ─────────────────────────────────────────────────────────────────────────────

class _NeuralNetPainter extends CustomPainter {
  final List<GameLevel> levels;
  final Set<String> completed;
  final bool Function(GameLevel) isUnlocked;
  final double pulseValue;
  final double entryValue;

  _NeuralNetPainter({
    required this.levels,
    required this.completed,
    required this.isUnlocked,
    required this.pulseValue,
    required this.entryValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final usableH = size.height - 80;
    const topPad = 80.0;

    Offset pos(GameLevel l) =>
        Offset(l.x * size.width, topPad + l.y * usableH);

    // ── Faint background radial glow ────────────────────────────────────
    final center = Offset(size.width / 2, size.height / 2);
    final radialPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF001829).withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCenter(
          center: center,
          width: size.width * 1.4,
          height: size.height * 1.4));
    canvas.drawRect(Offset.zero & size, radialPaint);

    // ── Edges ────────────────────────────────────────────────────────────
    for (final level in levels) {
      _drawEdgesFor(canvas, level, pos);
    }

    // ── Node outer rings (glow effect) ───────────────────────────────────
    for (final level in levels) {
      final p = pos(level);
      final tagColor = levelTagColor(level.tag);
      final isComp = completed.contains(level.id);
      final isUnlock = isUnlocked(level);

      if (isComp || isUnlock) {
        final glowR = 34.0 + (isComp ? pulseValue * 6 : 0);
        canvas.drawCircle(
          p,
          glowR,
          Paint()
            ..color = tagColor
                .withOpacity(isComp ? 0.08 + pulseValue * 0.06 : 0.04)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // ── Level labels ───────────────────────────────────────────────────
    for (final level in levels) {
      final p = pos(level);
      final isUnlock = isUnlocked(level);
      final isComp = completed.contains(level.id);
      final tagColor = levelTagColor(level.tag);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: level.title,
          style: TextStyle(
            fontFamily: 'Orbitron',
            color: isComp
                ? tagColor.withOpacity(0.9)
                : isUnlock
                    ? _kTextLight.withOpacity(0.85)
                    : _kTextDim.withOpacity(0.5),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 100);

      labelPainter.paint(
        canvas,
        Offset(p.dx - labelPainter.width / 2, p.dy + 32),
      );
    }
  }

  void _drawEdgesFor(
      Canvas canvas, GameLevel level, Offset Function(GameLevel) pos) {
    final destIds = _extractDependencies(level.unlockRule);
    if (destIds.isEmpty) return;

    final dest = pos(level);
    final levelCompleted = completed.contains(level.id);

    for (final srcId in destIds) {
      final srcLevel = kLevelById[srcId];
      if (srcLevel == null) continue;
      final src = pos(srcLevel);

      final srcCompleted = completed.contains(srcId);
      final edgeColor = (srcCompleted && levelCompleted)
          ? _kEdgeUnlocked
          : (srcCompleted ? const Color(0xFF1A3D2B) : _kEdgeColor);

      final paint = Paint()
        ..color = edgeColor.withOpacity(0.6)
        ..strokeWidth = srcCompleted ? 1.5 : 1.0
        ..style = PaintingStyle.stroke;

      // Draw a slightly curved edge
      final midX = (src.dx + dest.dx) / 2;
      final midY = (src.dy + dest.dy) / 2;
      final ctrlPt = Offset(midX, midY);

      final path = Path()
        ..moveTo(src.dx, src.dy)
        ..quadraticBezierTo(ctrlPt.dx, ctrlPt.dy, dest.dx, dest.dy);
      canvas.drawPath(path, paint);

      // Arrowhead near destination
      if (srcCompleted) {
        _drawArrow(canvas, src, dest, edgeColor.withOpacity(0.7));
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    const arrowLen = 8.0;
    const arrowWing = 4.0;
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    final tip = Offset(
      to.dx - cos(angle) * 36,
      to.dy - sin(angle) * 36,
    );
    final p1 = Offset(
      tip.dx - arrowLen * cos(angle) + arrowWing * sin(angle),
      tip.dy - arrowLen * sin(angle) - arrowWing * cos(angle),
    );
    final p2 = Offset(
      tip.dx - arrowLen * cos(angle) - arrowWing * sin(angle),
      tip.dy - arrowLen * sin(angle) + arrowWing * cos(angle),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  /// Flatten an UnlockRule into a list of level IDs it depends on.
  List<String> _extractDependencies(UnlockRule rule) {
    if (rule is AlwaysUnlocked) return [];
    if (rule is RequireLevel) return [rule.levelId];
    if (rule is RequireAll) return rule.levelIds;
    if (rule is RequireAny) return rule.levelIds;
    if (rule is RequireExpression) {
      return rule.children.expand(_extractDependencies).toList();
    }
    return [];
  }

  @override
  bool shouldRepaint(_NeuralNetPainter old) =>
      old.pulseValue != pulseValue ||
      old.entryValue != entryValue ||
      old.completed != completed;
}