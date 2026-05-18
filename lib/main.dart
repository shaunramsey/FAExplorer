import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import 'models.dart';
import 'node.dart';
import 'line.dart';
import 'start_arrow.dart';

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
  bool _placingStartArrow = false;

  StartArrowData? _startArrow;

  bool _draggingStartArrow = false;

  String? _draggingNodeId;
  String? _draggingLineId;
  String? _lineSourceNodeId;

  Offset? _lastPanPosition;
  Offset? _lastTapPosition;

  int _nodeCounter = 0;
  int _lineCounter = 0;

  final FocusNode _focusNode = FocusNode();

  String _nextId(String prefix) {
    if (prefix == 'n') {
      return '$prefix${_nodeCounter++}';
    }
    return '$prefix${_lineCounter++}';
  }

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _nodes.clear();
      _lines.clear();

      _draggingNodeId = null;
      _draggingLineId = null;
      _lineSourceNodeId = null;

      _startArrow = null;

      _nodeCounter = 0;
      _lineCounter = 0;
    });
  }

  void _setLineMode(bool value) {
    setState(() {
      _lineMode = value;
    });
  }

  void _onKeyEvent(KeyEvent event) {
    final isAlt =
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight;

    if (!isAlt) return;

    if (event is KeyDownEvent) {
      setState(() {
        _lineMode = !_lineMode;
      });
    }
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

      if (line.containsPoint(point, nodeA.center, nodeB.center)) {
        return line;
      }
    }
    return null;
  }

  bool _hitStartArrow(Offset point) {
    if (_startArrow == null) return false;

    final node = _nodes[_startArrow!.nodeId];
    if (node == null) return false;

    final dir = _startArrow!.direction();

    final end = Offset(
      node.center.dx - dir.dx * 50,
      node.center.dy - dir.dy * 50,
    );

    final start = Offset(
      end.dx - dir.dx * _startArrow!.length,
      end.dy - dir.dy * _startArrow!.length,
    );

    final mid = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );

    return (point - mid).distance < 40;
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (_lineMode) return;

    final clickedNode = _nodeAt(details.localPosition);
    if (clickedNode != null) return;

    setState(() {
      final pos = details.localPosition - const Offset(50, 50);
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
      if (_placingStartArrow) {
        setState(() {
          _startArrow = StartArrowData(nodeId: node.id);
          _placingStartArrow = false;
        });
        return;
      }

      if (_lineMode) {
        _lineSourceNodeId = node.id;
      } else {
        _draggingNodeId = node.id;
      }
    } else {
      if (_hitStartArrow(pos)) {
        _draggingStartArrow = true;
        return;
      }

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
        node.position = node.position + details.delta;
      });
    } else if (_draggingStartArrow && _startArrow != null) {
      setState(() {
        final node = _nodes[_startArrow!.nodeId]!;
        final center = node.center;

        final mouse = _lastPanPosition ?? center;

        final dir = Offset(
          mouse.dx - center.dx,
          mouse.dy - center.dy,
        );

        final dist = dir.distance;

        if (dist > 10) {
          _startArrow!.offset = Offset(dir.dx / dist, dir.dy / dist);
          _startArrow!.length = max(40, dist - 50);
        }
      });
    } else if (_draggingLineId != null) {
      setState(() {
        final line = _lines[_draggingLineId!]!;
        final nodeA = _nodes[line.nodeAId]!;
        final nodeB = _nodes[line.nodeBId]!;

        if (line.nodeAId == line.nodeBId) {
          final center = nodeA.center;
          final mouse = _lastPanPosition ?? center;

          final previous = mouse - details.delta;

          final oldAngle = atan2(
            previous.dy - center.dy,
            previous.dx - center.dx,
          );

          final newAngle = atan2(
            mouse.dy - center.dy,
            mouse.dx - center.dx,
          );

          line.selfLoopAngle += newAngle - oldAngle;
          return;
        }

        final dx = nodeB.center.dx - nodeA.center.dx;
        final dy = nodeB.center.dy - nodeA.center.dy;

        final length = sqrt(dx * dx + dy * dy);

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
    if (_lineMode && _lineSourceNodeId != null) {
      final destNode = _lastPanPosition != null
          ? _nodeAt(_lastPanPosition!)
          : null;

      if (destNode != null) {
        final srcId = _lineSourceNodeId!;
        final destId = destNode.id;

        setState(() {
          final id = _nextId('l');

          final line = LineData(
            id: id,
            nodeAId: srcId,
            nodeBId: destId,
          );

          _lines[id] = line;

          _nodes[srcId]?.connectedLineIds.add(id);
          _nodes[destId]?.connectedLineIds.add(id);
        });
      }

      _lineSourceNodeId = null;
    }

    _draggingNodeId = null;
    _draggingLineId = null;
    _draggingStartArrow = false;

    _lastPanPosition = null;
  }

  void _onPanUpdateWithTracking(DragUpdateDetails details) {
    _lastPanPosition = details.localPosition;
    _onPanUpdate(details);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automata Designer'),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'startArrow',
            tooltip: 'Set start state',
            backgroundColor: _placingStartArrow ? Colors.orange : null,
            onPressed: () {
              setState(() {
                _placingStartArrow = !_placingStartArrow;
              });
            },
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'lineMode',
            tooltip: _lineMode ? 'Exit line mode' : 'Enter line mode',
            backgroundColor:
                _lineMode ? Colors.lightBlueAccent : null,
            onPressed: () => _setLineMode(!_lineMode),
            child: Icon(
              _lineMode ? Icons.timeline : Icons.add_link,
            ),
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _lastTapPosition = details.localPosition;
          },
          onTap: () {
            if (_lastTapPosition == null ||
                _nodeAt(_lastTapPosition!) == null) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
            _lastTapPosition = null;
          },
          onDoubleTapDown: _onDoubleTapDown,
          onLongPress: _reset,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdateWithTracking,
          onPanEnd: _onPanEnd,
          child: Stack(
            children: [
              if (_startArrow != null &&
                  _nodes[_startArrow!.nodeId] != null)
                Positioned.fill(
                  child: StartArrowWidget(
                    data: _startArrow!,
                    nodeCenter:
                        _nodes[_startArrow!.nodeId]!.center,
                  ),
                ),
              ..._lines.values.map((line) {
                final nodeA = _nodes[line.nodeAId];
                final nodeB = _nodes[line.nodeBId];

                if (nodeA == null || nodeB == null) {
                  return const SizedBox.shrink();
                }

                return KeyedSubtree(
                  key: ValueKey(line.id),
                  child: Positioned.fill(
                    child: LineWidget(
                      data: line,
                      centerA: nodeA.center,
                      centerB: nodeB.center,
                      onLabelChanged: (text) {
                        setState(() {
                          line.label = text;
                        });
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
                  onLabelChanged: (text) {
                    setState(() {
                      node.label = text;
                    });
                  },
                  onLineModeSelect: () {
                    if (_lineMode) {
                      _lineSourceNodeId = node.id;
                    }
                  },
                  onDoubleTap: () {
                    setState(() {
                      node.isAccept = !node.isAccept;
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