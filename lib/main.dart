import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import 'dart:convert';
import 'models.dart';
import 'node.dart';
import 'line.dart';
import 'start_arrow.dart';
import 'package:file_picker/file_picker.dart';
import 'dsl_code.dart';
import 'simulator.dart';

void main() => runApp(const MyApp());

class BatchHighlightController extends TextEditingController {
  final bool Function(int lineIndex) isAccepted;
  final bool Function(int lineIndex) isRejected;

  BatchHighlightController({required this.isAccepted, required this.isRejected});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final lines = text.split('\n');

    final children = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      Color color = Colors.white;

      if (isAccepted(i)) {
        color = Colors.green;
      } else if (isRejected(i)) {
        color = Colors.red;
      }

      children.add(
        TextSpan(
          text: lines[i],
          style: GoogleFonts.courierPrime(color: color, fontSize: 16),
        ),
      );

      if (i != lines.length - 1) {
        children.add(
          TextSpan(
            text: '\n',
            style: GoogleFonts.courierPrime(color: Colors.white, fontSize: 16),
          ),
        );
      }
    }

    return TextSpan(children: children);
  }
}

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
  bool _showSimulator = true;

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

  final List<SavedExport> _savedExports = [];

  late final AutomataSimulator _simulator;

  Future<void> _openBatchSimulatorDialog() async {
    final accepted = <int>{};
    final rejected = <int>{};

    late BatchHighlightController controller;

    void rebuildResults() {
      accepted.clear();
      rejected.clear();

      final lines = controller.text.split('\n');

      for (int i = 0; i < lines.length; i++) {
        final str = lines[i].replaceAll('\r', '');

        final isComplete = i < lines.length - 1 || controller.text.endsWith('\n');

        if (!isComplete || str.isEmpty) {
          continue;
        }

        final oldTokens = List<String>.from(_simulator.tokens);
        final oldStates = _simulator.states.map(Set<String>.from).toList();
        final oldLines = _simulator.usedLines.map(Set<String>.from).toList();
        final oldStep = _simulator.step;

        _simulator.rebuild(str, startArrow: _startArrow);

        final result = _simulator.finalResult();

        if (result == SimResult.accept || result == SimResult.mixed) {
          accepted.add(i);
        } else {
          rejected.add(i);
        }

        _simulator.tokens = oldTokens;
        _simulator.step = oldStep;
        _simulator.states
          ..clear()
          ..addAll(oldStates);
        _simulator.usedLines
          ..clear()
          ..addAll(oldLines);
      }
    }

    controller = BatchHighlightController(
      isAccepted: (i) => accepted.contains(i),
      isRejected: (i) => rejected.contains(i),
    );

    controller.addListener(() {
      rebuildResults();
    });

    rebuildResults();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: Colors.black,
              title: Text('Batch String Simulator', style: GoogleFonts.courierPrime(color: Colors.white)),
              content: SizedBox(
                width: 700,
                height: 500,
                child: Column(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        cursorColor: Colors.white,
                        style: GoogleFonts.courierPrime(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'One string per line...\nPress enter to simulate.',
                          hintStyle: GoogleFonts.courierPrime(color: Colors.grey),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          setLocalState(() {});
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['txt'],
                              );

                              if (result == null || result.files.single.bytes == null) {
                                return;
                              }

                              final text = String.fromCharCodes(result.files.single.bytes!);

                              setLocalState(() {
                                controller.text = text;
                                rebuildResults();
                              });
                            },
                            child: Text('Import .txt', style: GoogleFonts.courierPrime()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STRING SIMULATION (delegates to AutomataSimulator)
  // ═══════════════════════════════════════════════════════════════
  final TextEditingController _simController = TextEditingController();

  Set<String> get _simActiveNodes => _simulator.activeNodes;
  Set<String> get _simActiveLines => _simulator.activeLines;

  void _refreshSimulation() {
    _simulator.rebuildGraph(startArrow: _startArrow);
    setState(() {});
  }

  void _simRebuild() {
    _simulator.rebuild(_simController.text, startArrow: _startArrow);
    if (_simulator.step > _simulator.tokens.length) {
      _simulator.step = _simulator.tokens.length;
    }
  }

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

    final end = Offset(node.center.dx + dir.dx * radius, node.center.dy + dir.dy * radius);

    final start = Offset(end.dx + dir.dx * _startArrow!.length, end.dy + dir.dy * _startArrow!.length);

    final line = end - start;
    final lenSq = line.dx * line.dx + line.dy * line.dy;

    if (lenSq == 0) return false;

    double t = ((point.dx - start.dx) * line.dx + (point.dy - start.dy) * line.dy) / lenSq;

    t = t.clamp(0.0, 1.0);

    final projection = Offset(start.dx + line.dx * t, start.dy + line.dy * t);

    return (point - projection).distance < 30;
  }

  bool _isLabelTaken(String label, String currentId) {
    final normalized = label.trim();

    if (normalized.isEmpty) return false;

    return _nodes.values.any((n) => n.id != currentId && n.label.trim() == normalized);
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
    _refreshSimulation();
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
    _refreshSimulation();
  }

  @override
  void initState() {
    super.initState();

    _focusNode.requestFocus();

    _simulator = AutomataSimulator(
      nodes: _nodes,
      lines: _lines,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _simController.dispose();
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

  // ═══════════════════════════════════════════════════════════════
  // DSL EXPORT
  // ═══════════════════════════════════════════════════════════════
  //
  // Produces a human-readable plaintext description of the graph.
  // One statement per line; blank lines for readability.
  //
  // Syntax produced (mirrors import syntax):
  //   nN = label          – node definition
  //   label = (x, y)      – position (only when non-default)
  //   label is accepted   – accept state
  //   labelA to labelB = lineLabel   – transition (= lineLabel optional)
  //   lineLabel curve = N – non-zero perpendicular part
  //   to label            – start arrow
  //   to label = saLabel  – start arrow with label
  //   to label length = N – start arrow length (only when non-default)
  // ═══════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════
  // DSL EXPORT
  // ═══════════════════════════════════════════════════════════════

  String _exportToDsl() {
    return DslCodec.exportToDsl(
      GraphState(
        nodes: _nodes,
        lines: _lines,
        startArrow: _startArrow,
        nodeCounter: _nodeCounter,
        lineCounter: _lineCounter,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SVG ARROW HELPER — draws a filled triangle arrowhead at [tip]
  // pointing in [angle] radians, and returns the shortened endpoint
  // (base of the arrowhead) so the stroke doesn't poke through.
  // ═══════════════════════════════════════════════════════════════
  static const double _svgArrowLen = 15;
  static const double _svgArrowWing = 9;

  /// Returns SVG markup for a filled arrowhead polygon at [tip] pointing
  /// in direction [angle].
  String _svgArrowhead(Offset tip, double angle) {
    final dx = cos(angle);
    final dy = sin(angle);
    final p1x = tip.dx - _svgArrowLen * dx + _svgArrowWing * dy;
    final p1y = tip.dy - _svgArrowLen * dy - _svgArrowWing * dx;
    final p2x = tip.dx - _svgArrowLen * dx - _svgArrowWing * dy;
    final p2y = tip.dy - _svgArrowLen * dy + _svgArrowWing * dx;
    return '<polygon points="${tip.dx},${tip.dy} $p1x,$p1y $p2x,$p2y" fill="var(--fg)"/>';
  }

  /// Returns the endpoint shortened by [_svgArrowLen] along [angle].
  Offset _shortenedEnd(Offset tip, double angle) {
    return Offset(tip.dx - cos(angle) * _svgArrowLen, tip.dy - sin(angle) * _svgArrowLen);
  }

  String _exportToSvg() {
    // ─────────────────────────────────────────────
    // BOUNDING BOX COMPUTATION
    // We collect every rectangle that must be visible:
    //   • node circles (center ± nodeRadius + strokeWidth)
    //   • line label text boxes
    //   • start-arrow line + its label text box
    // Lines themselves are only expanded if their midpoint already
    // falls outside the box formed by the above elements.
    // ─────────────────────────────────────────────

    const double nodeRadius = 42.0;
    const double nodePad = nodeRadius + 4; // stroke clearance
    const double pad = 30.0; // outer SVG padding

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    void expandPoint(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    void expandRect(double left, double top, double right, double bottom) {
      expandPoint(left, top);
      expandPoint(right, bottom);
    }

    // Nodes
    for (final node in _nodes.values) {
      final c = node.center;
      expandRect(c.dx - nodePad, c.dy - nodePad, c.dx + nodePad, c.dy + nodePad);
    }

    // Line label text boxes (always included)
    for (final line in _lines.values) {
      final nodeA = _nodes[line.nodeAId];
      final nodeB = _nodes[line.nodeBId];
      if (nodeA == null || nodeB == null) continue;

      if (line.label.trim().isNotEmpty) {
        const double boxW = 120;
        const double lineH = 36.0;
        final lineCount = '\n'.allMatches(line.label).length + 1;
        final double boxH = lineH * lineCount;
        final pos = line.getTextBoxLocation(nodeA.center, nodeB.center, boxW, boxH, line.label);
        expandRect(pos.dx, pos.dy, pos.dx + boxW, pos.dy + boxH);
      }

      // Expand for arc/loop geometry mid-point (only if already off-canvas)
      final geometry = line.computeGeometry(nodeA.center, nodeB.center);
      // We include the arc's midpoint so arcs don't clip unexpectedly
      expandPoint(geometry.midPoint.dx, geometry.midPoint.dy);
      expandPoint(geometry.startPoint.dx, geometry.startPoint.dy);
      expandPoint(geometry.endPoint.dx, geometry.endPoint.dy);
    }

    // Start arrow
    if (_startArrow != null) {
      final node = _nodes[_startArrow!.nodeId];
      if (node != null) {
        var dir = _startArrow!.direction();
        if (dir.distance == 0) dir = const Offset(-0.7071, -0.7071);
        final center = node.center;
        final arrowEnd = Offset(center.dx + dir.dx * 50, center.dy + dir.dy * 50);
        final arrowStart = Offset(
          arrowEnd.dx + dir.dx * _startArrow!.length,
          arrowEnd.dy + dir.dy * _startArrow!.length,
        );
        expandPoint(arrowStart.dx, arrowStart.dy);
        expandPoint(arrowEnd.dx, arrowEnd.dy);

        if (_startArrow!.label.trim().isNotEmpty) {
          const double boxW = 120;
          const double lineH = 36.0;
          final lineCount = '\n'.allMatches(_startArrow!.label).length + 1;
          final double boxH = lineH * lineCount;
          final perp = Offset(-dir.dy, dir.dx);
          final labelPos = Offset(arrowStart.dx + perp.dx * 30 - boxW / 2, arrowStart.dy + perp.dy * 30 - boxH / 2);
          expandRect(labelPos.dx, labelPos.dy, labelPos.dx + boxW, labelPos.dy + boxH);
        }
      }
    }

    // Fallback if graph is empty
    if (minX == double.infinity) {
      minX = 0;
      minY = 0;
      maxX = 400;
      maxY = 300;
    }

    final double vx = minX - pad;
    final double vy = minY - pad;
    final double vw = (maxX - minX) + pad * 2;
    final double vh = (maxY - minY) + pad * 2;

    // ─────────────────────────────────────────────
    // GRAPH DATA EMBEDDED AS JSON
    // ─────────────────────────────────────────────

    final graphData = {
      'version': 2,
      'nodes': _nodes.values.map((n) {
        return {
          'id': n.id,
          'x': n.position.dx,
          'y': n.position.dy,
          'label': n.label,
          'accept': n.isAccept,
          'haltAccept': n.isHaltAccept,
          'haltReject': n.isHaltReject,
        };
      }).toList(),
      'lines': _lines.values.map((l) {
        return {
          'id': l.id,
          'a': l.nodeAId,
          'b': l.nodeBId,
          'label': l.label,
          'curve': l.perpendicularPart,
          'loopAngle': l.selfLoopAngle,
        };
      }).toList(),
      'startArrow': _startArrow == null
          ? null
          : {
              'nodeId': _startArrow!.nodeId,
              'dx': _startArrow!.offset.dx,
              'dy': _startArrow!.offset.dy,
              'length': _startArrow!.length,
              'label': _startArrow!.label,
            },
    };

    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');

    // Emit viewBox tightly fitted to content; width/height in px match viewBox.
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg"'
      ' width="${vw.toStringAsFixed(1)}"'
      ' height="${vh.toStringAsFixed(1)}"'
      ' viewBox="${vx.toStringAsFixed(1)} ${vy.toStringAsFixed(1)} ${vw.toStringAsFixed(1)} ${vh.toStringAsFixed(1)}">',
    );
    buffer.writeln();

    // ─────────────────────────────────────────────
    // COLOR VARIABLES — edit these to retheme everything
    // ─────────────────────────────────────────────
    buffer.writeln('''<style>
  :root {
    --fg:          black;   /* stroke, arrow fill, text */
    --node-fill:   none;    /* node circle interior     */
    --label-fill:  black;   /* text inside nodes        */
    --hint-fill:   #888;    /* hint text color          */
  }
</style>
''');

    // Embedded graph data
    buffer.writeln('<script type="application/json" id="automata-data">');
    buffer.writeln(const JsonEncoder.withIndent('  ').convert(graphData));
    buffer.writeln('</script>');
    buffer.writeln();

    // ─────────────────────────────
    // LINES
    // ─────────────────────────────

    for (final line in _lines.values) {
      final nodeA = _nodes[line.nodeAId];
      final nodeB = _nodes[line.nodeBId];
      if (nodeA == null || nodeB == null) continue;

      final geometry = line.computeGeometry(nodeA.center, nodeB.center);
      const double strokeW = 4;

      if (line.nodeAId == line.nodeBId) {
        // ── Self loop ──
        final radius = geometry.circleRadius!;
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final arrowAngle = geometry.arrowAngle!;
        final shortenedEnd = _shortenedEnd(tipPt, arrowAngle);

        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <path d="M ${startPt.dx} ${startPt.dy} A $radius $radius 0 1 1 ${shortenedEnd.dx} ${shortenedEnd.dy}"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_svgArrowhead(tipPt, arrowAngle)}');
        buffer.writeln('</g>');
      } else if (geometry.hasCircle) {
        // ── Curved arc ──
        final radius = geometry.circleRadius!;
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final arrowAngle = geometry.arrowAngle!;
        final shortenedEnd = _shortenedEnd(tipPt, arrowAngle);
        final largeArc = geometry.sweepAngle!.abs() > pi ? 1 : 0;
        final sweep = geometry.sweepAngle! > 0 ? 1 : 0;

        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <path d="M ${startPt.dx} ${startPt.dy} A $radius $radius 0 $largeArc $sweep ${shortenedEnd.dx} ${shortenedEnd.dy}"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_svgArrowhead(tipPt, arrowAngle)}');
        buffer.writeln('</g>');
      } else {
        // ── Straight line ──
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final angle = atan2(tipPt.dy - startPt.dy, tipPt.dx - startPt.dx);
        final shortenedEnd = _shortenedEnd(tipPt, angle);

        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <line x1="${startPt.dx}" y1="${startPt.dy}" x2="${shortenedEnd.dx}" y2="${shortenedEnd.dy}"'
          ' stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_svgArrowhead(tipPt, angle)}');
        buffer.writeln('</g>');
      }

      // Label
      if (line.label.trim().isNotEmpty) {
        const double boxW = 120;
        const double lineH = 36.0;
        final lineCount = '\n'.allMatches(line.label).length + 1;
        final double boxH = lineH * lineCount;
        final textPos = line.getTextBoxLocation(nodeA.center, nodeB.center, boxW, boxH, line.label);
        final parts = line.label.split('\n');
        buffer.writeln(
          '<text x="${(textPos.dx + boxW / 2).toStringAsFixed(1)}" y="${(textPos.dy + 24).toStringAsFixed(1)}"'
          ' font-family="Courier New, monospace" font-weight="bold" font-size="30"'
          ' text-anchor="middle" fill="var(--fg)">',
        );
        for (int i = 0; i < parts.length; i++) {
          if (i == 0) {
            buffer.writeln('  <tspan>${htmlEscape.convert(parts[i])}</tspan>');
          } else {
            buffer.writeln(
              '  <tspan x="${(textPos.dx + boxW / 2).toStringAsFixed(1)}" dy="36">${htmlEscape.convert(parts[i])}</tspan>',
            );
          }
        }
        buffer.writeln('</text>');
      }
      buffer.writeln();
    }

    // ─────────────────────────────
    // NODES
    // ─────────────────────────────

    const double acceptRadius = 34.0;
    const double strokeWidth = 3.0;

    for (final node in _nodes.values) {
      final center = node.center;
      final hasLabel = node.label.trim().isNotEmpty;
      final displayText = hasLabel ? node.label : nodeIdToAlpha(node.id);
      final textColor = hasLabel ? 'var(--label-fill)' : 'var(--hint-fill)';

      buffer.writeln('<g class="node" data-id="${node.id}">');
      buffer.writeln(
        '  <circle cx="${center.dx}" cy="${center.dy}" r="$nodeRadius"'
        ' fill="var(--node-fill)" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
      );
      if (node.isAccept) {
        buffer.writeln(
          '  <circle cx="${center.dx}" cy="${center.dy}" r="$acceptRadius"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }

      if (node.isHaltAccept) {
        final left = center.dx - 24;
        final top = center.dy - 24;

        buffer.writeln(
          '  <rect x="$left" y="$top" width="48" height="48"'
          ' fill="green" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }

      if (node.isHaltReject) {
        final points = [
          '${center.dx - 12},${center.dy - 24}',
          '${center.dx + 12},${center.dy - 24}',
          '${center.dx + 24},${center.dy - 12}',
          '${center.dx + 24},${center.dy + 12}',
          '${center.dx + 12},${center.dy + 24}',
          '${center.dx - 12},${center.dy + 24}',
          '${center.dx - 24},${center.dy + 12}',
          '${center.dx - 24},${center.dy - 12}',
        ].join(' ');

        buffer.writeln(
          '  <polygon points="$points"'
          ' fill="red" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }
      buffer.writeln(
        '  <text x="${center.dx}" y="${center.dy}"'
        ' dominant-baseline="middle" text-anchor="middle"'
        ' font-family="Courier New, monospace" font-weight="bold" font-size="24"'
        ' fill="$textColor">${htmlEscape.convert(displayText)}</text>',
      );
      buffer.writeln('</g>');
      buffer.writeln();
    }

    // ─────────────────────────────
    // START ARROW
    // ─────────────────────────────

    if (_startArrow != null) {
      final node = _nodes[_startArrow!.nodeId];
      if (node != null) {
        var dir = _startArrow!.direction();
        if (dir.distance == 0) dir = const Offset(-0.7071, -0.7071);

        final center = node.center;
        final tipPt = Offset(center.dx + dir.dx * 50, center.dy + dir.dy * 50);
        final arrowStart = Offset(tipPt.dx + dir.dx * _startArrow!.length, tipPt.dy + dir.dy * _startArrow!.length);
        final angle = atan2(tipPt.dy - arrowStart.dy, tipPt.dx - arrowStart.dx);
        final shortenedTip = _shortenedEnd(tipPt, angle);

        buffer.writeln('<g class="start-arrow">');
        buffer.writeln(
          '  <line x1="${arrowStart.dx}" y1="${arrowStart.dy}" x2="${shortenedTip.dx}" y2="${shortenedTip.dy}"'
          ' stroke="var(--fg)" stroke-width="4" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_svgArrowhead(tipPt, angle)}');

        // Start arrow label
        if (_startArrow!.label.trim().isNotEmpty) {
          const double boxW = 120;
          const double lineH = 36.0;
          final lineCount = '\n'.allMatches(_startArrow!.label).length + 1;
          final double boxH = lineH * lineCount;
          final perp = Offset(-dir.dy, dir.dx);
          final labelPos = Offset(arrowStart.dx + perp.dx * 30 - boxW / 2, arrowStart.dy + perp.dy * 30 - boxH / 2);
          final parts = _startArrow!.label.split('\n');
          buffer.writeln(
            '<text x="${(labelPos.dx + boxW / 2).toStringAsFixed(1)}" y="${(labelPos.dy + 24).toStringAsFixed(1)}"'
            ' font-family="Courier New, monospace" font-weight="bold" font-size="30"'
            ' text-anchor="middle" fill="var(--fg)">',
          );
          for (int i = 0; i < parts.length; i++) {
            if (i == 0) {
              buffer.writeln('  <tspan>${htmlEscape.convert(parts[i])}</tspan>');
            } else {
              buffer.writeln(
                '  <tspan x="${(labelPos.dx + boxW / 2).toStringAsFixed(1)}" dy="36">${htmlEscape.convert(parts[i])}</tspan>',
              );
            }
          }
          buffer.writeln('</text>');
        }

        buffer.writeln('</g>');
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  void _applyGraphState(GraphState state) {
    setState(() {
      _nodes
        ..clear()
        ..addAll(state.nodes);
      _lines
        ..clear()
        ..addAll(state.lines);
      _startArrow = state.startArrow;
      _nodeCounter = state.nodeCounter;
      _lineCounter = state.lineCounter;
      _draggingNodeId = null;
      _draggingLineId = null;
      _lineSourceNodeId = null;
    });
    _refreshSimulation();
  }

  String? _importFromDsl(String src) {
    try {
      _applyGraphState(DslCodec.importFromDsl(src));
      return null;
    } catch (e) {
      return 'Parse error: $e';
    }
  }

  String? _importFromSvg(String svg) {
    try {
      _applyGraphState(DslCodec.importFromSvg(svg));
      return null;
    } catch (e) {
      return 'SVG import failed: $e';
    }
  }

  // ─────────────────────────────────────────────
  // EXPORT DIALOG
  // ─────────────────────────────────────────────

  void _showExportDialog() {
    final dsl = _exportToDsl();

    final nameController = TextEditingController(text: 'Export ${_savedExports.length + 1}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export', style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold)),

        content: SizedBox(
          width: double.maxFinite,

          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Save Name', border: OutlineInputBorder()),
              ),

              const SizedBox(height: 12),

              Text('Copied to clipboard.', style: GoogleFonts.courierPrime(fontSize: 13)),

              const SizedBox(height: 10),

              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),

                child: SingleChildScrollView(
                  child: SelectableText(
                    dsl.isEmpty ? '(empty graph)' : dsl,

                    style: GoogleFonts.courierPrime(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        actions: [
          TextButton(
            onPressed: () async {
              final svg = _exportToSvg();

              await Clipboard.setData(ClipboardData(text: svg));

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.black,
                  content: Text('SVG copied to clipboard', style: GoogleFonts.courierPrime()),
                ),
              );

              Navigator.pop(context);
            },

            child: const Text('Export SVG'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _savedExports.insert(
                  0,
                  SavedExport(
                    name: nameController.text.trim().isEmpty ? 'Untitled' : nameController.text.trim(),

                    dsl: dsl,
                  ),
                );
              });

              Navigator.of(ctx).pop();

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export saved')));
            },

            child: const Text('Save'),
          ),

          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: dsl));

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
            },

            child: const Text('Copy'),
          ),

          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // IMPORT DIALOG
  // ─────────────────────────────────────────────

  void _showImportDialog() {
    final controller = TextEditingController();
    String? errorText;

    const hint =
        'n0 = hello world\n'
        'n1 = yes and no\n'
        'hello world to yes and no = pears\n'
        'pears curve = 30\n'
        'apples\n'
        'apples to yes and no\n'
        'to apples\n'
        'apples to apples = 1\n'
        'apples = (0, 0)\n'
        'to apples length = 150\n'
        'apples is accepted';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Import', style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    expands: true,
                    style: GoogleFonts.courierPrime(fontSize: 13),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: hint,
                      hintStyle: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black38),
                      errorText: errorText,
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final clip = await Clipboard.getData(Clipboard.kTextPlain);
                if (clip?.text != null) {
                  controller.text = clip!.text!;
                }
              },
              child: const Text('Paste'),
            ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();

                final lower = text.toLowerCase();

                final isSvg = lower.contains('<svg') && lower.contains('</svg>');

                final err = isSvg ? _importFromSvg(text) : _importFromDsl(text);
                if (err == null) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import successful')));
                } else {
                  setDialogState(() => errorText = err);
                }
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  void _setLineMode(bool value) {
    setState(() {
      _lineMode = value;
    });
  }

  void _showExportHistory() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Saved Exports', style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold)),

              content: SizedBox(
                width: double.maxFinite,
                height: 400,

                child: _savedExports.isEmpty
                    ? const Center(child: Text('No saved exports'))
                    : ListView.builder(
                        itemCount: _savedExports.length,

                        itemBuilder: (context, index) {
                          if (index >= _savedExports.length) {
                            return const SizedBox.shrink();
                          }

                          final save = _savedExports[index];

                          return ListTile(
                            title: Text(save.name),

                            subtitle: Text(
                              save.dsl.trim().isEmpty ? '(empty export)' : save.dsl.split('\n').first,

                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),

                            onTap: () {
                              Navigator.of(ctx).pop();

                              final err = _importFromDsl(save.dsl);

                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                              }
                            },

                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,

                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),

                                  onPressed: () {
                                    final controller = TextEditingController(text: save.name);

                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Rename Export'),

                                        content: TextField(controller: controller),

                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                            },

                                            child: const Text('Cancel'),
                                          ),

                                          FilledButton(
                                            onPressed: () {
                                              setState(() {
                                                save.name = controller.text.trim();
                                              });

                                              setDialogState(() {});

                                              Navigator.pop(context);
                                            },

                                            child: const Text('Save'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                IconButton(
                                  icon: const Icon(Icons.delete),

                                  onPressed: () {
                                    setState(() {
                                      _savedExports.removeAt(index);
                                    });

                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                  },

                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onKeyEvent(KeyEvent event) {
    final isShift =
        event.logicalKey == LogicalKeyboardKey.shiftLeft || event.logicalKey == LogicalKeyboardKey.shiftRight;

    if (!isShift) return;

    if (event is KeyDownEvent) {
      setState(() {
        _lineMode = !_lineMode;
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

    final end = Offset(node.center.dx + dir.dx * radius, node.center.dy + dir.dy * radius);

    final start = Offset(end.dx + dir.dx * _startArrow!.length, end.dy + dir.dy * _startArrow!.length);

    final line = end - start;

    final lenSq = line.dx * line.dx + line.dy * line.dy;

    if (lenSq == 0) return false;

    double t = ((point.dx - start.dx) * line.dx + (point.dy - start.dy) * line.dy) / lenSq;

    t = t.clamp(0.0, 1.0);

    final projection = Offset(start.dx + line.dx * t, start.dy + line.dy * t);

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
    _refreshSimulation();
  }

  void _onPanEnd(DragEndDetails details) {
    if (_lineMode && _lineSourceNodeId != null) {
      final destNode = _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;

      if (destNode != null) {
        final srcId = _lineSourceNodeId!;
        final destId = destNode.id;

        final alreadyExists = _lines.values.any((line) => line.nodeAId == srcId && line.nodeBId == destId);

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
    _refreshSimulation();
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
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 8),

              ListTile(
                title: Text('Batch Simulator', style: GoogleFonts.courierPrime()),
                onTap: () {
                  Navigator.pop(context);
                  _openBatchSimulatorDialog();
                },
              ),

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

              SwitchListTile(
                title: const Text('String Simulator'),
                subtitle: const Text('Show/hide the simulator panel.'),
                value: _showSimulator,
                onChanged: (value) {
                  setState(() {
                    _showSimulator = value;
                  });
                },
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Export'),
                subtitle: const Text('Copy graph to clipboard'),
                onTap: () {
                  Navigator.of(context).pop(); // close drawer
                  _showExportDialog();
                },
              ),

              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Import'),
                subtitle: const Text('Load graph from clipboard or text input'),
                onTap: () {
                  Navigator.of(context).pop(); // close drawer
                  _showImportDialog();
                },
              ),

              const Divider(),

              const SizedBox(height: 8),

              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Export History'),
                subtitle: const Text('View saved exports'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showExportHistory();
                },
              ),

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

          const SizedBox(height: 12),

          FloatingActionButton.small(
            heroTag: 'toggleSim',
            tooltip: _showSimulator ? 'Hide simulator' : 'Show simulator',
            backgroundColor: _showSimulator ? Colors.purple.shade100 : null,
            onPressed: () {
              setState(() {
                _showSimulator = !_showSimulator;
              });
            },
            child: const Icon(Icons.science, size: 20),
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

            if (_placingStartArrow) {
              final tappedNode = _nodeAt(details.localPosition);

              if (tappedNode != null) {
                setState(() {
                  _startArrow = StartArrowData(nodeId: tappedNode.id);

                  _refreshSimulation();

                  _placingStartArrow = false;
                });
              }
            }
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
                    highlighted: _simulator.step == -1 && _simulator.tokens.isNotEmpty,

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
                      highlighted: _simActiveLines.contains(line.id),
                      onLabelChanged: (text) {
                        setState(() {
                          line.label = text;
                          _refreshSimulation();
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

              // ═══════════════════════════════════════════════════
              // STRING SIMULATION OVERLAY (top-left)
              // ═══════════════════════════════════════════════════
              if (_showSimulator)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withOpacity(0.96),
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: StatefulBuilder(
                        builder: (ctx, setPanel) {
                          void rebuild() {
                            setState(() => _simRebuild());
                            setPanel(() {});
                          }

                          String stepLabel() {
                            if (_simulator.tokens.isEmpty) return '—';
                            if (_simulator.step < 0) return 'start';
                            return '${_simulator.step} / ${_simulator.tokens.length}';
                          }

                          Widget statusBox() {
                            IconData icon;
                            Color color;
                            final atEnd = _simulator.step == _simulator.tokens.length && _simulator.tokens.isNotEmpty;
                            if (!atEnd || _simulator.states.isEmpty) {
                              icon = Icons.question_mark;
                              color = Colors.grey.shade400;
                            } else {
                              final r = _simulator.finalResult();
                              if (r == SimResult.accept) {
                                icon = Icons.check;
                                color = Colors.green;
                              } else if (r == SimResult.reject) {
                                icon = Icons.close;
                                color = Colors.red;
                              } else {
                                icon = Icons.question_mark;
                                color = Colors.orange;
                              }
                            }
                            return Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black54, width: 1.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(icon, color: color, size: 20),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'String Simulation',
                                    style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => setState(() => _showSimulator = false),
                                    child: const Icon(Icons.close, size: 16, color: Colors.black54),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              TextField(
                                controller: _simController,
                                style: GoogleFonts.courierPrime(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Enter input string…',
                                  hintStyle: GoogleFonts.courierPrime(fontSize: 12, color: Colors.black38),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  suffixIcon: _simController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () {
                                            _simController.clear();
                                            setState(() {
                                              _simulator.tokens = [];
                                              _simulator.step = -1;
                                              _simulator.states.clear();
                                              _simulator.usedLines.clear();
                                            });
                                            setPanel(() {});
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (v) {
                                  rebuild();
                                  setState(() => _simulator.step = -1);
                                  setPanel(() {});
                                },
                              ),

                              const SizedBox(height: 6),

                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.skip_previous, size: 20),
                                    tooltip: 'Go to start',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    onPressed: _simulator.tokens.isEmpty
                                        ? null
                                        : () {
                                            setState(() => _simulator.step = -1);
                                            setPanel(() {});
                                          },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left, size: 20),
                                    tooltip: 'Step back',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    onPressed: (_simulator.step <= -1 || _simulator.tokens.isEmpty)
                                        ? null
                                        : () {
                                            setState(() => _simulator.step--);
                                            setPanel(() {});
                                          },
                                  ),
                                  const Spacer(),
                                  statusBox(),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right, size: 20),
                                    tooltip: 'Step forward',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    onPressed: (_simulator.tokens.isEmpty || _simulator.step >= _simulator.tokens.length)
                                        ? null
                                        : () {
                                            setState(() {
                                              _simulator.step++;

                                              // If the newly displayed state contains
                                              // a halt accept node, next frame becomes final.
                                              if (_simulator.step < _simulator.states.length) {
                                                final states = _simulator.states[_simulator.step];

                                                bool hasHaltAccept = false;

                                                for (final nid in states) {
                                                  final node = _nodes[nid];

                                                  if (node?.isHaltAccept == true) {
                                                    hasHaltAccept = true;
                                                    break;
                                                  }
                                                }

                                                if (hasHaltAccept) {
                                                  _simulator.step = _simulator.tokens.length;
                                                }
                                              }
                                            });

                                            setPanel(() {});
                                          },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.skip_next, size: 20),
                                    tooltip: 'Go to end',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    onPressed: (_simulator.tokens.isEmpty || _simulator.step == _simulator.tokens.length)
                                        ? null
                                        : () {
                                            setState(() => _simulator.step = _simulator.tokens.length);
                                            setPanel(() {});
                                          },
                                  ),
                                ],
                              ),

                              Center(
                                child: Text(
                                  stepLabel(),
                                  style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black54),
                                ),
                              ),

                              if (_simulator.tokens.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: List.generate(_simulator.tokens.length, (i) {
                                      final consumed = _simulator.step > i;
                                      final current = _simulator.step == i;
                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: current
                                              ? Colors.lightBlueAccent.withOpacity(0.4)
                                              : consumed
                                              ? Colors.grey.shade200
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: current ? Colors.lightBlueAccent : Colors.black26,
                                            width: current ? 2 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _simulator.tokens[i],
                                          style: GoogleFonts.courierPrime(
                                            fontSize: 12,
                                            color: consumed ? Colors.black38 : Colors.black,
                                            fontWeight: current ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
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
                  highlighted: _simActiveNodes.contains(node.id),

                  isLabelTaken: _isLabelTaken,

                  onLabelChanged: (text) {
                    setState(() {
                      node.label = text;
                      _refreshSimulation();
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
                    _refreshSimulation();
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

class SavedExport {
  String name;
  String dsl;

  SavedExport({required this.name, required this.dsl});
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
