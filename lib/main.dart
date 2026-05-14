import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import 'models.dart';
import 'node.dart';
import 'line.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Automata Designer',
      home: AutomataScreen(),
    );
  }
}

class AutomataScreen extends StatefulWidget {
  const AutomataScreen({super.key});

  @override
  State<AutomataScreen> createState() => _AutomataScreenState();
}

class _AutomataScreenState extends State<AutomataScreen> {
  final Map<String, NodeData> _nodes = {};
  final Map<String, LineData> _lines = {};

  bool _lineMode = false;

  String? _draggingNodeId;
  String? _draggingLineId;
  String? _lineSourceNodeId;

  Offset? _lastPanPosition;
  Offset? _lastTapPosition;

  int _idCounter = 0;

  String _nextId(String prefix) {
    return '$prefix${_idCounter++}';
  }

  // ─────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────

  void _reset() {
    setState(() {
      _nodes.clear();
      _lines.clear();

      _draggingNodeId = null;
      _draggingLineId = null;
      _lineSourceNodeId = null;
    });
  }

  void _setLineMode(bool value) {
    setState(() {
      _lineMode = value;
    });
  }

  NodeData? _nodeAt(Offset point) {
    for (final node in _nodes.values) {
      if (node.containsPoint(point)) {
        return node;
      }
    }

    return null;
  }

  LineData? _lineAt(Offset point) {
    for (final line in _lines.values) {
      final nodeA = _nodes[line.nodeAId]!;
      final nodeB = _nodes[line.nodeBId]!;

      if (
        line.containsPoint(
          point,
          nodeA.center,
          nodeB.center,
        )
      ) {
        return line;
      }
    }

    return null;
  }

  // ─────────────────────────────────────────────
  // Gestures
  // ─────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails details) {
    if (_lineMode) return;

    final clickedNode = _nodeAt(details.localPosition);

    // Double-clicking node should NOT create node
    if (clickedNode != null) {
      return;
    }

    setState(() {
      final pos =
          details.localPosition - const Offset(50, 50);

      final id = _nextId('n');

      _nodes[id] = NodeData(
        id: id,
        position: pos,
      );
    });
  }

  void _onPanStart(DragStartDetails details) {
  final pos = details.localPosition;

  _draggingNodeId = null;
  _draggingLineId = null;

  final node = _nodeAt(pos);

  if (node != null) {
    if (_lineMode) {
      _lineSourceNodeId = node.id;
    } else {
      _draggingNodeId = node.id;
    }
  } else {
    final line = _lineAt(pos);

    if (line != null) {
      _draggingLineId = line.id;
    }
  }
}

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingNodeId != null) {
      setState(() {
        final node = _nodes[_draggingNodeId!]!;

        node.position =
            node.position + details.delta;
      });
    }

    else if (_draggingLineId != null) {
      setState(() {
        final line =
            _lines[_draggingLineId!]!;

        final nodeA =
            _nodes[line.nodeAId]!;

        final nodeB =
            _nodes[line.nodeBId]!;

        final dx =
            nodeB.center.dx - nodeA.center.dx;

        final dy =
            nodeB.center.dy - nodeA.center.dy;

        final length =
            sqrt(dx * dx + dy * dy);

        if (length != 0) {
          final perpDx = dy / length;
          final perpDy = -dx / length;

          line.perpendicularPart +=
              details.delta.dx * perpDx +
              details.delta.dy * perpDy;
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (
      _lineMode &&
      _lineSourceNodeId != null
    ) {
      final destNode =
          _lastPanPosition != null
          ? _nodeAt(_lastPanPosition!)
          : null;

      if (destNode != null) {
        final srcId =
            _lineSourceNodeId!;

        final destId =
            destNode.id;

        final alreadyExists =
            _lines.values.any(
          (l) =>
              l.nodeAId == srcId &&
              l.nodeBId == destId,
        );

        if (!alreadyExists) {
          setState(() {
            final id =
                _nextId('l');

            final line = LineData(
              id: id,
              nodeAId: srcId,
              nodeBId: destId,
            );

            _lines[id] = line;

            _nodes[srcId]
                ?.connectedLineIds
                .add(id);

            _nodes[destId]
                ?.connectedLineIds
                .add(id);
          });
        }
      }

      _lineSourceNodeId = null;
    }

    _draggingNodeId = null;
    _draggingLineId = null;
    _lastPanPosition = null;
  }

  void _onPanUpdateWithTracking(
    DragUpdateDetails details,
  ) {
    _lastPanPosition =
        details.localPosition;

    _onPanUpdate(details);
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Automata Designer',
        ),
      ),

      floatingActionButton:
          FloatingActionButton(
        tooltip: _lineMode
            ? 'Exit line mode'
            : 'Enter line mode',

        backgroundColor:
            _lineMode
            ? Colors.lightBlueAccent
            : null,

        onPressed: () {
          _setLineMode(!_lineMode);
        },

        child: Icon(
          _lineMode
              ? Icons.timeline
              : Icons.add_link,
        ),
      ),

      body: KeyboardListener(
        focusNode:
            FocusNode()..requestFocus(),

        autofocus: true,

        onKeyEvent: (event) {
          if (
            event is KeyDownEvent &&
            HardwareKeyboard
                .instance
                .isAltPressed
          ) {
            _setLineMode(true);
          }

          if (
            event is KeyUpEvent &&
            (
              event.logicalKey ==
                  LogicalKeyboardKey.altLeft ||
              event.logicalKey ==
                  LogicalKeyboardKey.altRight
            )
          ) {
            _setLineMode(false);
          }
        },

        child: GestureDetector(
          behavior:
              HitTestBehavior.opaque,

          onTapDown: (details) {
            _lastTapPosition = details.localPosition;
          },

          onTap: () {
            // Only unfocus (deselect everything) when the tap is on empty
            // canvas — not on a node.  Tapping a node fires both the node's
            // own GestureDetector (selects it) and this one (because the
            // node uses HitTestBehavior.translucent); calling unfocus here
            // would immediately cancel the selection we just made.
            // Note: _lastPanPosition is null outside of a pan, so we use a
            // separate field for the last tap position.
            if (_lastTapPosition == null ||
                _nodeAt(_lastTapPosition!) == null) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
            _lastTapPosition = null;
          },

          onDoubleTapDown:
              _onDoubleTapDown,

          onLongPress: _reset,

          onPanStart: _onPanStart,

          onPanUpdate:
              _onPanUpdateWithTracking,

          onPanEnd: _onPanEnd,

          child: Stack(
            children: [
              // ─────────────────────
              // Lines
              // ─────────────────────

              ..._lines.values.map(
                (line) {
                  final nodeA =
                      _nodes[line.nodeAId];

                  final nodeB =
                      _nodes[line.nodeBId];

                  if (
                    nodeA == null ||
                    nodeB == null
                  ) {
                    return const SizedBox
                        .shrink();
                  }

                  return KeyedSubtree(
  key: ValueKey(line.id),

  child: Positioned.fill(
    child: LineWidget(
      data: line,

      centerA:
          nodeA.center,

      centerB:
          nodeB.center,

      onLabelChanged:
          (text) {
        setState(() {
          line.label = text;
        });
      },
    ),
  ),
);
                },
              ),

              // ─────────────────────
              // Nodes
              // ─────────────────────

              ..._nodes.values.map(
                (node) => Node(
                  key: ValueKey(node.id),

                  data: node,

                  lineMode: _lineMode,

                  onLabelChanged:
                      (text) {
                    setState(() {
                      node.label = text;
                    });
                  },

                  onLineModeSelect: () {
                    if (_lineMode) {
                      _lineSourceNodeId =
                          node.id;
                    }
                  },

                  onDoubleTap: () {
                    setState(() {
                      node.isAccept =
                          !node.isAccept;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}