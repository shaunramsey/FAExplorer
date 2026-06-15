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
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'widgets/app_theme.dart';

import 'game_level.dart';
// LevelDifficulty is also declared in game_level.dart — no extra import needed.
import 'game_progress_store.dart';
import 'tutorial_screen.dart';
import 'dsl_code.dart';
import 'fa_equivalence.dart';
import 'models.dart';
import 'automaton_type_checker.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;
import 'widgets/palette_fab.dart';
import 'node.dart';
import 'line.dart';
import 'start_arrow.dart';
// ─────────────────────────────────────────────────────────────────────────────

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
  final Map<String, NodeData> _nodes = {};
  final Map<String, LineData> _lines = {};
  StartArrowData? _startArrow;
  int _nodeCounter = 0;
  int _lineCounter = 0;

  // ── interaction state ───────────────────────────────────────────────────
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
  bool _checking = false;
  String? _checkResult;
  bool _isCorrect = false;

  // ── save / load state ────────────────────────────────────────────────────
  bool _loadingSavedDsl = true;
  Timer? _saveDebounce;

  // ── animation ───────────────────────────────────────────────────────────
  late final AnimationController _successCtrl;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _loadSavedDsl();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _focusNode.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  // ── persistence helpers ─────────────────────────────────────────────────

  /// Restores the user's previous work for this level from SharedPreferences.
  ///
  /// In easy mode, if no saved progress exists yet, the canvas is seeded from
  /// [GameLevel.easyModeNodes] so the nodes are already placed.
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
      } catch (_) {
        // Corrupted save — fall through and try the scaffold seed instead.
        _tryApplyEasyScaffold();
      }
    } else if (widget.difficulty == LevelDifficulty.easy &&
        widget.level.hasEasyMode) {
      // No saved progress yet — seed from the node list.
      _tryApplyEasyScaffold();
    }
    if (mounted) setState(() => _loadingSavedDsl = false);
  }

  /// Seeds the canvas with the easy-mode pre-placed nodes (no transitions).
  /// Called on a fresh easy-mode start or after a corrupted save.
  void _tryApplyEasyScaffold() {
    final easyNodes = widget.level.easyModeNodes;
    if (easyNodes == null || easyNodes.isEmpty) return;

    final nodes = <String, NodeData>{};
    StartArrowData? startArrow;

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
        // No transitions pre-placed — the player draws those themselves.
        _lines.clear();
        _startArrow = startArrow;
        _nodeCounter = nodes.length;
        _lineCounter = 0;
      });
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
    } catch (_) {
      // Non-fatal — best-effort save.
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  String _nextId(String prefix) {
    if (prefix == 'n') return '$prefix${_nodeCounter++}';
    return '$prefix${_lineCounter++}';
  }

  NodeData? _nodeAt(Offset p) {
    for (final n in _nodes.values) {
      if (n.containsPoint(p)) return n;
    }
    return null;
  }

  LineData? _lineAt(Offset p) {
    for (final l in _lines.values) {
      final a = _nodes[l.nodeAId], b = _nodes[l.nodeBId];
      if (a == null || b == null) continue;
      if (l.containsPoint(p, a.center, b.center)) return l;
    }
    return null;
  }

  bool _isLabelTaken(String label, String currentId) {
    final n = label.trim();
    if (n.isEmpty) return false;
    return _nodes.values.any((nd) => nd.id != currentId && nd.label.trim() == n);
  }

  bool _canStartLineFrom(String? id) =>
      id != null && (_nodes[id]?.canHaveOutgoingTransitions ?? false);

  void _deleteNode(String id) {
    final node = _nodes[id];
    if (node == null) return;
    for (final lid in node.connectedLineIds.toList()) {
      _deleteLine(lid);
    }
    if (_startArrow?.nodeId == id) _startArrow = null;
    _nodes.remove(id);
  }

  void _deleteLine(String id) {
    final l = _lines[id];
    if (l == null) return;
    _nodes[l.nodeAId]?.connectedLineIds.remove(id);
    _nodes[l.nodeBId]?.connectedLineIds.remove(id);
    _lines.remove(id);
  }

  bool _hitStartArrow(Offset point) {
    if (_startArrow == null) return false;
    final node = _nodes[_startArrow!.nodeId];
    if (node == null) return false;
    var dir = _startArrow!.direction();
    if (dir.distance == 0) dir = const Offset(-0.7071, -0.7071);
    const r = 50.0;
    final end = Offset(node.center.dx + dir.dx * r, node.center.dy + dir.dy * r);
    final start = Offset(end.dx + dir.dx * _startArrow!.length,
        end.dy + dir.dy * _startArrow!.length);
    if ((point - start).distance < 44) return true;
    final line = end - start;
    final lenSq = line.dx * line.dx + line.dy * line.dy;
    if (lenSq == 0) return false;
    double t =
        ((point.dx - start.dx) * line.dx + (point.dy - start.dy) * line.dy) /
            lenSq;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(start.dx + line.dx * t, start.dy + line.dy * t);
    return (point - proj).distance < 44;
  }

  // ── pan / drag handlers ─────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;
    _draggingNodeId = null;
    _draggingLineId = null;
    _isPanningCanvas = false;
    _draggingStartArrow = false;

    if (_deleteMode) {
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

    final node = _nodeAt(pos);
    if (node != null) {
      if (_lineMode) {
        if (_canStartLineFrom(node.id)) _lineSourceNodeId = node.id;
      } else {
        _draggingNodeId = node.id;
      }
    } else {
      if (_hitStartArrow(pos)) {
        _draggingStartArrow = true;
      } else {
        final l = _lineAt(pos);
        if (l != null) {
          _draggingLineId = l.id;
        } else if (!_lineMode) {
          _isPanningCanvas = true;
        }
      }
    }
  }

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
        if (dist > 10) {
          _startArrow!.offset = Offset(dir.dx / dist, dir.dy / dist);
          _startArrow!.length = max(40, dist - 50);
        }
      });
    } else if (_draggingLineId != null) {
      setState(() {
        final line = _lines[_draggingLineId!]!;
        final a = _nodes[line.nodeAId]!, b = _nodes[line.nodeBId]!;
        if (line.nodeAId == line.nodeBId) {
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

  void _onPanUpdateTracking(DragUpdateDetails d) {
    _onPanUpdate(d);
    _lastPanPosition = d.localPosition;
    if (_lineSourceNodeId != null && _lineMode) {
      setState(() => _rubberBandEnd = d.localPosition);
    } else {
      if (_lineSourceNodeId != null || _rubberBandEnd != null) {
        setState(() {
          _lineSourceNodeId = null;
          _rubberBandEnd = null;
        });
      }
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_lineMode && _lineSourceNodeId != null) {
      final dest =
          _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;
      if (dest != null) {
        final src = _lineSourceNodeId!;
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

  Future<void> _checkAnswer() async {
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
        // Legacy SVG-asset path
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
        } catch (_) {
          setState(() {
            _checking = false;
            _checkResult =
                '⚠ Could not parse target SVG.\nCheck the embedded automata-data script block.';
          });
          return;
        }
      }

      // 2. If the level specifies a required automaton type (DFA vs NFA), check
      // it now — BEFORE running the (more expensive) equivalence check.
      final requiredType = widget.level.requiredAutomatonType;
      if (requiredType != null) {
        final typeResult = AutomatonTypeChecker.check(
          nodes: _nodes,
          lines: _lines,
          startArrow: _startArrow,
          alphabet: widget.level.alphabet,
          required: requiredType,
        );

        if (!typeResult.isCorrectType) {
          // Build a player-facing message.  Hard errors first, then warnings.
          final errors = typeResult.violations
              .where((v) => v.severity == ViolationSeverity.error)
              .map((v) => '  ✗ ${v.message}')
              .join('\n');
          final warnings = typeResult.violations
              .where((v) => v.severity == ViolationSeverity.warning)
              .map((v) => '  ⚠ ${v.message}')
              .join('\n');
          final detail = [errors, warnings].where((s) => s.isNotEmpty).join('\n');

          setState(() {
            _checking = false;
            _checkResult = '${typeResult.primaryMessage}'
                '${detail.isNotEmpty ? '\n\n$detail' : ''}';
          });
          return; // block progression — don't run equivalence check
        }
      }

      // 3. Run the appropriate equivalence check based on the level's assigned
      // automata mode.
      //    NFA/DFA: exact BFS-based check.
      //    PDA / TM: bounded simulation (heuristic; detects many bugs).
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
            widget.onCompleted?.call();
            _successCtrl.forward(from: 0);
            _showSuccessDialog();
          } else {
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
    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.level.title,
                style: GoogleFonts.orbitron(fontWeight: FontWeight.w700)),
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
          if (_checking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
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
            ),
        ],
      ),
      body: _loadingSavedDsl
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // ── Goal banner ──────────────────────────────────────────────
          _GoalBanner(
            description: widget.level.description,
            tagColor: context.watch<AppThemeNotifier>().tagColor(widget.level.tag),
            automataMode: widget.level.automataMode,
            requiredAutomatonType: widget.level.requiredAutomatonType,
            alphabet: widget.level.alphabet,
            checkResult: _checkResult,
            isCorrect: _isCorrect,
          ),

          // ── Canvas ───────────────────────────────────────────────────
          Expanded(
            child: KeyboardListener(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (e) {
                final isShift = e.logicalKey == LogicalKeyboardKey.shiftLeft ||
                    e.logicalKey == LogicalKeyboardKey.shiftRight;
                if (isShift && e is KeyDownEvent) {
                  setState(() => _lineMode = !_lineMode);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (d) {
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
                            painter: _RubberBandPainter(
                              start: _nodes[_lineSourceNodeId!]!.center,
                              end: _rubberBandEnd!,
                              color: theme.accent,
                            ),
                          ),
                        ),
                      ),

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
      ),

      // ── FAB toolbar ───────────────────────────────────────────────────
      floatingActionButton: Column(
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
                      widget.progressStore.clearLevelDsl(widget.level.id);
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Goal banner
// ─────────────────────────────────────────────────────────────────────────────

class _GoalBanner extends StatelessWidget {
  final String description;
  final Color tagColor;
  final String? checkResult;
  final bool isCorrect;
  final AutomataMode automataMode;
  final RequiredAutomatonType? requiredAutomatonType;
  final Set<String> alphabet;

  const _GoalBanner({
    required this.description,
    required this.tagColor,
    required this.automataMode,
    required this.alphabet,
    this.requiredAutomatonType,
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

          // ── Check result ──────────────────────────────────────────────
          if (checkResult != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isCorrect
                  ? theme.accentGreen.withOpacity(0.12)
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
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withOpacity(0.85)),
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
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
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
        side: BorderSide(color: tagColor.withOpacity(0.8), width: 2),
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
                  color: tagColor.withOpacity(0.15),
                  boxShadow: [
                    BoxShadow(
                      color: tagColor.withOpacity(0.6),
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
//  Rubber-band painter — line + arrowhead, matches the sandbox canvas style
// ─────────────────────────────────────────────────────────────────────────────

class _RubberBandPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  const _RubberBandPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.5;
    const arrowLen = 14.0;
    const arrowWing = 8.0;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return;

    final angle = atan2(dy, dx);
    final shortenedEnd = Offset(
      end.dx - cos(angle) * arrowLen,
      end.dy - sin(angle) * arrowLen,
    );

    // Line
    canvas.drawLine(
      start,
      shortenedEnd,
      Paint()
        ..color = color.withOpacity(0.7)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Arrowhead
    final cdx = cos(angle);
    final cdy = sin(angle);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - arrowLen * cdx + arrowWing * cdy,
               end.dy - arrowLen * cdy - arrowWing * cdx)
      ..lineTo(end.dx - arrowLen * cdx - arrowWing * cdy,
               end.dy - arrowLen * cdy + arrowWing * cdx)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.7)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_RubberBandPainter old) =>
      old.start != start || old.end != end || old.color != color;
}