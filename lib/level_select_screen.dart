// ─────────────────────────────────────────────────────────────────────────────
//  Level Select Screen — horizontal neural-network layout
//
//  Changes from original:
//  • Removed column labels (Foundation, Basics, etc.) — they didn't match the
//    actual level groupings and their overlay was intercepting touch events,
//    breaking the sandbox button.
//  • Sandbox button now works correctly.
//  • All edges are thicker and brighter overall for legibility.
//  • New "partial prereqs" edge state (amber): THIS prereq is done, but the
//    destination level is still locked because other prereqs are missing.
//  • New "missing prereq" edge state (pulsing orange, dashed): THIS is the
//    specific prereq blocking an otherwise almost-unlocked level — draws
//    attention to exactly what the player needs to do next.
//  • Multi-column edges are routed above or below intermediate nodes so they
//    never visually pass through unrelated level cards.
//  • Arrowheads are larger and arrows always drawn (not gated by entryValue).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'game_level.dart';
import 'game_progress_store.dart';
import 'game_puzzle.dart';
import 'main.dart' show kBg, kSurface, kBorder, kBorderMid, kAccent, kTextDim, kTextMid, kTextLight;

// ─────────────────────────────────────────────────────────────────────────────
//  Layout constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kNodeW = 148.0; // node card width
const double _kNodeH = 88.0; // node card height
const double _kColGap = 220.0; // horizontal gap between column centres
const double _kRowGap = 140.0; // vertical gap between row centres
const double _kTopPad = 72.0; // space for the top bar (reduced, no column labels)
const double _kBotPad = 80.0;
const double _kLegendH = 58.0; // height reserved at bottom for legend
const double _kSidePad = 120.0; // left/right canvas padding
const double _kMinRowPad = 20.0; // minimum vertical padding above/below nodes

// ─────────────────────────────────────────────────────────────────────────────
//  Colour palette
// ─────────────────────────────────────────────────────────────────────────────

const _kGridLine = Color(0xFF0D1620);
const _kEdgeDim = Color(0xFF1A2E40); // locked path — slightly brighter than original
const _kEdgeActive = Color(0xFF1CBD8A); // prereq done, dest available — vibrant teal
const _kEdgeBright = Color(0xFF1FD99A); // both done — bright teal-green
const _kEdgeAlmost = Color(0xFFFFAA00); // this prereq done but dest still locked — amber
const _kEdgeBlocking = Color(0xFFFF6D00); // this is the MISSING prereq — pulsing orange
const _kLockBg = Color(0xFF080D14);
const _kLockBorder = Color(0xFF141E2A);

// ─────────────────────────────────────────────────────────────────────────────
//  Position helpers (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

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

Map<String, Offset> _buildPositions(List<GameLevel> levels, double canvasH) {
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

double _canvasWidth(List<GameLevel> levels) {
  int maxCol = 0;
  for (final l in levels) {
    final c = _colIndex(l.x);
    if (c > maxCol) maxCol = c;
  }
  return _kSidePad * 2 + maxCol * _kColGap + _kNodeW;
}

double _canvasHeight(List<GameLevel> levels, double screenH) => screenH;

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
    final usableH = canvasH - _kTopPad - _kBotPad - _kLegendH;
    final gap = count > 1 ? min(_kRowGap, usableH / (count - 1)) : 0.0;
    final totalSpan = count > 1 ? gap * (count - 1) : 0.0;
    final topOffset = count > 1 ? _kTopPad + (usableH - totalSpan) / 2.0 : _kTopPad + usableH / 2.0;
    for (int i = 0; i < count; i++) {
      final cy = topOffset + (count == 1 ? 0.0 : i * gap);
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

  const LevelSelectScreen({super.key, required this.progressStore, required this.onGoToSandbox});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _flowCtrl;
  late final AnimationController _entryCtrl;

  Set<String> _completed = {};

  @override
  void initState() {
    super.initState();
    _completed = widget.progressStore.loadCompletedLevels();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

    _flowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
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
        builder: (_) => GamePuzzleScreen(level: level, progressStore: widget.progressStore, onCompleted: _reload),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final canvasH = _canvasHeight(kAllLevels, screenH);
    final positions = _computePositionsFromDeps(kAllLevels, canvasH);
    final canvasW = _canvasWidthFromPositions(positions);

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // ── Background grid ────────────────────────────────────────────
          CustomPaint(
            size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
            painter: _GridPainter(),
          ),

          // ── Scrollable canvas (horizontal only) ───────────────────────
          AnimatedBuilder(
            animation: Listenable.merge([_pulseCtrl, _flowCtrl, _entryCtrl]),
            builder: (context, _) {
              final entryVal = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut).value;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: canvasW,
                  height: canvasH,
                  child: Stack(
                    children: [
                      // Edges (drawn below node cards)
                      CustomPaint(
                        size: Size(canvasW, canvasH),
                        painter: _EdgePainter(
                          levels: kAllLevels,
                          positions: positions,
                          completed: _completed,
                          isUnlocked: _isUnlocked,
                          flowValue: _flowCtrl.value,
                          pulseValue: _pulseCtrl.value,
                          entryValue: entryVal,
                          canvasH: canvasH,
                        ),
                      ),

                      // Node cards (rendered on top of edges)
                      for (final level in kAllLevels)
                        Positioned(
                          left: positions[level.id]!.dx - _kNodeW / 2,
                          top: positions[level.id]!.dy - _kNodeH / 2,
                          child: SizedBox(
                            width: _kNodeW,
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
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          // ── Top bar (no column labels on top of it anymore) ────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: _TopBar(completed: _completed.length, total: kAllLevels.length, onSandbox: widget.onGoToSandbox),
            ),
          ),

          // ── Legend ─────────────────────────────────────────────────────
          const _Legend(),
        ],
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

  const _TopBar({required this.completed, required this.total, required this.onSandbox});

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
                    color: kAccent,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  'LEARNING MAP',
                  style: GoogleFonts.orbitron(
                    color: kTextDim,
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
                const Icon(Icons.open_with, color: kTextDim, size: 14),
                const SizedBox(width: 4),
                Text('SCROLL', style: GoogleFonts.orbitron(color: kTextDim, fontSize: 8, letterSpacing: 2)),
              ],
            ),

            const Spacer(),

            // Progress
            Row(
              children: [
                Text(
                  '$completed / $total',
                  style: GoogleFonts.orbitron(color: kTextLight, fontSize: 12, letterSpacing: 1),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 70,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: total > 0 ? completed / total : 0,
                      backgroundColor: _kGridLine,
                      valueColor: const AlwaysStoppedAnimation(kAccent),
                      minHeight: 5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 14),

            // Sandbox button — previously blocked by the _ColumnLabels overlay;
            // now works correctly since that overlay has been removed.
            TextButton(
              onPressed: onSandbox,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: kBorderMid, width: 1),
                ),
                foregroundColor: kTextDim,
              ),
              child: Text('SANDBOX', style: GoogleFonts.orbitron(color: kTextDim, fontSize: 9, letterSpacing: 2)),
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

  const _NodeCard({required this.level, required this.unlocked, required this.completed, required this.pulseAnim});

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
            : kTextMid.withOpacity(0.85);

        final bgColor = completed
            ? tagColor.withOpacity(0.10)
            : unlocked
            ? tagColor.withOpacity(0.05)
            : kBorder;

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
                      Icon(Icons.radio_button_unchecked, color: tagColor.withOpacity(0.7), size: 11)
                    else
                      Icon(Icons.lock_outline, color: kTextDim, size: 11),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: tagColor.withOpacity(unlocked ? 0.15 : 0.06),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        (level.tag ?? 'misc').toUpperCase(),
                        style: GoogleFonts.orbitron(
                          color: unlocked ? tagColor.withOpacity(0.9) : kTextDim,
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
                        ? kTextLight
                        : kTextDim,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 5),

                // ── Unlock requirement or "READY" ────────────────────────
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

  const _UnlockHint({required this.level, required this.unlocked, required this.completed});

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
    if (rule is RequireAny) return 'NEED ANY PREREQ';
    if (rule is RequireExpression) return 'NEED MULTIPLE';
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
        decoration: BoxDecoration(color: tagColor.withOpacity(0.12), borderRadius: BorderRadius.circular(3)),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kBorderMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kTextMid.withOpacity(0.25)),
      ),
      child: Text(
        _shortHint(),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.sourceCodePro(
          color: kTextLight,
          fontSize: 7.5,
          letterSpacing: 0.8,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
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

  List<String> _requiredTitles() => _extractIds(level.unlockRule).map((id) => kLevelById[id]?.title ?? id).toList();

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
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final titles = _requiredTitles();
    final isAnd = _isAnd();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderMid, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: kBorderMid, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          Row(
            children: [
              Icon(Icons.lock, color: kTextDim, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  level.title,
                  style: GoogleFonts.orbitron(
                    color: kTextLight,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            Text('This level is always available.', style: GoogleFonts.sourceCodePro(color: kTextMid, fontSize: 13))
          else ...[
            Text(
              titles.length == 1
                  ? 'TO UNLOCK, COMPLETE:'
                  : isAnd
                  ? 'TO UNLOCK, COMPLETE ALL OF:'
                  : 'TO UNLOCK, COMPLETE ANY ONE OF:',
              style: GoogleFonts.orbitron(color: kTextDim, fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...titles.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: tagColor.withOpacity(0.6), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(t, style: GoogleFonts.sourceCodePro(color: kTextLight, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
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
//  Legend — updated to show new edge states
// ─────────────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  static const _tags = [
    ('intro', kAccent, 'Intro'),
    ('dfa', Color(0xFF69FF47), 'DFA'),
    ('nfa', Color(0xFFFFD740), 'NFA'),
    ('pda', Color(0xFFFF6D00), 'PDA'),
    ('tm', Color(0xFFE040FB), 'TM'),
    ('boss', Color(0xFFFF1744), 'Boss'),
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
              spacing: 16,
              runSpacing: 6,
              children: [
                // ── Node state indicators ──────────────────────────────
                _LegendItem(
                  icon: const Icon(Icons.check_circle, color: kTextLight, size: 11),
                  label: 'Completed',
                  color: kTextLight,
                ),
                _LegendItem(
                  icon: const Icon(Icons.radio_button_unchecked, color: kTextMid, size: 11),
                  label: 'Available',
                  color: kTextMid,
                ),
                _LegendItem(
                  icon: const Icon(Icons.lock_outline, color: kTextDim, size: 11),
                  label: 'Locked',
                  color: kTextDim,
                ),

                Container(width: 1, height: 14, color: kBorderMid),

                // ── Tag colours ────────────────────────────────────────
                for (final (_, color, label) in _tags)
                  _LegendItem(
                    icon: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    ),
                    label: label,
                    color: color.withOpacity(0.85),
                  ),

                Container(width: 1, height: 14, color: kBorderMid),

                // ── Edge state indicators ──────────────────────────────
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 3,
                    decoration: BoxDecoration(color: _kEdgeBright, borderRadius: BorderRadius.circular(1.5)),
                  ),
                  label: 'Both done',
                  color: _kEdgeBright,
                ),
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 2.5,
                    decoration: BoxDecoration(color: _kEdgeActive, borderRadius: BorderRadius.circular(1.5)),
                  ),
                  label: 'Prereq done',
                  color: _kEdgeActive,
                ),
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 2,
                    decoration: BoxDecoration(color: _kEdgeAlmost, borderRadius: BorderRadius.circular(1)),
                  ),
                  label: 'Partial prereqs',
                  color: _kEdgeAlmost,
                ),
                _LegendItem(
                  icon: _DashedLine(color: _kEdgeBlocking, width: 18),
                  label: 'Missing prereq',
                  color: _kEdgeBlocking,
                ),
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 1.5,
                    decoration: BoxDecoration(color: _kEdgeDim, borderRadius: BorderRadius.circular(1)),
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

/// Small dashed-line widget for the legend.
class _DashedLine extends StatelessWidget {
  final Color color;
  final double width;

  const _DashedLine({required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, 2.5),
      painter: _DashPainter(color: color),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(min(x + 4, size.width), size.height / 2), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _LegendItem extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color color;

  const _LegendItem({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.orbitron(color: color, fontSize: 7, letterSpacing: 1.2, fontWeight: FontWeight.w500),
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
//  Path data helper — carries a computed edge path plus metadata for drawing.
// ─────────────────────────────────────────────────────────────────────────────

class _PathData {
  const _PathData({required this.path, required this.arrowFrom, this.isSimple = false, this.ctrl1, this.ctrl2});

  /// The computed Flutter Path (one or two cubic bezier segments).
  final Path path;

  /// The control point just before [dst], used to derive the arrowhead angle.
  final Offset arrowFrom;

  /// True = single cubic bezier (suitable for flow-dot animation).
  final bool isSimple;

  /// Only populated when [isSimple] is true.
  final Offset? ctrl1;
  final Offset? ctrl2;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Edge painter
// ─────────────────────────────────────────────────────────────────────────────

class _EdgePainter extends CustomPainter {
  final List<GameLevel> levels;
  final Map<String, Offset> positions;
  final Set<String> completed;
  final bool Function(GameLevel) isUnlocked;
  final double flowValue;
  final double pulseValue;
  final double entryValue;
  final double canvasH; // used for routing bounds

  _EdgePainter({
    required this.levels,
    required this.positions,
    required this.completed,
    required this.isUnlocked,
    required this.flowValue,
    required this.pulseValue,
    required this.entryValue,
    required this.canvasH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final level in levels) {
      _drawEdgesFor(canvas, level);
    }
  }

  // ── Rule helpers ───────────────────────────────────────────────────────────

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

  bool _isOrRule(UnlockRule rule) {
    if (rule is RequireAny) return true;
    if (rule is RequireExpression) return !rule.isAnd;
    return false;
  }

  // ── Main per-level edge drawing ────────────────────────────────────────────

  void _drawEdgesFor(Canvas canvas, GameLevel dest) {
    final destPos = positions[dest.id];
    if (destPos == null) return;

    final deps = _extractDeps(dest.unlockRule);
    if (deps.isEmpty) return;

    final destCompleted = completed.contains(dest.id);
    final destUnlocked = isUnlocked(dest);
    final destIsOr = _isOrRule(dest.unlockRule);

    // Count how many of dest's prereqs are already completed.
    final numCompletedDeps = deps.where((id) => completed.contains(id)).length;

    // "Almost unlocked" = dest is still locked but some of its prereqs ARE done.
    // (Impossible for OR rules since any single done dep → dest unlocked, so
    //  this state is exclusive to AND-type rules.)
    final isAlmostUnlocked = !destUnlocked && numCompletedDeps > 0;

    for (final srcId in deps) {
      final srcLevel = kLevelById[srcId];
      if (srcLevel == null) continue;
      final srcPos = positions[srcId];
      if (srcPos == null) continue;

      final srcCompleted = completed.contains(srcId);

      // ── Classify this edge ──────────────────────────────────────────────

      Color edgeColor;
      double strokeW;
      bool drawGlow;
      bool blockingDash; // extra-visible dashes for the "missing prereq" state

      if (srcCompleted && destCompleted) {
        edgeColor = const Color.fromARGB(255, 0, 255, 26).withOpacity(0.90);
        strokeW = 1.0;
        drawGlow = true;
        blockingDash = false;
      } else if (srcCompleted && destUnlocked) {
        edgeColor = _kEdgeActive.withOpacity(0.95);
        strokeW = 1.0;
        drawGlow = true;
        blockingDash = false;
      } else if (srcCompleted && isAlmostUnlocked) {
        edgeColor = const Color(0xFFFFD54F);
        strokeW = 3.0;
        drawGlow = true;
        blockingDash = false;
      } else if (!srcCompleted && isAlmostUnlocked) {
        edgeColor = const Color(0xFFFF3B30).withOpacity(0.55 + pulseValue * 0.45);
        strokeW = 4.0;
        drawGlow = true;
        blockingDash = true;
      } else {
        edgeColor = _kEdgeDim.withOpacity(0.95);
        strokeW = 3.5;
        drawGlow = false;
        blockingDash = false;
      }

      // ── Build path, routing around intermediate nodes ───────────────────

      final src = Offset(srcPos.dx + _kNodeW / 2, srcPos.dy);
      final dst = Offset(destPos.dx - _kNodeW / 2, destPos.dy);
      final intermediate = _getIntermediatePositions(srcId, dest.id, src.dx, dst.dx);
      final pathData = _buildEdgePath(src, dst, intermediate);

      // ── Glow layer ──────────────────────────────────────────────────────

      if (drawGlow) {
        canvas.drawPath(
          pathData.path,
          Paint()
            ..color = edgeColor.withOpacity(0.22)
            ..strokeWidth = strokeW + 18
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      // ── Main line ───────────────────────────────────────────────────────

      // OR-rule edges are lightly dashed; blocking edges get a bolder dash.
      final useDash = destIsOr || blockingDash;
      final dashLen = blockingDash ? 14.0 : 8.0;
      final gapLen = blockingDash ? 6.0 : 5.0;
      final drawPath = useDash ? _dashPath(pathData.path, dashLen, gapLen) : pathData.path;

      canvas.drawPath(
        drawPath,
        Paint()
          ..color = edgeColor
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      if (!srcCompleted && isAlmostUnlocked) {
        for (final metric in drawPath.computeMetrics()) {
          final t = (flowValue * metric.length);

          final tangent = metric.getTangentForOffset(t);
          if (tangent != null) {
            canvas.drawCircle(
              tangent.position,
              7,
              Paint()
                ..color = Colors.redAccent
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
            );
          }
        }
      }

      // ── Flow dot (only active/bright edges with simple bezier path) ─────

      if (pathData.isSimple && entryValue >= 1.0 && (srcCompleted && destUnlocked || srcCompleted && destCompleted)) {
        final t = (flowValue + srcId.hashCode * 0.37) % 1.0;
        final pt = _cubicPoint(src, pathData.ctrl1!, pathData.ctrl2!, dst, t);
        canvas.drawCircle(pt, destCompleted ? 3.5 : 3.0, Paint()..color = edgeColor.withOpacity(0.95));
      }

      // ── Arrowhead ───────────────────────────────────────────────────────

      _drawArrow(canvas, pathData.arrowFrom, dst, edgeColor, strokeW);
    }
  }

  // ── Routing helpers ────────────────────────────────────────────────────────

  /// Returns all node positions whose centre X lies strictly between
  /// [srcX] and [dstX], i.e. intermediate nodes that an edge might cross.
  List<Offset> _getIntermediatePositions(String srcId, String destId, double srcX, double dstX) {
    // Adjacent-column edges (gap ≤ one column) have no intermediates.
    if (dstX - srcX <= _kColGap) return const [];

    final result = <Offset>[];
    for (final entry in positions.entries) {
      final id = entry.key;
      if (id == srcId || id == destId) continue;
      final p = entry.value;
      if (p.dx > srcX + 5 && p.dx < dstX - 5) {
        result.add(p);
      }
    }
    return result;
  }

  /// Builds a bezier path from [src] to [dst].
  ///
  /// For direct (no-conflict) edges: a standard S-curve cubic bezier.
  /// For edges that would visually pass through intermediate nodes: a
  /// two-segment cubic that routes above or below those nodes.
  _PathData _buildEdgePath(Offset src, Offset dst, List<Offset> intermediate) {
    final ctrlDist = (dst.dx - src.dx) * 0.45;

    bool pathHitsNodes(List<Offset> pts) {
      for (final entry in positions.entries) {
        final p = entry.value;

        // Ignore source/destination nodes.
        if ((p - Offset(src.dx - _kNodeW / 2, src.dy)).distance < 5 ||
            (p - Offset(dst.dx + _kNodeW / 2, dst.dy)).distance < 5) {
          continue;
        }

        final rect = Rect.fromCenter(center: p, width: _kNodeW + 50, height: _kNodeH + 50);

        for (int i = 0; i < pts.length - 1; i++) {
          final seg = Rect.fromPoints(pts[i], pts[i + 1]).inflate(20);

          if (rect.overlaps(seg)) {
            return true;
          }
        }
      }

      return false;
    }

    // Simple adjacent-column connection.
    if (dst.dx - src.dx <= _kColGap) {
      final ctrl1 = Offset(src.dx + ctrlDist, src.dy);
      final ctrl2 = Offset(dst.dx - ctrlDist, dst.dy);

      return _PathData(
        path: Path()
          ..moveTo(src.dx, src.dy)
          ..cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, dst.dx, dst.dy),
        isSimple: true,
        ctrl1: ctrl1,
        ctrl2: ctrl2,
        arrowFrom: ctrl2,
      );
    }

    final candidateYs = <double>[
      _kTopPad + 30,
      _kTopPad + 120,
      canvasH * 0.25,
      canvasH * 0.75,
      canvasH - _kBotPad - _kLegendH - 120,
      canvasH - _kBotPad - _kLegendH - 30,
    ];

    double chosenY = candidateYs.first;

    for (final y in candidateYs) {
      final test = [src, Offset(src.dx, y), Offset(dst.dx, y), dst];

      if (!pathHitsNodes(test)) {
        chosenY = y;
        break;
      }
    }

    final midX = (src.dx + dst.dx) / 2;
    final halfCtrl = ctrlDist * 0.7;

    final arrowFrom = Offset(dst.dx - halfCtrl, dst.dy);

    return _PathData(
      path: Path()
        ..moveTo(src.dx, src.dy)
        ..cubicTo(src.dx + halfCtrl, src.dy, midX - 20, chosenY, midX, chosenY)
        ..cubicTo(midX + 20, chosenY, arrowFrom.dx, arrowFrom.dy, dst.dx, dst.dy),
      isSimple: false,
      arrowFrom: arrowFrom,
    );
  }

  // ── Drawing primitives ─────────────────────────────────────────────────────

  Offset _cubicPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * mt * p0.dx + 3 * mt * mt * t * p1.dx + 3 * mt * t * t * p2.dx + t * t * t * p3.dx,
      mt * mt * mt * p0.dy + 3 * mt * mt * t * p1.dy + 3 * mt * t * t * p2.dy + t * t * t * p3.dy,
    );
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color, double w) {
    if ((to - from).distance < 1.0) return; // guard: no direction
    const len = 12.0;
    const wing = 7.0;
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    final tip = Offset(to.dx - cos(angle) * 2, to.dy - sin(angle) * 2);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - len * cos(angle) + wing * sin(angle), tip.dy - len * sin(angle) - wing * cos(angle))
        ..lineTo(tip.dx - len * cos(angle) - wing * sin(angle), tip.dy - len * sin(angle) + wing * cos(angle))
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  Path _dashPath(Path source, double dashLength, double gapLength) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final next = min(distance + (draw ? dashLength : gapLength), metric.length);
        if (draw) {
          dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        }
        draw = !draw;
        distance = next;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.flowValue != flowValue ||
      old.pulseValue != pulseValue ||
      old.entryValue != entryValue ||
      old.completed != completed;
}
