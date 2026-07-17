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
import 'widgets/responsive_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Layout constants
// ─────────────────────────────────────────────────────────────────────────────

// Base (unscaled) sizes — every screen actually gets these multiplied by a
// responsive scale factor via _LevelMapLayout.scaled() below, so the map
// shrinks/grows sensibly across phone/tablet/desktop widths.
const double _kNodeW = 148.0; // node card width
const double _kNodeH = 88.0; // node card height
const double _kColGap = 220.0; // horizontal gap between column centres
const double _kRowGap = 140.0; // vertical gap between row centres
const double _kTopPad = 96.0; // space for the top bar + scroll slider row
const double _kBotPad = 80.0;
const double _kLegendH = 58.0; // height reserved at bottom for legend
const double _kSidePad = 120.0; // left/right canvas padding
// minimum vertical padding above/below nodes

// ─────────────────────────────────────────────────────────────────────────────
//  Colour palette
// ─────────────────────────────────────────────────────────────────────────────
// (Colours are pulled from AppThemeNotifier/AppThemeData throughout this
// file rather than hardcoded here — this section header is a leftover from
// an earlier version where the palette lived in this file directly.)

// ─────────────────────────────────────────────────────────────────────────────
//  Position helpers (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

// The map's vertical extent is simply the full screen height — there's no
// separate "canvas is taller than the viewport" scroll dimension; only
// horizontal scrolling is supported (see the SingleChildScrollView further
// down), so canvas height always exactly matches what's visible.
double _canvasHeight(List<GameLevel> levels, double screenH) => screenH;

// Canvas width is derived FROM the computed node positions (the widest node's
// centre X + half its width + padding) rather than being a fixed constant —
// so the scrollable width automatically grows to fit however many columns
// the dependency graph ends up needing.
double _canvasWidthFromPositions(
  Map<String, Offset> positions, {
  double nodeW = _kNodeW,
  double sidePad = _kSidePad,
}) {
  final maxX = positions.values.fold<double>(0.0, (cur, p) => max(cur, p.dx));
  return maxX + nodeW / 2 + sidePad;
}

// Bundles every layout constant above into one object, scaled by a single
// responsive factor — passing this one object around (rather than each
// constant individually) keeps every layout/drawing function's signature
// manageable.
class _LevelMapLayout {
  final double nodeW;
  final double nodeH;
  final double colGap;
  final double rowGap;
  final double topPad;
  final double botPad;
  final double legendH;
  final double sidePad;

  const _LevelMapLayout({
    required this.nodeW,
    required this.nodeH,
    required this.colGap,
    required this.rowGap,
    required this.topPad,
    required this.botPad,
    required this.legendH,
    required this.sidePad,
  });

  factory _LevelMapLayout.scaled(double scale) {
    return _LevelMapLayout(
      nodeW: _kNodeW * scale,
      nodeH: _kNodeH * scale,
      colGap: _kColGap * scale,
      rowGap: _kRowGap * scale,
      topPad: _kTopPad * scale,
      botPad: _kBotPad * scale,
      legendH: _kLegendH * scale,
      sidePad: _kSidePad * scale,
    );
  }
}

/// Computes an (x, y) position for every level, arranged as a horizontal
/// layered graph: each level's column ("layer") is determined by its
/// dependency depth, and within a column, levels are stacked vertically and
/// ordered to roughly line up with their prerequisites' average Y position
/// (a simple barycenter heuristic) so edges cross each other as little as
/// possible.
Map<String, Offset> _computePositionsFromDeps(
  List<GameLevel> levels,
  double canvasH,
  _LevelMapLayout layout,
) {
  // Shared with LayerConstraintValidator in game_level.dart, so the layout
  // rendered here and the startup validation can never disagree about what
  // a "layer" is.
  final layerById = computeLevelLayers(levels);

  // Flattens any UnlockRule (including nested RequireExpression trees) down
  // to the flat list of level ids it depends on — used purely to compute
  // each level's barycenter below, not for unlock evaluation itself (that's
  // UnlockRule.isSatisfied, called elsewhere).
  List<String> extractLevelDependencies(GameLevel level) {
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

  // Group every level into its column (layer index), per computeLevelLayers.
  final Map<int, List<GameLevel>> cols = {};
  for (final l in levels) {
    final c = layerById[l.id] ?? 0;
    cols.putIfAbsent(c, () => []).add(l);
  }

  final Map<String, Offset> result = {};
  for (final entry in cols.entries) {
    final colIdx = entry.key;
    final members = [...entry.value];

    // Sort members within this column by "barycenter": the average Y
    // position of each level's prerequisites (falling back to the level's
    // own authored `y` hint when it has no resolvable deps). This is the
    // classic layered-graph-drawing heuristic for minimizing edge crossings
    // — levels whose prerequisites cluster near the top tend to end up near
    // the top of their own column too.
    members.sort((a, b) {
      double barycenter(GameLevel level) {
        final deps = extractLevelDependencies(level);

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

    // Column X is simply sidePad + colIdx columns of colGap width — evenly
    // spaced, left to right.
    final cx = layout.sidePad + colIdx * layout.colGap;
    final count = members.length;
    // Vertical space actually available for node centres, after reserving
    // room for the top bar and the bottom legend.
    final usableH = canvasH - layout.topPad - layout.botPad - layout.legendH;
    // Use the ideal rowGap unless there isn't enough usableH to fit every
    // member at that spacing — in a tall column, shrink the gap so all
    // members still fit rather than overflowing the canvas.
    final gap = count > 1 ? min(layout.rowGap, usableH / (count - 1)) : 0.0;
    final totalSpan = count > 1 ? gap * (count - 1) : 0.0;
    // Center the whole stack of nodes vertically within usableH (rather than
    // always starting from the top), so a short column doesn't look
    // top-heavy inside a tall canvas.
    final topOffset = count > 1
        ? layout.topPad + (usableH - totalSpan) / 2.0
        : layout.topPad + usableH / 2.0;
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
  final VoidCallback? onGoToMenu;

  const LevelSelectScreen({
    super.key,
    required this.progressStore,
    required this.onGoToSandbox,
    this.onGoToStudy,
    this.onGoToMenu,
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> with TickerProviderStateMixin {
  // Three independent animation controllers driving different visual
  // effects, all merged into one Listenable (see build() below) so a single
  // AnimatedBuilder repaints in response to any of them:
  //   _pulseCtrl — slow breathing glow on unlocked/completed node cards and
  //                on "missing prereq" blocking edges.
  //   _flowCtrl  — the little dot that continuously travels along
  //                active/bright edges, suggesting "progress flowing."
  //   _entryCtrl — one-shot entrance animation played once on first build.
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

    // Mirror the scroll offset into _scrollFraction so the top-bar Slider
    // stays in sync when the user pans the canvas by touch/trackpad rather
    // than by dragging the slider itself.
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      final fraction = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
      // Only setState when the fraction actually moved a meaningful amount
      // — avoids a setState() storm on every sub-pixel scroll delta.
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
      // Union of hard + easy completions — a level completed on EITHER
      // difficulty should count toward unlocking anything that depends on
      // it, regardless of which difficulty the player is currently viewing.
      _completedAny = widget.progressStore.loadCompletedLevels(LevelDifficulty.hard)
        ..addAll(widget.progressStore.loadCompletedLevels(LevelDifficulty.easy));
    });
  }

  void _reload() => _loadCompleted();

  // ── Cheat code logic ──────────────────────────────────────────────────────

  /// Valid cheat codes (case-insensitive).
  static const _kCodeUnlockAll = 'UNLOCK_ALL';
  static const _kCodeLockAll   = 'LOCK_ALL';

  // Handles raw physical keyboard input anywhere on this screen (desktop/web
  // "type a cheat code" entry point — mobile instead uses the long-press
  // dialog, see _showCheatDialog below).
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
    // Marks every level complete on BOTH difficulties (not just the one
    // currently selected) so switching the difficulty toggle afterward
    // still shows everything unlocked/completed either way.
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

  // Small transient toast (SnackBar) confirming a cheat code was applied,
  // styled to look like a terminal/console message consistent with the
  // "cheat code" theme.
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
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Opens the cheat-code dialog (triggered by long-pressing the title on mobile).
  // Mobile/touch equivalent of the physical-keyboard listener above — since
  // touch devices have no reliable "type anywhere" keyboard capture, a
  // long-press on the title opens an explicit text-entry dialog instead.
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
    ).then((_) => ctrl.dispose());
  }

  // ── Small state-query helpers used throughout build() and child widgets ──
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
    // The pushed screen may have marked the level complete — reload so
    // badges/unlocks reflect it the moment the player returns, but only if
    // this State is still mounted (the await above can outlive it).
    if (!mounted) return;
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
    final screenSize = MediaQuery.sizeOf(context);
    final screenH = screenSize.height;
    final layout = _LevelMapLayout.scaled(levelMapLayoutScale(context));
    final canvasH = _canvasHeight(kAllLevels, screenH);
    // Positions are recomputed on every build (cheap — just arithmetic over
    // kAllLevels, no layout pass) rather than cached, so completing a level
    // and reloading progress can never leave stale positions behind.
    final positions = _computePositionsFromDeps(kAllLevels, canvasH, layout);
    final canvasW = _canvasWidthFromPositions(
      positions,
      nodeW: layout.nodeW,
      sidePad: layout.sidePad,
    );
    // For the progress bar, count puzzle levels and tutorial levels separately
    final puzzleLevels = kAllLevels.where((l) => !l.isTutorial).toList();
    final completedPuzzles = _completed.intersection(puzzleLevels.map((l) => l.id).toSet()).length;

    return Focus(
      // Wraps the whole screen so physical keyboard input (the cheat-code
      // listener) is captured regardless of which child widget technically
      // has focus.
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
            // Merging all three controllers into one Listenable means this
            // single builder repaints on every tick of pulse, flow, OR entry
            // — rather than needing three separate AnimatedBuilders.
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
                          left: positions[level.id]!.dx - layout.nodeW / 2,
                          top: positions[level.id]!.dy - layout.nodeH / 2,
                          child: SizedBox(
                            width: layout.nodeW,
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
                onMenu: widget.onGoToMenu,
                scrollFraction: _scrollFraction,
                onScrollChanged: _scrollToFraction,
                difficulty: _difficulty,
                onDifficultyChanged: (d) {
                  setState(() => _difficulty = d);
                  // Switching difficulty changes which completion set
                  // `_completed` reflects (badges/progress counter), so
                  // reload it right away rather than waiting for the next
                  // unrelated rebuild.
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
  final VoidCallback? onMenu;
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
    this.onMenu,
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

                // Progress — "completed / total" label plus a thin bar,
                // scoped to puzzle levels only (tutorials are excluded from
                // both numbers so the bar reflects actual puzzle-solving
                // progress).
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
                MainMenuButton(onPressed: onMenu),
                const SizedBox(width: 4),
                // Study button is optional (onStudy may be null when this
                // screen is embedded somewhere that doesn't offer Study
                // Mode) — only rendered when a callback was actually given.
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
          // A manual horizontal-pan control mirroring the canvas's own
          // scroll position (kept in sync both ways — see
          // _LevelSelectScreenState's ScrollController listener above).
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
                      activeTrackColor: theme.accent.withValues(alpha: 0.7),
                      inactiveTrackColor: theme.gridLine,
                      thumbColor: theme.accent,
                      overlayColor: theme.accent.withValues(alpha: 0.15),
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

// The visual card representing one level on the map: tag chip, title,
// completion badges, and an unlock hint — with a pulsing glow whose
// intensity/color depends on the level's unlocked/completed state.
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
      builder: (_, _) {
        // Glow intensity: strongest+widest breathing range for completed
        // cards, a subtler breathing range for merely-unlocked cards, and
        // none at all for locked cards.
        final glowOpacity = completed
            ? 0.35 + pulseAnim.value * 0.25
            : unlocked
            ? 0.12 + pulseAnim.value * 0.08
            : 0.0;

        final borderColor = completed
            ? tagColor.withValues(alpha: 0.85)
            : unlocked
            ? tagColor.withValues(alpha: 0.55)
            : theme.textMid.withValues(alpha: 0.85);

        final bgColor = completed
            ? tagColor.withValues(alpha: 0.10)
            : unlocked
            ? tagColor.withValues(alpha: 0.05)
            : theme.border;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: completed ? 1.8 : 1.2),
            boxShadow: glowOpacity > 0
                ? [
                    BoxShadow(
                      color: tagColor.withValues(alpha: glowOpacity),
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
                    // Status icon: filled/check for completed, outline for
                    // merely unlocked, lock for locked — and a different
                    // icon pair (school vs check) specifically for tutorial
                    // levels, so tutorials read as "read this" rather than
                    // "solve this."
                    if (completed)
                      Icon(
                        level.isTutorial ? Icons.school : Icons.check_circle,
                        color: tagColor,
                        size: 13,
                      )
                    else if (unlocked)
                      Icon(
                        level.isTutorial ? Icons.school_outlined : Icons.radio_button_unchecked,
                        color: tagColor.withValues(alpha: 0.7),
                        size: 11,
                      )
                    else
                      Icon(Icons.lock_outline, color: theme.textDim, size: 11),
                    const SizedBox(width: 4),
                    // Tag chip (DFA/NFA/PDA/TM/etc.) — dimmed when locked.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: tagColor.withValues(alpha: unlocked ? 0.15 : 0.06),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        (level.tag ?? 'misc').toUpperCase(),
                        style: GoogleFonts.orbitron(
                          color: unlocked ? tagColor.withValues(alpha: 0.9) : theme.textDim,
                          fontSize: 6.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // ── Dual-difficulty completion badges ────────────────
                    // Tutorials have no difficulty split (there's nothing
                    // to "solve"), so badges are only shown for puzzle levels.
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
        // Iterates LevelDifficulty.values directly rather than hardcoding
        // two GestureDetectors, so a future third difficulty tier would
        // render automatically without touching this widget.
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

    // Both difficulties completed: overlap the two badges side by side in a
    // slightly-wider-than-one-badge box (size + 6, not size * 2) so they
    // visually cluster rather than spreading apart.
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

// Simple green circular checkmark — deliberately plain/cheap to build,
// contrasting with the much fancier hand-painted gear badge below (Hard
// mode gets the more elaborate "trophy-like" treatment).
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

// Hand-painted gold gear/star badge for Hard-mode completions — built
// entirely from Canvas primitives (no image asset) so it scales crisply at
// any size and can pick up theme-independent gold tones that don't need to
// track the app's color scheme.
class _HardBadgePainter extends CustomPainter {
  static const _gold = Color(0xFFFFB300);
  static const _goldDeep = Color(0xFFE65100);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy);

    // Gear teeth: six small rounded rectangles, each drawn at the origin
    // then rotated+translated into place around the circle — canvas.save/
    // restore isolates each tooth's transform from the next.
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

    // Outer filled circle (the gear's body, beneath the teeth already drawn).
    canvas.drawCircle(Offset(cx, cy), r * 0.68, Paint()..color = _gold..style = PaintingStyle.fill);

    // Inner dark disc — a radial gradient from deep gold to slightly more
    // transparent deep gold, giving a subtle embossed/depth look.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.50,
      Paint()
        ..shader = RadialGradient(
          colors: [_goldDeep.withValues(alpha: 0.9), _goldDeep.withValues(alpha: 0.65)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.50)),
    );

    // Six-pointed star: alternates between outer and inner radius for each
    // of the 12 points (2 per star point) around the circle, starting at
    // -π/2 (straight up) so the star sits upright.
    const starPoints = 6;
    final outerR = r * 0.33;
    final innerR = r * 0.17;
    final starPath = Path();
    for (var i = 0; i < starPoints * 2; i++) {
      final angle = (i / (starPoints * 2)) * 2 * pi - pi / 2;
      final sr = i.isEven ? outerR : innerR;
      final x = cx + cos(angle) * sr;
      final y = cy + sin(angle) * sr;
      if (i == 0) {
        starPath.moveTo(x, y);
      } else {
        starPath.lineTo(x, y);
      }
    }
    starPath.close();
    canvas.drawPath(starPath, Paint()..color = _gold..style = PaintingStyle.fill);

    // Centre dot — a small highlight to finish the badge.
    canvas.drawCircle(Offset(cx, cy), r * 0.09, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  // Static badge, nothing about it ever changes between rebuilds — never
  // worth repainting.
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

  // Produces a short, card-sized label describing what's still needed to
  // unlock this level — mirrors _LockedSheet._requiredTitles/_extractIds
  // below but returns a compact single string instead of a full list,
  // since card space is much tighter than the bottom sheet's.
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
          color: tagColor.withValues(alpha: 0.8),
          fontSize: 7.5,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (unlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
        child: Text(
          // Tutorials are "read," puzzle levels are "played" — small wording
          // difference to set the right expectation before tapping.
          level.isTutorial ? 'TAP TO READ' : 'TAP TO PLAY',
          style: GoogleFonts.sourceCodePro(
            color: tagColor.withValues(alpha: 0.9),
            fontSize: 7,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Locked: show the short prerequisite hint from _shortHint() above.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.borderMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.textMid.withValues(alpha: 0.25)),
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

// Full-detail modal shown when tapping a locked level — unlike the compact
// _UnlockHint on the card itself, this lists every individual prerequisite
// by name and clarifies whether ALL or ANY of them are required.
class _LockedSheet extends StatelessWidget {
  final GameLevel level;
  final Color tagColor;

  const _LockedSheet({required this.level, required this.tagColor});

  List<String> _requiredTitles() => _extractIds(level.unlockRule).map((id) => kLevelById[id]?.title ?? id).toList();

  // Same UnlockRule-flattening logic as
  // _computePositionsFromDeps.extractLevelDependencies and
  // _EdgePainter._extractDeps — three independent copies of essentially the
  // same tree-walk exist in this file because each call site needs a
  // slightly different return shape/context; not consolidated into one
  // shared helper.
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

  // Whether the top-level rule wants ALL listed prerequisites (vs. ANY one
  // of them) — used purely to word the sheet's heading correctly ("COMPLETE
  // ALL OF" vs "COMPLETE ANY ONE OF"). Defaults to true (AND) for any rule
  // shape not explicitly recognized, which also happens to be correct for
  // RequireLevel (a single dependency, where AND/OR is moot).
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Small "grabber" bar, purely decorative — signals this is a
          // draggable bottom sheet even though drag-to-dismiss isn't
          // actually wired up beyond the default showModalBottomSheet
          // behavior.
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: theme.borderMid, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Header row: lock icon, level title, tag chip.
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
                  color: tagColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: tagColor.withValues(alpha: 0.3)),
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

          // Prerequisite list, or a reassuring "always available" message
          // for the (here, unreachable in practice since this sheet only
          // shows for LOCKED levels) empty-deps case.
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
                      decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.6), shape: BoxShape.circle),
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

          // Dismiss button — full width for an easy, obvious tap target.
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                backgroundColor: tagColor.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: tagColor.withValues(alpha: 0.25)),
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

// Fixed footer strip explaining every node-state icon, tag color, and edge
// style used on the map — a static key/legend, not interactive.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final d = theme.data;
    // (id, color, label) triples for every tag — the id isn't actually used
    // below (only color/label are read via the `(_, color, label)` pattern
    // in the `for` loop), kept here mainly for readability/documentation of
    // which tag each row corresponds to.
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
        // Fades from transparent at the top to nearly-opaque background at
        // the bottom, so the legend readably sits over whatever part of the
        // map scrolls underneath it without a hard visual seam.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              d.bg.withValues(alpha: 0),
              d.bg.withValues(alpha: 0.92),
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              // Wrap (rather than a fixed Row) lets the legend reflow onto
              // multiple lines on narrow screens instead of overflowing.
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

                // Vertical divider between the node-state group and the
                // tag-color group.
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
                    color: color.withValues(alpha: 0.85),
                  ),

                Container(width: 1, height: 14, color: theme.borderMid),

                // ── Edge state indicators ──────────────────────────────
                // Five states, thickest/brightest-to-dimmest, mirroring the
                // classification logic in _EdgePainter._drawEdgesFor below
                // (each swatch's stroke width here roughly matches that
                // state's actual on-canvas stroke width, so the legend
                // "looks like" the real edges).
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

// Draws a simple fixed-pattern dashed horizontal line (4px dash, 3px gap)
// — used only by the legend's "Missing prereq" swatch above. The real
// dashed edges on the canvas use the more flexible _dashPath() helper on
// _EdgePainter further down, which can dash an arbitrary bezier Path rather
// than just a straight line.
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
      x += 7; // 4px dash + 3px gap
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

// One "swatch + label" row used throughout _Legend above.
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

// Faint fixed-spacing grid drawn behind everything else, purely for visual
// texture (evokes a "circuit board" / neural-net aesthetic) — not aligned
// to node positions or scroll offset in any way.
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

// Draws every prerequisite edge on the map: classifies each edge into one of
// five visual states based on completion/unlock status, routes a path that
// avoids passing through unrelated node cards, then draws a glow layer, the
// main stroke (dashed for OR-rules or "blocking" edges), an optional
// traveling flow-dot, and an arrowhead.
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

  // Same UnlockRule-flattening as _computePositionsFromDeps and
  // _LockedSheet — see the note on _LockedSheet._extractIds above for why
  // this isn't consolidated into one shared function.
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

  // Whether `rule`'s top level is an OR (any-of) rather than an AND
  // (all-of) — used to decide whether every edge INTO this level should be
  // drawn lightly dashed (an OR rule means completing just one edge's
  // source is enough, so no single edge is strictly "required").
  bool _isOrRule(UnlockRule rule) {
    if (rule is RequireAny) return true;
    if (rule is RequireExpression) return !rule.isAnd;
    return false;
  }

  // ── Main per-level edge drawing ────────────────────────────────────────────

  // Draws every incoming prerequisite edge for `dest` (one call per level in
  // paint() above covers the whole graph, since every edge is defined by
  // its destination's unlockRule).
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
      // Five mutually-exclusive states, checked in priority order (most
      // "positive" first). Each sets color/stroke-width/glow/dash together,
      // since they always travel as a unit for a given state.

      Color edgeColor;
      double strokeW;
      bool drawGlow;
      bool blockingDash; // extra-visible dashes for the "missing prereq" state

      if (srcCompleted && destCompleted) {
        // Both ends done: the brightest, thinnest "fully settled" line.
        edgeColor = theme.edgeBright.withValues(alpha: 0.90);
        strokeW = 1.0;
        drawGlow = true;
        blockingDash = false;
      } else if (srcCompleted && destUnlocked) {
        // Source done, destination now playable (but not yet completed):
        // active/encouraging color.
        edgeColor = theme.edgeActive.withValues(alpha: 0.95);
        strokeW = 1.0;
        drawGlow = true;
        blockingDash = false;
      } else if (srcCompleted && isAlmostUnlocked) {
        // THIS prereq is satisfied, but dest is still locked because of a
        // SIBLING prereq — amber, to distinguish "your part is done" from
        // "you're actually unblocked."
        edgeColor = theme.edgeAlmost;
        strokeW = 3.0;
        drawGlow = true;
        blockingDash = false;
      } else if (!srcCompleted && isAlmostUnlocked) {
        // THIS is the specific still-missing prereq blocking an
        // otherwise-almost-ready level — the thickest, pulsing, dashed
        // "pay attention to me" state, deliberately the loudest visual on
        // the whole map.
        edgeColor = theme.edgeBlocking.withValues(alpha: 0.55 + pulseValue * 0.45);
        strokeW = 4.0;
        drawGlow = true;
        blockingDash = true;
      } else {
        // Default/fallback: neither end has any special status yet — a
        // plain dim line.
        edgeColor = theme.edgeDim.withValues(alpha: 0.95);
        strokeW = 3.5;
        drawGlow = false;
        blockingDash = false;
      }

      // ── Build path, routing around intermediate nodes ───────────────────

      // Anchor the edge to the outer edge of each node card (half-width in
      // from centre), not the raw centre-to-centre line, so it visually
      // touches the card boundary rather than running underneath the card.
      final src = Offset(srcPos.dx + _kNodeW / 2, srcPos.dy);
      final dst = Offset(destPos.dx - _kNodeW / 2, destPos.dy);
      final intermediate = _getIntermediatePositions(srcId, dest.id, src.dx, dst.dx);
      final pathData = _buildEdgePath(src, dst, intermediate);

      // ── Glow layer ──────────────────────────────────────────────────────
      // A wide, heavily blurred, low-alpha stroke drawn UNDER the crisp main
      // line, giving active/bright/blocking edges a soft neon halo.
      if (drawGlow) {
        canvas.drawPath(
          pathData.path,
          Paint()
            ..color = edgeColor.withValues(alpha: 0.22)
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
      // Extra "warning pip" for the blocking state: a soft red glow dot
      // riding along the SAME animated position as the flow dot below,
      // drawn on top of the dashed line to make the missing prereq edge
      // even harder to miss. Iterates every contour of drawPath (a dashed
      // path has many short contours, one per dash segment) and drops one
      // dot per contour at the same fractional-length position.
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
      // A single small dot traveling continuously along the edge, only for
      // "positive" states (bright/active) and only on simple (single-bezier,
      // non-routed) paths — routed multi-segment paths don't get a flow dot
      // since _cubicPoint below only samples one bezier segment, not the
      // full two-segment routed path.
      if (pathData.isSimple && entryValue >= 1.0 && (srcCompleted && destUnlocked || srcCompleted && destCompleted)) {
        // Offsetting `t` by a hash of srcId (mod 1.0) staggers each edge's
        // dot to a different phase, so all the dots on screen don't move in
        // perfect unison.
        final t = (flowValue + srcId.hashCode * 0.37) % 1.0;
        final pt = _cubicPoint(src, pathData.ctrl1!, pathData.ctrl2!, dst, t);
        canvas.drawCircle(pt, destCompleted ? 3.5 : 3.0, Paint()..color = edgeColor.withValues(alpha: 0.95));
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
      // Small 5px insets on both sides avoid flagging nodes that sit almost
      // exactly at src/dst's own X (e.g. same-column siblings) as
      // "intermediate."
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
    // Used below purely for collision-testing (samplesHitNodes) — the
    // actual rendered path is still the exact analytic bezier drawn via
    // Path.cubicTo, this discretized version is only for the geometric
    // "does this route avoid every intermediate node" check.
    List<Offset> sampleCubic(Offset p0, Offset p1, Offset p2, Offset p3, {int steps = 120}) {
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
    // (srcNodeCenter/dstNodeCenter reconstruct each node's actual CENTRE
    // from the edge-anchor points src/dst, which are offset by half the
    // node width — see _drawEdgesFor's `src`/`dst` construction above —
    // purely so the exclusion check below can identify and skip testing
    // against the edge's own two endpoint nodes.)
    final srcNodeCenter = Offset(src.dx - _kNodeW / 2, src.dy);
    final dstNodeCenter = Offset(dst.dx + _kNodeW / 2, dst.dy);

    bool samplesHitNodes(List<Offset> pts) {
      for (final entry in positions.entries) {
        final p = entry.value;
        if ((p - srcNodeCenter).distance < 8 || (p - dstNodeCenter).distance < 8) continue;
        // Padded well beyond the actual card size (+120 on each dimension)
        // so a route has to clear a generous buffer around every card, not
        // just graze past its literal edge.
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
    // Cheap path for the common case (src and dst are in neighboring, or
    // near-neighboring, columns): a single symmetric cubic bezier with
    // horizontal control points, no node-avoidance search needed since
    // adjacent columns rarely have anything sitting directly between them.
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
    // A grab-bag of candidate horizontal "lanes" (Y coordinates) to route
    // through: a few fixed lanes near the top and bottom of the canvas
    // (leaving room to bypass most rows of nodes entirely), plus proportional
    // fractions of canvas height for good general coverage.
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

    // Also offer lanes that sit just above/below each intermediate node —
    // often the tightest-fitting valid route hugs directly alongside the
    // very node it needs to avoid, rather than detouring all the way to a
    // fixed far lane.
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

    // Try each candidate lane, closest-to-straight-line first, and use the
    // first one whose sampled path doesn't intersect any node card.
    for (final y in candidateYs) {
      if ((y - midY).abs() > maxDeviation) {
        // Lane deviates too far from the natural line to be worth trying —
        // skip rather than produce an oddly circuitous route.
        continue;
      }
      {
        // Two cubic bezier segments meeting at (midX, y): src -> (midX, y)
        // -> dst, forming a shallow "over/under" arc through the chosen
        // lane rather than one single bezier (which couldn't easily be bent
        // to pass through an arbitrary intermediate point).
        final c1 = Offset(src.dx + halfCtrl, src.dy);
        final c2 = Offset(midX - 60, y);
        final c3 = Offset(midX + 60, y);
        final c4 = arrowFrom;

        final seg1 = sampleCubic(src, c1, c2, Offset(midX, y));
        final seg2 = sampleCubic(Offset(midX, y), c3, c4, dst);

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

    // Absolute fallback: every candidate lane hit at least one node — route
    // hard above all nodes at the vertical midpoint, clamped to stay within
    // the canvas's usable vertical band. This can still visually clip a
    // node in pathological layouts, but guarantees SOME path is always
    // returned rather than the function failing to produce an edge at all.
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

  // Standard cubic bezier point formula (De Casteljau / Bernstein basis form)
  // — evaluates the curve at parameter t ∈ [0, 1] for both simple-path flow
  // dots and the node-avoidance sampler above.
  Offset _cubicPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * mt * p0.dx + 3 * mt * mt * t * p1.dx + 3 * mt * t * t * p2.dx + t * t * t * p3.dx,
      mt * mt * mt * p0.dy + 3 * mt * mt * t * p1.dy + 3 * mt * t * t * p2.dy + t * t * t * p3.dy,
    );
  }

  // Draws a solid triangular arrowhead at `to`, oriented along the
  // direction from `from` to `to`.
  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color, double w) {
    if ((to - from).distance < 1.0) return; // guard: no direction
    const len = 12.0;
    const wing = 7.0;
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    // Pull the tip back 2px from the exact target point so the arrowhead's
    // point doesn't visually poke past the node card's edge.
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

  // Converts a solid Path into a dashed Path by walking each contour
  // ("metric") and alternately extracting dash-length and skipping
  // gap-length sub-segments — works for any path shape (straight, single
  // bezier, or the two-segment routed paths above), unlike _DashPainter's
  // fixed-straight-line-only version used in the legend.
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