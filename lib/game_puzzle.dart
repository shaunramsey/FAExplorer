// ─────────────────────────────────────────────────────────────────────────────
//  Game Puzzle Screen
//
//  Wraps the full AutomataScreen canvas but:
//  • Shows the level description / goal at the top
//  • Adds a "Check Answer" button that loads the target SVG and runs
//    FA equivalence checking against the user's current graph
//  • Celebrates with a completion dialog on success
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'game_level.dart';
import 'game_progress_store.dart';
import 'dsl_code.dart';
import 'fa_equivalence.dart';
import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;
import 'node.dart';
import 'line.dart';
import 'start_arrow.dart';
import 'main.dart'
    show
        kBg,
        kSurface,
        kBorder,
        kBorderMid,
        kAccent,
        kAccentGreen,
        kTextDim,
        kTextMid,
        kTextLight;

// ─────────────────────────────────────────────────────────────────────────────

class GamePuzzleScreen extends StatefulWidget {
  final GameLevel level;
  final GameProgressStore progressStore;
  final VoidCallback? onCompleted;

  const GamePuzzleScreen({
    super.key,
    required this.level,
    required this.progressStore,
    this.onCompleted,
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
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _successCtrl.dispose();
    super.dispose();
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
        return;
      }
      final l = _lineAt(pos);
      if (l != null) {
        setState(() => _deleteLine(l.id));
        return;
      }
      if (_hitStartArrow(pos)) {
        setState(() => _startArrow = null);
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

      // 2. Run the appropriate equivalence check based on the level's assigned
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
          await widget.progressStore.markCompleted(widget.level.id);
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
          _checkResult = levelMode != AutomataMode.ndfa
              ? '? Bounded simulation completed but could not confirm equivalence.\n\n'
                'If your machine handles all tested inputs correctly it may still be right —\n'
                'try a few more edge cases manually.'
              : '? Could not determine equivalence (search space too large).\n\n'
                'Try simplifying your automaton or check manually.';
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
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(widget.level.title,
            style: GoogleFonts.orbitron(fontWeight: FontWeight.w700)),
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
                      ? kAccentGreen
                      : kAccent,
                  foregroundColor: kBg,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Goal banner ──────────────────────────────────────────────
          _GoalBanner(
            description: widget.level.description,
            tagColor: levelTagColor(widget.level.tag),
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
                          onDelete: () =>
                              setState(() => _startArrow = null),
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
                            onLabelChanged: (t) =>
                                setState(() => line.label = t),
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
                        onLabelChanged: (t) =>
                            setState(() => node.label = t),
                        onLineModeSelect: () {
                          if (_lineMode && _canStartLineFrom(node.id)) {
                            _lineSourceNodeId = node.id;
                          }
                        },
                        onDoubleTap: () {
                          if (!node.canToggleNormalAccept) return;
                          setState(() => node.isAccept = !node.isAccept);
                        },
                        onDelete: () =>
                            setState(() => _deleteNode(node.id)),
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
          _PaletteFab(
            heroTag: 'gp_start',
            tooltip: 'Set start state',
            icon: Icons.play_arrow,
            active: _placingStartArrow,
            activeColor: const Color(0xFFFF6D00),
            onPressed: () =>
                setState(() => _placingStartArrow = !_placingStartArrow),
          ),
          const SizedBox(height: 10),
          _PaletteFab(
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
          _PaletteFab(
            heroTag: 'gp_line',
            tooltip: _lineMode ? 'Exit line mode' : 'Enter line mode',
            icon: _lineMode ? Icons.timeline : Icons.add_link,
            active: _lineMode,
            activeColor: kAccent,
            onPressed: () => setState(() => _lineMode = !_lineMode),
          ),
          const SizedBox(height: 10),
          _PaletteFab(
            heroTag: 'gp_reset',
            tooltip: 'Clear canvas',
            icon: Icons.refresh,
            active: false,
            activeColor: kAccent,
            small: true,
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: kSurface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: kBorderMid),
                ),
                title: Text(
                  'Clear canvas?',
                  style: GoogleFonts.orbitron(
                    color: kTextLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                content: Text(
                  'This will delete all your work on this puzzle.',
                  style: GoogleFonts.sourceCodePro(
                    color: kTextMid,
                    fontSize: 13,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: kTextDim,
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
            ),
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

  const _GoalBanner({
    required this.description,
    required this.tagColor,
    this.checkResult,
    this.isCorrect = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: tagColor, width: 4),
                bottom: const BorderSide(color: kBorderMid),
              ),
            ),
            child: Text(
              description,
              style: GoogleFonts.sourceCodePro(
                fontSize: 13,
                color: kTextMid,
                height: 1.5,
              ),
            ),
          ),
          if (checkResult != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isCorrect
                  ? const Color(0xFF0D2A1F)   // tinted from kAccentGreen
                  : const Color(0xFF1F0D0D),  // tinted from error
              child: Text(
                checkResult!,
                style: GoogleFonts.sourceCodePro(
                  fontSize: 12,
                  color: isCorrect
                      ? kAccentGreen
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
    final tagColor = levelTagColor(widget.level.tag);

    return Dialog(
      backgroundColor: kBg,
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

  const _RubberBandPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    const color = Color.fromARGB(255, 0, 229, 255); // kAccent — matches the rest of the canvas
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
      old.start != start || old.end != end;
}

// ─────────────────────────────────────────────────────────────────────────────
//  _PaletteFab — matches the sandbox canvas FAB style exactly
// ─────────────────────────────────────────────────────────────────────────────
class _PaletteFab extends StatelessWidget {
  const _PaletteFab({
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onPressed,
    this.small = false,
  });

  final Object heroTag;
  final String tooltip;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    const bgIdle = kSurface;
    const fgIdle = kTextDim;
    const border = kBorderMid;

    final bg = active ? activeColor.withOpacity(0.14) : bgIdle;
    final fg = active ? activeColor : fgIdle;
    final side = active
        ? BorderSide(color: activeColor.withOpacity(0.7), width: 1.5)
        : const BorderSide(color: border, width: 1);

    final size = small ? 36.0 : 48.0;
    final iconSize = small ? 18.0 : 22.0;

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(small ? 8 : 12),
          border: Border.all(color: side.color, width: side.width),
          boxShadow: active
              ? [BoxShadow(
                  color: activeColor.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 0,
                )]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(small ? 8 : 12),
            onTap: onPressed,
            child: Icon(icon, color: fg, size: iconSize),
          ),
        ),
      ),
    );
  }
}