import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

// ─────────────────────────────────────────────────────────────────────────────
//  GraphState  (plain data bag passed in / returned)
// ─────────────────────────────────────────────────────────────────────────────

class GraphState {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;
  final int nodeCounter;
  final int lineCounter;
  final AutomataMode automataMode;

  /// Convenience getter for code that still checks the PDA flag.
  bool get pdaMode => automataMode == AutomataMode.pda;

  const GraphState({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.nodeCounter,
    required this.lineCounter,
    this.automataMode = AutomataMode.ndfa,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  DslCodec
// ─────────────────────────────────────────────────────────────────────────────

class DslCodec {
  const DslCodec._();

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _escapeDsl(String text) => text.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');

  static String _unescapeDsl(String text) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == r'\' && i + 1 < text.length) {
        final next = text[i + 1];
        if (next == 'n') {
          buffer.write('\n');
        } else {
          buffer.write(next);
        }
        i++;
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

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
    final sameLabel = lines.values.where((l) => l.label.trim() == label).toList();
    if (sameLabel.length <= 1) return _escapeDsl(label);
    // Use occurrence index (0-based) so the reference survives id re-numbering
    // on reimport.  Format: ~N(label)  where N is the rank among same-label lines.
    final rank = sameLabel.indexWhere((l) => l.id == line.id);
    return '~$rank(${_escapeDsl(label)})';
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

    if (g.automataMode == AutomataMode.pda) {
      out.add('pda mode');
      out.add('');
    } else if (g.automataMode == AutomataMode.tm) {
      out.add('tm mode');
      out.add('');
    }

    // Node definitions
    for (final n in g.nodes.values) {
      final num = int.tryParse(n.id.substring(1)) ?? 0;
      final rawLabel = n.label.trim().isEmpty ? _numberToAlphaLabel(num) : n.label;
      String label = _escapeDsl(rawLabel);
      if (n.isHaltAccept) {
        label = '<<$label>>';
      } else if (n.isHaltReject) {
        label = '>>$label<<';
      }
      out.add('${n.id} = $label');
      if (n.isBlackBox) {
        // Store DSL as human-readable escaped text (not base64) so users can
        // read and edit it directly.  Newlines become the literal \n sequence.
        // Export blackbox DSL in multi-line block format for easy editing
        final dslLines = n.blackBoxDsl.split('\n');
        out.add('${n.id} blackbox dsl {');
        for (final dslLine in dslLines) {
          out.add('  ${dslLine}');
        }
        out.add('}');
      }
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
  /// Returns a [GraphState] on success, or throws a descriptive [Exception].
  static GraphState importFromDsl(String src) {
    // Preprocess: normalize multi-line blackbox dsl blocks into single lines
    final List<String> workspaces = _preprocessBlackboxBlocks(src);
    src = workspaces[0];

    final Map<String, NodeData> newNodes = <String, NodeData>{};
    final labelToId = <String, String>{};
    final newLines = <String, LineData>{};
    // Maps label → ordered list of line ids (insertion order = occurrence rank).
    // Multiple lines may share the same label; we keep all ids so ~N(label)
    // references can be resolved correctly after a roundtrip.
    final lineLabelToIds = <String, List<String>>{};
    StartArrowData? newStartArrow;
    int nodeCounter = 0, lineCounter = 0;
    AutomataMode automataMode = AutomataMode.ndfa;

    bool looksLikePdaTransitionLabel(String lbl) {
      final s = lbl.trim();
      if (s.isEmpty) return false;
      return s.contains(',') && (s.contains('|') || s.contains('/'));
    }

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
      bool hasHaltMarker = false;
      if (lbl.startsWith('<<') && lbl.endsWith('>>')) {
        haltAccept = true;
        hasHaltMarker = true;
        lbl = lbl.substring(2, lbl.length - 2);
      } else if (lbl.startsWith('>>') && lbl.endsWith('<<')) {
        haltReject = true;
        hasHaltMarker = true;
        lbl = lbl.substring(2, lbl.length - 2);
      }
      final existing = idForLabel(lbl);
      if (existing != null) {
        if (hasHaltMarker) {
          newNodes[existing]!.applyHaltFromLabel(haltAccept: haltAccept, haltReject: haltReject);
        }
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
      if (node.isHaltState) node.isAccept = false;
      newNodes[id] = node;
      labelToId[lbl] = id;
      return id;
    }

    for (var rawLine in src.split('\n')) {
      final ci = rawLine.indexOf('#');
      if (ci >= 0) rawLine = rawLine.substring(0, ci);
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // ── pda mode [on|off] / tm mode [on|off] ─────────────────────────────
      final pdaModeMatch = RegExp(r'^pda\s+mode(?:\s+(on|off))?$', caseSensitive: false).firstMatch(line);
      if (pdaModeMatch != null) {
        final flag = pdaModeMatch.group(1)?.toLowerCase();
        if (flag != 'off') automataMode = AutomataMode.pda;
        continue;
      }
      final tmModeMatch = RegExp(r'^tm\s+mode(?:\s+(on|off))?$', caseSensitive: false).firstMatch(line);
      if (tmModeMatch != null) {
        final flag = tmModeMatch.group(1)?.toLowerCase();
        if (flag != 'off') automataMode = AutomataMode.tm;
        continue;
      }

      // ── to <node> [length/angle/=label] ──────────────────────────────────
      if (line.toLowerCase().startsWith('to ')) {
        final rest = line.substring(3).trim();

        final lengthMatch = RegExp(r'^(.+?)\s+length\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(rest);
        if (lengthMatch != null) {
          final nid = ensureNode(_unescapeDsl(lengthMatch.group(1)!.trim()));
          final len = double.parse(lengthMatch.group(2)!);
          newStartArrow ??= StartArrowData(nodeId: nid);
          newStartArrow = (newStartArrow.nodeId != nid)
              ? StartArrowData(nodeId: nid, length: len, label: newStartArrow.label)
              : StartArrowData(nodeId: nid, offset: newStartArrow.offset, length: len, label: newStartArrow.label);
          continue;
        }

        final angleMatch = RegExp(
          r'^(.+?)\s+angle\s*=\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)$',
          caseSensitive: false,
        ).firstMatch(rest);
        if (angleMatch != null) {
          final nid = ensureNode(_unescapeDsl(angleMatch.group(1)!.trim()));
          final dx = double.parse(angleMatch.group(2)!);
          final dy = double.parse(angleMatch.group(3)!);
          newStartArrow ??= StartArrowData(nodeId: nid);
          newStartArrow = StartArrowData(
            nodeId: nid,
            offset: Offset(dx, dy),
            length: newStartArrow.length,
            label: newStartArrow.label,
          );
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
        final lid = _resolveLineRef(_unescapeDsl(curveMatch.group(1)!.trim()), newLines, lineLabelToIds);
        if (lid != null) newLines[lid]!.perpendicularPart = double.parse(curveMatch.group(2)!);
        continue;
      }

      // ── <line> loop angle = N ─────────────────────────────────────────────
      final loopMatch = RegExp(r'^(.+?)\s+loop\s+angle\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(line);
      if (loopMatch != null) {
        final lid = _resolveLineRef(_unescapeDsl(loopMatch.group(1)!.trim()), newLines, lineLabelToIds);
        if (lid != null) newLines[lid]!.selfLoopAngle = double.parse(loopMatch.group(2)!);
        continue;
      }

      // ── <node> is accepted ────────────────────────────────────────────────
      final acceptMatch = RegExp(r'^(.+?)\s+is\s+accepted$', caseSensitive: false).firstMatch(line);
      if (acceptMatch != null) {
        final lbl = _unescapeDsl(acceptMatch.group(1)!.trim());
        final acceptNode = newNodes[idForLabel(lbl) ?? ensureNode(lbl)]!;
        if (acceptNode.canToggleNormalAccept) {
          acceptNode.isAccept = true;
        }
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
        if (newNodes[idA]!.canHaveOutgoingTransitions) {
          final lid = 'l${lineCounter++}';
          newLines[lid] = LineData(id: lid, nodeAId: idA, nodeBId: idB, label: lineLabel);
          newNodes[idA]!.connectedLineIds.add(lid);
          newNodes[idB]!.connectedLineIds.add(lid);
          if (lineLabel.isNotEmpty && looksLikePdaTransitionLabel(lineLabel)) {
            if (automataMode == AutomataMode.ndfa) automataMode = AutomataMode.pda;
          }
          if (lineLabel.isNotEmpty) {
            lineLabelToIds.putIfAbsent(lineLabel, () => []).add(lid);
          }
        }
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
        var lbl = _unescapeDsl(nodeDefMatch.group(2)!.trim());
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;

        bool haltAccept = false, haltReject = false;
        if (lbl.startsWith('<<') && lbl.endsWith('>>')) {
          haltAccept = true;
          lbl = lbl.substring(2, lbl.length - 2);
        } else if (lbl.startsWith('>>') && lbl.endsWith('<<')) {
          haltReject = true;
          lbl = lbl.substring(2, lbl.length - 2);
        }

        if (!newNodes.containsKey(id)) {
          final node = NodeData(
            id: id,
            position: _defaultPosition(newNodes.length),
            label: lbl,
            isHaltAccept: haltAccept,
            isHaltReject: haltReject,
          );
          if (node.isHaltState) node.isAccept = false;
          newNodes[id] = node;
        } else {
          newNodes[id]!.label = lbl;
          newNodes[id]!.applyHaltFromLabel(haltAccept: haltAccept, haltReject: haltReject);
        }
        if (lbl.isNotEmpty) labelToId[lbl] = id;
        continue;
      }

      // ── nN blackbox = description ────────────────────────────────────────
      final blackBoxDefMatch = RegExp(r'^(n\d+)\s+blackbox\s*=\s*(.*)$', caseSensitive: false).firstMatch(line);
      if (blackBoxDefMatch != null) {
        final id = blackBoxDefMatch.group(1)!;
        final desc = _unescapeDsl(blackBoxDefMatch.group(2)!.trim());
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        final node = newNodes[id] ?? NodeData(id: id, position: _defaultPosition(newNodes.length));
        node.isBlackBox = true;
        node.blackBoxDescription = desc;
        if (node.label.trim().isEmpty) {
          node.label = 'BB ${id.toUpperCase()}';
        }
        newNodes[id] = node;
        continue;
      }

      // ── nN blackbox dsl = <escaped> ──────────────────────────────────────
      // (inline single-line form — the block form is handled after this loop
      //  via the workspaces post-processing pass below)
      final blackBoxDslMatch = RegExp(r'^(n\d+)\s+blackbox\s+dsl\s*=\s*(.*)$', caseSensitive: false).firstMatch(line);
      if (blackBoxDslMatch != null) {
        final id = blackBoxDslMatch.group(1)!;
        final encoded = blackBoxDslMatch.group(2)!.trim();
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        final node = newNodes[id] ?? NodeData(id: id, position: _defaultPosition(newNodes.length));
        node.isBlackBox = true;
        node.blackBoxDsl = _decodeMaybeLegacyBase64(encoded);
        if (node.label.trim().isEmpty) {
          node.label = 'BB ${id.toUpperCase()}';
        }
        newNodes[id] = node;
        continue;
      }

      // ── bare label → create node ─────────────────────────────────────────
      ensureNode(_unescapeDsl(line));
    }

    // ── Apply blackbox DSL payloads from the preprocessed workspace entries ──
    //
    // _preprocessBlackboxBlocks() extracted every  `nN blackbox dsl { ... }`
    // block into workspaces[1], workspaces[2], … as a single escaped line of
    // the form:
    //
    //   n2 blackbox dsl = <escaped dsl content>
    //
    // The main loop above handles the inline `nN blackbox dsl = ...` form when
    // it appears literally in workspaces[0], but the block-format payloads live
    // in the extra workspace slots and were deliberately excluded from the main
    // source text.  We apply them here, after all nodes have been created.
    for (int i = 1; i < workspaces.length; i++) {
      final entry = workspaces[i].trim();
      if (entry.isEmpty) continue;

      final bbDslMatch = RegExp(
        r'^(n\d+)\s+blackbox\s+dsl\s*=\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(entry);
      if (bbDslMatch == null) continue;

      final id = bbDslMatch.group(1)!;
      final encoded = bbDslMatch.group(2)!.trim();
      final num = int.tryParse(id.substring(1)) ?? -1;
      if (num >= nodeCounter) nodeCounter = num + 1;

      // The node must already exist from the `nN blackbox = description` line
      // in the main DSL body.  Create a shell only if something went wrong.
      if (!newNodes.containsKey(id)) {
        newNodes[id] = NodeData(
          id: id,
          position: _defaultPosition(newNodes.length),
        );
      }

      final node = newNodes[id]!;
      node.isBlackBox = true;
      node.blackBoxDsl = _decodeMaybeLegacyBase64(encoded);

      if (node.label.trim().isEmpty) {
        node.label = 'BB ${id.toUpperCase()}';
      }
    }

    return GraphState(
      nodes: newNodes,
      lines: newLines,
      startArrow: newStartArrow,
      nodeCounter: nodeCounter,
      lineCounter: lineCounter,
      automataMode: automataMode,
    );
  }

  // ── SVG IMPORT ─────────────────────────────────────────────────────────────

  static GraphState importFromSvg(String svg) {
    final scriptMatch = RegExp(r'<script[^>]*id="automata-data"[^>]*>(.*?)</script>', dotAll: true).firstMatch(svg);

    if (scriptMatch == null) throw Exception('No embedded automata data found.');

    final data = jsonDecode(scriptMatch.group(1)!.trim()) as Map<String, dynamic>;
    final newNodes = <String, NodeData>{};
    final newLines = <String, LineData>{};
    AutomataMode automataMode = AutomataMode.ndfa;

    bool looksLikePdaTransitionLabel(String lbl) {
      final s = lbl.trim();
      if (s.isEmpty) return false;
      return s.contains(',') && (s.contains('|') || s.contains('/'));
    }

    for (final n in data['nodes'] as List) {
      final node = NodeData(
        id: n['id'] as String,
        position: Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble()),
        label: (n['label'] as String?) ?? '',
        isAccept: n['accept'] == true,
        isHaltAccept: n['haltAccept'] == true,
        isHaltReject: n['haltReject'] == true,
      );
      if (node.isHaltState) node.isAccept = false;
      newNodes[node.id] = node;
    }

    for (final l in data['lines'] as List) {
      final nodeAId = l['a'] as String;
      if (newNodes[nodeAId]?.canHaveOutgoingTransitions != true) continue;

      final line =
          LineData(
              id: l['id'] as String,
              nodeAId: nodeAId,
              nodeBId: l['b'] as String,
              label: (l['label'] as String?) ?? '',
            )
            ..perpendicularPart = (l['curve'] as num?)?.toDouble() ?? 0
            ..selfLoopAngle = (l['loopAngle'] as num?)?.toDouble() ?? 0;
      newLines[line.id] = line;
      newNodes[line.nodeAId]?.connectedLineIds.add(line.id);
      newNodes[line.nodeBId]?.connectedLineIds.add(line.id);

      if (line.label.isNotEmpty && looksLikePdaTransitionLabel(line.label)) {
        if (automataMode == AutomataMode.ndfa) automataMode = AutomataMode.pda;
      }
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
    for (final id in newNodes.keys) {
      highestNode = max(highestNode, (int.tryParse(id.substring(1)) ?? 0) + 1);
    }
    for (final id in newLines.keys) {
      highestLine = max(highestLine, (int.tryParse(id.substring(1)) ?? 0) + 1);
    }

    return GraphState(
      nodes: newNodes,
      lines: newLines,
      startArrow: startArrow,
      nodeCounter: highestNode,
      lineCounter: highestLine,
      automataMode: automataMode,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────
  /// Preprocesses DSL to convert multi-line blackbox blocks into single-line
  /// format for easier parsing. Converts:
  ///   n0 blackbox dsl {
  ///     n0 = A
  ///     n1 = B
  ///   }
  /// Into: n0 blackbox dsl = n0 = A\nn1 = B
  static List<String> _preprocessBlackboxBlocks(String src) {
    final returns = <String>[""];
    final lines = src.split('\n');
    final result = <String>[]; // list of lines that are the "main workspace"
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      final blockMatch = RegExp(r'^(n\d+)\s+blackbox\s+dsl\s*{\s*$', caseSensitive: false).firstMatch(line);
      if (blockMatch != null) {
        final nodeId = blockMatch.group(1)!;
        final blockLines = <String>[];
        i++;
        // Collect lines until closing brace
        while (i < lines.length) {
          final rawLine = lines[i];
          final trimmedLine = rawLine.trim();
          if (trimmedLine == '}' || trimmedLine == '} #') break;
          if (trimmedLine.isEmpty) {
            blockLines.add('');
            i++;
            continue;
          }

          String contentLine = rawLine;
          if (contentLine.startsWith('  ')) {
            contentLine = contentLine.substring(2);
          } else if (contentLine.startsWith('\t')) {
            contentLine = contentLine.substring(1);
          }
          blockLines.add(contentLine);
          i++;
        }
        // Convert back to escaped format for old parser
        final String dslContent = blockLines.join('\n');
        returns.add('$nodeId blackbox dsl = ${_escapeDsl(dslContent)}');
      } else {
        result.add(lines[i]);
      }
      i++;
    }
    returns[0] = result.join('\n');
    return returns;
  }

  /// Decodes a blackbox DSL value that may be either the new plain-escaped
  /// text format or the old base64 format (for backward compatibility).
  ///
  /// A pure base64 string only contains `[A-Za-z0-9+/=]`.  A DSL string
  /// almost always contains spaces, newline escapes (`\n`), `=` signs inside
  /// node definitions, etc.  We use that distinction as a heuristic.
  static String _decodeMaybeLegacyBase64(String encoded) {
    final isLikelyBase64 = encoded.isNotEmpty && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(encoded);
    if (isLikelyBase64) {
      try {
        return utf8.decode(base64Decode(encoded));
      } catch (_) {
        // Not valid base64 after all — fall through to plain-text decode.
      }
    }
    return _unescapeDsl(encoded);
  }

  static String? _resolveLineRef(String lbl, Map<String, LineData> lines, Map<String, List<String>> lineLabelToIds) {
    // New occurrence-index form:  ~N(label) → Nth line (0-based) with that label
    final rankMatch = RegExp(r'^~(\d+)\((.*)\)$', dotAll: true).firstMatch(lbl);
    if (rankMatch != null) {
      final rank = int.tryParse(rankMatch.group(1)!) ?? 0;
      final label = _unescapeDsl(rankMatch.group(2)!);
      final ids = lineLabelToIds[label];
      if (ids != null && rank < ids.length) return ids[rank];
      return null;
    }
    // Legacy explicit-id form:  lN(label) → kept for backward compat, use id directly
    final explicit = RegExp(r'^(l\d+)\((.*)\)$', dotAll: true).firstMatch(lbl);
    if (explicit != null) return explicit.group(1);
    if (lines.containsKey(lbl)) return lbl;
    // Accept 1-based numeric line ids in DSL (e.g. "l1") by mapping them
    // to the internal zero-based ids ("l0"). This makes the DSL friendlier
    // for users who expect 1-based numbering while keeping internal ids as-is.
    final oneBasedMatch = RegExp(r'^l(\d+)$').firstMatch(lbl);
    if (oneBasedMatch != null) {
      final num = int.tryParse(oneBasedMatch.group(1)!) ?? 0;
      if (num > 0) {
        final candidate = 'l${num - 1}';
        if (lines.containsKey(candidate)) return candidate;
      }
    }
    // Plain label lookup: use the first recorded id for this label
    final ids = lineLabelToIds[lbl];
    return ids?.isNotEmpty == true ? ids!.first : null;
  }

  static int _findToSeparator(String s) {
    for (int i = 0; i < s.length - 3; i++) {
      if (s[i] == ' ' && s.substring(i + 1, i + 3).toLowerCase() == 'to' && s[i + 3] == ' ') return i;
    }
    return -1;
  }
}