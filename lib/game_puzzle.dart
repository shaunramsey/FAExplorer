// ─────────────────────────────────────────────────────────────────────────────
//  Game Puzzle Screen
//
//  Wraps the full AutomataScreen canvas but:
//  • Shows the level description / goal at the top
//  • Adds a "Check Answer" button that loads the target SVG and runs
//    FA equivalence checking against the user's current graph
//  • Celebrates with a completion dialog on success
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
// sqrt/atan2/max/min/pi — reused for the same curve/self-loop drag math as
// AutomataScreen, plus min/max for the read-only DFA canvas's fit-to-view
// bounding-box arithmetic.
import 'dart:math';
import 'package:flutter/material.dart';
// LogicalKeyboardKey — Shift-key line-mode shortcut; rootBundle — loads the
// legacy .svg level-target asset for levels that predate DSL-embedded
// targets (see _checkAnswer's SVG fallback path below).
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'widgets/app_theme.dart';
// isCompactLayout — same phone/tablet breakpoint helper used across the app.
import 'widgets/responsive_layout.dart';

import 'game_level.dart';
// LevelDifficulty and PuzzleVariant are declared in game_level.dart.
import 'game_data.dart';
import 'tutorial_screen.dart';
import 'import_export.dart';
// Only the equivalence-checking surface is imported (an explicit `show`
// list) rather than the whole file, since equivalence_dialog.dart also
// exports dialog *widgets* this screen has no use for.
import 'dialogs/equivalence_dialog.dart'
    show
        checkEquivalence,
        checkPdaEquivalence,
        checkTmEquivalence,
        EquivalenceResult,
        EquivalenceStatus,
        AutomatonTypeChecker,
        RequiredAutomatonType;
// regexToDfa — compiles the player's typed regex for dfaToRegex levels.
import 'simulator.dart';
import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;
// LineWidget, Node, StartArrowWidget, RubberBandPainter, PaletteFab — same
// canvas building blocks AutomataScreen uses, reused here so puzzle levels
// look and feel identical to the free-form editor.
import 'widgets/graph_widgets.dart';
// ─────────────────────────────────────────────────────────────────────────────

/// A single puzzle level's play screen: an editable (or, for dfaToRegex
/// levels, read-only) automaton canvas plus a "Check Answer" flow that runs
/// equivalence checking against the level's target machine. Distinct from
/// [AutomataScreen] (the free-form designer) — this widget owns its own,
/// much simpler graph-editing state scoped to just this one level, and adds
/// per-level persistence, an easy/hard scaffold, and win-condition checking
/// on top.
class GamePuzzleScreen extends StatefulWidget {
  final GameLevel level;
  final GameProgressStore progressStore;
  final VoidCallback? onCompleted;

  /// The difficulty the player chose when opening this level.
  ///
  /// [LevelDifficulty.hard] (default) — blank canvas, original behaviour.
  /// [LevelDifficulty.easy]           — canvas is pre-seeded with nodes from
  ///                                    [GameLevel.easyScaffoldDsl].
  final LevelDifficulty difficulty;

  const GamePuzzleScreen({
    super.key,
    required this.level,
    required this.progressStore,
    this.onCompleted,
    this.difficulty = LevelDifficulty.hard,
  });

  @override
  State<GamePuzzleScreen> createState() => _GamePuzzleScreenState();
}

class _GamePuzzleScreenState extends State<GamePuzzleScreen>
    with TickerProviderStateMixin {
  // ── user graph state ────────────────────────────────────────────────────
  // The player's in-progress solution graph — same shape as
  // AutomataScreen's _nodes/_lines, but scoped to just this one level and
  // persisted under a per-level, per-difficulty key (see _saveNow).
  final Map<String, NodeData> _nodes = {};
  final Map<String, LineData> _lines = {};
  StartArrowData? _startArrow;
  int _nodeCounter = 0;
  int _lineCounter = 0;

  // ── interaction state ───────────────────────────────────────────────────
  // Same three mutually-adjusted canvas modes as AutomataScreen (see the
  // delete-mode FAB below, which turns the other two off).
  bool _lineMode = false;
  bool _deleteMode = false;
  bool _placingStartArrow = false;

  String? _draggingNodeId;
  String? _draggingLineId;
  bool _draggingStartArrow = false;
  bool _isPanningCanvas = false;
  Offset? _lastPanPosition;
  Offset? _rubberBandEnd;
  String? _lineSourceNodeId;
  Offset? _lastTapPosition;

  final FocusNode _focusNode = FocusNode();

  // ── check state ─────────────────────────────────────────────────────────
  // Drives the AppBar/bottom-bar "Check" button's spinner and the goal
  // banner's result message — set by _checkAnswer/_checkRegexAnswer.
  bool _checking = false;
  String? _checkResult;
  bool _isCorrect = false;

  // ── DFA → Regex input (only used for PuzzleVariant.dfaToRegex) ───────────
  final TextEditingController _regexInputCtrl = TextEditingController();

  /// Cached [GraphState] for [PuzzleVariant.dfaToRegex] levels.
  /// Parsed once in [initState] so [_ReadOnlyDfaCanvas] always receives the
  /// same [NodeData] objects with their DSL positions already applied.
  GraphState? _dfaGs;

  // ── save / load state ────────────────────────────────────────────────────
  bool _loadingSavedDsl = true;
  Timer? _saveDebounce;

  // ── animation ───────────────────────────────────────────────────────────
  // Drives the success-dialog's entrance animation — kicked off via
  // .forward(from: 0) right before showing the dialog on a correct answer.
  late final AnimationController _successCtrl;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Pre-parse the read-only DFA for dfaToRegex levels once here so the
    // same NodeData objects (positions already applied) are reused every build.
    if (widget.level.puzzleVariant == PuzzleVariant.dfaToRegex &&
        widget.level.dsl.isNotEmpty) {
      try {
        _dfaGs = DslCodec.importFromDsl(widget.level.dsl);
      } catch (e) {
        debugPrint('Failed to parse level DSL for dfaToRegex: $e');
      }
    }

    _loadSavedDsl();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _focusNode.dispose();
    _successCtrl.dispose();
    _regexInputCtrl.dispose();
    super.dispose();
  }

  // ── persistence helpers ─────────────────────────────────────────────────

  /// Restores the user's previous work for this level from SharedPreferences.
  ///
  /// In easy mode, if no saved progress exists yet, the canvas is seeded from
  /// either [GameLevel.easyModeNodes] (if defined) or from the level's own DSL
  /// with all transitions stripped — so nodes are pre-placed but the player
  /// still has to draw the connections.
  Future<void> _loadSavedDsl() async {
    final dsl = widget.progressStore.loadLevelDsl(widget.level.id, widget.difficulty);
    if (dsl != null && dsl.isNotEmpty) {
      // Restore existing in-progress save.
      try {
        final gs = DslCodec.importFromDsl(dsl);
        if (mounted) {
          setState(() {
            _nodes
              ..clear()
              ..addAll(gs.nodes);
            _lines
              ..clear()
              ..addAll(gs.lines);
            _startArrow = gs.startArrow;
            // Resync counters so new IDs never collide with restored ones.
            _nodeCounter = _nodes.length;
            _lineCounter = _lines.length;
          });
        }
      } catch (e) {
        debugPrint('Corrupted saved DSL for level ${widget.level.id}: $e');
        // Fall through and try the scaffold seed instead.
        _tryApplyEasyScaffold();
      }
    } else if (widget.difficulty == LevelDifficulty.easy) {
      // No saved progress yet — seed the canvas with nodes only.
      _tryApplyEasyScaffold();
    }
    if (mounted) setState(() => _loadingSavedDsl = false);
  }

  /// Seeds the canvas with pre-placed nodes and no transitions.
  ///
  /// Priority:
  ///   1. [GameLevel.easyModeNodes] — explicit per-level override.
  ///   2. The level's embedded DSL — nodes (positions, labels, accept/start
  ///      flags) are imported and all transition lines are discarded.
  ///
  /// Called on a fresh easy-mode start or after a corrupted save is detected.
  void _tryApplyEasyScaffold() {
    // ── Option 1: explicit EasyModeNode list ──────────────────────────────
    final easyNodes = widget.level.easyModeNodes;
    if (easyNodes != null && easyNodes.isNotEmpty) {
      final nodes = <String, NodeData>{};
      StartArrowData? startArrow;

      // Build fresh NodeData from each lightweight EasyModeNode descriptor
      // (id/x/y/label/isAccept/isStart) — these aren't full NodeData
      // objects in the level definition, just enough to place a state.
      for (final en in easyNodes) {
        final node = NodeData(id: en.id, position: Offset(en.x, en.y));
        node.label = en.label;
        node.isAccept = en.isAccept;
        nodes[en.id] = node;
        if (en.isStart) startArrow = StartArrowData(nodeId: en.id);
      }

      if (mounted) {
        setState(() {
          _nodes
            ..clear()
            ..addAll(nodes);
          _lines.clear(); // no transitions pre-placed
          _startArrow = startArrow;
          _nodeCounter = nodes.length;
          _lineCounter = 0;
        });
      }
      return;
    }

    // ── Option 2: derive scaffold from the level's embedded DSL ───────────
    if (widget.level.dsl.isEmpty) return; // nothing to seed from

    try {
      final gs = DslCodec.importFromDsl(widget.level.dsl);

      // Keep nodes and start arrow; drop all transition lines.
      if (mounted) {
        setState(() {
          _nodes
            ..clear()
            ..addAll(gs.nodes);
          _lines.clear(); // intentionally stripped for easy mode
          _startArrow = gs.startArrow;
          // Counter starts at the number of nodes so new IDs never collide
          // with the pre-placed ones (n0, n1, …).
          _nodeCounter = gs.nodes.length;
          _lineCounter = 0;
        });
      }
    } catch (e) {
      debugPrint('Failed to seed easy scaffold from level DSL: $e');
    }
  }

  /// Schedules a debounced save (fires 800 ms after the last canvas change).
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  /// Immediately serialises the current canvas and writes it to SharedPreferences.
  Future<void> _saveNow() async {
    try {
      final dsl = DslCodec.exportToDsl(
        GraphState(
          nodes: _nodes,
          lines: _lines,
          startArrow: _startArrow,
          nodeCounter: _nodeCounter,
          lineCounter: _lineCounter,
          automataMode: widget.level.automataMode,
        ),
      );
      await widget.progressStore.saveLevelDsl(widget.level.id, dsl, widget.difficulty);
    } catch (e) {
      debugPrint('Failed to save level progress: $e');
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  /// Mints the next unique node ("n0", "n1", …) or line ("l0", "l1", …) ID,
  /// same scheme as AutomataScreen's _nextId.
  String _nextId(String prefix) {
    if (prefix == 'n') return '$prefix${_nodeCounter++}';
    return '$prefix${_lineCounter++}';
  }

  /// Bundles the player's current graph into a [GraphState] snapshot — used
  /// by hit-testing (nodeAt/lineAt/hitStartArrow below) and by [_saveNow]/
  /// [_checkAnswer] wherever the whole graph needs to be passed as a unit.
  GraphState get _graphState => GraphState(
        nodes: _nodes,
        lines: _lines,
        startArrow: _startArrow,
        nodeCounter: _nodeCounter,
        lineCounter: _lineCounter,
        automataMode: widget.level.automataMode,
      );

  NodeData? _nodeAt(Offset p) => _graphState.nodeAt(p);

  LineData? _lineAt(Offset p) => _graphState.lineAt(p);

  /// True if some *other* node already has this exact (trimmed) label.
  /// Empty labels never count as a duplicate.
  bool _isLabelTaken(String label, String currentId) {
    final n = label.trim();
    if (n.isEmpty) return false;
    return _nodes.values.any((nd) => nd.id != currentId && nd.label.trim() == n);
  }

  /// Whether link-mode dragging may originate from this node (false for,
  /// e.g., a halt state that can't have outgoing transitions).
  bool _canStartLineFrom(String? id) =>
      id != null && (_nodes[id]?.canHaveOutgoingTransitions ?? false);

  /// Removes a state and every transition attached to it (via [_deleteLine],
  /// which also detaches the line from its *other* endpoint). Clears the
  /// start arrow too if it pointed at this node. Unlike AutomataScreen's
  /// version, this one doesn't call setState/refresh itself — callers wrap
  /// it in their own setState and follow up with _scheduleSave.
  void _deleteNode(String id) {
    final node = _nodes[id];
    if (node == null) return;
    for (final lid in node.connectedLineIds.toList()) {
      _deleteLine(lid);
    }
    if (_startArrow?.nodeId == id) _startArrow = null;
    _nodes.remove(id);
  }

  /// Removes a transition and detaches it from both endpoint nodes'
  /// connectedLineIds bookkeeping.
  void _deleteLine(String id) {
    final l = _lines[id];
    if (l == null) return;
    _nodes[l.nodeAId]?.connectedLineIds.remove(id);
    _nodes[l.nodeBId]?.connectedLineIds.remove(id);
    _lines.remove(id);
  }

  bool _hitStartArrow(Offset point) => _graphState.hitStartArrow(point);

  // ── pan / drag handlers ─────────────────────────────────────────────────
  // Same three-phase (start/update/end) drag protocol as AutomataScreen's
  // canvas — see that file's more heavily-annotated equivalents for the
  // full rationale; comments here focus on what differs.

  /// Determines what a drag gesture means the moment it begins: deleting
  /// (delete mode), starting a new link (line mode), dragging an existing
  /// line's curve, dragging the start arrow, dragging a node, or panning
  /// the canvas — checked in that priority order.
  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;
    _draggingNodeId = null;
    _draggingLineId = null;
    _isPanningCanvas = false;
    _draggingStartArrow = false;

    if (_deleteMode) {
      // Node > line > start-arrow priority — deleting a node already
      // cascades into deleting its lines via _deleteNode.
      final n = _nodeAt(pos);
      if (n != null) {
        setState(() => _deleteNode(n.id));
        _scheduleSave();
        return;
      }
      final l = _lineAt(pos);
      if (l != null) {
        setState(() => _deleteLine(l.id));
        _scheduleSave();
        return;
      }
      if (_hitStartArrow(pos)) {
        setState(() => _startArrow = null);
        _scheduleSave();
        return;
      }
      return;
    }

    if (_lineMode) {
      final node = _nodeAt(pos);
      if (node != null && _canStartLineFrom(node.id)) {
        _lineSourceNodeId = node.id;
      }
      return;
    }

    // Lines take priority over nodes so transitions can be curved near states.
    final l = _lineAt(pos);
    if (l != null) {
      _draggingLineId = l.id;
      return;
    }

    if (_hitStartArrow(pos)) {
      _draggingStartArrow = true;
      return;
    }

    final node = _nodeAt(pos);
    if (node != null) {
      _draggingNodeId = node.id;
    } else {
      _isPanningCanvas = true;
    }
  }

  /// Applies this frame's drag delta: pans every node together (canvas
  /// pan), moves a single node, adjusts the start arrow's direction/length,
  /// or reshapes a transition line — self-loop angle if the line loops back
  /// to its own node, otherwise perpendicular curve offset.
  void _onPanUpdate(DragUpdateDetails d) {
    if (_isPanningCanvas) {
      setState(() {
        for (final n in _nodes.values) {
          n.position = n.position + d.delta;
        }
      });
      return;
    }
    if (_draggingNodeId != null) {
      setState(() {
        _nodes[_draggingNodeId!]!.position += d.delta;
      });
    } else if (_draggingStartArrow && _startArrow != null) {
      setState(() {
        final center = _nodes[_startArrow!.nodeId]!.center;
        final mouse = d.localPosition;
        final dir = mouse - center;
        final dist = dir.distance;
        // Ignore tiny movements to avoid the direction snapping erratically
        // near the node's center, where the direction is numerically
        // unstable.
        if (dist > 10) {
          _startArrow!.offset = Offset(dir.dx / dist, dir.dy / dist);
          // Length is distance-from-node minus the 50px standoff (matches
          // StartArrowWidget's fixed `radius`), floored at 40.
          _startArrow!.length = max(40, dist - 50);
        }
      });
    } else if (_draggingLineId != null) {
      setState(() {
        final line = _lines[_draggingLineId!]!;
        final a = _nodes[line.nodeAId]!, b = _nodes[line.nodeBId]!;
        if (line.nodeAId == line.nodeBId) {
          // Self-loop: rotate the loop by the pointer's incremental angular
          // change around the node's center since last frame.
          final center = a.center;
          final mouse = d.localPosition;
          final previous = mouse - d.delta;
          final oldA = atan2(previous.dy - center.dy, previous.dx - center.dx);
          final newA = atan2(mouse.dy - center.dy, mouse.dx - center.dx);
          // Clamp to avoid wrap-around jumps when crossing the atan2 branch cut
          var delta = newA - oldA;
          if (delta > pi) delta -= 2 * pi;
          if (delta < -pi) delta += 2 * pi;
          line.selfLoopAngle += delta;
        } else {
          // Ordinary line: accumulate the drag delta's component
          // perpendicular to the A→B direction as the line's curve offset.
          final dx = b.center.dx - a.center.dx;
          final dy = b.center.dy - a.center.dy;
          final len = sqrt(dx * dx + dy * dy);
          if (len > 0) {
            line.perpendicularPart +=
                d.delta.dx * (dy / len) + d.delta.dy * (-dx / len);
          }
        }
      });
    }
  }

  /// Wraps [_onPanUpdate] to also track the pointer's latest position (used
  /// by [_onPanEnd] to resolve a link-mode drop target) and drive the
  /// rubber-band preview line while a link-mode drag is in progress.
  void _onPanUpdateTracking(DragUpdateDetails d) {
    _onPanUpdate(d);
    _lastPanPosition = d.localPosition;
    if (_lineSourceNodeId != null && _lineMode) {
      setState(() => _rubberBandEnd = d.localPosition);
    } else {
      // Clean up stale rubber-band state left over from a mode switch
      // mid-drag.
      if (_lineSourceNodeId != null || _rubberBandEnd != null) {
        setState(() {
          _lineSourceNodeId = null;
          _rubberBandEnd = null;
        });
      }
    }
  }

  /// Finalizes whatever drag was in progress. The only case that creates
  /// something is completing a link-mode drag over a valid destination
  /// node; every other drag kind was already applied frame-by-frame in
  /// [_onPanUpdate].
  void _onPanEnd(DragEndDetails d) {
    if (_lineMode && _lineSourceNodeId != null) {
      final dest =
          _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;
      if (dest != null) {
        final src = _lineSourceNodeId!;
        // Guard against an ineligible source and against creating a second
        // parallel transition between the same ordered pair of states.
        if (_canStartLineFrom(src) &&
            !_lines.values.any(
                (l) => l.nodeAId == src && l.nodeBId == dest.id)) {
          setState(() {
            final id = _nextId('l');
            final line = LineData(id: id, nodeAId: src, nodeBId: dest.id);
            _lines[id] = line;
            _nodes[src]?.connectedLineIds.add(id);
            _nodes[dest.id]?.connectedLineIds.add(id);
          });
        }
      }
    }
    _draggingNodeId = null;
    _draggingLineId = null;
    _draggingStartArrow = false;
    _isPanningCanvas = false;
    _lastPanPosition = null;
    _rubberBandEnd = null;
    _lineSourceNodeId = null;
    _scheduleSave();
  }

  // ── answer checking ─────────────────────────────────────────────────────

  // ── DFA → Regex answer check ────────────────────────────────────────────
  //
  // For dfaToRegex levels the player types a regex string.  We compile it to
  // an NFA, then run the standard FA equivalence check against the target DFA
  // stored in the level DSL.  The canvas is irrelevant for this variant.

  /// Compiles the player's typed regex, then checks it for language
  /// equivalence against the level's target DFA. Sets [_checkResult]/
  /// [_isCorrect] and, on success, marks the level complete and shows the
  /// success dialog — mirrors [_checkAnswer]'s structure but operates on
  /// [_regexInputCtrl].text instead of the canvas graph.
  Future<void> _checkRegexAnswer() async {
    final pattern = _regexInputCtrl.text.trim();
    if (pattern.isEmpty) {
      setState(() {
        _checkResult = '? Enter a regular expression above, then tap Check.';
      });
      return;
    }

    setState(() {
      _checking = true;
      _checkResult = null;
      _isCorrect = false;
    });

    try {
      // Compile the player's regex to an NFA.
      final compiled = regexToDfa(pattern);
      if (compiled.isError) {
        setState(() {
          _checking = false;
          _checkResult = '✗ Regex parse error: ${compiled.error}';
        });
        return;
      }

      // Load the target DFA from the level DSL.
      GraphState target;
      try {
        target = DslCodec.importFromDsl(widget.level.dsl);
      } catch (e) {
        setState(() {
          _checking = false;
          _checkResult = '⚠ Could not parse embedded level DSL.\n$e';
        });
        return;
      }

      // Run NFA ↔ DFA equivalence check.
      final result = checkEquivalence(
        nodes1: compiled.nodes,
        lines1: compiled.lines,
        startArrow1: compiled.startArrow,
        nodes2: target.nodes,
        lines2: target.lines,
        startArrow2: target.startArrow,
      );

      setState(() => _checking = false);

      switch (result.status) {
        case EquivalenceStatus.equivalent:
          _isCorrect = true;
          _checkResult = '✓ Correct! Your regex describes exactly the same language as the DFA.';
          await widget.progressStore.markCompleted(widget.level.id, widget.difficulty);
          if (!mounted) return;
          widget.onCompleted?.call();
          _successCtrl.forward(from: 0);
          _showSuccessDialog();
          break;

        case EquivalenceStatus.notEquivalent:
          // A "witness" is a concrete input string on which the two
          // machines disagree — shown to the player as a concrete
          // counterexample rather than a bare "wrong" verdict.
          final witness = result.witness ?? '';
          final by = result.acceptedByMachine;
          final yourSide   = by == 1 ? 'your regex' : 'the target DFA';
          final otherSide  = by == 1 ? 'the target DFA' : 'your regex';
          final inputDesc  = witness.isEmpty ? '~ (empty string)' : '"$witness"';
          _checkResult = '✗ Not equivalent.\n\n'
              'Distinguishing witness: $inputDesc\n'
              '$yourSide accepts it but $otherSide does not.';
          break;

        case EquivalenceStatus.unknownCapReached:
          _checkResult = '? Could not determine equivalence (search space too large).\n\n'
              'Try simplifying your regex or check manually.';
          break;

        case EquivalenceStatus.noStartState:
          // Should be unreachable in practice — regexToDfa always produces
          // a machine with a start state — but handled defensively rather
          // than left as an unmatched case.
          _checkResult = '? Compiled NFA has no start state — this is a bug. '
              'Please report it.';
          break;
      }

      setState(() {});
    } catch (e) {
      setState(() {
        _checking = false;
        _checkResult = 'Error: $e';
      });
    }
  }

  /// Main answer-checking flow for canvas-based puzzle variants
  /// (buildAutomaton / regexToDfa): resolves the level's target machine,
  /// optionally enforces a required automaton type (DFA vs NFA), runs
  /// the appropriate equivalence check for the level's automata mode
  /// (NFA/DFA exact check, or bounded PDA/TM simulation), and reports the
  /// result. Delegates to [_checkRegexAnswer] instead for dfaToRegex
  /// levels, since those check a typed string rather than the canvas.
  Future<void> _checkAnswer() async {
    // Delegate to the regex-input check for dfaToRegex levels.
    if (widget.level.puzzleVariant == PuzzleVariant.dfaToRegex) {
      await _checkRegexAnswer();
      return;
    }

    setState(() {
      _checking = true;
      _checkResult = null;
      _isCorrect = false;
    });

    try {
      // 1. Resolve target graph — prefer embedded DSL, fall back to SVG asset.
      GraphState target;
      if (widget.level.dsl.isNotEmpty) {
        try {
          target = DslCodec.importFromDsl(widget.level.dsl);
        } catch (e) {
          setState(() {
            _checking = false;
            _checkResult = '⚠ Could not parse embedded level DSL.\n$e';
          });
          return;
        }
      } else {
        // Legacy SVG-asset path: older levels shipped their target as a
        // bundled .svg file (exported from another tool) rather than
        // inline DSL text — still supported for backward compatibility.
        String svgText;
        try {
          svgText = await rootBundle.loadString(widget.level.svgAsset);
        } catch (_) {
          setState(() {
            _checking = false;
            _checkResult =
                '⚠ Target level file not found.\n(${widget.level.svgAsset})\n\nMake sure it is listed in pubspec.yaml.';
          });
          return;
        }
        try {
          target = DslCodec.importFromSvg(svgText);
        } catch (e) {
          setState(() {
            _checking = false;
            _checkResult =
                '⚠ Could not parse target SVG.\n$e';
          });
          return;
        }
      }

      // 2. If the level specifies a required automaton type (DFA vs NFA), check
      // it now — BEFORE running the (more expensive) equivalence check.
      // In easy mode, this check is skipped when the level sets
      // easyModeBypassTypeCheck = true, allowing any FA type.
      final requiredType = widget.level.requiredAutomatonType;
      final skipTypeCheck = widget.difficulty == LevelDifficulty.easy &&
          widget.level.easyModeBypassTypeCheck;
      if (requiredType != null && !skipTypeCheck) {
        final typeResult = AutomatonTypeChecker.check(
          nodes: _nodes,
          lines: _lines,
          startArrow: _startArrow,
          alphabet: widget.level.alphabet,
          required: requiredType,
        );

        if (!typeResult.isCorrectType) {
          // Build a player-facing message. Hard errors first, then warnings —
          // shared with game_data.dart so the formatting stays consistent
          // wherever a type-check result needs to be displayed.
          final msg = buildTypeErrorMessage(typeResult)!;
          final detail = [
            ...msg.errors.map((e) => '  ✗ $e'),
            ...msg.warnings.map((w) => '  ⚠ $w'),
          ].join('\n');

          setState(() {
            _checking = false;
            _checkResult = '${msg.headline}'
                '${detail.isNotEmpty ? '\n\n$detail' : ''}';
          });
          return; // block progression — don't run equivalence check
        }
      }

      // 3. Run the appropriate equivalence check based on the level's assigned
      // automata mode.
      //    NFA/DFA: exact BFS-based check.
      //    PDA / TM: bounded simulation (heuristic; detects many bugs).
      final levelMode = widget.level.automataMode;
      EquivalenceResult result;
      switch (levelMode) {
        case AutomataMode.pda:
          result = checkPdaEquivalence(
            nodes1: _nodes,
            lines1: _lines,
            startArrow1: _startArrow,
            nodes2: target.nodes,
            lines2: target.lines,
            startArrow2: target.startArrow,
            maxInputLength: 6,
            maxTests: 600,
          );
          break;
        case AutomataMode.tm:
          result = checkTmEquivalence(
            nodes1: _nodes,
            lines1: _lines,
            startArrow1: _startArrow,
            nodes2: target.nodes,
            lines2: target.lines,
            startArrow2: target.startArrow,
            maxInputLength: 5,
            maxTests: 400,
            maxStepsPerInput: 500,
          );
          break;
        default:
          result = checkEquivalence(
            nodes1: _nodes,
            lines1: _lines,
            startArrow1: _startArrow,
            nodes2: target.nodes,
            lines2: target.lines,
            startArrow2: target.startArrow,
          );
      }

      setState(() {
        _checking = false;
      });

      switch (result.status) {
        case EquivalenceStatus.equivalent:
          _isCorrect = true;
          _checkResult = '✓ Correct! Your automaton is equivalent to the target.';
          await widget.progressStore.markCompleted(widget.level.id, widget.difficulty);
          await _saveNow(); // persist the winning solution immediately
          if (!mounted) return;
          widget.onCompleted?.call();
          _successCtrl.forward(from: 0);
          _showSuccessDialog();
          break;

        case EquivalenceStatus.notEquivalent:
          final witness = result.witness ?? '';
          final by = result.acceptedByMachine;
          final yourMachine = by == 1 ? 'your automaton' : 'the target';
          final other = by == 1 ? 'the target' : 'your automaton';
          final inputDesc = witness.isEmpty ? '∅ (empty string)' : '"$witness"';
          _checkResult = '✗ Not equivalent.\n\n'
              'Distinguishing witness: $inputDesc\n'
              '$yourMachine accepts it but $other does not.';
          break;

        case EquivalenceStatus.unknownCapReached:
          if (levelMode == AutomataMode.pda || levelMode == AutomataMode.tm) {
            // PDA / TM equivalence is undecidable in general — the bounded
            // simulation passed all test cases, which is the best we can do.
            // Count this as a level completion.
            _isCorrect = true;
            _checkResult = '✓ All tested inputs matched the target behaviour.\n\n'
                'PDA/TM equivalence cannot be verified exactly, but your machine '
                'passed the full bounded test suite — level complete!';
            await widget.progressStore.markCompleted(widget.level.id, widget.difficulty);
            await _saveNow();
            if (!mounted) return;
            widget.onCompleted?.call();
            _successCtrl.forward(from: 0);
            _showSuccessDialog();
          } else {
            // For NFA/DFA levels this path means the exact BFS search
            // exceeded its state-space cap — genuinely inconclusive, unlike
            // the PDA/TM case above where "passed everything we tried" is
            // treated as a pass.
            _checkResult = '? Could not determine equivalence (search space too large).\n\n'
                'Try simplifying your automaton or check manually.';
          }
          break;

        case EquivalenceStatus.noStartState:
          _checkResult =
              '? No start state.\n\nAdd a start arrow pointing to your initial state.';
          break;
      }

      setState(() {});
    } catch (e) {
      setState(() {
        _checking = false;
        _checkResult = 'Error: $e';
      });
    }
  }

  /// Shows the celebratory "LEVEL COMPLETE" dialog. Not dismissible by
  /// tapping outside — the player must explicitly tap "BACK TO MAP", which
  /// pops both the dialog and this puzzle screen in one go.
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SuccessDialog(
        level: widget.level,
        onNext: () {
          Navigator.of(context).pop(); // close dialog
          Navigator.of(context).pop(); // go back to level select
        },
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // If somehow a tutorial level is opened via GamePuzzleScreen, redirect it.
    if (widget.level.isTutorial) {
      return TutorialScreen(
        level: widget.level,
        progressStore: widget.progressStore,
        onCompleted: widget.onCompleted,
      );
    }
    final theme = context.watch<AppThemeNotifier>();
    final compact = isCompactLayout(context);
    return Scaffold(
      backgroundColor: theme.bg,
      // dfaToRegex levels keep a persistent text field docked under a
      // pannable read-only canvas. Letting the Scaffold shrink for the
      // keyboard (the default) resizes that canvas's viewport mid-read,
      // which makes InteractiveViewer re-clamp the current pan position —
      // felt as an unexpected "snap". Other puzzle variants don't have this
      // canvas+persistent-field combo, so they keep the default behaviour.
      resizeToAvoidBottomInset:
          widget.level.puzzleVariant != PuzzleVariant.dfaToRegex,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.level.title,
                style: GoogleFonts.orbitron(
                    fontWeight: FontWeight.w700, fontSize: compact ? 14 : null)),
            // Difficulty label (EASY/HARD) is dropped on compact/phone
            // widths to save AppBar vertical space — the title alone still
            // fits comfortably there.
            if (!compact)
              Text(
                widget.difficulty.displayName.toUpperCase(),
                style: GoogleFonts.orbitron(
                  fontSize: 9,
                  letterSpacing: 3,
                  color: widget.difficulty.isHard
                      ? const Color(0xFFFFB300)
                      : const Color(0xFF4CAF50),
                ),
              ),
          ],
        ),
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Three mutually-exclusive states for the "Check" action:
          // spinner while checking, a labeled button on wide layouts, or a
          // bare icon button on compact ones (where the bottom bar's full
          // "Check Answer" button is the primary action instead — see
          // bottomNavigationBar below).
          if (_checking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!compact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.icon(
                onPressed: _checkAnswer,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('Check',
                    style: GoogleFonts.orbitron(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: _isCorrect
                      ? theme.accentGreen
                      : theme.accent,
                  foregroundColor: theme.bg,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Check answer',
              onPressed: _checkAnswer,
              icon: Icon(Icons.check_circle_outline,
                  color: _isCorrect ? theme.accentGreen : theme.accent),
            ),
        ],
      ),
      body: _loadingSavedDsl
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(theme),

      // ── FAB toolbar ───────────────────────────────────────────────────
      // dfaToRegex levels render a read-only canvas (see _buildDfaToRegexBody)
      // — there's nothing to edit, so no editing-mode FABs are shown.
      floatingActionButton: widget.level.puzzleVariant == PuzzleVariant.dfaToRegex
          ? null // no FAB needed — canvas is read-only
          : _buildFab(context, theme),
      // Compact layouts get a full-width "Check Answer" button pinned to
      // the bottom instead of relying solely on the small AppBar icon —
      // easier to hit on a phone. Suppressed for dfaToRegex (its own
      // regex-input panel already docks at the bottom of the screen).
      bottomNavigationBar: compact &&
              widget.level.puzzleVariant != PuzzleVariant.dfaToRegex
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FilledButton.icon(
                  onPressed: _checking ? null : _checkAnswer,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text('Check Answer',
                      style: GoogleFonts.orbitron(
                          fontWeight: FontWeight.w700, fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _isCorrect ? theme.accentGreen : theme.accent,
                    foregroundColor: theme.bg,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  // ── Body router ──────────────────────────────────────────────────────────

  /// Picks the body layout for the level's [PuzzleVariant]: a read-only
  /// DFA diagram + regex input for dfaToRegex, or the standard editable
  /// canvas for everything else.
  Widget _buildBody(AppThemeNotifier theme) {
    switch (widget.level.puzzleVariant) {
      case PuzzleVariant.dfaToRegex:
        return _buildDfaToRegexBody(theme);
      case PuzzleVariant.regexToDfa:
      case PuzzleVariant.buildAutomaton:
        return _buildCanvasBody(theme);
    }
  }

  // ── DFA → Regex body: read-only DFA canvas + regex text input ────────────

  /// Layout for dfaToRegex levels: goal banner, a pannable/zoomable
  /// read-only rendering of the target DFA, and a docked text field for
  /// the player's regex answer. Switches between a vertical stack (narrow)
  /// and the DFA canvas getting more relative space (wide) via
  /// [LayoutBuilder].
  Widget _buildDfaToRegexBody(AppThemeNotifier theme) {
    final gs = _dfaGs;
    final compact = isCompactLayout(context);
    // The Scaffold no longer resizes for the keyboard on this puzzle variant
    // (see resizeToAvoidBottomInset above), so the regex field has to lift
    // itself above the keyboard manually — the DFA canvas above it is
    // otherwise unaffected and keeps a stable viewport while typing.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = !compact && constraints.maxWidth > 500;

        final goalBanner = _GoalBanner(
          description: widget.level.description,
          tagColor: theme.tagColor(widget.level.tag),
          automataMode: widget.level.automataMode,
          requiredAutomatonType: widget.level.requiredAutomatonType,
          alphabet: widget.level.alphabet,
          checkResult: _checkResult,
          isCorrect: _isCorrect,
          puzzleVariant: widget.level.puzzleVariant,
        );

        // Falls back to a plain error message if the level's DSL failed to
        // parse in initState (_dfaGs stayed null) — the player would
        // otherwise see a blank canvas with no explanation.
        final dfaPreview = gs == null
            ? Center(
                child: Text('Could not load DFA.',
                    style: TextStyle(color: theme.textMid)))
            : _ReadOnlyDfaCanvas(gs: gs, theme: theme);

        final regexPanel = _RegexInputPanel(
          controller: _regexInputCtrl,
          theme: theme,
          isCorrect: _isCorrect,
        );

        if (wide) {
          // Wide layout: DFA canvas gets a fixed flex ratio (3 parts of
          // the Column) since the regex panel's own height is fixed/
          // content-driven, not flex-based.
          return Column(
            children: [
              goalBanner,
              Expanded(
                flex: 3,
                child: dfaPreview,
              ),
              Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: regexPanel,
              ),
            ],
          );
        }

        return Column(
          children: [
            goalBanner,
            // The regex panel only needs its natural (content) height — it's
            // a label, a single text field, and a hint line. Forcing it into
            // an Expanded flex slot (as before) claimed roughly a third of
            // the screen on narrow/mobile layouts that it never actually
            // used, starving the DFA diagram of the room it needs to be
            // readable. Give it just what it needs and let the diagram have
            // everything else.
            Expanded(child: dfaPreview),
            Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: regexPanel,
            ),
          ],
        );
      },
    );
  }

  // ── Standard canvas body (buildAutomaton + regexToDfa) ───────────────────

  /// Layout for buildAutomaton and regexToDfa levels: goal banner on top,
  /// full-size editable canvas below — structurally the same
  /// KeyboardListener > GestureDetector > Stack shape as AutomataScreen's
  /// canvas, just without the simulator/mode-switching machinery (a puzzle
  /// level always has exactly one fixed automataMode, set by the level
  /// definition).
  Widget _buildCanvasBody(AppThemeNotifier theme) {
    return Column(
        children: [
          // ── Goal banner ──────────────────────────────────────────────
          _GoalBanner(
            description: widget.level.description,
            tagColor: theme.tagColor(widget.level.tag),
            automataMode: widget.level.automataMode,
            requiredAutomatonType: widget.level.requiredAutomatonType,
            alphabet: widget.level.alphabet,
            checkResult: _checkResult,
            isCorrect: _isCorrect,
            puzzleVariant: widget.level.puzzleVariant,
            targetRegex: widget.level.targetRegex,
          ),

          // ── Canvas ───────────────────────────────────────────────────
          Expanded(
            child: KeyboardListener(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (e) {
                // Shift toggles line mode, same shortcut as AutomataScreen.
                final isShift = e.logicalKey == LogicalKeyboardKey.shiftLeft ||
                    e.logicalKey == LogicalKeyboardKey.shiftRight;
                if (isShift && e is KeyDownEvent) {
                  setState(() => _lineMode = !_lineMode);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (d) {
                  // Double-tapping empty canvas creates a new node centered
                  // on the tap point; suppressed in line mode or when the
                  // tap actually landed on an existing node.
                  if (_lineMode) return;
                  if (_nodeAt(d.localPosition) != null) return;
                  setState(() {
                    final pos = d.localPosition - const Offset(50, 50);
                    final id = _nextId('n');
                    _nodes[id] = NodeData(id: id, position: pos);
                  });
                  _scheduleSave();
                },
                onTapDown: (d) {
                  _lastTapPosition = d.localPosition;
                  // Tapping a node while placing the start arrow commits it
                  // as the start state and exits placement mode.
                  if (_placingStartArrow) {
                    final n = _nodeAt(d.localPosition);
                    if (n != null) {
                      setState(() {
                        _startArrow = StartArrowData(nodeId: n.id);
                        _placingStartArrow = false;
                      });
                      _scheduleSave();
                    }
                  }
                },
                onTap: () {
                  // A plain tap on empty canvas returns keyboard focus to
                  // the canvas, so the Shift-key shortcut keeps working
                  // after finishing a label edit.
                  if (_lastTapPosition == null ||
                      _nodeAt(_lastTapPosition!) == null) {
                    _focusNode.requestFocus();
                  }
                  _lastTapPosition = null;
                },
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdateTracking,
                onPanEnd: _onPanEnd,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_startArrow != null &&
                        _nodes[_startArrow!.nodeId] != null)
                      Positioned.fill(
                        child: StartArrowWidget(
                          data: _startArrow!,
                          nodeCenter: _nodes[_startArrow!.nodeId]!.center,
                          deleteMode: _deleteMode,
                          onDelete: () {
                            setState(() => _startArrow = null);
                            _scheduleSave();
                          },
                        ),
                      ),

                    // rubber-band line
                    if (_lineSourceNodeId != null && _rubberBandEnd != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: RubberBandPainter(
                              start: _nodes[_lineSourceNodeId!]!.center,
                              end: _rubberBandEnd!,
                              color: theme.accent,
                            ),
                          ),
                        ),
                      ),

                    // Transition lines, painted before nodes so node
                    // circles sit on top of line endpoints. `highlighted`
                    // is always false here — puzzle levels have no
                    // simulator/step-playback UI to highlight against.
                    ..._lines.values.map((line) {
                      final a = _nodes[line.nodeAId];
                      final b = _nodes[line.nodeBId];
                      if (a == null || b == null) return const SizedBox.shrink();
                      return KeyedSubtree(
                        key: ValueKey(line.id),
                        child: Positioned.fill(
                          child: LineWidget(
                            data: line,
                            centerA: a.center,
                            centerB: b.center,
                            deleteMode: _deleteMode,
                            highlighted: false,
                            onLabelChanged: (t) {
                              setState(() => line.label = t);
                              _scheduleSave();
                            },
                          ),
                        ),
                      );
                    }),

                    ..._nodes.values.map(
                      (node) => Node(
                        key: ValueKey(node.id),
                        data: node,
                        lineMode: _lineMode,
                        // Locks node label editing while placing the start
                        // arrow — a tap during that mode should only ever
                        // commit the start arrow, never open the label
                        // field underneath it.
                        interactionLocked: _placingStartArrow,
                        deleteMode: _deleteMode,
                        highlighted: false,
                        isLabelTaken: _isLabelTaken,
                        onLabelChanged: (t) {
                          setState(() => node.label = t);
                          _scheduleSave();
                        },
                        onLineModeSelect: () {
                          if (_lineMode && _canStartLineFrom(node.id)) {
                            _lineSourceNodeId = node.id;
                          }
                        },
                        onDoubleTap: () {
                          // In line mode, double-tap is repurposed: instead
                          // of toggling accept state, it drops the start
                          // arrow on whichever node was double-clicked.
                          if (_lineMode) {
                            setState(() => _startArrow = StartArrowData(nodeId: node.id));
                            _scheduleSave();
                            return;
                          }

                          if (!node.canToggleNormalAccept) return;
                          setState(() => node.isAccept = !node.isAccept);
                          _scheduleSave();
                        },
                        onDelete: () {
                          setState(() => _deleteNode(node.id));
                          _scheduleSave();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  }

  // ── FAB toolbar (canvas modes only) ──────────────────────────────────────

  /// Vertical stack of mode-toggle FABs for canvas-based puzzle variants:
  /// start-arrow placement, delete mode, line mode, and a "clear canvas"
  /// action (with a confirmation dialog) — a trimmed-down version of
  /// AutomataScreen's FAB column, minus the simulator-visibility toggle
  /// (puzzle levels have no simulator panel).
  Widget _buildFab(BuildContext context, AppThemeNotifier theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PaletteFab(
          heroTag: 'gp_start',
          tooltip: 'Set start state',
          icon: Icons.play_arrow,
          active: _placingStartArrow,
          activeColor: const Color(0xFFFF6D00),
          onPressed: () =>
              setState(() => _placingStartArrow = !_placingStartArrow),
        ),
        const SizedBox(height: 10),
        PaletteFab(
          heroTag: 'gp_delete',
          tooltip: 'Delete mode',
          icon: Icons.delete_outline,
          active: _deleteMode,
          activeColor: Theme.of(context).colorScheme.error,
          onPressed: () => setState(() {
            _deleteMode = !_deleteMode;
            // Delete mode is mutually exclusive with the other editing
            // modes.
            if (_deleteMode) {
              _lineMode = false;
              _placingStartArrow = false;
            }
          }),
        ),
        const SizedBox(height: 10),
        PaletteFab(
          heroTag: 'gp_line',
          tooltip: _lineMode ? 'Exit line mode' : 'Enter line mode',
          icon: _lineMode ? Icons.timeline : Icons.add_link,
          active: _lineMode,
          activeColor: theme.accent,
          onPressed: () => setState(() => _lineMode = !_lineMode),
        ),
        const SizedBox(height: 10),
        PaletteFab(
          heroTag: 'gp_reset',
          tooltip: 'Clear canvas',
          icon: Icons.refresh,
          active: false,
          activeColor: theme.accent,
          small: true,
          onPressed: () {
            // Read the theme once via the static accessor (rather than
            // context.watch) since this dialog builder runs outside the
            // normal widget-rebuild lifecycle of _buildFab itself.
            final dialogTheme = AppThemeNotifier.read(context);
            showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: dialogTheme.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: dialogTheme.borderMid),
              ),
              title: Text(
                'Clear canvas?',
                style: GoogleFonts.orbitron(
                  color: dialogTheme.textLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              content: Text(
                'This will delete all your work on this puzzle.',
                style: GoogleFonts.sourceCodePro(
                  color: dialogTheme.textMid,
                  fontSize: 13,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: dialogTheme.textDim,
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.orbitron(fontSize: 11, letterSpacing: 1)),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _nodes.clear();
                      _lines.clear();
                      _startArrow = null;
                      _nodeCounter = 0;
                      _lineCounter = 0;
                      _checkResult = null;
                      _isCorrect = false;
                    });
                    widget.progressStore.clearLevelDsl(
                      widget.level.id,
                      widget.difficulty,
                    );
                    // In easy mode, re-seed the scaffold after clearing so
                    // nodes reappear at their original positions.
                    if (widget.difficulty == LevelDifficulty.easy) {
                      _tryApplyEasyScaffold();
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Clear',
                      style: GoogleFonts.orbitron(fontSize: 11, letterSpacing: 1)),
                ),
              ],
            ),
          );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Goal banner
// ─────────────────────────────────────────────────────────────────────────────

/// The panel docked at the top of a puzzle screen: the level's prose
/// description, an alphabet/mode info row, an optional target-regex box
/// (regexToDfa levels), and the latest check result (success/failure
/// message), all left-bordered in the level's [tagColor].
class _GoalBanner extends StatelessWidget {
  final String description;
  final Color tagColor;
  final String? checkResult;
  final bool isCorrect;
  final AutomataMode automataMode;
  final RequiredAutomatonType? requiredAutomatonType;
  final Set<String> alphabet;
  final PuzzleVariant puzzleVariant;
  final String targetRegex;

  const _GoalBanner({
    required this.description,
    required this.tagColor,
    required this.automataMode,
    required this.alphabet,
    this.requiredAutomatonType,
    this.puzzleVariant = PuzzleVariant.buildAutomaton,
    this.targetRegex = '',
    this.checkResult,
    this.isCorrect = false,
  });

  /// Returns the display label and color for the mode chip.
  (String label, Color color) _modeInfo(AppThemeNotifier theme) {
    // If a specific automaton type is required, that is the primary label.
    if (requiredAutomatonType != null) {
      return switch (requiredAutomatonType!) {
        RequiredAutomatonType.dfa => ('DFA', const Color(0xFF4FC3F7)),
        RequiredAutomatonType.nfa => ('NFA', const Color(0xFFCE93D8)),
      };
    }
    // Otherwise derive from the automata mode.
    return switch (automataMode) {
      AutomataMode.pda => ('PDA', const Color(0xFFFFB74D)),
      AutomataMode.tm  => ('TM',  const Color(0xFFEF9A9A)),
      // ndfa with no type restriction means either DFA or NFA is accepted.
      _                => ('FA',  const Color(0xFF80CBC4)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final (modeLabel, modeColor) = _modeInfo(theme);

    // Alphabet display: sorted symbols joined by commas, or "—" if empty.
    final alphabetText = alphabet.isEmpty
        ? '—'
        : (alphabet.toList()..sort()).join(', ');

    return Container(
      width: double.infinity,
      color: theme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Description ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: tagColor, width: 4),
                bottom: BorderSide(color: theme.borderMid),
              ),
            ),
            child: Text(
              description,
              style: GoogleFonts.sourceCodePro(
                fontSize: 13,
                color: theme.textMid,
                height: 1.5,
              ),
            ),
          ),

          // ── Alphabet + Mode info row ──────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: theme.surface,
              border: Border(
                left: BorderSide(color: tagColor, width: 4),
                bottom: BorderSide(color: theme.borderMid),
              ),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Alphabet chip
                _InfoChip(
                  icon: Icons.abc,
                  label: 'Σ = { $alphabetText }',
                  color: theme.textDim,
                  theme: theme,
                ),
                // Mode chip
                _InfoChip(
                  icon: Icons.account_tree_outlined,
                  label: modeLabel,
                  color: modeColor,
                  theme: theme,
                  bold: true,
                ),
              ],
            ),
          ),

          // ── Regex expression box (regexToDfa levels only) ─────────────
          // Shows the target regex the player must build an equivalent
          // machine for — only meaningful (and non-empty) for regexToDfa,
          // hence the puzzleVariant guard.
          if (puzzleVariant == PuzzleVariant.regexToDfa && targetRegex.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF050D18),
                border: Border(
                  left: BorderSide(color: const Color(0xFF00E5FF), width: 4),
                  bottom: BorderSide(color: theme.borderMid),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.functions, color: Color(0xFF00E5FF), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Regex:  ',
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 12,
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      targetRegex,
                      style: GoogleFonts.courierPrime(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00E5FF),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Check result ──────────────────────────────────────────────
          // Only rendered once a check has actually run; animates its
          // background/text color in when correctness flips (e.g. a fresh
          // wrong answer replaces a previous one without an abrupt jump).
          if (checkResult != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isCorrect
                  ? theme.accentGreen.withValues(alpha: 0.12)
                  : const Color(0xFF1F0D0D),
              child: Text(
                checkResult!,
                style: GoogleFonts.sourceCodePro(
                  fontSize: 12,
                  color: isCorrect
                      ? theme.accentGreen
                      : const Color(0xFFFF6B6B),
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small labelled chip used inside _GoalBanner
// ─────────────────────────────────────────────────────────────────────────────

/// A small icon+label pill in a tinted rounded box — used for both the
/// alphabet chip ("Σ = { a, b }") and the mode chip ("DFA"/"PDA"/etc.) in
/// [_GoalBanner].
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final AppThemeNotifier theme;
  final bool bold;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.theme,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.sourceCodePro(
              fontSize: 12,
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              letterSpacing: bold ? 0.8 : 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Success dialog
// ─────────────────────────────────────────────────────────────────────────────

/// The "LEVEL COMPLETE" celebration dialog shown by [_showSuccessDialog]:
/// a glowing checkmark badge, the level title, and a "BACK TO MAP" button.
/// Plays a bouncy elastic scale-in animation on mount.
class _SuccessDialog extends StatefulWidget {
  final GameLevel level;
  final VoidCallback onNext;

  const _SuccessDialog({required this.level, required this.onNext});

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Starts playing immediately on mount (..forward()) — the dialog
    // doesn't wait for any external trigger since showing it *is* the
    // trigger.
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    // elasticOut gives the badge a bouncy "pop" overshoot rather than a
    // flat linear/eased scale-up, matching the celebratory tone.
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final tagColor = context.watch<AppThemeNotifier>().tagColor(widget.level.tag);

    return Dialog(
      backgroundColor: theme.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: tagColor.withValues(alpha: 0.8), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ScaleTransition(
          scale: _scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // glow star
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tagColor.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: tagColor.withValues(alpha: 0.6),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(Icons.check, color: tagColor, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'LEVEL COMPLETE',
                style: GoogleFonts.orbitron(
                  color: tagColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.level.title,
                style: GoogleFonts.orbitron(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: widget.onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: tagColor,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Text(
                    'BACK TO MAP',
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
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
//  Read-only DFA canvas  (used by dfaToRegex levels)
//
//  Renders the target DFA in a non-interactive, scrollable canvas so the player
//  can read it while typing their regex answer.
// ─────────────────────────────────────────────────────────────────────────────

class _ReadOnlyDfaCanvas extends StatefulWidget {
  final GraphState gs;
  final AppThemeNotifier theme;

  const _ReadOnlyDfaCanvas({required this.gs, required this.theme});

  @override
  State<_ReadOnlyDfaCanvas> createState() => _ReadOnlyDfaCanvasState();
}

class _ReadOnlyDfaCanvasState extends State<_ReadOnlyDfaCanvas> {
  // Extra space reserved around the diagram's node bounding box when
  // computing content size / fit-to-view scale, so nodes/labels near the
  // edge aren't flush against the viewport border.
  static const double _contentPadding = 90;
  static const double _minScale = 0.15;
  static const double _maxScale = 3.0;

  // Desired pan headroom in *screen* pixels, kept roughly constant across
  // zoom levels.
  //
  // boundaryMargin has to do more than just "add some space": if the
  // (scaled) content is smaller than the viewport along an axis —
  // routine, since _fitToView scales uniformly and most diagrams don't
  // match the screen's aspect ratio — InteractiveViewer's boundary math
  // degenerates for that axis and pins the content to one edge instead of
  // centering/panning normally. That's what made horizontal panning feel
  // "forced to the left" while vertical (the axis that actually filled the
  // viewport after fitting) panned fine. _boundaryMargin below computes
  // each axis independently and pads enough to cover that axis's slack,
  // not just a flat guess.
  static const double _screenMarginPx = 300;

  final TransformationController _transformCtrl = TransformationController();
  // Guards the one-time auto-fit-to-view that runs on first layout (see
  // build()'s post-frame callback below) — flipped back to false in
  // didUpdateWidget when a different DFA is loaded, so re-fitting happens
  // again for the new content.
  bool _didAutoFit = false;
  Size _lastViewportSize = Size.zero;

  /// Computes InteractiveViewer's boundaryMargin fresh from the current
  /// zoom level and content size, independently per axis — see the class
  /// doc comment above for why a flat/constant margin doesn't work here.
  EdgeInsets get _boundaryMargin {
    final scale = _transformCtrl.value.getMaxScaleOnAxis();
    final safeScale = scale > 0 ? scale : _minScale;
    // Desired screen-space margin, converted into content-space units by
    // dividing by the current scale (so it looks the same size in pixels
    // regardless of zoom level).
    final base = _screenMarginPx / safeScale;

    final bounds = _computeNodeBounds();
    final contentWidth = bounds.right + _contentPadding;
    final contentHeight = bounds.bottom + _contentPadding;

    double marginFor(double viewportExtent, double contentExtent) {
      if (viewportExtent <= 0) return base;
      // How much (screen-space) empty space is left after the scaled
      // content is placed in the viewport along this axis.
      final slack = viewportExtent - contentExtent * safeScale;
      if (slack <= 0) return base; // content already fills/exceeds viewport
      // Split the slack evenly on both sides, on top of the base margin,
      // converted back into content-space units.
      return base + slack / (2 * safeScale);
    }

    return EdgeInsets.symmetric(
      horizontal: marginFor(_lastViewportSize.width, contentWidth),
      vertical: marginFor(_lastViewportSize.height, contentHeight),
    );
  }

  @override
  void didUpdateWidget(covariant _ReadOnlyDfaCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different puzzle's DFA was loaded (e.g. navigating between levels
    // re-uses this widget) — re-fit to the new graph instead of keeping the
    // old pan/zoom position, which would likely show the wrong region.
    if (oldWidget.gs != widget.gs) {
      _didAutoFit = false;
    }
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  /// Tight bounding box around every node's footprint, in the DFA's own
  /// (DSL-authored) coordinate space. Node positions are top-left corners;
  /// black-box nodes are wider (140px) than normal circular states (100px).
  Rect _computeNodeBounds() {
    final nodes = widget.gs.nodes.values;
    if (nodes.isEmpty) return const Rect.fromLTWH(0, 0, 200, 200);

    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;

    for (final node in nodes) {
      final w = node.isBlackBox ? 140.0 : 100.0;
      const h = 100.0;
      left = min(left, node.position.dx);
      top = min(top, node.position.dy);
      right = max(right, node.position.dx + w);
      bottom = max(bottom, node.position.dy + h);
    }
    // Node positions are authored non-negative (placed via onDoubleTapDown
    // localPosition in the level editor), but guard against stray negatives
    // so the content box below never has a negative origin.
    left = min(left, 0);
    top = min(top, 0);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Scales and centers the whole diagram inside [viewportSize] so it's
  /// fully visible without any manual zooming — the actual fix for levels
  /// where nodes were being authored well outside the small preview box.
  void _fitToView(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;
    final bounds = _computeNodeBounds();
    final contentWidth = bounds.right + _contentPadding;
    final contentHeight = bounds.bottom + _contentPadding;

    // Uniform scale (same factor both axes) that fits the *tighter* of the
    // two dimensions, so nothing overflows the viewport. Clamped so a tiny
    // diagram doesn't zoom in past 1.0 (native size) — only ever shrinks
    // to fit, never magnifies past 100% on auto-fit.
    final scale = min(
      viewportSize.width / contentWidth,
      viewportSize.height / contentHeight,
    ).clamp(_minScale, 1.0);

    final graphCenter = bounds.center;
    // Translation that places the content's center at the viewport's
    // center, at the chosen scale.
    final dx = viewportSize.width / 2 - graphCenter.dx * scale;
    final dy = viewportSize.height / 2 - graphCenter.dy * scale;

    setState(() {
      _transformCtrl.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0);
    });
  }

  /// Zooms in/out by [factor] (e.g. 1.25 to zoom in, 0.8 to zoom out),
  /// keeping the viewport's *center point* visually fixed rather than
  /// zooming around the content origin — the usual "zoom toward where
  /// you're looking" behavior.
  void _zoomBy(double factor) {
    if (_lastViewportSize == Size.zero) return;
    final currentScale = _transformCtrl.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final adjust = targetScale / currentScale;
    if (adjust == 1.0) return;

    // Zoom around the viewport's center point rather than the origin.
    final center = Offset(
      _lastViewportSize.width / 2,
      _lastViewportSize.height / 2,
    );
    // Convert the screen-space center into content ("scene") coordinates
    // first, so the translate-scale-translate sequence below zooms
    // relative to that fixed content point rather than the Matrix4
    // origin.
    final focal = _transformCtrl.toScene(center);
    setState(() {
      _transformCtrl.value = _transformCtrl.value.clone()
        ..translateByDouble(focal.dx, focal.dy, 0.0, 1.0)
        ..scaleByDouble(adjust, adjust, 1.0, 1.0)
        ..translateByDouble(-focal.dx, -focal.dy, 0.0, 1.0);
    });
  }

  /// Re-runs [_fitToView] against the last known viewport size — wired to
  /// both the "fit to view" zoom-control button and double-tapping the
  /// canvas.
  void _resetView() {
    if (_lastViewportSize != Size.zero) _fitToView(_lastViewportSize);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final gs = widget.gs;
    final bounds = _computeNodeBounds();
    final contentWidth = bounds.right + _contentPadding;
    final contentHeight = bounds.bottom + _contentPadding;

    return Container(
      color: theme.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          _lastViewportSize = viewportSize;

          // One-time auto-fit: deferred to a post-frame callback since
          // calling setState synchronously during build() (which
          // _fitToView does) isn't allowed.
          if (!_didAutoFit) {
            _didAutoFit = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fitToView(viewportSize);
            });
          }

          return Stack(
            children: [
              GestureDetector(
                onDoubleTap: _resetView,
                child: InteractiveViewer(
                  transformationController: _transformCtrl,
                  // constrained: false lets the child (the SizedBox below)
                  // be larger than the viewport, which is required for
                  // InteractiveViewer's own pan/zoom to have anything to
                  // scroll — otherwise it would force-fit the child to the
                  // viewport itself.
                  constrained: false,
                  boundaryMargin: _boundaryMargin,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  // Rebuild after each gesture so _boundaryMargin picks up
                  // the scale that gesture ended at, ready for the next
                  // pan/zoom — without recalculating on every drag frame.
                  onInteractionEnd: (_) => setState(() {}),
                  child: SizedBox(
                    width: contentWidth,
                    height: contentHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Start arrow
                        if (gs.startArrow != null &&
                            gs.nodes.containsKey(gs.startArrow!.nodeId))
                          Positioned.fill(
                            child: IgnorePointer(
                              child: StartArrowWidget(
                                data: gs.startArrow!,
                                nodeCenter: gs.nodes[gs.startArrow!.nodeId]!.center,
                                deleteMode: false,
                                onDelete: () {},
                              ),
                            ),
                          ),

                        // Transition lines — IgnorePointer'd since this
                        // whole canvas is read-only; the label TextFields
                        // inside LineWidget would otherwise still accept
                        // focus/taps despite onLabelChanged being a no-op.
                        ...gs.lines.values.map((line) {
                          final a = gs.nodes[line.nodeAId];
                          final b = gs.nodes[line.nodeBId];
                          if (a == null || b == null) return const SizedBox.shrink();
                          return Positioned.fill(
                            child: IgnorePointer(
                              child: LineWidget(
                                data: line,
                                centerA: a.center,
                                centerB: b.center,
                                deleteMode: false,
                                highlighted: false,
                                onLabelChanged: (_) {}, // read-only, never fires
                              ),
                            ),
                          );
                        }),

                        // State nodes — non-interactive (interactionLocked: true
                        // handles this; do NOT wrap in IgnorePointer here — Node
                        // positions itself with an internal Positioned widget and
                        // must be a direct Stack child).
                        ...gs.nodes.values.map(
                          (node) => Node(
                            key: ValueKey('ro_${node.id}'),
                            data: node,
                            lineMode: false,
                            interactionLocked: true,
                            deleteMode: false,
                            highlighted: false,
                            isLabelTaken: (_, _) => false,
                            onLabelChanged: (_) {},
                            onLineModeSelect: () {},
                            onDoubleTap: () {},
                            onDelete: () {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Watermark label — pinned to the viewport, not the pannable
              // content, so it stays put regardless of pan/zoom.
              Positioned(
                bottom: 8,
                right: 12,
                child: IgnorePointer(
                  child: Text(
                    'read-only',
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 10,
                      color: theme.textDim.withValues(alpha: 0.4),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),

              // Zoom / recenter controls.
              Positioned(
                top: 8,
                right: 8,
                child: _CanvasZoomControls(
                  theme: theme,
                  onZoomIn: () => _zoomBy(1.25),
                  onZoomOut: () => _zoomBy(0.8),
                  onFit: _resetView,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small floating zoom/fit control cluster for _ReadOnlyDfaCanvas.
// ─────────────────────────────────────────────────────────────────────────────

/// A small pill-shaped cluster of three icon buttons (zoom out / fit / zoom
/// in) floated in the corner of [_ReadOnlyDfaCanvas].
class _CanvasZoomControls extends StatelessWidget {
  final AppThemeNotifier theme;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  const _CanvasZoomControls({
    required this.theme,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderMid),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CanvasZoomButton(icon: Icons.remove, tooltip: 'Zoom out', onTap: onZoomOut, theme: theme),
          _CanvasZoomButton(icon: Icons.fit_screen, tooltip: 'Fit to view', onTap: onFit, theme: theme),
          _CanvasZoomButton(icon: Icons.add, tooltip: 'Zoom in', onTap: onZoomIn, theme: theme),
        ],
      ),
    );
  }
}

/// A single icon button within [_CanvasZoomControls].
class _CanvasZoomButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final AppThemeNotifier theme;

  const _CanvasZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: theme.textMid),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Regex Input Panel  (used by dfaToRegex levels)
//
//  A sticky panel at the bottom of the screen where the player types their
//  regular expression.  Notifies the parent via the shared [controller].
// ─────────────────────────────────────────────────────────────────────────────

/// The docked text-entry panel for dfaToRegex levels: a label, the regex
/// text field itself (color/border shift to green once [isCorrect]), and a
/// hint line listing the supported operators.
class _RegexInputPanel extends StatelessWidget {
  final TextEditingController controller;
  final AppThemeNotifier theme;
  final bool isCorrect;

  const _RegexInputPanel({
    required this.controller,
    required this.theme,
    required this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    // Local accent distinct from the app theme's usual accent — a cyan
    // tone used only within this regex-input panel to visually tie it to
    // the matching "Regex:" box in _GoalBanner (which uses the same
    // color).
    const accentRegex = Color(0xFF00E5FF);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(
          top: BorderSide(color: theme.borderMid),
          left: BorderSide(
            color: isCorrect ? const Color(0xFF1FD99A) : accentRegex,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your regular expression:',
            style: GoogleFonts.sourceCodePro(
              fontSize: 11,
              color: theme.textDim,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: theme.bg,
              border: Border.all(
                color: isCorrect
                    ? const Color(0xFF1FD99A)
                    : accentRegex.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: controller,
              // Locks the field once the answer is correct — no point
              // letting the player keep editing a winning solution (and
              // it visually reinforces "you're done" alongside the green
              // border).
              enabled: !isCorrect,
              style: GoogleFonts.courierPrime(
                fontSize: 20,
                color: isCorrect ? const Color(0xFF1FD99A) : accentRegex,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
              cursorColor: accentRegex,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'e.g.  (a+b)*b',
                hintStyle: GoogleFonts.courierPrime(
                  fontSize: 18,
                  color: theme.textDim.withValues(alpha: 0.5),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Operators: concat (ab), union (a+b), star (a*), grouping (…)',
            style: GoogleFonts.sourceCodePro(
              fontSize: 10,
              color: theme.textDim,
            ),
          ),
        ],
      ),
    );
  }
}