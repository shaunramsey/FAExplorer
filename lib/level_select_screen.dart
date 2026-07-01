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
//  • Scroll slider in the top bar: drag it to pan the canvas horizontally.
//    The slider also updates as the canvas is scrolled by touch/trackpad.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'game_level.dart';
import 'game_data.dart';
import 'game_puzzle.dart';
import 'tutorial_screen.dart';
import 'widgets/app_theme.dart';
import 'widgets/app_theme_settings.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Layout constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kNodeW = 148.0; // node card width
const double _kNodeH = 88.0; // node card height
const double _kColGap = 220.0; // horizontal gap between column centres
const double _kRowGap = 140.0; // vertical gap between row centres
const double _kTopPad = 96.0; // space for the top bar + scroll slider row
const double _kBotPad = 80.0;
const double _kLegendH = 58.0; // height reserved at bottom for legend
const double _kSidePad = 120.0; // left/right canvas padding
const double _kMinRowPad = 20.0; // minimum vertical padding above/below nodes

// ─────────────────────────────────────────────────────────────────────────────
//  Colour palette
// ─────────────────────────────────────────────────────────────────────────────

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
      layer[next] = max(layer[next]!, layer[cur]! + 2);
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
  List<String> _extractLevelDependencies(GameLevel level) {
  List<String> extract(UnlockRule rule) {
    if (rule is AlwaysUnlocked) return [];
    if (rule is RequireLevel) return [rule.levelId];
    if (rule is RequireAll) return rule.levelIds;
    if (rule is RequireAny) return rule.levelIds;
    if (rule is RequireExpression) {
      return rule.children.expand(extract).toList();
    }
    return [];
  }

  return extract(level.unlockRule);
}

  final Map<int, List<GameLevel>> cols = {};
  for (final l in levels) {
    final c = layerById[l.id] ?? 0;
    cols.putIfAbsent(c, () => []).add(l);
  }

  final Map<String, Offset> result = {};
  for (final entry in cols.entries) {
    final colIdx = entry.key;
    final members = [...entry.value];

members.sort((a, b) {
  double barycenter(GameLevel level) {
    final deps = _extractLevelDependencies(level);

    if (deps.isEmpty) {
      return level.y;
    }

    double sum = 0;
    int count = 0;

    for (final depId in deps) {
      final dep = kLevelById[depId];
      if (dep != null) {
        sum += dep.y;
        count++;
      }
    }

    return count == 0 ? level.y : sum / count;
  }

  return barycenter(a).compareTo(barycenter(b));
});
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
  final VoidCallback? onGoToStudy;

  const LevelSelectScreen({super.key, required this.progressStore, required this.onGoToSandbox, this.onGoToStudy});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _flowCtrl;
  late final AnimationController _entryCtrl;

  final ScrollController _scrollCtrl = ScrollController();
  double _scrollFraction = 0.0; // 0..1, drives the top-bar slider

  // ── Cheat-code (keyboard) ─────────────────────────────────────────────────
  /// Accumulates physical keyboard characters typed anywhere on this screen.
  String _cheatBuffer = '';
  /// Clear the buffer 3 s after the last keystroke so stray presses don't linger.
  Timer? _cheatTimer;
  final FocusNode _cheatFocus = FocusNode();

  /// Tracks which difficulty the player is currently viewing.
  /// Completion badges and the progress counter reflect this selection.
  LevelDifficulty _difficulty = LevelDifficulty.hard;

  /// Completed IDs for the *currently selected* difficulty.
  Set<String> _completed = {};

  /// Union of all completed IDs across both difficulties — used for unlock
  /// evaluation so completing on either difficulty counts toward prerequisites.
  Set<String> _completedAny = {};

  @override
  void initState() {
    super.initState();
    _loadCompleted();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _flowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();

    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      final fraction = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
      if ((fraction - _scrollFraction).abs() > 0.001) {
        setState(() => _scrollFraction = fraction);
      }
    });

    // Grab focus so keyboard events are captured immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cheatFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _flowCtrl.dispose();
    _entryCtrl.dispose();
    _scrollCtrl.dispose();
    _cheatFocus.dispose();
    _cheatTimer?.cancel();
    super.dispose();
  }

  void _loadCompleted() {
    setState(() {
      _completed = widget.progressStore.loadCompletedLevels(_difficulty);
      _completedAny = widget.progressStore.loadCompletedLevels(LevelDifficulty.hard)
        ..addAll(widget.progressStore.loadCompletedLevels(LevelDifficulty.easy));
    });
  }

  void _reload() => _loadCompleted();

  // ── Cheat code logic ──────────────────────────────────────────────────────

  /// Valid cheat codes (case-insensitive).
  static const _kCodeUnlockAll = 'UNLOCK_ALL';
  static const _kCodeLockAll   = 'LOCK_ALL';

  void _onCheatKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final ch = event.character;
    if (ch == null || ch.isEmpty) {
      // Non-printing key (Enter, Space, Backspace, etc.)  — treat Enter as submit.
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        _tryCheatCode(_cheatBuffer.trim());
      } else if (event.logicalKey == LogicalKeyboardKey.backspace && _cheatBuffer.isNotEmpty) {
        setState(() => _cheatBuffer = _cheatBuffer.substring(0, _cheatBuffer.length - 1));
      }
      return;
    }
    // Accumulate only alphanumeric / underscore chars (to avoid accidental triggers
    // from copy-paste shortcuts, arrow keys carrying characters on some platforms).
    if (RegExp(r'[a-zA-Z0-9_]').hasMatch(ch)) {
      setState(() => _cheatBuffer += ch.toUpperCase());
    }
    // Reset auto-clear timer.
    _cheatTimer?.cancel();
    _cheatTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _cheatBuffer = '');
    });
    // Auto-trigger when the buffer exactly matches a known code.
    if (_cheatBuffer == _kCodeUnlockAll || _cheatBuffer == _kCodeLockAll) {
      _cheatTimer?.cancel();
      _tryCheatCode(_cheatBuffer);
    }
  }

  Future<void> _tryCheatCode(String code) async {
    final upper = code.toUpperCase().trim();
    setState(() => _cheatBuffer = '');
    _cheatTimer?.cancel();

    if (upper == _kCodeUnlockAll) {
      await _cheatUnlockAll();
    } else if (upper == _kCodeLockAll) {
      await _cheatLockAll();
    } else if (code.isNotEmpty) {
      // Unknown code — show a brief "unrecognised" toast.
      if (!mounted) return;
      _showCheatToast('Unknown code: "$code"', const Color(0xFFFF5252));
    }
  }

  Future<void> _cheatUnlockAll() async {
    for (final level in kAllLevels) {
      await widget.progressStore.markCompleted(level.id, LevelDifficulty.hard);
      await widget.progressStore.markCompleted(level.id, LevelDifficulty.easy);
    }
    _loadCompleted();
    if (!mounted) return;
    _showCheatToast('All ${kAllLevels.length} levels unlocked ✓', const Color(0xFF1FD99A));
  }

  Future<void> _cheatLockAll() async {
    await widget.progressStore.resetAll();
    _loadCompleted();
    if (!mounted) return;
    _showCheatToast('Progress reset — all levels locked', const Color(0xFFFFB300));
  }

  void _showCheatToast(String message, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.terminal, color: color, size: 16),
            const SizedBox(width: 10),
            Text(
              message,
              style: GoogleFonts.courierPrime(color: color, fontSize: 13, letterSpacing: 0.5),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0A0F1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Opens the cheat-code dialog (triggered by long-pressing the title on mobile).
  void _showCheatDialog() {
    final ctrl = TextEditingController();
    final theme = AppThemeNotifier.read(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.borderMid),
        ),
        title: Row(
          children: [
            Icon(Icons.terminal, color: theme.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              'Enter Cheat Code',
              style: GoogleFonts.courierPrime(color: theme.textLight, fontSize: 15),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: GoogleFonts.courierPrime(color: theme.textLight, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. UNLOCK_ALL',
                hintStyle: GoogleFonts.courierPrime(color: theme.textDim, fontSize: 13),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.borderMid),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.accent, width: 1.5),
                ),
                filled: true,
                fillColor: theme.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (v) {
                Navigator.of(ctx).pop();
                _tryCheatCode(v);
              },
            ),
            const SizedBox(height: 10),
            Text(
              'UNLOCK_ALL  •  LOCK_ALL',
              style: GoogleFonts.courierPrime(color: theme.textDim, fontSize: 10, letterSpacing: 1),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.courierPrime(color: theme.textMid)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.accent, foregroundColor: Colors.black),
            onPressed: () {
              Navigator.of(ctx).pop();
              _tryCheatCode(ctrl.text);
            },
            child: Text('Apply', style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  bool _isUnlocked(GameLevel l) => l.unlockRule.isSatisfied(_completedAny);
  bool _isCompleted(String id) => _completed.contains(id);
  bool _isCompletedHard(String id) =>
      widget.progressStore.loadCompletedLevels(LevelDifficulty.hard).contains(id);
  bool _isCompletedEasy(String id) =>
      widget.progressStore.loadCompletedLevels(LevelDifficulty.easy).contains(id);

  void _onTap(GameLevel level) {
    if (!_isUnlocked(level)) {
      _showLockedSheet(level);
    } else {
      _openLevel(level);
    }
  }

  void _showLockedSheet(GameLevel level) {
    final tagColor = AppThemeNotifier.read(context).tagColor(level.tag);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LockedSheet(level: level, tagColor: tagColor),
    );
  }

  Future<void> _openLevel(GameLevel level) async {
    if (level.isTutorial) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TutorialScreen(
            level: level,
            progressStore: widget.progressStore,
            onCompleted: _reload,
          ),
        ),
      );
    } else {
      // Always honour the player's selected difficulty. Levels without an
      // easy-mode scaffold (level.hasEasyMode == false) simply start from a
      // blank canvas in Easy too — GamePuzzleScreen already handles that case
      // by skipping scaffold seeding while still using Easy's save/completion
      // keys, so progress is tracked correctly under the chosen difficulty.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GamePuzzleScreen(
            level: level,
            progressStore: widget.progressStore,
            onCompleted: _reload,
            difficulty: _difficulty,
          ),
        ),
      );
    }
    _reload();
  }

  /// Jumps the canvas to the given fraction (0 = leftmost, 1 = rightmost).
  void _scrollToFraction(double fraction) {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    _scrollCtrl.jumpTo((fraction * max).clamp(0.0, max));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final screenH = MediaQuery.of(context).size.height;
    final canvasH = _canvasHeight(kAllLevels, screenH);
    final positions = _computePositionsFromDeps(kAllLevels, canvasH);
    final canvasW = _canvasWidthFromPositions(positions);
    // For the progress bar, count puzzle levels and tutorial levels separately
    final puzzleLevels = kAllLevels.where((l) => !l.isTutorial).toList();
    final completedPuzzles = _completed.intersection(puzzleLevels.map((l) => l.id).toSet()).length;

    return Focus(
      focusNode: _cheatFocus,
      autofocus: true,
      onKeyEvent: (_, event) {
        _onCheatKey(event);
        return KeyEventResult.ignored; // don't swallow events (scrolling still works)
      },
      child: Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          // ── Background grid ────────────────────────────────────────────
          CustomPaint(
            size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
            painter: _GridPainter(gridColor: theme.gridLine),
          ),

          // ── Scrollable canvas (horizontal only) ───────────────────────
          AnimatedBuilder(
            animation: Listenable.merge([_pulseCtrl, _flowCtrl, _entryCtrl]),
            builder: (context, _) {
              final entryVal = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut).value;

              return SingleChildScrollView(
                controller: _scrollCtrl,
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
                          theme: theme.data,
                          levels: kAllLevels,
                          positions: positions,
                          completed: _completedAny,
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
                                completedHard: _isCompletedHard(level.id),
                                completedEasy: _isCompletedEasy(level.id),
                                currentDifficulty: _difficulty,
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

          // ── Top bar ────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: _TopBar(
                completed: completedPuzzles,
                total: puzzleLevels.length,
                onSandbox: widget.onGoToSandbox,
                onStudy: widget.onGoToStudy,
                scrollFraction: _scrollFraction,
                onScrollChanged: _scrollToFraction,
                difficulty: _difficulty,
                onDifficultyChanged: (d) {
                  setState(() => _difficulty = d);
                  _loadCompleted();
                },
                onTitleLongPress: _showCheatDialog,
              ),
            ),
          ),

          // ── Legend ─────────────────────────────────────────────────────
          const _Legend(),
        ],
      ),
    ), // Scaffold
    ); // Focus
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final int completed;
  final int total;
  final VoidCallback onSandbox;
  final VoidCallback? onStudy;
  final double scrollFraction;
  final ValueChanged<double> onScrollChanged;
  final LevelDifficulty difficulty;
  final ValueChanged<LevelDifficulty> onDifficultyChanged;
  /// Called when the player long-presses the title — opens the cheat-code dialog.
  final VoidCallback? onTitleLongPress;

  const _TopBar({
    required this.completed,
    required this.total,
    required this.onSandbox,
    this.onStudy,
    required this.scrollFraction,
    required this.onScrollChanged,
    required this.difficulty,
    required this.onDifficultyChanged,
    this.onTitleLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                // Title — long-press opens the cheat-code dialog on mobile/touch
                GestureDetector(
                  onLongPress: onTitleLongPress,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AUTOMATA',
                        style: GoogleFonts.orbitron(
                          color: theme.accent,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      Text(
                        'LEARNING MAP',
                        style: GoogleFonts.orbitron(
                          color: theme.textDim,
                          fontSize: 8,
                          letterSpacing: 3.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Difficulty toggle ────────────────────────────────────
                _DifficultyToggle(
                  current: difficulty,
                  onChanged: onDifficultyChanged,
                ),

                const SizedBox(width: 12),

                // Progress
                Row(
                  children: [
                    Text(
                      '$completed / $total',
                      style: GoogleFonts.orbitron(color: theme.textLight, fontSize: 12, letterSpacing: 1),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 70,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: total > 0 ? completed / total : 0,
                          backgroundColor: theme.gridLine,
                          valueColor: AlwaysStoppedAnimation(theme.accent),
                          minHeight: 5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 14),

                IconButton(
                  tooltip: 'Appearance & colors',
                  icon: Icon(Icons.palette_outlined, color: theme.textMid, size: 20),
                  onPressed: () => showAppThemeSettings(context),
                ),
                const SizedBox(width: 4),
                if (onStudy != null) ...[
                  TextButton(
                    onPressed: onStudy,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(color: theme.borderMid, width: 1),
                      ),
                      foregroundColor: theme.textDim,
                    ),
                    child: Text('STUDY', style: GoogleFonts.orbitron(color: theme.textDim, fontSize: 9, letterSpacing: 2)),
                  ),
                  const SizedBox(width: 4),
                ],
                TextButton(
                  onPressed: onSandbox,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(color: theme.borderMid, width: 1),
                    ),
                    foregroundColor: theme.textDim,
                  ),
                  child: Text('SANDBOX', style: GoogleFonts.orbitron(color: theme.textDim, fontSize: 9, letterSpacing: 2)),
                ),
              ],
            ),
          ),

          // ── Scroll slider ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
            child: Row(
              children: [
                Icon(Icons.chevron_left, color: theme.textDim, size: 16),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: theme.accent.withOpacity(0.7),
                      inactiveTrackColor: theme.gridLine,
                      thumbColor: theme.accent,
                      overlayColor: theme.accent.withOpacity(0.15),
                    ),
                    child: Slider(
                      value: scrollFraction,
                      onChanged: onScrollChanged,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.textDim, size: 16),
              ],
            ),
          ),
        ],
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
  final bool completedHard;
  final bool completedEasy;
  final LevelDifficulty currentDifficulty;
  final Animation<double> pulseAnim;

  const _NodeCard({
    required this.level,
    required this.unlocked,
    required this.completed,
    required this.completedHard,
    required this.completedEasy,
    required this.currentDifficulty,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final tagColor = theme.tagColor(level.tag);

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
            : theme.textMid.withOpacity(0.85);

        final bgColor = completed
            ? tagColor.withOpacity(0.10)
            : unlocked
            ? tagColor.withOpacity(0.05)
            : theme.border;

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
                      Icon(
                        level.isTutorial ? Icons.school : Icons.check_circle,
                        color: tagColor,
                        size: 13,
                      )
                    else if (unlocked)
                      Icon(
                        level.isTutorial ? Icons.school_outlined : Icons.radio_button_unchecked,
                        color: tagColor.withOpacity(0.7),
                        size: 11,
                      )
                    else
                      Icon(Icons.lock_outline, color: theme.textDim, size: 11),
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
                          color: unlocked ? tagColor.withOpacity(0.9) : theme.textDim,
                          fontSize: 6.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // ── Dual-difficulty completion badges ────────────────
                    if (!level.isTutorial)
                      _CompletionBadges(
                        completedHard: completedHard,
                        completedEasy: completedEasy,
                        currentDifficulty: currentDifficulty,
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
                        ? theme.textLight
                        : theme.textDim,
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
//  Difficulty toggle (Easy / Hard pill in the top bar)
// ─────────────────────────────────────────────────────────────────────────────

class _DifficultyToggle extends StatelessWidget {
  const _DifficultyToggle({required this.current, required this.onChanged});

  final LevelDifficulty current;
  final ValueChanged<LevelDifficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: theme.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.borderMid),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: LevelDifficulty.values.map((d) {
          final selected = d == current;
          const easyColor = Color(0xFF4CAF50);
          const hardColor = Color(0xFFFFB300);
          final activeColor = d.isHard ? hardColor : easyColor;
          return GestureDetector(
            onTap: () => onChanged(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                d.displayName.toUpperCase(),
                style: GoogleFonts.orbitron(
                  fontSize: 8,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.black87 : theme.textDim,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Completion badges — shown in the top-right of each node card
// ─────────────────────────────────────────────────────────────────────────────

/// Shows a small badge for each difficulty the player has completed.
/// Hard → gold gear badge.  Easy → green check badge.
/// If neither is completed, renders nothing.
class _CompletionBadges extends StatelessWidget {
  const _CompletionBadges({
    required this.completedHard,
    required this.completedEasy,
    required this.currentDifficulty,
  });

  final bool completedHard;
  final bool completedEasy;
  final LevelDifficulty currentDifficulty;

  @override
  Widget build(BuildContext context) {
    if (!completedHard && !completedEasy) return const SizedBox.shrink();

    const size = 14.0;

    if (completedHard && completedEasy) {
      return SizedBox(
        width: size + 6,
        height: size,
        child: Stack(
          children: [
            Positioned(left: 0, child: _EasyBadge(size: size)),
            Positioned(right: 0, child: _HardBadge(size: size)),
          ],
        ),
      );
    }
    if (completedHard) return _HardBadge(size: size);
    return _EasyBadge(size: size);
  }
}

class _EasyBadge extends StatelessWidget {
  const _EasyBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
      child: Icon(Icons.check_rounded, size: size * 0.65, color: Colors.white),
    );
  }
}

class _HardBadge extends StatelessWidget {
  const _HardBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _HardBadgePainter());
  }
}

class _HardBadgePainter extends CustomPainter {
  static const _gold = Color(0xFFFFB300);
  static const _goldDeep = Color(0xFFE65100);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy);

    // Gear teeth
    final toothPaint = Paint()..color = _gold..style = PaintingStyle.fill;
    for (var i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * pi;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(r * 0.80, 0), width: r * 0.30, height: r * 0.20),
          const Radius.circular(1),
        ),
        toothPaint,
      );
      canvas.restore();
    }

    // Outer filled circle
    canvas.drawCircle(Offset(cx, cy), r * 0.68, Paint()..color = _gold..style = PaintingStyle.fill);

    // Inner dark disc
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.50,
      Paint()
        ..shader = RadialGradient(
          colors: [_goldDeep.withOpacity(0.9), _goldDeep.withOpacity(0.65)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.50)),
    );

    // Six-pointed star
    const starPoints = 6;
    final outerR = r * 0.33;
    final innerR = r * 0.17;
    final starPath = Path();
    for (var i = 0; i < starPoints * 2; i++) {
      final angle = (i / (starPoints * 2)) * 2 * pi - pi / 2;
      final sr = i.isEven ? outerR : innerR;
      final x = cx + cos(angle) * sr;
      final y = cy + sin(angle) * sr;
      if (i == 0) starPath.moveTo(x, y); else starPath.lineTo(x, y);
    }
    starPath.close();
    canvas.drawPath(starPath, Paint()..color = _gold..style = PaintingStyle.fill);

    // Centre dot
    canvas.drawCircle(Offset(cx, cy), r * 0.09, Paint()..color = Colors.white.withOpacity(0.9));
  }

  @override
  bool shouldRepaint(_HardBadgePainter _) => false;
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
    final theme = context.watch<AppThemeNotifier>();
    final tagColor = theme.tagColor(level.tag);

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
          level.isTutorial ? 'TAP TO READ' : 'TAP TO PLAY',
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
        color: theme.borderMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.textMid.withOpacity(0.25)),
      ),
      child: Text(
        _shortHint(),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.sourceCodePro(
          color: theme.textLight,
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
    final theme = context.watch<AppThemeNotifier>();
    final titles = _requiredTitles();
    final isAnd = _isAnd();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.borderMid, width: 1.5),
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
              decoration: BoxDecoration(color: theme.borderMid, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          Row(
            children: [
              Icon(Icons.lock, color: theme.textDim, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  level.title,
                  style: GoogleFonts.orbitron(
                    color: theme.textLight,
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
            Text('This level is always available.', style: GoogleFonts.sourceCodePro(color: theme.textMid, fontSize: 13))
          else ...[
            Text(
              titles.length == 1
                  ? 'TO UNLOCK, COMPLETE:'
                  : isAnd
                  ? 'TO UNLOCK, COMPLETE ALL OF:'
                  : 'TO UNLOCK, COMPLETE ANY ONE OF:',
              style: GoogleFonts.orbitron(color: theme.textDim, fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w600),
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
                      child: Text(t, style: GoogleFonts.sourceCodePro(color: theme.textLight, fontSize: 13)),
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

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final d = theme.data;
    final tags = [
      ('intro', d.tagIntro, 'Intro'),
      ('dfa', d.tagDfa, 'DFA'),
      ('nfa', d.tagNfa, 'NFA'),
      ('pda', d.tagPda, 'PDA'),
      ('tm', d.tagTm, 'TM'),
      ('boss', d.tagBoss, 'Boss'),
    ];
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: _kLegendH + 8,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              d.bg.withOpacity(0),
              d.bg.withOpacity(0.92),
            ],
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
                  icon: Icon(Icons.check_circle, color: theme.textLight, size: 11),
                  label: 'Completed',
                  color: theme.textLight,
                ),
                _LegendItem(
                  icon: Icon(Icons.radio_button_unchecked, color: theme.textMid, size: 11),
                  label: 'Available',
                  color: theme.textMid,
                ),
                _LegendItem(
                  icon: Icon(Icons.lock_outline, color: theme.textDim, size: 11),
                  label: 'Locked',
                  color: theme.textDim,
                ),

                Container(width: 1, height: 14, color: theme.borderMid),

                // ── Tag colours ────────────────────────────────────────
                for (final (_, color, label) in tags)
                  _LegendItem(
                    icon: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    ),
                    label: label,
                    color: color.withOpacity(0.85),
                  ),

                Container(width: 1, height: 14, color: theme.borderMid),

                // ── Edge state indicators ──────────────────────────────
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 3,
                    decoration: BoxDecoration(color: d.edgeBright, borderRadius: BorderRadius.circular(1.5)),
                  ),
                  label: 'Both done',
                  color: d.edgeBright,
                ),
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 2.5,
                    decoration: BoxDecoration(color: d.edgeActive, borderRadius: BorderRadius.circular(1.5)),
                  ),
                  label: 'Prereq done',
                  color: d.edgeActive,
                ),
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 2,
                    decoration: BoxDecoration(color: d.edgeAlmost, borderRadius: BorderRadius.circular(1)),
                  ),
                  label: 'Partial prereqs',
                  color: d.edgeAlmost,
                ),
                _LegendItem(
                  icon: _DashedLine(color: d.edgeBlocking, width: 18),
                  label: 'Missing prereq',
                  color: d.edgeBlocking,
                ),
                _LegendItem(
                  icon: Container(
                    width: 18,
                    height: 1.5,
                    decoration: BoxDecoration(color: d.edgeDim, borderRadius: BorderRadius.circular(1)),
                  ),
                  label: 'Locked path',
                  color: d.edgeDim,
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
  const _GridPainter({required this.gridColor});

  final Color gridColor;

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
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.gridColor != gridColor;
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
  final AppThemeData theme;
  final List<GameLevel> levels;
  final Map<String, Offset> positions;
  final Set<String> completed;
  final bool Function(GameLevel) isUnlocked;
  final double flowValue;
  final double pulseValue;
  final double entryValue;
  final double canvasH;

  _EdgePainter({
    required this.theme,
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
        edgeColor = theme.edgeBright.withOpacity(0.90);
        strokeW = 1.0;
        drawGlow = true;
        blockingDash = false;
      } else if (srcCompleted && destUnlocked) {
        edgeColor = theme.edgeActive.withOpacity(0.95);
        strokeW = 1.0;
        drawGlow = true;
        blockingDash = false;
      } else if (srcCompleted && isAlmostUnlocked) {
        edgeColor = theme.edgeAlmost;
        strokeW = 3.0;
        drawGlow = true;
        blockingDash = false;
      } else if (!srcCompleted && isAlmostUnlocked) {
        edgeColor = theme.edgeBlocking.withOpacity(0.55 + pulseValue * 0.45);
        strokeW = 4.0;
        drawGlow = true;
        blockingDash = true;
      } else {
        edgeColor = theme.edgeDim.withOpacity(0.95);
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
    // Adjacent-column edges (gap ≤ one column + tolerance) have no intermediates.
    if (dstX - srcX <= _kColGap + 10) return const [];

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
  /// For adjacent-column edges: a standard S-curve cubic bezier.
  /// For multi-column edges: a two-segment cubic that arcs through a
  /// horizontal lane chosen to avoid all intermediate node cards.
  _PathData _buildEdgePath(Offset src, Offset dst, List<Offset> intermediate) {
    final ctrlDist = (dst.dx - src.dx) * 0.45;

    // ── Bezier sampler ──────────────────────────────────────────────────────
    // Approximate a cubic bezier with [steps] sample points.
    List<Offset> _sampleCubic(Offset p0, Offset p1, Offset p2, Offset p3, {int steps = 120}) {
      final pts = <Offset>[];
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        pts.add(_cubicPoint(p0, p1, p2, p3, t));
      }
      return pts;
    }

    // ── Node-avoidance check ─────────────────────────────────────────────────
    // Returns true if any sample point in [pts] falls inside a node card
    // (with padding), ignoring the src and dst nodes themselves.
    final srcNodeCenter = Offset(src.dx - _kNodeW / 2, src.dy);
    final dstNodeCenter = Offset(dst.dx + _kNodeW / 2, dst.dy);

    bool samplesHitNodes(List<Offset> pts) {
      for (final entry in positions.entries) {
        final p = entry.value;
        if ((p - srcNodeCenter).distance < 8 || (p - dstNodeCenter).distance < 8) continue;
        final rect = Rect.fromCenter(
          center: p,
          width: _kNodeW + 120,
          height: _kNodeH + 120,
        );
        for (final pt in pts) {
          if (rect.contains(pt)) return true;
        }
      }
      return false;
    }

    // ── Adjacent-column: simple S-curve ─────────────────────────────────────
    if (dst.dx - src.dx <= _kColGap * 4) {
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

    // ── Multi-column: arc through a horizontal bypass lane ──────────────────
    // Build a rich candidate list: fixed lanes + per-node offsets.
    final usableBottom = canvasH - _kBotPad - _kLegendH;
    final candidateYs = <double>[
      _kTopPad + 362,
      _kTopPad + 50,
      _kTopPad + 90,
      canvasH * 0.18,
      canvasH * 0.28,
      canvasH * 0.72,
      canvasH * 0.82,
      usableBottom - 90,
      usableBottom - 50,
      usableBottom - 18,
    ];

    // Also offer lanes that sit just above/below each intermediate node.
    for (final p in intermediate) {
      candidateYs.add(p.dy - _kNodeH / 2 - 36);
      candidateYs.add(p.dy + _kNodeH / 2 + 36);
    }

    // Sort by distance from the midpoint of src/dst so we prefer lanes that
    // stay close to the natural straight line when possible.
    final midY = (src.dy + dst.dy) / 2;
    candidateYs.sort((a, b) => (a - midY).abs().compareTo((b - midY).abs()));

    final midX = (src.dx + dst.dx) / 2;
    final halfCtrl = ctrlDist * 0.7;
    final arrowFrom = Offset(dst.dx - halfCtrl, dst.dy);

    const maxDeviation = 220.0;

for (final y in candidateYs) {
  if ((y - midY).abs() > maxDeviation) {
    continue;
  }{
      // Two cubic bezier segments meeting at (midX, y).
      final c1 = Offset(src.dx + halfCtrl, src.dy);
      final c2 = Offset(midX - 60, y);
      final c3 = Offset(midX + 60, y);
      final c4 = arrowFrom;

      final seg1 = _sampleCubic(src, c1, c2, Offset(midX, y));
      final seg2 = _sampleCubic(Offset(midX, y), c3, c4, dst);

      if (!samplesHitNodes([...seg1, ...seg2])) {
        return _PathData(
          path: Path()
            ..moveTo(src.dx, src.dy)
            ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, midX, y)
            ..cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, dst.dx, dst.dy),
          isSimple: false,
          arrowFrom: arrowFrom,
        );
      }
    }
}

    // Absolute fallback: route hard above all nodes.
    final fallbackY = midY.clamp(
  _kTopPad + 40,
  canvasH - _kBotPad - _kLegendH - 40,
);
    return _PathData(
      path: Path()
        ..moveTo(src.dx, src.dy)
        ..cubicTo(src.dx + halfCtrl, src.dy, midX - 20, fallbackY, midX, fallbackY)
        ..cubicTo(midX + 20, fallbackY, arrowFrom.dx, arrowFrom.dy, dst.dx, dst.dy),
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
      old.completed != completed ||
      old.theme.edgeDim != theme.edgeDim ||
      old.theme.edgeActive != theme.edgeActive ||
      old.theme.edgeBright != theme.edgeBright ||
      old.theme.edgeAlmost != theme.edgeAlmost ||
      old.theme.edgeBlocking != theme.edgeBlocking;
}