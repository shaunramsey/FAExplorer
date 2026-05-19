import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
    return MaterialApp(
      title: 'Automata Designer',
      theme: ThemeData(
        textTheme: GoogleFonts.courierPrimeTextTheme(),
        primaryTextTheme: GoogleFonts.courierPrimeTextTheme(),
      ),
      home: const AutomataScreen(),
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
  bool _deleteMode = false;

  bool _showHelpOverlay = false;

  StartArrowData? _startArrow;

  bool _draggingStartArrow = false;

  String? _draggingNodeId;
  String? _draggingLineId;
  String? _lineSourceNodeId;

  Offset? _lastPanPosition;
  Offset? _lastTapPosition;
  Offset? _rubberBandEnd;

  int _nodeCounter = 0;
  int _lineCounter = 0;

  final FocusNode _focusNode = FocusNode();

  void _cancelRubberBand() {
  _lineSourceNodeId = null;
  _rubberBandEnd = null;
}

  bool _hitStartArrowSimple(Offset point) {
  if (_startArrow == null) return false;

  final node = _nodes[_startArrow!.nodeId];
  if (node == null) return false;

  var dir = _startArrow!.direction();

  if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
    dir = const Offset(-0.7071, -0.7071);
  }

  const double radius = 50;

  final end = Offset(
    node.center.dx + dir.dx * radius,
    node.center.dy + dir.dy * radius,
  );

  final start = Offset(
    end.dx + dir.dx * _startArrow!.length,
    end.dy + dir.dy * _startArrow!.length,
  );

  final line = end - start;
  final lenSq = line.dx * line.dx + line.dy * line.dy;

  if (lenSq == 0) return false;

  double t = ((point.dx - start.dx) * line.dx +
          (point.dy - start.dy) * line.dy) /
      lenSq;

  t = t.clamp(0.0, 1.0);

  final projection = Offset(
    start.dx + line.dx * t,
    start.dy + line.dy * t,
  );

  return (point - projection).distance < 30;
}

  bool _isLabelTaken(String label, String currentId) {
     final normalized = label.trim();

      if (normalized.isEmpty) return false;

      return _nodes.values.any((n) =>
      n.id != currentId && n.label.trim() == normalized);
}

  String _nextId(String prefix) {
    if (prefix == 'n') {
      return '$prefix${_nodeCounter++}';
    }

    return '$prefix${_lineCounter++}';
  }

  void _deleteLine(String lineId) {
    final line = _lines[lineId];

    if (line == null) return;

    _nodes[line.nodeAId]?.connectedLineIds.remove(lineId);

    _nodes[line.nodeBId]?.connectedLineIds.remove(lineId);

    _lines.remove(lineId);
  }

  void _deleteNode(String nodeId) {
    final node = _nodes[nodeId];

    if (node == null) return;

    for (final lineId in node.connectedLineIds.toList()) {
      _deleteLine(lineId);
    }

    if (_startArrow?.nodeId == nodeId) {
      _startArrow = null;
    }

    _nodes.remove(nodeId);
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
  final isShift =
      event.logicalKey == LogicalKeyboardKey.shiftLeft ||
      event.logicalKey == LogicalKeyboardKey.shiftRight;

  if (!isShift) return;

  if (event is KeyDownEvent) {
    setState(() {
      _lineMode = !_lineMode;

      // 🔥 IMPORTANT: cancel any in-progress line drag
      _draggingLineId = null;
      _draggingNodeId = null;

      _cancelRubberBand();
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

  var dir = _startArrow!.direction();

  // Default top-left
  if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
    dir = const Offset(-0.7071, -0.7071);
  }

  const double radius = 50;

  final end = Offset(
    node.center.dx + dir.dx * radius,
    node.center.dy + dir.dy * radius,
  );

  final start = Offset(
    end.dx + dir.dx * _startArrow!.length,
    end.dy + dir.dy * _startArrow!.length,
  );

  final line = end - start;

  final lenSq = line.dx * line.dx + line.dy * line.dy;

  if (lenSq == 0) return false;

  double t = ((point.dx - start.dx) * line.dx +
          (point.dy - start.dy) * line.dy) /
      lenSq;

  t = t.clamp(0.0, 1.0);

  final projection = Offset(
    start.dx + line.dx * t,
    start.dy + line.dy * t,
  );

  final distance = (point - projection).distance;

  return distance < 30;
}

  void _onDoubleTapDown(TapDownDetails details) {
    if (_lineMode) return;

    final clickedNode = _nodeAt(details.localPosition);

    if (clickedNode != null) return;

    setState(() {
      final pos = details.localPosition - const Offset(50, 50);

      final id = _nextId('n');

      _nodes[id] = NodeData(id: id, position: pos);
    });
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;

    _draggingNodeId = null;
    _draggingLineId = null;

    if (_deleteMode) {
  final node = _nodeAt(pos);

  if (node != null) {
    setState(() {
      _deleteNode(node.id);
    });
    return;
  }

  final line = _lineAt(pos);

  if (line != null) {
    setState(() {
      _deleteLine(line.id);
    });
    return;
  }

  if (_hitStartArrowSimple(pos)) {
    setState(() {
      _startArrow = null;
    });
    return;
  }

  return;
}

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

        final mouse = details.localPosition;

        final dir = Offset(mouse.dx - center.dx, mouse.dy - center.dy);

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

          final oldAngle = atan2(previous.dy - center.dy, previous.dx - center.dx);

          final newAngle = atan2(mouse.dy - center.dy, mouse.dx - center.dx);

          line.selfLoopAngle += newAngle - oldAngle;

          return;
        }

        final dx = nodeB.center.dx - nodeA.center.dx;
        final dy = nodeB.center.dy - nodeA.center.dy;

        final length = sqrt(dx * dx + dy * dy);

        if (length != 0) {
          final perpDx = dy / length;
          final perpDy = -dx / length;

          line.perpendicularPart += details.delta.dx * perpDx + details.delta.dy * perpDy;
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_lineMode && _lineSourceNodeId != null) {
      final destNode = _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;

      if (destNode != null) {
  final srcId = _lineSourceNodeId!;
  final destId = destNode.id;

  final alreadyExists = _lines.values.any(
    (line) => line.nodeAId == srcId && line.nodeBId == destId,
  );

  if (!alreadyExists) {
    setState(() {
      final id = _nextId('l');

      final line = LineData(id: id, nodeAId: srcId, nodeBId: destId);

      _lines[id] = line;

      _nodes[srcId]?.connectedLineIds.add(id);
      _nodes[destId]?.connectedLineIds.add(id);
    });
  }
} else {
  _cancelRubberBand();
}

      _lineSourceNodeId = null;
    }

    _draggingNodeId = null;
    _draggingLineId = null;
    _draggingStartArrow = false;

    _lastPanPosition = null;
    _rubberBandEnd = null;
    _cancelRubberBand();
    _lineSourceNodeId = null;
    _rubberBandEnd = null;
  }

  void _onPanUpdateWithTracking(DragUpdateDetails details) {
    _lastPanPosition = details.localPosition;

    _onPanUpdate(details);

    if (_lineSourceNodeId != null && _lineMode) {
  setState(() {
    _rubberBandEnd = details.localPosition;
  });
} else {
  _cancelRubberBand();
}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),

              SwitchListTile(
                title: const Text('Show Help'),
                subtitle: const Text('Displays controls and textbox commands.'),
                value: _showHelpOverlay,
                onChanged: (value) {
                  setState(() {
                    _showHelpOverlay = value;
                  });
                },
              ),

              const SizedBox(height: 8),

              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MarkdownFileScreen(title: 'About', assetPath: 'assets/About.md'),
                    ),
                  );
                },
                child: const Text('View About'),
              ),

              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MarkdownFileScreen(title: 'Changelog', assetPath: 'assets/Changelog.md'),
                    ),
                  );
                },
                child: const Text('View Changelog'),
              ),

              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MarkdownFileScreen(title: 'Version', assetPath: 'assets/Version.md'),
                    ),
                  );
                },
                child: const Text('View Version'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),

      appBar: AppBar(title: const Text('Automata Designer')),

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
            heroTag: 'deleteMode',
            tooltip: 'Delete mode',
            backgroundColor: _deleteMode ? Colors.red : null,
            onPressed: () {
              setState(() {
                _deleteMode = !_deleteMode;

                if (_deleteMode) {
                  _lineMode = false;
                  _placingStartArrow = false;
                }
              });
            },
            child: const Icon(Icons.delete),
          ),

          const SizedBox(height: 12),

          FloatingActionButton(
            heroTag: 'lineMode',
            tooltip: _lineMode ? 'Exit line mode' : 'Enter line mode',
            backgroundColor: _lineMode ? Colors.lightBlueAccent : null,
            onPressed: () => _setLineMode(!_lineMode),
            child: Icon(_lineMode ? Icons.timeline : Icons.add_link),
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
            if (_lastTapPosition == null || _nodeAt(_lastTapPosition!) == null) {
              _focusNode.requestFocus();
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
              if (_startArrow != null && _nodes[_startArrow!.nodeId] != null)
  Positioned.fill(
    child: StartArrowWidget(
      data: _startArrow!,
      nodeCenter: _nodes[_startArrow!.nodeId]!.center,

      deleteMode: _deleteMode,

      onDelete: () {
        setState(() {
          _startArrow = null;
        });
      },
    ),
  ),

              if (_lineSourceNodeId != null && _rubberBandEnd != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _RubberBandPainter(start: _nodes[_lineSourceNodeId!]!.center, end: _rubberBandEnd!),
                    ),
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
                      deleteMode: _deleteMode,
                      onLabelChanged: (text) {
                        setState(() {
                          line.label = text;
                        });
                      },
                    ),
                  ),
                );
              }),

              if (_showHelpOverlay)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.black.withOpacity(0.9),
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.all(16),
                      child: DefaultTextStyle(
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text('Quick Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

                            SizedBox(height: 12),

                            Text('• Double click empty space → Create node'),
                            Text('• Drag node → Move node'),
                            Text('• Double click node → Toggle accept state'),
                            Text('• Shift or link button → Line mode'),
                            Text('• Drag line → Curve line'),
                            Text('• Long press screen → Reset graph'),
                            Text('• Delete button → Delete mode'),

                            SizedBox(height: 16),

                            Text('Textbox Commands', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

                            SizedBox(height: 8),

                            Text('[[DELTA_CAP]] → Δ'),
                            Text('[[DELTA]] → δ'),
                            Text('[[EPSILON]] → ε'),
                            Text('[[SIGMA_CAP]] → Σ'),
                            Text('[[SIGMA]] → σ'),
                            Text('[[LAMBDA]] → λ'),
                            Text('[[PHI]] → φ'),
                            Text('[[/0]] → ∅'),
                            Text('[[INFINITY]] → ∞'),
                            Text('[[/abc]] → ã̸b̸c̸  (slashed letters)'),

                            SizedBox(height: 12),

                            Text(
                              'Tip: Commands can be typed directly inside node and line labels.',
                              style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              ..._nodes.values.map(
                (node) => Node(
                  key: ValueKey(node.id),
                  data: node,
                  lineMode: _lineMode,
                  deleteMode: _deleteMode,

                  isLabelTaken: _isLabelTaken,

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

                  onDelete: () {
                    setState(() {
                      _deleteNode(node.id);
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

class MarkdownFileScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const MarkdownFileScreen({super.key, required this.title, required this.assetPath});

  @override
  State<MarkdownFileScreen> createState() => _MarkdownFileScreenState();
}

class _MarkdownFileScreenState extends State<MarkdownFileScreen> {
  String _content = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final text = await rootBundle.loadString(widget.assetPath);

      setState(() {
        _content = text;
      });
    } catch (e) {
      setState(() {
        _content = 'Failed to load ${widget.assetPath}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(_content, style: GoogleFonts.courierPrime(fontSize: 16)),
      ),
    );
  }
}

class _RubberBandPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  const _RubberBandPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.lightBlueAccent.withOpacity(0.85);

    canvas.drawLine(start, end, paint);

    final angle = atan2(end.dy - start.dy, end.dx - start.dx);

    const len = 14.0;
    const wing = 8.0;

    final dx = cos(angle);
    final dy = sin(angle);

    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - len * dx + wing * dy, end.dy - len * dy - wing * dx)
      ..lineTo(end.dx - len * dx - wing * dy, end.dy - len * dy + wing * dx)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.lightBlueAccent.withOpacity(0.85)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_RubberBandPainter old) {
    return old.start != start || old.end != end;
  }
}