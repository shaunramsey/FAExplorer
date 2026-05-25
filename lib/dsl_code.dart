import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  GraphState  (plain data bag passed in / returned)
// ─────────────────────────────────────────────────────────────────────────────

class GraphState {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;
  final int nodeCounter;
  final int lineCounter;

  const GraphState({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.nodeCounter,
    required this.lineCounter,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  DslCodec
// ─────────────────────────────────────────────────────────────────────────────

class DslCodec {
  const DslCodec._();

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _escapeDsl(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');

  static String _unescapeDsl(String text) =>
      text.replaceAll(r'\n', '\n').replaceAll(r'\\', r'\');

  // Node ref: prefer label, fall back to id, use id(label) for duplicates.
  static String _nodeRef(NodeData node, Map<String, NodeData> nodes) {
    final label = node.label.trim();
    if (label.isEmpty) return node.id;
    final dups = nodes.values.where((n) => n.label.trim() == label).length;
    if (dups <= 1) return _escapeDsl(label);
    return '${node.id}(${_escapeDsl(label)})';
  }

  static String _lineRef(LineData line, Map<String, LineData> lines) {
    final label = line.label.trim();
    if (label.isEmpty) return line.id;
    final dups = lines.values.where((l) => l.label.trim() == label).length;
    if (dups <= 1) return _escapeDsl(label);
    return '${line.id}(${_escapeDsl(label)})';
  }

  static String _numberToAlphaLabel(int index) {
    index += 1;
    String result = '';
    while (index > 0) {
      index--;
      result = String.fromCharCode(65 + (index % 26)) + result;
      index ~/= 26;
    }
    return result;
  }

  static Offset _defaultPosition(int count) {
    if (count == 0) return const Offset(300, 300);
    int ring = 0, capacity = 0, ringSize = 7;
    while (capacity + ringSize <= count) {
      capacity += ringSize;
      ring++;
      ringSize += 6;
    }
    final pos = count - capacity;
    final angle = (2 * pi * pos) / ringSize - pi / 2;
    final radius = 180.0 * (ring + 1);
    return Offset(300 + cos(angle) * radius, 300 + sin(angle) * radius);
  }

  // ── DSL EXPORT ─────────────────────────────────────────────────────────────

  static String exportToDsl(GraphState g) {
    final out = <String>[];

    // Node definitions
    for (final n in g.nodes.values) {
      final num = int.tryParse(n.id.substring(1)) ?? 0;
      final rawLabel = n.label.trim().isEmpty ? _numberToAlphaLabel(num) : n.label;
      String label = _escapeDsl(rawLabel);
      if (n.isHaltAccept) label = '<<$label>>';
      else if (n.isHaltReject) label = '>>$label<<';
      out.add('${n.id} = $label');
    }
    if (g.nodes.isNotEmpty) out.add('');

    // Positions
    bool wrote = false;
    for (final n in g.nodes.values) {
      out.add('${_nodeRef(n, g.nodes)} = (${n.position.dx.toStringAsFixed(1)}, ${n.position.dy.toStringAsFixed(1)})');
      wrote = true;
    }
    if (wrote) out.add('');

    // Accept states
    wrote = false;
    for (final n in g.nodes.values) {
      if (!n.isAccept) continue;
      out.add('${_nodeRef(n, g.nodes)} is accepted');
      wrote = true;
    }
    if (wrote) out.add('');

    // Transitions
    wrote = false;
    for (final l in g.lines.values) {
      final a = g.nodes[l.nodeAId], b = g.nodes[l.nodeBId];
      if (a == null || b == null) continue;
      final ra = _nodeRef(a, g.nodes), rb = _nodeRef(b, g.nodes);
      out.add(l.label.trim().isEmpty ? '$ra to $rb' : '$ra to $rb = ${_escapeDsl(l.label)}');
      wrote = true;
    }
    if (wrote) out.add('');

    // Curves
    wrote = false;
    for (final l in g.lines.values) {
      if (l.perpendicularPart.abs() <= 0.5) continue;
      out.add('${_lineRef(l, g.lines)} curve = ${l.perpendicularPart.toStringAsFixed(1)}');
      wrote = true;
    }
    if (wrote) out.add('');

    // Self-loop angles
    wrote = false;
    for (final l in g.lines.values) {
      if (l.nodeAId != l.nodeBId) continue;
      out.add('${_lineRef(l, g.lines)} loop angle = ${l.selfLoopAngle.toStringAsFixed(4)}');
      wrote = true;
    }
    if (wrote) out.add('');

    // Start arrow
    if (g.startArrow != null) {
      final node = g.nodes[g.startArrow!.nodeId];
      if (node != null) {
        final ref = _nodeRef(node, g.nodes);
        final sa = g.startArrow!;
        out.add(sa.label.trim().isEmpty ? 'to $ref' : 'to $ref = ${_escapeDsl(sa.label)}');
        if ((sa.length - 100).abs() > 0.5) out.add('to $ref length = ${sa.length.toStringAsFixed(1)}');
        final dir = sa.direction();
        out.add('to $ref angle = ${dir.dx.toStringAsFixed(4)}, ${dir.dy.toStringAsFixed(4)}');
      }
    }

    return out.join('\n').trimRight();
  }

  // ── DSL IMPORT ─────────────────────────────────────────────────────────────

  /// Returns a [GraphState] on success, or throws a descriptive [Exception].
  static GraphState importFromDsl(String src) {
    final newNodes = <String, NodeData>{};
    final labelToId = <String, String>{};
    final newLines = <String, LineData>{};
    final lineLabelToId = <String, String>{};
    StartArrowData? newStartArrow;
    int nodeCounter = 0, lineCounter = 0;

    String? idForLabel(String lbl) {
      lbl = _unescapeDsl(lbl.trim());
      final explicit = RegExp(r'^(n\d+)\((.*)\)$').firstMatch(lbl);
      if (explicit != null) return explicit.group(1);
      if (newNodes.containsKey(lbl)) return lbl;
      return labelToId[lbl];
    }

    String ensureNode(String lbl) {
      lbl = _unescapeDsl(lbl);
      bool haltAccept = false, haltReject = false;
      if (lbl.startsWith('<<') && lbl.endsWith('>>')) {
        haltAccept = true; lbl = lbl.substring(2, lbl.length - 2);
      } else if (lbl.startsWith('>>') && lbl.endsWith('<<')) {
        haltReject = true; lbl = lbl.substring(2, lbl.length - 2);
      }
      final existing = idForLabel(lbl);
      if (existing != null) {
        newNodes[existing]!.isHaltAccept = haltAccept;
        newNodes[existing]!.isHaltReject = haltReject;
        return existing;
      }
      final id = 'n${nodeCounter++}';
      final node = NodeData(
        id: id,
        position: _defaultPosition(newNodes.length),
        label: lbl,
        isHaltAccept: haltAccept,
        isHaltReject: haltReject,
      );
      newNodes[id] = node;
      labelToId[lbl] = id;
      return id;
    }

    for (var rawLine in src.split('\n')) {
      final ci = rawLine.indexOf('#');
      if (ci >= 0) rawLine = rawLine.substring(0, ci);
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // ── to <node> [length/angle/=label] ──────────────────────────────────
      if (line.toLowerCase().startsWith('to ')) {
        final rest = line.substring(3).trim();

        final lengthMatch = RegExp(r'^(.+?)\s+length\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(rest);
        if (lengthMatch != null) {
          final nid = ensureNode(_unescapeDsl(lengthMatch.group(1)!.trim()));
          final len = double.parse(lengthMatch.group(2)!);
          newStartArrow ??= StartArrowData(nodeId: nid);
          newStartArrow = (newStartArrow!.nodeId != nid)
              ? StartArrowData(nodeId: nid, length: len, label: newStartArrow!.label)
              : StartArrowData(nodeId: nid, offset: newStartArrow!.offset, length: len, label: newStartArrow!.label);
          continue;
        }

        final angleMatch = RegExp(r'^(.+?)\s+angle\s*=\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(rest);
        if (angleMatch != null) {
          final nid = ensureNode(_unescapeDsl(angleMatch.group(1)!.trim()));
          final dx = double.parse(angleMatch.group(2)!);
          final dy = double.parse(angleMatch.group(3)!);
          newStartArrow ??= StartArrowData(nodeId: nid);
          newStartArrow = StartArrowData(nodeId: nid, offset: Offset(dx, dy), length: newStartArrow!.length, label: newStartArrow!.label);
          continue;
        }

        final eq = rest.indexOf('=');
        if (eq >= 0) {
          final nid = ensureNode(_unescapeDsl(rest.substring(0, eq).trim()));
          newStartArrow = StartArrowData(nodeId: nid, label: _unescapeDsl(rest.substring(eq + 1).trim()));
        } else {
          newStartArrow = StartArrowData(nodeId: ensureNode(_unescapeDsl(rest)));
        }
        continue;
      }

      // ── <line> curve = N ──────────────────────────────────────────────────
      final curveMatch = RegExp(r'^(.+?)\s+curve\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(line);
      if (curveMatch != null) {
        final lid = _resolveLineRef(_unescapeDsl(curveMatch.group(1)!.trim()), newLines, lineLabelToId);
        if (lid != null) newLines[lid]!.perpendicularPart = double.parse(curveMatch.group(2)!);
        continue;
      }

      // ── <line> loop angle = N ─────────────────────────────────────────────
      final loopMatch = RegExp(r'^(.+?)\s+loop\s+angle\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(line);
      if (loopMatch != null) {
        final lid = _resolveLineRef(_unescapeDsl(loopMatch.group(1)!.trim()), newLines, lineLabelToId);
        if (lid != null) newLines[lid]!.selfLoopAngle = double.parse(loopMatch.group(2)!);
        continue;
      }

      // ── <node> is accepted ────────────────────────────────────────────────
      final acceptMatch = RegExp(r'^(.+?)\s+is\s+accepted$', caseSensitive: false).firstMatch(line);
      if (acceptMatch != null) {
        final lbl = _unescapeDsl(acceptMatch.group(1)!.trim());
        newNodes[idForLabel(lbl) ?? ensureNode(lbl)]!.isAccept = true;
        continue;
      }

      // ── <nodeA> to <nodeB> [= label] ──────────────────────────────────────
      final toIdx = _findToSeparator(line);
      if (toIdx >= 0) {
        final leftPart = _unescapeDsl(line.substring(0, toIdx).trim());
        final rightPart = line.substring(toIdx + 4).trim();
        String lineLabel = '', nodeBLabel = rightPart;
        final eq = rightPart.indexOf('=');
        if (eq >= 0) {
          nodeBLabel = _unescapeDsl(rightPart.substring(0, eq).trim());
          lineLabel = _unescapeDsl(rightPart.substring(eq + 1).trim());
        }
        final idA = ensureNode(leftPart), idB = ensureNode(nodeBLabel);
        final lid = 'l${lineCounter++}';
        newLines[lid] = LineData(id: lid, nodeAId: idA, nodeBId: idB, label: lineLabel);
        newNodes[idA]!.connectedLineIds.add(lid);
        newNodes[idB]!.connectedLineIds.add(lid);
        if (lineLabel.isNotEmpty) lineLabelToId[lineLabel] = lid;
        continue;
      }

      // ── label = (x, y) ───────────────────────────────────────────────────
      final posMatch = RegExp(r'^(.+?)\s*=\s*\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)$').firstMatch(line);
      if (posMatch != null) {
        final lbl = _unescapeDsl(posMatch.group(1)!.trim());
        final nid = idForLabel(lbl) ?? ensureNode(lbl);
        newNodes[nid]!.position = Offset(double.parse(posMatch.group(2)!), double.parse(posMatch.group(3)!));
        continue;
      }

      // ── nN = label ───────────────────────────────────────────────────────
      final nodeDefMatch = RegExp(r'^(n\d+)\s*=\s*(.*)$').firstMatch(line);
      if (nodeDefMatch != null) {
        final id = nodeDefMatch.group(1)!;
        final lbl = _unescapeDsl(nodeDefMatch.group(2)!.trim());
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        if (!newNodes.containsKey(id)) {
          newNodes[id] = NodeData(id: id, position: _defaultPosition(newNodes.length), label: lbl);
        } else {
          newNodes[id]!.label = lbl;
        }
        if (lbl.isNotEmpty) labelToId[lbl] = id;
        continue;
      }

      // ── bare label → create node ─────────────────────────────────────────
      ensureNode(_unescapeDsl(line));
    }

    return GraphState(
      nodes: newNodes,
      lines: newLines,
      startArrow: newStartArrow,
      nodeCounter: nodeCounter,
      lineCounter: lineCounter,
    );
  }

  // ── SVG IMPORT ─────────────────────────────────────────────────────────────

  static GraphState importFromSvg(String svg) {
    final scriptMatch = RegExp(
      r'<script[^>]*id="automata-data"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(svg);

    if (scriptMatch == null) throw Exception('No embedded automata data found.');

    final data = jsonDecode(scriptMatch.group(1)!.trim()) as Map<String, dynamic>;
    final newNodes = <String, NodeData>{};
    final newLines = <String, LineData>{};

    for (final n in data['nodes'] as List) {
      final node = NodeData(
        id: n['id'] as String,
        position: Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble()),
        label: (n['label'] as String?) ?? '',
        isAccept: n['accept'] == true,
        isHaltAccept: n['haltAccept'] == true,
        isHaltReject: n['haltReject'] == true,
      );
      newNodes[node.id] = node;
    }

    for (final l in data['lines'] as List) {
      final line = LineData(
        id: l['id'] as String,
        nodeAId: l['a'] as String,
        nodeBId: l['b'] as String,
        label: (l['label'] as String?) ?? '',
      )
        ..perpendicularPart = (l['curve'] as num?)?.toDouble() ?? 0
        ..selfLoopAngle = (l['loopAngle'] as num?)?.toDouble() ?? 0;
      newLines[line.id] = line;
      newNodes[line.nodeAId]?.connectedLineIds.add(line.id);
      newNodes[line.nodeBId]?.connectedLineIds.add(line.id);
    }

    StartArrowData? startArrow;
    if (data['startArrow'] != null) {
      final sa = data['startArrow'] as Map<String, dynamic>;
      startArrow = StartArrowData(
        nodeId: sa['nodeId'] as String,
        offset: Offset((sa['dx'] as num).toDouble(), (sa['dy'] as num).toDouble()),
        length: (sa['length'] as num).toDouble(),
        label: (sa['label'] as String?) ?? '',
      );
    }

    int highestNode = 0, highestLine = 0;
    for (final id in newNodes.keys) highestNode = max(highestNode, (int.tryParse(id.substring(1)) ?? 0) + 1);
    for (final id in newLines.keys) highestLine = max(highestLine, (int.tryParse(id.substring(1)) ?? 0) + 1);

    return GraphState(
      nodes: newNodes,
      lines: newLines,
      startArrow: startArrow,
      nodeCounter: highestNode,
      lineCounter: highestLine,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static String? _resolveLineRef(
    String lbl,
    Map<String, LineData> lines,
    Map<String, String> labelToId,
  ) {
    final explicit = RegExp(r'^(l\d+)\((.*)\)$').firstMatch(lbl);
    if (explicit != null) return explicit.group(1);
    if (lines.containsKey(lbl)) return lbl;
    return labelToId[lbl];
  }

  static int _findToSeparator(String s) {
    for (int i = 0; i < s.length - 3; i++) {
      if (s[i] == ' ' && s.substring(i + 1, i + 3).toLowerCase() == 'to' && s[i + 3] == ' ') return i;
    }
    return -1;
  }
}