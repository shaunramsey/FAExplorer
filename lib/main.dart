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

  final List<SavedExport> _savedExports = [];

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

  String _numberToAlphabetLabel(int index) {
    index += 1;

    String result = '';

    while (index > 0) {
      index--;

      result = String.fromCharCode(65 + (index % 26)) + result;

      index ~/= 26;
    }

    return result;
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
    final lines = <String>[];

    String escapeDsl(String text) {
      return text.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');
    }

    // ─────────────────────────────────────────────
    // NODE DEFINITIONS
    // ─────────────────────────────────────────────

    for (final n in _nodes.values) {
      final displayLabel = n.label.trim().isEmpty ? _numberToAlphabetLabel(int.parse(n.id.substring(1))) : n.label;

      lines.add('${n.id} = ${escapeDsl(displayLabel)}');
    }

    if (_nodes.isNotEmpty) {
      lines.add('');
    }

    // ─────────────────────────────────────────────
    // POSITIONS
    // ─────────────────────────────────────────────

    bool wrotePos = false;

    for (final n in _nodes.values) {
      final x = n.position.dx.toStringAsFixed(1);
      final y = n.position.dy.toStringAsFixed(1);

      lines.add('${_nodeRef(n)} = ($x, $y)');

      wrotePos = true;
    }

    if (wrotePos) {
      lines.add('');
    }

    // ─────────────────────────────────────────────
    // ACCEPT STATES
    // ─────────────────────────────────────────────

    bool wroteAccept = false;

    for (final n in _nodes.values) {
      if (!n.isAccept) continue;

      lines.add('${_nodeRef(n)} is accepted');

      wroteAccept = true;
    }

    if (wroteAccept) {
      lines.add('');
    }

    // ─────────────────────────────────────────────
    // TRANSITIONS
    // ─────────────────────────────────────────────

    bool wroteLines = false;

    for (final l in _lines.values) {
      final nodeA = _nodes[l.nodeAId];
      final nodeB = _nodes[l.nodeBId];

      if (nodeA == null || nodeB == null) continue;

      final refA = _nodeRef(nodeA);
      final refB = _nodeRef(nodeB);

      if (l.label.trim().isEmpty) {
        lines.add('$refA to $refB');
      } else {
        lines.add('$refA to $refB = ${escapeDsl(l.label)}');
      }

      wroteLines = true;
    }

    if (wroteLines) {
      lines.add('');
    }

    // ─────────────────────────────────────────────
    // CURVES
    // ─────────────────────────────────────────────

    bool wroteCurves = false;

    for (final l in _lines.values) {
      if (l.perpendicularPart.abs() <= 0.5) continue;

      final curveRef = _lineRef(l);

      lines.add('$curveRef curve = ${l.perpendicularPart.toStringAsFixed(1)}');

      wroteCurves = true;
    }

    if (wroteCurves) {
      lines.add('');
    }

    // ─────────────────────────────────────────────
    // START ARROW
    // ─────────────────────────────────────────────

    if (_startArrow != null) {
      final node = _nodes[_startArrow!.nodeId];

      if (node != null) {
        final ref = _nodeRef(node);

        if (_startArrow!.label.trim().isEmpty) {
          lines.add('to $ref');
        } else {
          lines.add('to $ref = ${escapeDsl(_startArrow!.label)}');
        }

        if ((_startArrow!.length - 100).abs() > 0.5) {
          lines.add('to $ref length = ${_startArrow!.length.toStringAsFixed(1)}');
        }

        final dir = _startArrow!.direction();

        lines.add('to $ref angle = ${dir.dx.toStringAsFixed(4)}, ${dir.dy.toStringAsFixed(4)}');
      }
    }

    return lines.join('\n').trimRight();
  }

  // ═══════════════════════════════════════════════════════════════
  // NODE REFERENCES
  // ═══════════════════════════════════════════════════════════════

  String _nodeRef(NodeData node) {
    String escapeDsl(String text) {
      return text.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');
    }

    final label = node.label.trim();

    if (label.isEmpty) {
      return node.id;
    }

    final duplicateCount = _nodes.values.where((n) => n.label.trim() == label).length;

    // Unique label → just use label
    if (duplicateCount <= 1) {
      return escapeDsl(label);
    }

    // Duplicate label → use id(label)
    return '${node.id}(${escapeDsl(label)})';
  }

  // ═══════════════════════════════════════════════════════════════
  // LINE REFERENCES
  // ═══════════════════════════════════════════════════════════════

  String _lineRef(LineData line) {
    String escapeDsl(String text) {
      return text.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');
    }

    final label = line.label.trim();

    if (label.isEmpty) {
      return line.id;
    }

    final duplicateCount = _lines.values.where((l) => l.label.trim() == label).length;

    if (duplicateCount <= 1) {
      return escapeDsl(label);
    }

    return '${line.id}(${escapeDsl(label)})';
  }

  Offset _defaultPosition(int index) {
    if (index == 0) return const Offset(300, 300);
    // Spiral outward: rings of 6, 12, 18 …
    int ring = 0;
    int capacity = 0;
    int ringSize = 7;
    while (capacity + ringSize <= index) {
      capacity += ringSize;
      ring++;
      ringSize += 6;
    }
    final posInRing = index - capacity;
    final total = ringSize;
    final angle = (2 * pi * posInRing) / total - pi / 2;
    final radius = 180.0 * (ring + 1);
    return Offset(300 + cos(angle) * radius, 300 + sin(angle) * radius);
  }

  String? _importFromDsl(String src) {
    try {
      final newNodes = <String, NodeData>{};
      final labelToId = <String, String>{};
      final newLines = <String, LineData>{};
      final lineLabelToId = <String, String>{};

      StartArrowData? newStartArrow;

      int nodeCounter = 0;
      int lineCounter = 0;

      // Unescapes exported multiline text.
      String unescapeDsl(String text) {
        return text.replaceAll(r'\n', '\n').replaceAll(r'\\', r'\');
      }

      String? idForLabel(String lbl) {
        lbl = unescapeDsl(lbl.trim());

        // n0(Label)
        final explicitRef = RegExp(r'^(n\d+)\((.*)\)$').firstMatch(lbl);

        if (explicitRef != null) {
          return explicitRef.group(1);
        }

        // direct ID
        if (newNodes.containsKey(lbl)) {
          return lbl;
        }

        // normal label
        return labelToId[lbl];
      }

      String ensureNode(String lbl) {
        lbl = unescapeDsl(lbl);

        final existing = idForLabel(lbl);

        if (existing != null) return existing;

        final id = 'n${nodeCounter++}';

        final pos = _defaultPosition(newNodes.length);

        final node = NodeData(id: id, position: pos, label: lbl);

        newNodes[id] = node;

        labelToId[lbl.trim()] = id;

        return id;
      }

      final rawLines = src.split('\n');

      for (var rawLine in rawLines) {
        final commentIdx = rawLine.indexOf('#');

        if (commentIdx >= 0) {
          rawLine = rawLine.substring(0, commentIdx);
        }

        final line = rawLine.trim();

        if (line.isEmpty) continue;

        // ── start arrow: "to label …" ─────────────────────────
        if (line.toLowerCase().startsWith('to ')) {
          final rest = line.substring(3).trim();

          final lengthRe = RegExp(r'^(.+?)\s+length\s*=\s*(-?[\d.]+)$', caseSensitive: false);

          final lengthMatch = lengthRe.firstMatch(rest);

          if (lengthMatch != null) {
            final nodeLabel = unescapeDsl(lengthMatch.group(1)!.trim());

            final length = double.parse(lengthMatch.group(2)!);

            final nodeId = ensureNode(nodeLabel);

            newStartArrow ??= StartArrowData(nodeId: nodeId);

            if (newStartArrow.nodeId != nodeId) {
              newStartArrow = StartArrowData(nodeId: nodeId, length: length, label: newStartArrow.label);
            } else {
              newStartArrow = StartArrowData(
                nodeId: nodeId,
                offset: newStartArrow.offset,
                length: length,
                label: newStartArrow.label,
              );
            }

            continue;
          }

          final angleRe = RegExp(r'^(.+?)\s+angle\s*=\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)$', caseSensitive: false);

          final angleMatch = angleRe.firstMatch(rest);

          if (angleMatch != null) {
            final nodeLabel = unescapeDsl(angleMatch.group(1)!.trim());

            final dx = double.parse(angleMatch.group(2)!);
            final dy = double.parse(angleMatch.group(3)!);

            final nodeId = ensureNode(nodeLabel);

            newStartArrow ??= StartArrowData(nodeId: nodeId);

            newStartArrow = StartArrowData(
              nodeId: nodeId,
              offset: Offset(dx, dy),
              length: newStartArrow.length,
              label: newStartArrow.label,
            );

            continue;
          }

          final eqIdx = rest.indexOf('=');

          if (eqIdx >= 0) {
            final nodeLabel = unescapeDsl(rest.substring(0, eqIdx).trim());

            final saLabel = unescapeDsl(rest.substring(eqIdx + 1).trim());

            final nodeId = ensureNode(nodeLabel);

            newStartArrow = StartArrowData(nodeId: nodeId, label: saLabel);
          } else {
            final nodeId = ensureNode(unescapeDsl(rest));

            newStartArrow = StartArrowData(nodeId: nodeId);
          }

          continue;
        }

        // ── "lineLabel curve = N" ─────────────────────────────
        final curveRe = RegExp(r'^(.+?)\s+curve\s*=\s*(-?[\d.]+)$', caseSensitive: false);
        final curveMatch = curveRe.firstMatch(line);

        if (curveMatch != null) {
          final lbl = unescapeDsl(curveMatch.group(1)!.trim());

          final val = double.parse(curveMatch.group(2)!);

          String? lid;

          final explicitRef = RegExp(r'^(l\d+)\((.*)\)$').firstMatch(lbl);

          if (explicitRef != null) {
            lid = explicitRef.group(1);
          } else if (newLines.containsKey(lbl)) {
            lid = lbl;
          } else {
            lid = lineLabelToId[lbl];
          }

          if (lid != null && newLines.containsKey(lid)) {
            newLines[lid]!.perpendicularPart = val;
          }

          continue;
        }

        // ── "label is accepted" ───────────────────────────────
        final acceptRe = RegExp(r'^(.+?)\s+is\s+accepted$', caseSensitive: false);

        final acceptMatch = acceptRe.firstMatch(line);

        if (acceptMatch != null) {
          final lbl = unescapeDsl(acceptMatch.group(1)!.trim());

          final nid = idForLabel(lbl) ?? ensureNode(lbl);

          newNodes[nid]!.isAccept = true;

          continue;
        }

        // ── "labelA to labelB [= lineLabel]" ─────────────────
        final toIdx = _findToSeparator(line);

        if (toIdx >= 0) {
          final leftPart = unescapeDsl(line.substring(0, toIdx).trim());

          final rightPart = line.substring(toIdx + 4).trim();

          String lineLabel = '';
          String nodeBLabel = rightPart;

          final eqIdx = rightPart.indexOf('=');

          if (eqIdx >= 0) {
            nodeBLabel = unescapeDsl(rightPart.substring(0, eqIdx).trim());

            lineLabel = unescapeDsl(rightPart.substring(eqIdx + 1).trim());
          }

          final idA = ensureNode(leftPart);
          final idB = ensureNode(nodeBLabel);

          final lid = 'l${lineCounter++}';

          final lineData = LineData(id: lid, nodeAId: idA, nodeBId: idB, label: lineLabel);

          newLines[lid] = lineData;

          newNodes[idA]!.connectedLineIds.add(lid);
          newNodes[idB]!.connectedLineIds.add(lid);

          if (lineLabel.isNotEmpty) {
            lineLabelToId[lineLabel] = lid;
          }

          continue;
        }

        // ── "label = (x, y)" ───────────────────────────────
        final posRe = RegExp(r'^(.+?)\s*=\s*\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)$');

        final posMatch = posRe.firstMatch(line);

        if (posMatch != null) {
          final lbl = unescapeDsl(posMatch.group(1)!.trim());

          final x = double.parse(posMatch.group(2)!);
          final y = double.parse(posMatch.group(3)!);

          final nid = idForLabel(lbl) ?? ensureNode(lbl);

          newNodes[nid]!.position = Offset(x, y);

          continue;
        }

        // ── "nN = label" ────────────────────────────────────
        final nodeDefRe = RegExp(r'^(n\d+)\s*=\s*(.*)$');

        final nodeDefMatch = nodeDefRe.firstMatch(line);

        if (nodeDefMatch != null) {
          final id = nodeDefMatch.group(1)!;

          final lbl = unescapeDsl(nodeDefMatch.group(2)!.trim());

          final num = int.tryParse(id.substring(1)) ?? -1;

          if (num >= nodeCounter) {
            nodeCounter = num + 1;
          }

          if (!newNodes.containsKey(id)) {
            final pos = _defaultPosition(newNodes.length);

            final node = NodeData(id: id, position: pos, label: lbl);

            newNodes[id] = node;
          } else {
            newNodes[id]!.label = lbl;
          }

          if (lbl.isNotEmpty) {
            labelToId[lbl] = id;
          }

          continue;
        }

        // ── bare "label" → create node ─────────────────────
        ensureNode(unescapeDsl(line));
      }

      setState(() {
        _nodes
          ..clear()
          ..addAll(newNodes);

        _lines
          ..clear()
          ..addAll(newLines);

        _startArrow = newStartArrow;

        _nodeCounter = nodeCounter;
        _lineCounter = lineCounter;

        _draggingNodeId = null;
        _draggingLineId = null;
        _lineSourceNodeId = null;
      });

      return null;
    } catch (e) {
      return 'Parse error: $e';
    }
  }

  /// Find the index of the first " to " that is NOT inside a word.
  /// Returns the index of the space before "to", or -1 if not found.
  int _findToSeparator(String s) {
    int i = 0;
    while (i < s.length - 3) {
      if (s[i] == ' ' && s.substring(i + 1, i + 3).toLowerCase() == 'to' && s[i + 3] == ' ') {
        return i;
      }
      i++;
    }
    return -1;
  }

  // ─────────────────────────────────────────────
  // EXPORT DIALOG
  // ─────────────────────────────────────────────

  void _showExportDialog() {
    final dsl = _exportToDsl();

    Clipboard.setData(ClipboardData(text: dsl));

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
            onPressed: () {
              setState(() {
                _savedExports.insert(0,
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
                final err = _importFromDsl(controller.text.trim());
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
