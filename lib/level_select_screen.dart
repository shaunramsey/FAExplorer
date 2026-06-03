// ─────────────────────────────────────────────────────────────────────────────
//  Level Select Screen — horizontal neural-network layout
//
//  Scrolls left → right through columns (difficulty layers).
//  Each node shows its title + a visible unlock requirement beneath it.
//  Edges are drawn as animated bezier curves between nodes.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'game_level.dart';
import 'game_progress_store.dart';
import 'game_puzzle.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Layout constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kNodeW       = 148.0; // node card width
const double _kNodeH       = 88.0;  // node card height
const double _kColGap      = 220.0; // horizontal gap between column centres
const double _kRowGap      = 140.0; // vertical gap between row centres
const double _kTopPad      = 96.0;  // space for the top bar
const double _kBotPad      = 80.0;
const double _kLegendH     = 52.0;  // height reserved at bottom for legend
const double _kSidePad     = 120.0;  // left/right canvas padding
const double _kMinRowPad   = 20.0;  // minimum vertical padding above/below nodes

// ─────────────────────────────────────────────────────────────────────────────
//  Colour palette
// ─────────────────────────────────────────────────────────────────────────────

const _kBg           = Color(0xFF05080F);
const _kGridLine     = Color(0xFF0D1620);
const _kEdgeDim      = Color(0xFF0E2030);
const _kEdgeActive   = Color(0xFF0E4A38);
const _kEdgeBright   = Color(0xFF1FD99A);
const _kTextDim      = Color(0xFF3A4A5E);
const _kTextMid      = Color(0xFF6B7E96);
const _kTextLight    = Color(0xFFCDD5E0);
const _kLockBg       = Color(0xFF080D14);
const _kLockBorder   = Color(0xFF141E2A);

// ─────────────────────────────────────────────────────────────────────────────
//  Level column layout
//
//  Each GameLevel carries an `x` in [0,1] which we re-interpret here as a
//  column index, and a `y` in [0,1] as the row position within that column.
//  We convert them to absolute pixel positions on the scrollable canvas.
// ─────────────────────────────────────────────────────────────────────────────

/// The layout bucketed by column (left-to-right difficulty layers).
/// We derive columns from each level's `x` value bucketed into bands.
int _colIndex(double x) {
  if (x < 0.15) return 0;
  if (x < 0.28) return 1;
  if (x < 0.42) return 2;
  if (x < 0.56) return 3;
  if (x < 0.68) return 4;
  if (x < 0.78) return 5;
  if (x < 0.88) return 6;
  return 7;
}

/// Given all levels, compute absolute Offset(cx, cy) for each level id.
///
/// Nodes are distributed evenly within each column so they never overlap,
/// while still respecting the relative y-order of levels.  The minimum
/// inter-node distance is [_kNodeH] + [_kMinRowPad].
Map<String, Offset> _buildPositions(List<GameLevel> levels, double canvasH) {
  // Group by column
  final Map<int, List<GameLevel>> cols = {};
  for (final l in levels) {
    final c = _colIndex(l.x);
    cols.putIfAbsent(c, () => []).add(l);
  }

  final Map<String, Offset> result = {};

  for (final entry in cols.entries) {
    final colIdx = entry.key;
    final members = entry.value..sort((a, b) => a.y.compareTo(b.y));

    final cx = _kSidePad + colIdx * _kColGap;
    final count = members.length;

    // Minimum height needed to fit all nodes without overlap
    final minRequired = count * _kNodeH + (count - 1) * _kMinRowPad;
    // Usable vertical band (between top bar and bottom padding, minus legend)
    final usableH = canvasH - _kTopPad - _kBotPad - _kLegendH;
    // Stretch to whichever is larger so gaps are generous
    final totalSpan = minRequired > usableH ? minRequired : usableH;
    // Gap between node *centres*
    final gap = count > 1 ? totalSpan / (count - 1) : 0.0;
    // Centre the block vertically
    final blockH = count > 1 ? gap * (count - 1) : 0.0;
    final topOffset = _kTopPad + (usableH - blockH) / 2.0;

    for (int i = 0; i < count; i++) {
      final cy = count == 1
          ? _kTopPad + usableH / 2.0
          : topOffset + i * gap;
      result[members[i].id] = Offset(cx, cy);
    }
  }

  return result;
}

double _canvasWidth(List<GameLevel> levels) {
  int maxCol = 0;
  for (final l in levels) {
    final c = _colIndex(l.x);
    if (c > maxCol) maxCol = c;
  }
  return _kSidePad * 2 + maxCol * _kColGap + _kNodeW;
}

/// Minimum canvas height so the tallest column never has overlapping nodes.
/// Always at least [screenH] so the canvas fills the viewport.
double _canvasHeight(List<GameLevel> levels, double screenH) {
  final layerById = _computeLayersFromDeps(levels);
  final Map<int, int> colCounts = {};
  for (final layer in layerById.values) {
    colCounts[layer] = (colCounts[layer] ?? 0) + 1;
  }
  final maxCount = colCounts.values.fold(0, (a, b) => a > b ? a : b);
  final needed = _kTopPad
      + maxCount * _kNodeH
      + (maxCount - 1) * (_kRowGap - _kNodeH)
      + _kBotPad
      + _kLegendH;
  return needed > screenH ? needed : screenH;
}

double _canvasWidthFromPositions(Map<String, Offset> positions) {
  final maxX = positions.values.fold<double>(0.0, (cur, p) => max(cur, p.dx));
  return maxX + _kNodeW / 2 + _kSidePad;
}

Map<String, int> _computeLayersFromDeps(List<GameLevel> levels) {
  final Map<String, List<String>> adj = {for (var l in levels) l.id: []};
  final Map<String, int> indeg = {for (var l in levels) l.id: 0};

  List<String> depsOf(UnlockRule rule) {
    if (rule is AlwaysUnlocked) return [];
    if (rule is RequireLevel) return [rule.levelId];
    if (rule is RequireAll) return rule.levelIds;
    if (rule is RequireAny) return rule.levelIds;
    if (rule is RequireExpression) return rule.children.expand(depsOf).toList();
    return [];
  }

  for (final l in levels) {
    final deps = depsOf(l.unlockRule);
    for (final d in deps) {
      if (!adj.containsKey(d)) continue;
      adj[d] = [...adj[d]!, l.id];
      indeg[l.id] = indeg[l.id]! + 1;
    }
  }

  final List<String> q = [];
  final Map<String, int> layer = {for (var l in levels) l.id: 0};
  for (final id in indeg.keys) {
    if (indeg[id] == 0) q.add(id);
  }

  while (q.isNotEmpty) {
    final cur = q.removeAt(0);
    for (final next in adj[cur]!) {
      layer[next] = max(layer[next]!, layer[cur]! + 1);
      indeg[next] = indeg[next]! - 1;
      if (indeg[next] == 0) q.add(next);
    }
  }

  int maxAssigned = layer.values.fold(0, (a, b) => a > b ? a : b);
  for (final id in indeg.keys) {
    if (indeg[id]! > 0) {
      maxAssigned += 1;
      layer[id] = maxAssigned;
    }
  }

  return layer;
}

Map<String, Offset> _computePositionsFromDeps(List<GameLevel> levels, double canvasH) {
  final layerById = _computeLayersFromDeps(levels);

  final Map<int, List<GameLevel>> cols = {};
  for (final l in levels) {
    final c = layerById[l.id] ?? 0;
    cols.putIfAbsent(c, () => []).add(l);
  }

  final Map<String, Offset> result = {};
  for (final entry in cols.entries) {
    final colIdx = entry.key;
    final members = entry.value..sort((a, b) => a.y.compareTo(b.y));

    final cx = _kSidePad + colIdx * _kColGap;
    final count = members.length;

    final minRequired = count * _kNodeH + (count - 1) * _kMinRowPad;
    final usableH = canvasH - _kTopPad - _kBotPad - _kLegendH;
    final totalSpan = minRequired > usableH ? minRequired : usableH;
    final gap = count > 1 ? totalSpan / (count - 1) : 0.0;
    final blockH = count > 1 ? gap * (count - 1) : 0.0;
    final topOffset = _kTopPad + (usableH - blockH) / 2.0;

    for (int i = 0; i < count; i++) {
      final cy = count == 1 ? _kTopPad + usableH / 2.0 : topOffset + i * gap;
      result[members[i].id] = Offset(cx, cy);
    }
  }

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
//  LevelSelectScreen
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
  late final AnimationController _flowCtrl;
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

    _flowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _flowCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _completed = widget.progressStore.loadCompletedLevels();
      });

  bool _isUnlocked(GameLevel l) => l.unlockRule.isSatisfied(_completed);
  bool _isCompleted(String id) => _completed.contains(id);

  void _onTap(GameLevel level) {
    if (!_isUnlocked(level)) {
      _showLockedSheet(level);
    } else {
      _openLevel(level);
    }
  }

  void _showLockedSheet(GameLevel level) {
    final tagColor = levelTagColor(level.tag);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LockedSheet(level: level, tagColor: tagColor),
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
    final screenH = MediaQuery.of(context).size.height;
    // Ensure the canvas is tall enough to never overlap nodes in any column
    final canvasH = _canvasHeight(kAllLevels, screenH);
    final positions = _computePositionsFromDeps(kAllLevels, canvasH);
    final canvasW = _canvasWidthFromPositions(positions);

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // ── Background grid ────────────────────────────────────────────
          CustomPaint(
            size: Size(MediaQuery.of(context).size.width,
                MediaQuery.of(context).size.height),
            painter: _GridPainter(),
          ),

          // ── Scrollable canvas (horizontal only) ───────────────────────
          AnimatedBuilder(
            animation: Listenable.merge([_pulseCtrl, _flowCtrl, _entryCtrl]),
            builder: (context, _) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: canvasW,
                  height: canvasH,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(canvasW, canvasH),
                        painter: _EdgePainter(
                          levels: kAllLevels,
                          positions: positions,
                          completed: _completed,
                          isUnlocked: _isUnlocked,
                          flowValue: _flowCtrl.value,
                          pulseValue: _pulseCtrl.value,
                          entryValue: CurvedAnimation(
                            parent: _entryCtrl,
                            curve: Curves.easeOut,
                          ).value,
                        ),
                      ),

                      // Node cards
                      for (final level in kAllLevels)
                        Positioned(
                          left: positions[level.id]!.dx - _kNodeW / 2,
                          top: positions[level.id]!.dy - _kNodeH / 2,
                          width: _kNodeW,
                          height: _kNodeH,
                          child: GestureDetector(
                            onTap: () => _onTap(level),
                            child: _NodeCard(
                              level: level,
                              unlocked: _isUnlocked(level),
                              completed: _isCompleted(level.id),
                              pulseAnim: _pulseCtrl,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          // ── Top bar ────────────────────────────────────────────────────
          _TopBar(
            completed: _completed.length,
            total: kAllLevels.length,
            onSandbox: widget.onGoToSandbox,
          ),

          // ── Column labels ──────────────────────────────────────────────
          _ColumnLabels(levels: kAllLevels, screenH: screenH),

          // ── Legend ─────────────────────────────────────────────────────
          const _Legend(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Column labels (pinned to top, scrolls with content via a second scroll view
//  that is synced — simpler: just overlay static labels from positions)
// ─────────────────────────────────────────────────────────────────────────────

class _ColumnLabels extends StatelessWidget {
  final List<GameLevel> levels;
  final double screenH;

  const _ColumnLabels({required this.levels, required this.screenH});

  static const _names = {
    0: 'FOUNDATION',
    1: 'BASICS',
    2: 'STRINGS',
    3: 'PATTERNS',
    4: 'ADVANCED',
    5: 'SUFFIX',
    6: 'LANGUAGE',
    7: 'CHALLENGE',
  };

  @override
  Widget build(BuildContext context) {
    // Determine which columns exist using dependency layout
    final positions = _computePositionsFromDeps(levels, _canvasHeight(levels, screenH));
    final Set<int> usedCols = {};
    for (final p in positions.values) usedCols.add(((p.dx - _kSidePad) / _kColGap).floor());

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: _kTopPad,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: _canvasWidthFromPositions(positions),
          child: Stack(
            children: [
              for (final col in usedCols)
                Positioned(
                  left: _kSidePad + col * _kColGap - _kNodeW / 2,
                  top: 60,
                  width: _kNodeW,
                  child: Text(
                    _names[col] ?? 'LAYER $col',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.orbitron(
                      color: _kTextDim,
                      fontSize: 7.5,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final int completed;
  final int total;
  final VoidCallback onSandbox;

  const _TopBar({
    required this.completed,
    required this.total,
    required this.onSandbox,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Title
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUTOMATA',
                  style: GoogleFonts.orbitron(
                    color: const Color(0xFF00E5FF),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  'LEARNING MAP',
                  style: GoogleFonts.orbitron(
                    color: _kTextDim,
                    fontSize: 8,
                    letterSpacing: 3.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 20),

            // Scroll hint
            Row(
              children: [
                const Icon(Icons.open_with, color: _kTextDim, size: 14),
                const SizedBox(width: 4),
                Text(
                  'SCROLL',
                  style: GoogleFonts.orbitron(
                    color: _kTextDim,
                    fontSize: 8,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Progress
            Row(
              children: [
                Text(
                  '$completed / $total',
                  style: GoogleFonts.orbitron(
                    color: _kTextLight,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 70,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: total > 0 ? completed / total : 0,
                      backgroundColor: const Color(0xFF0D1620),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                      minHeight: 5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 14),

            // Sandbox
            TextButton(
              onPressed: onSandbox,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: Color(0xFF1A2535), width: 1),
                ),
                foregroundColor: _kTextDim,
              ),
              child: Text(
                'SANDBOX',
                style: GoogleFonts.orbitron(
                  color: _kTextDim,
                  fontSize: 9,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Node Card
// ─────────────────────────────────────────────────────────────────────────────

class _NodeCard extends StatelessWidget {
  final GameLevel level;
  final bool unlocked;
  final bool completed;
  final Animation<double> pulseAnim;

  const _NodeCard({
    required this.level,
    required this.unlocked,
    required this.completed,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final tagColor = levelTagColor(level.tag);

    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) {
        final glowOpacity = completed
            ? 0.35 + pulseAnim.value * 0.25
            : unlocked
                ? 0.12 + pulseAnim.value * 0.08
                : 0.0;

        final borderColor = completed
            ? tagColor.withOpacity(0.85)
            : unlocked
                ? tagColor.withOpacity(0.55)
                : _kLockBorder;

        final bgColor = completed
            ? tagColor.withOpacity(0.10)
            : unlocked
                ? tagColor.withOpacity(0.05)
                : _kLockBg;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: completed ? 1.8 : 1.2),
            boxShadow: glowOpacity > 0
                ? [
                    BoxShadow(
                      color: tagColor.withOpacity(glowOpacity),
                      blurRadius: completed ? 22 : 10,
                      spreadRadius: completed ? 2 : 0,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Status icon row ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (completed)
                      Icon(Icons.check_circle, color: tagColor, size: 13)
                    else if (unlocked)
                      Icon(Icons.radio_button_unchecked,
                          color: tagColor.withOpacity(0.7), size: 11)
                    else
                      Icon(Icons.lock_outline, color: _kTextDim, size: 11),
                    const SizedBox(width: 4),
                    // Tag pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: tagColor.withOpacity(unlocked ? 0.15 : 0.06),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        (level.tag ?? 'misc').toUpperCase(),
                        style: GoogleFonts.orbitron(
                          color: unlocked
                              ? tagColor.withOpacity(0.9)
                              : _kTextDim,
                          fontSize: 6.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 5),

                // ── Title ────────────────────────────────────────────────
                Text(
                  level.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.orbitron(
                    color: completed
                        ? tagColor
                        : unlocked
                            ? _kTextLight
                            : _kTextDim,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 5),

                // ── Unlock requirement or "READY" ─────────────────────
                _UnlockHint(level: level, unlocked: unlocked, completed: completed),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Unlock hint (shown inside each node card)
// ─────────────────────────────────────────────────────────────────────────────

class _UnlockHint extends StatelessWidget {
  final GameLevel level;
  final bool unlocked;
  final bool completed;

  const _UnlockHint({
    required this.level,
    required this.unlocked,
    required this.completed,
  });

  String _shortHint() {
    final rule = level.unlockRule;
    if (rule is AlwaysUnlocked) return 'AVAILABLE';
    if (rule is RequireLevel) {
      final dep = kLevelById[rule.levelId];
      return 'NEED: ${dep?.title ?? rule.levelId}';
    }
    if (rule is RequireAll) {
      if (rule.levelIds.length == 1) {
        final dep = kLevelById[rule.levelIds.first];
        return 'NEED: ${dep?.title ?? rule.levelIds.first}';
      }
      return 'NEED ALL ${rule.levelIds.length} PREREQS';
    }
    if (rule is RequireAny) {
      return 'NEED ANY PREREQ';
    }
    if (rule is RequireExpression) {
      return 'NEED MULTIPLE';
    }
    return 'LOCKED';
  }

  @override
  Widget build(BuildContext context) {
    final tagColor = levelTagColor(level.tag);

    if (completed) {
      return Text(
        'COMPLETE',
        style: GoogleFonts.sourceCodePro(
          color: tagColor.withOpacity(0.8),
          fontSize: 7.5,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (unlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: tagColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          'TAP TO PLAY',
          style: GoogleFonts.sourceCodePro(
            color: tagColor.withOpacity(0.9),
            fontSize: 7,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Locked — show requirement
    return Text(
      _shortHint(),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.sourceCodePro(
        color: _kTextMid,
        fontSize: 7,
        letterSpacing: 0.8,
        height: 1.4,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Locked bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LockedSheet extends StatelessWidget {
  final GameLevel level;
  final Color tagColor;

  const _LockedSheet({required this.level, required this.tagColor});

  /// Build a rich description of the exact requirements.
  List<String> _requiredTitles() {
    return _extractIds(level.unlockRule)
        .map((id) => kLevelById[id]?.title ?? id)
        .toList();
  }

  List<String> _extractIds(UnlockRule rule) {
    if (rule is AlwaysUnlocked) return [];
    if (rule is RequireLevel) return [rule.levelId];
    if (rule is RequireAll) return rule.levelIds;
    if (rule is RequireAny) return rule.levelIds;
    if (rule is RequireExpression) {
      return rule.children.expand(_extractIds).toList();
    }
    return [];
  }

  bool _isAnd() {
    final rule = level.unlockRule;
    if (rule is RequireAll) return true;
    if (rule is RequireExpression) return rule.isAnd;
    return true; // single requirement = doesn't matter
  }

  @override
  Widget build(BuildContext context) {
    final titles = _requiredTitles();
    final isAnd = _isAnd();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1A2535), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2A3A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            children: [
              Icon(Icons.lock, color: _kTextDim, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  level.title,
                  style: GoogleFonts.orbitron(
                    color: _kTextLight,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: tagColor.withOpacity(0.3)),
                ),
                child: Text(
                  (level.tag ?? 'misc').toUpperCase(),
                  style: GoogleFonts.orbitron(
                    color: tagColor,
                    fontSize: 9,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (titles.isEmpty)
            Text(
              'This level is always available.',
              style: GoogleFonts.sourceCodePro(
                  color: _kTextMid, fontSize: 13),
            )
          else ...[
            Text(
              titles.length == 1
                  ? 'TO UNLOCK, COMPLETE:'
                  : isAnd
                      ? 'TO UNLOCK, COMPLETE ALL OF:'
                      : 'TO UNLOCK, COMPLETE ANY ONE OF:',
              style: GoogleFonts.orbitron(
                color: _kTextDim,
                fontSize: 9,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...titles.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tagColor.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t,
                          style: GoogleFonts.sourceCodePro(
                            color: _kTextLight,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                backgroundColor: tagColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: tagColor.withOpacity(0.25)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'GOT IT',
                style: GoogleFonts.orbitron(
                  color: tagColor,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Legend — pinned to the bottom, shows tag colours + node-state icons
// ─────────────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  static const _tags = [
    ('intro', Color(0xFF00E5FF), 'Intro'),
    ('dfa',   Color(0xFF69FF47), 'DFA'),
    ('nfa',   Color(0xFFFFD740), 'NFA'),
    ('pda',   Color(0xFFFF6D00), 'PDA'),
    ('tm',    Color(0xFFE040FB), 'TM'),
    ('boss',  Color(0xFFFF1744), 'Boss'),
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: _kLegendH + 8,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00050810), Color(0xE6050810)],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 18,
              runSpacing: 6,
              children: [
                // ── Node state indicators ──────────────────────────────
                _LegendItem(
                  icon: const Icon(Icons.check_circle, color: _kTextLight, size: 11),
                  label: 'Completed',
                  color: _kTextLight,
                ),
                _LegendItem(
                  icon: const Icon(Icons.radio_button_unchecked, color: _kTextMid, size: 11),
                  label: 'Available',
                  color: _kTextMid,
                ),
                _LegendItem(
                  icon: const Icon(Icons.lock_outline, color: _kTextDim, size: 11),
                  label: 'Locked',
                  color: _kTextDim,
                ),
                // Separator
                Container(width: 1, height: 14, color: const Color(0xFF1A2535)),
                // ── Tag colours ────────────────────────────────────────
                for (final (_, color, label) in _tags)
                  _LegendItem(
                    icon: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    label: label,
                    color: color.withOpacity(0.85),
                  ),
                // ── Edge colours ───────────────────────────────────────
                Container(width: 1, height: 14, color: const Color(0xFF1A2535)),
                _LegendItem(
                  icon: Container(
                    width: 16,
                    height: 2,
                    decoration: BoxDecoration(
                      color: _kEdgeBright,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  label: 'Both done',
                  color: _kEdgeBright,
                ),
                _LegendItem(
                  icon: Container(
                    width: 16,
                    height: 1.5,
                    decoration: BoxDecoration(
                      color: _kEdgeActive,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  label: 'Prereq done',
                  color: _kEdgeActive,
                ),
                _LegendItem(
                  icon: Container(
                    width: 16,
                    height: 1,
                    decoration: BoxDecoration(
                      color: _kEdgeDim,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  label: 'Locked path',
                  color: _kEdgeDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color color;

  const _LegendItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.orbitron(
            color: color,
            fontSize: 7,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Background grid painter
// ─────────────────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kGridLine
      ..strokeWidth = 0.5;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Edge painter — draws bezier curves between dependent nodes
// ─────────────────────────────────────────────────────────────────────────────

class _EdgePainter extends CustomPainter {
  final List<GameLevel> levels;
  final Map<String, Offset> positions;
  final Set<String> completed;
  final bool Function(GameLevel) isUnlocked;
  final double flowValue;
  final double pulseValue;
  final double entryValue;

  _EdgePainter({
    required this.levels,
    required this.positions,
    required this.completed,
    required this.isUnlocked,
    required this.flowValue,
    required this.pulseValue,
    required this.entryValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final level in levels) {
      _drawEdgesFor(canvas, level);
    }
  }

  List<String> _extractDeps(UnlockRule rule) {
    if (rule is AlwaysUnlocked) return [];
    if (rule is RequireLevel) return [rule.levelId];
    if (rule is RequireAll) return rule.levelIds;
    if (rule is RequireAny) return rule.levelIds;
    if (rule is RequireExpression) {
      return rule.children.expand(_extractDeps).toList();
    }
    return [];
  }

  void _drawEdgesFor(Canvas canvas, GameLevel dest) {
    final destPos = positions[dest.id];
    if (destPos == null) return;

    final deps = _extractDeps(dest.unlockRule);
    final destCompleted = completed.contains(dest.id);

    for (final srcId in deps) {
      final srcLevel = kLevelById[srcId];
      if (srcLevel == null) continue;
      final srcPos = positions[srcId];
      if (srcPos == null) continue;

      final srcCompleted = completed.contains(srcId);
      final edgeActive = srcCompleted;
      final edgeBright = srcCompleted && destCompleted;

      // Edge colour
      Color edgeColor;
      double strokeW;
      if (edgeBright) {
        edgeColor = _kEdgeBright.withOpacity(0.55 + pulseValue * 0.25);
        strokeW = 2.0;
      } else if (edgeActive) {
        edgeColor = _kEdgeActive.withOpacity(0.45 + pulseValue * 0.2);
        strokeW = 1.5;
      } else {
        edgeColor = _kEdgeDim.withOpacity(0.5);
        strokeW = 1.0;
      }

      // Anchor on the right edge of src card, left edge of dest card
      final src = Offset(srcPos.dx + _kNodeW / 2, srcPos.dy);
      final dst = Offset(destPos.dx - _kNodeW / 2, destPos.dy);

      final ctrlDist = (dst.dx - src.dx).abs() * 0.45;
      final ctrl1 = Offset(src.dx + ctrlDist, src.dy);
      final ctrl2 = Offset(dst.dx - ctrlDist, dst.dy);

      final path = Path()
        ..moveTo(src.dx, src.dy)
        ..cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, dst.dx, dst.dy);

      canvas.drawPath(
        path,
        Paint()
          ..color = edgeColor
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );

      // Animated flow dot on active edges
      if (edgeActive && entryValue >= 1.0) {
        final t = (flowValue + srcId.hashCode * 0.37) % 1.0;
        final pt = _cubicPoint(src, ctrl1, ctrl2, dst, t);
        canvas.drawCircle(
          pt,
          edgeBright ? 3.0 : 2.0,
          Paint()
            ..color = edgeBright
                ? _kEdgeBright.withOpacity(0.9)
                : _kEdgeActive.withOpacity(0.8),
        );
      }

      // Arrow tip at destination
      if (edgeActive) {
        _drawArrow(canvas, ctrl2, dst, edgeColor, strokeW);
      }
    }
  }

  Offset _cubicPoint(
      Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * mt * p0.dx +
          3 * mt * mt * t * p1.dx +
          3 * mt * t * t * p2.dx +
          t * t * t * p3.dx,
      mt * mt * mt * p0.dy +
          3 * mt * mt * t * p1.dy +
          3 * mt * t * t * p2.dy +
          t * t * t * p3.dy,
    );
  }

  void _drawArrow(
      Canvas canvas, Offset from, Offset to, Color color, double w) {
    const len = 8.0;
    const wing = 4.5;
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    final tip = Offset(to.dx - cos(angle) * 2, to.dy - sin(angle) * 2);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - len * cos(angle) + wing * sin(angle),
            tip.dy - len * sin(angle) - wing * cos(angle))
        ..lineTo(tip.dx - len * cos(angle) - wing * sin(angle),
            tip.dy - len * sin(angle) + wing * cos(angle))
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.flowValue != flowValue ||
      old.pulseValue != pulseValue ||
      old.entryValue != entryValue ||
      old.completed != completed;
}