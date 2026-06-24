import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../node.dart';
import '../line.dart';
import '../start_arrow.dart';
import 'rubber_band_painter.dart';
import 'app_theme.dart';
import 'palette_fab.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataCanvasEmbed
//
//  A self-contained automata canvas suitable for embedding inside any widget
//  (e.g. the study-mode drawing area or a read-only DFA preview).
//
//  Provides the full draw / edit experience — double-tap to create states,
//  drag to move, line-mode rubber-band to draw transitions, draggable start
//  arrow, delete mode, canvas panning — without any session persistence,
//  simulators, or Scaffold chrome.
//
//  [initialNodes] / [initialLines] / [initialStart]
//      Seed the canvas on first build.  Deep-copied internally so the caller's
//      maps are never mutated.
//
//  [onChanged]
//      Fired after every structural edit so the caller can read the current FA
//      state for grading or other purposes.
//
//  [readOnly]
//      When true, disables all editing and the toolbar.  Only panning is
//      allowed so the user can navigate the diagram.  Used to show the
//      "target DFA" preview in study mode.
// ─────────────────────────────────────────────────────────────────────────────

class AutomataCanvasEmbed extends StatefulWidget {
  final Map<String, NodeData> initialNodes;
  final Map<String, LineData> initialLines;
  final StartArrowData? initialStart;
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onChanged;
  final bool readOnly;

  const AutomataCanvasEmbed({
    super.key,
    required this.initialNodes,
    required this.initialLines,
    required this.initialStart,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<AutomataCanvasEmbed> createState() => _AutomataCanvasEmbedState();
}

class _AutomataCanvasEmbedState extends State<AutomataCanvasEmbed> {
  // ── FA state ────────────────────────────────────────────────────────────
  late final Map<String, NodeData> _nodes;
  late final Map<String, LineData> _lines;
  StartArrowData? _startArrow;

  // Counter high-water marks so new IDs never collide with existing ones.
  int _nodeCounter = 0;
  int _lineCounter = 0;

  // ── Interaction modes ───────────────────────────────────────────────────
  bool _lineMode = false;
  bool _placingStartArrow = false;
  bool _deleteMode = false;

  // ── Drag state ──────────────────────────────────────────────────────────
  bool _draggingStartArrow = false;
  String? _draggingNodeId;
  String? _draggingLineId;
  String? _lineSourceNodeId;
  bool _isPanningCanvas = false;

  Offset? _lastPanPosition;
  Offset? _rubberBandEnd;

  // ── Unique hero tags (multiple embeds can coexist on-screen) ────────────
  final Object _startArrowTag = Object();
  final Object _lineModeTag = Object();
  final Object _deleteModeTag = Object();

  // ────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Deep-copy so we never mutate the caller's maps.
    _nodes = Map.of(widget.initialNodes);
    _lines = Map.of(widget.initialLines);
    _startArrow = widget.initialStart;

    // Set counters above any existing ID numbers to avoid collisions.
    for (final id in _nodes.keys) {
      final n = int.tryParse(id.replaceFirst('n', ''));
      if (n != null && n >= _nodeCounter) _nodeCounter = n + 1;
    }
    for (final id in _lines.keys) {
      final n = int.tryParse(id.replaceFirst('l', ''));
      if (n != null && n >= _lineCounter) _lineCounter = n + 1;
    }
  }

  // ── Change notification ─────────────────────────────────────────────────
  void _notify() => widget.onChanged(_nodes, _lines, _startArrow);

  // ── ID generation ───────────────────────────────────────────────────────
  String _nextNodeId() => 'n${_nodeCounter++}';
  String _nextLineId() => 'l${_lineCounter++}';

  // ── Hit-testing helpers ─────────────────────────────────────────────────

  bool _isLabelTaken(String label, String currentId) {
    final t = label.trim();
    if (t.isEmpty) return false;
    return _nodes.values.any((n) => n.id != currentId && n.label.trim() == t);
  }

  bool _canStartLineFrom(String? id) =>
      _nodes[id]?.canHaveOutgoingTransitions ?? false;

  NodeData? _nodeAt(Offset pt) {
    for (final n in _nodes.values) {
      if (n.containsPoint(pt)) return n;
    }
    return null;
  }

  LineData? _lineAt(Offset pt) {
    for (final l in _lines.values) {
      final a = _nodes[l.nodeAId];
      final b = _nodes[l.nodeBId];
      if (a == null || b == null) continue;
      if (l.containsPoint(pt, a.center, b.center)) return l;
    }
    return null;
  }

  bool _hitStartArrow(Offset pt) {
    if (_startArrow == null) return false;
    final node = _nodes[_startArrow!.nodeId];
    if (node == null) return false;

    var dir = _startArrow!.direction();
    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    const double radius = 50;
    final end  = Offset(node.center.dx + dir.dx * radius, node.center.dy + dir.dy * radius);
    final tail = Offset(end.dx + dir.dx * _startArrow!.length, end.dy + dir.dy * _startArrow!.length);

    if ((pt - tail).distance < 44) return true;

    final seg   = end - tail;
    final lenSq = seg.dx * seg.dx + seg.dy * seg.dy;
    if (lenSq == 0) return false;

    final t = ((pt.dx - tail.dx) * seg.dx + (pt.dy - tail.dy) * seg.dy) / lenSq;
    final proj = Offset(tail.dx + seg.dx * t.clamp(0.0, 1.0),
                        tail.dy + seg.dy * t.clamp(0.0, 1.0));
    return (pt - proj).distance < 44;
  }

  // ── Deletion helpers ────────────────────────────────────────────────────

  void _cancelRubberBand() {
    _lineSourceNodeId = null;
    _rubberBandEnd = null;
  }

  void _deleteLine(String id) {
    final line = _lines[id];
    if (line == null) return;
    _nodes[line.nodeAId]?.connectedLineIds.remove(id);
    _nodes[line.nodeBId]?.connectedLineIds.remove(id);
    _lines.remove(id);
    _notify();
  }

  void _deleteNode(String id) {
    final node = _nodes[id];
    if (node == null) return;
    for (final lid in node.connectedLineIds.toList()) _deleteLine(lid);
    if (_startArrow?.nodeId == id) _startArrow = null;
    _nodes.remove(id);
    _notify();
  }

  // ── Gesture handlers (extracted from AutomataScreen) ────────────────────

  void _onDoubleTapDown(TapDownDetails d) {
    if (_lineMode) return;
    if (_nodeAt(d.localPosition) != null) return;
    setState(() {
      final id = _nextNodeId();
      _nodes[id] = NodeData(
        id: id,
        position: d.localPosition - const Offset(50, 50),
      );
    });
    _notify();
  }

  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;
    _draggingNodeId    = null;
    _draggingLineId    = null;
    _isPanningCanvas   = false;
    _draggingStartArrow = false;

    if (_deleteMode) {
      final node = _nodeAt(pos);
      if (node != null) {
        setState(() => _deleteNode(node.id));
        return;
      }
      final line = _lineAt(pos);
      if (line != null) {
        setState(() => _deleteLine(line.id));
        return;
      }
      if (_hitStartArrow(pos)) {
        setState(() {
          _startArrow = null;
          _notify();
        });
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
      return;
    }

    if (_hitStartArrow(pos)) {
      _draggingStartArrow = true;
      return;
    }

    final line = _lineAt(pos);
    if (line != null) {
      _draggingLineId = line.id;
    } else if (!_lineMode) {
      _isPanningCanvas = true;
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
        _nodes[_draggingNodeId!]!.position =
            _nodes[_draggingNodeId!]!.position + d.delta;
      });
      return;
    }

    if (_draggingStartArrow && _startArrow != null) {
      setState(() {
        final center = _nodes[_startArrow!.nodeId]!.center;
        final mouse  = d.localPosition;
        final dir    = Offset(mouse.dx - center.dx, mouse.dy - center.dy);
        final dist   = dir.distance;
        if (dist > 10) {
          _startArrow!.offset = Offset(dir.dx / dist, dir.dy / dist);
          _startArrow!.length = max(40, dist - 50);
        }
      });
      return;
    }

    if (_draggingLineId != null) {
      setState(() {
        final line = _lines[_draggingLineId!]!;
        final a    = _nodes[line.nodeAId]!;
        final b    = _nodes[line.nodeBId]!;

        if (line.nodeAId == line.nodeBId) {
          // Self-loop: rotate the loop angle.
          final center = a.center;
          final prev   = (_lastPanPosition ?? center) - d.delta;
          final oldA   = atan2(prev.dy - center.dy, prev.dx - center.dx);
          final newA   = atan2(d.localPosition.dy - center.dy,
                               d.localPosition.dx - center.dx);
          line.selfLoopAngle += newA - oldA;
          return;
        }

        // Curved arc: adjust perpendicular offset.
        final dx  = b.center.dx - a.center.dx;
        final dy  = b.center.dy - a.center.dy;
        final len = sqrt(dx * dx + dy * dy);
        if (len != 0) {
          line.perpendicularPart +=
              d.delta.dx * (dy / len) + d.delta.dy * (-dx / len);
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (_lineMode && _lineSourceNodeId != null) {
      final dest = _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;

      if (dest != null && _canStartLineFrom(_lineSourceNodeId!)) {
        final src    = _lineSourceNodeId!;
        final exists = _lines.values.any(
            (l) => l.nodeAId == src && l.nodeBId == dest.id);
        if (!exists) {
          setState(() {
            final id   = _nextLineId();
            final line = LineData(id: id, nodeAId: src, nodeBId: dest.id);
            _lines[id] = line;
            _nodes[src]?.connectedLineIds.add(id);
            _nodes[dest.id]?.connectedLineIds.add(id);
          });
          _notify();
        }
      }

      setState(_cancelRubberBand);
      _lineSourceNodeId = null;
    }

    _draggingNodeId     = null;
    _draggingLineId     = null;
    _draggingStartArrow = false;
    _isPanningCanvas    = false;
    _lastPanPosition    = null;
    setState(_cancelRubberBand);
    _notify();
  }

  void _onPanUpdateWithTracking(DragUpdateDetails d) {
    _lastPanPosition = d.localPosition;
    _onPanUpdate(d);
    if (_lineSourceNodeId != null && _lineMode) {
      setState(() => _rubberBandEnd = d.localPosition);
    } else if (_lineSourceNodeId != null || _rubberBandEnd != null) {
      setState(_cancelRubberBand);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    final canvasBody = widget.readOnly
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Allow panning even in read-only so the user can navigate.
            onPanUpdate: (d) => setState(() {
              for (final n in _nodes.values) {
                n.position = n.position + d.delta;
              }
            }),
            child: _CanvasContents(
              nodes: _nodes,
              lines: _lines,
              startArrow: _startArrow,
              lineMode: false,
              deleteMode: false,
              placingStartArrow: false,
              lineSourceNodeId: null,
              rubberBandEnd: null,
              isLabelTaken: _isLabelTaken,
              onNodeLabelChanged: (_, __) {},
              onLineModeSelect: (_) {},
              onNodeDoubleTap: (_) {},
              onNodeDelete: (_) {},
              onLineDelete: (_) {},
              onLineLabelChanged: (_, __) {},
              onStartArrowDelete: () {},
            ),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: _onDoubleTapDown,
            onTapDown: (d) {
              if (!_placingStartArrow) return;
              final node = _nodeAt(d.localPosition);
              if (node != null) {
                setState(() {
                  _startArrow = StartArrowData(nodeId: node.id);
                  _placingStartArrow = false;
                });
                _notify();
              }
            },
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdateWithTracking,
            onPanEnd: _onPanEnd,
            child: _CanvasContents(
              nodes: _nodes,
              lines: _lines,
              startArrow: _startArrow,
              lineMode: _lineMode,
              deleteMode: _deleteMode,
              placingStartArrow: _placingStartArrow,
              lineSourceNodeId: _lineSourceNodeId,
              rubberBandEnd: _rubberBandEnd,
              isLabelTaken: _isLabelTaken,
              onNodeLabelChanged: (id, text) {
                setState(() => _nodes[id]!.label = text);
                _notify();
              },
              onLineModeSelect: (id) {
                if (_lineMode && _canStartLineFrom(id)) {
                  _lineSourceNodeId = id;
                }
              },
              onNodeDoubleTap: (id) {
                final node = _nodes[id];
                if (node == null || !node.canToggleNormalAccept) return;
                setState(() => node.isAccept = !node.isAccept);
                _notify();
              },
              onNodeDelete: (id) {
                setState(() => _deleteNode(id));
              },
              onLineDelete: (id) {
                setState(() => _deleteLine(id));
              },
              onLineLabelChanged: (id, text) {
                setState(() => _lines[id]!.label = text);
                _notify();
              },
              onStartArrowDelete: () {
                setState(() {
                  _startArrow = null;
                  _notify();
                });
              },
            ),
          );

    return Stack(
      children: [
        Positioned.fill(child: canvasBody),

        // ── Empty-canvas hint (edit mode only) ─────────────────────────
        if (!widget.readOnly && _nodes.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_outlined,
                        color: theme.textDim.withOpacity(0.22), size: 36),
                    const SizedBox(height: 10),
                    Text(
                      'Double-tap to add a state\n'
                      'Drag node to move  ·  Use toolbar to draw transitions',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.textDim.withOpacity(0.28),
                        fontSize: 11,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Mini toolbar (edit mode only) ────────────────────────────
        if (!widget.readOnly)
          Positioned(
            right: 12,
            bottom: 12,
            child: _MiniToolbar(
              lineMode: _lineMode,
              placingStartArrow: _placingStartArrow,
              deleteMode: _deleteMode,
              startArrowTag: _startArrowTag,
              lineModeTag: _lineModeTag,
              deleteModeTag: _deleteModeTag,
              onStartArrowToggle: () => setState(() {
                _placingStartArrow = !_placingStartArrow;
                if (_placingStartArrow) {
                  _lineMode = false;
                  _deleteMode = false;
                }
              }),
              onLineModeToggle: () => setState(() {
                _lineMode = !_lineMode;
                if (_lineMode) {
                  _placingStartArrow = false;
                  _deleteMode = false;
                }
              }),
              onDeleteModeToggle: () => setState(() {
                _deleteMode = !_deleteMode;
                if (_deleteMode) {
                  _lineMode = false;
                  _placingStartArrow = false;
                }
              }),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _CanvasContents — pure rendering widget for nodes, lines, start arrow
// ─────────────────────────────────────────────────────────────────────────────

class _CanvasContents extends StatelessWidget {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;

  final bool lineMode;
  final bool deleteMode;
  final bool placingStartArrow;
  final String? lineSourceNodeId;
  final Offset? rubberBandEnd;

  final bool Function(String label, String nodeId) isLabelTaken;
  final void Function(String id, String text) onNodeLabelChanged;
  final void Function(String id) onLineModeSelect;
  final void Function(String id) onNodeDoubleTap;
  final void Function(String id) onNodeDelete;
  final void Function(String id) onLineDelete;
  final void Function(String id, String text) onLineLabelChanged;
  final VoidCallback onStartArrowDelete;

  const _CanvasContents({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.lineMode,
    required this.deleteMode,
    required this.placingStartArrow,
    required this.lineSourceNodeId,
    required this.rubberBandEnd,
    required this.isLabelTaken,
    required this.onNodeLabelChanged,
    required this.onLineModeSelect,
    required this.onNodeDoubleTap,
    required this.onNodeDelete,
    required this.onLineDelete,
    required this.onLineLabelChanged,
    required this.onStartArrowDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Start arrow ─────────────────────────────────────────────────
        if (startArrow != null && nodes[startArrow!.nodeId] != null)
          Positioned.fill(
            child: StartArrowWidget(
              data: startArrow!,
              nodeCenter: nodes[startArrow!.nodeId]!.center,
              deleteMode: deleteMode,
              onDelete: onStartArrowDelete,
            ),
          ),

        // ── Rubber band (line preview while dragging) ───────────────────
        if (lineSourceNodeId != null &&
            rubberBandEnd != null &&
            nodes[lineSourceNodeId!] != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: RubberBandPainter(
                  start: nodes[lineSourceNodeId!]!.center,
                  end: rubberBandEnd!,
                  color: Colors.lightBlueAccent,
                ),
              ),
            ),
          ),

        // ── Transition lines ────────────────────────────────────────────
        ...lines.values.map((line) {
          final a = nodes[line.nodeAId];
          final b = nodes[line.nodeBId];
          if (a == null || b == null) return const SizedBox.shrink();
          return KeyedSubtree(
            key: ValueKey(line.id),
            child: Positioned.fill(
              child: LineWidget(
                data: line,
                centerA: a.center,
                centerB: b.center,
                deleteMode: deleteMode,
                highlighted: false,
                onLabelChanged: (text) => onLineLabelChanged(line.id, text),
              ),
            ),
          );
        }),

        // ── State nodes ─────────────────────────────────────────────────
        ...nodes.values.map((node) => Node(
              key: ValueKey(node.id),
              data: node,
              lineMode: lineMode,
              interactionLocked: placingStartArrow,
              deleteMode: deleteMode,
              highlighted: false,
              tapeCount: 1,
              isLabelTaken: isLabelTaken,
              onLabelChanged: (text) => onNodeLabelChanged(node.id, text),
              onLineModeSelect: () => onLineModeSelect(node.id),
              onDoubleTap: () => onNodeDoubleTap(node.id),
              onDelete: () => onNodeDelete(node.id),
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _MiniToolbar — compact FAB column placed inside the canvas
// ─────────────────────────────────────────────────────────────────────────────

class _MiniToolbar extends StatelessWidget {
  final bool lineMode;
  final bool placingStartArrow;
  final bool deleteMode;

  final Object startArrowTag;
  final Object lineModeTag;
  final Object deleteModeTag;

  final VoidCallback onStartArrowToggle;
  final VoidCallback onLineModeToggle;
  final VoidCallback onDeleteModeToggle;

  const _MiniToolbar({
    required this.lineMode,
    required this.placingStartArrow,
    required this.deleteMode,
    required this.startArrowTag,
    required this.lineModeTag,
    required this.deleteModeTag,
    required this.onStartArrowToggle,
    required this.onLineModeToggle,
    required this.onDeleteModeToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.surface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.borderMid),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Set start-state arrow
          Tooltip(
            message: placingStartArrow
                ? 'Tap a state to set it as start'
                : 'Set start state',
            child: PaletteFab(
              heroTag: startArrowTag,
              tooltip: 'Set start state',
              icon: Icons.play_arrow,
              active: placingStartArrow,
              activeColor: const Color(0xFFFF6D00),
              onPressed: onStartArrowToggle,
              small: true,
            ),
          ),
          const SizedBox(height: 6),

          // Line mode (draw transitions)
          PaletteFab(
            heroTag: lineModeTag,
            tooltip: lineMode ? 'Exit line mode' : 'Draw transition',
            icon: lineMode ? Icons.timeline : Icons.add_link,
            active: lineMode,
            activeColor: theme.accent,
            onPressed: onLineModeToggle,
            small: true,
          ),
          const SizedBox(height: 6),

          // Delete mode
          PaletteFab(
            heroTag: deleteModeTag,
            tooltip: 'Delete mode',
            icon: Icons.delete_outline,
            active: deleteMode,
            activeColor: theme.error,
            onPressed: onDeleteModeToggle,
            small: true,
          ),
        ],
      ),
    );
  }
}