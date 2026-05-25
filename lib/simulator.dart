import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';
import 'token_replacements.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SimulationResult
// ─────────────────────────────────────────────────────────────────────────────

/// The outcome of evaluating the final step.
enum SimResult { accept, reject, mixed }

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataSimulator
// ─────────────────────────────────────────────────────────────────────────────

/// Pure NFA simulation engine.  Holds no Flutter state — call [rebuild] to
/// recompute after the graph or input string changes.
class AutomataSimulator {
  AutomataSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  // ── Public state ──────────────────────────────────────────────────────────

  List<String> tokens = [];

  /// `_simStates[i]` = set of active node IDs after consuming `i` tokens.
  /// Index 0 = initial (before any token).
  final List<Set<String>> states = [];

  /// `lines[i]` = line IDs used going from step `i-1` to step `i`.
  final List<Set<String>> usedLines = [];

  /// Current display step.  -1 = before input; 0..n = after n tokens consumed.
  int step = -1;

  // ── Derived getters ───────────────────────────────────────────────────────

  Set<String> get activeNodes {
    if (states.isEmpty) return {};
    final idx = step + 1;
    if (idx < 0 || idx >= states.length) return {};
    return states[idx];
  }

  Set<String> get activeLines {
    if (usedLines.isEmpty) return {};
    final idx = step + 1;
    if (idx < 0 || idx >= usedLines.length) return {};
    return usedLines[idx];
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Re-tokenises [input] and rebuilds the full simulation.
  void rebuild(String input, {StartArrowData? startArrow}) {
    tokens = _tokenize(input);
    _build(startArrow: startArrow);
    if (step > tokens.length) step = tokens.length;
  }

  /// Recomputes with the current [tokens] (used when the graph changes but
  /// the input string has not).
  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step > tokens.length) step = tokens.length;
  }

  /// Returns 1 = accept, 0 = reject, -1 = mixed (NFA branches disagree).
  int finalResult() {
    if (states.isEmpty) return 0;
    final finalStates = states.last;
    if (finalStates.isEmpty) return 0;

    // If any historical state contains a halt-accept node → accept.
    for (final s in states) {
      for (final nid in s) {
        if (nodes[nid]?.isHaltAccept == true) return 1;
      }
    }

    bool anyAccept = false;
    bool anyReject = false;

    for (final nid in finalStates) {
      final node = nodes[nid];
      if (node == null) continue;
      if (node.isHaltAccept) return 1;
      if (node.isHaltReject) return 0;
      if (node.isAccept) {
        anyAccept = true;
      } else {
        anyReject = true;
      }
    }

    if (anyAccept && anyReject) return -1;
    return anyAccept ? 1 : 0;
  }

  // ── Tokenizer ─────────────────────────────────────────────────────────────

  List<String> _tokenize(String input) {
    final result = <String>[];
    int i = 0;

    while (i < input.length) {
      if (input[i].trim().isEmpty) { i++; continue; }

      // [[COMMAND]] token
      if (i + 1 < input.length && input[i] == '[' && input[i + 1] == '[') {
        final close = input.indexOf(']]', i + 2);
        if (close >= 0) {
          result.add(_resolveCommand(input.substring(i, close + 2)));
          i = close + 2;
          continue;
        }
      }

      // "multi character token"
      if (input[i] == '"') {
        final close = input.indexOf('"', i + 1);
        if (close >= 0) {
          result.add(input.substring(i + 1, close));
          i = close + 1;
          continue;
        }
      }

      result.add(input[i]);
      i++;
    }

    return result;
  }

  // ── Token normalisation ───────────────────────────────────────────────────

  String _resolveCommand(String token) {
    final trimmed = token.trim();
    if (!trimmed.startsWith('[[') || !trimmed.endsWith(']]')) return token;
    final inner = trimmed.substring(2, trimmed.length - 2).trim().toUpperCase();
    return kTokenReplacements[inner] ?? token;
  }

  String _normalize(String token) => _resolveCommand(token.trim());

  bool _isNullToken(String token) => _normalize(token) == '∅';

  bool _isEpsilonLabel(String label, bool atEnd, bool nullExplicit) {
    final n = _normalize(label);
    if (n.isEmpty || n == '~') return true;
    if (n == '∅') return atEnd && !nullExplicit;
    return false;
  }

  // ── Epsilon closure ───────────────────────────────────────────────────────

  (Set<String>, Set<String>) _epsilonClosure(
    Set<String> start,
    bool atEnd,
    bool nullExplicit,
  ) {
    final visited = <String>{...start};
    final used = <String>{};
    final queue = <({String nodeId, bool usedNull})>[
      for (final n in start) (nodeId: n, usedNull: false),
    ];
    final seen = <String>{};

    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      final key = '${cur.nodeId}:${cur.usedNull}';
      if (!seen.add(key)) continue;

      final node = nodes[cur.nodeId];
      if (node == null) continue;
      if (node.isHaltAccept || node.isHaltReject) continue;

      for (final line in lines.values) {
        if (line.nodeAId != cur.nodeId) continue;

        final alts = line.label.split(RegExp(r'[,\n]')).map((s) => s.trim());

        bool normalEps = false;
        bool nullJump = false;

        for (final alt in alts) {
          final n = _normalize(alt);
          if (n.isEmpty || n == '~') normalEps = true;
          if (n == '∅' && atEnd && !nullExplicit) nullJump = true;
        }

        if (cur.usedNull) continue;
        if (!normalEps && !nullJump) continue;

        used.add(line.id);
        visited.add(line.nodeBId);
        queue.add((nodeId: line.nodeBId, usedNull: nullJump));
      }
    }

    return (visited, used);
  }

  // ── Core build ────────────────────────────────────────────────────────────

  void _build({StartArrowData? startArrow}) {
    final nullExplicit = tokens.any(_isNullToken);
    states.clear();
    usedLines.clear();

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      states.add({});
      usedLines.add({});
      return;
    }

    final init = startArrow.nodeId;
    final (initClosure, initLines) = _epsilonClosure({init}, tokens.isEmpty, nullExplicit);

    Set<String> current = initClosure;
    states.add(Set.from(current));
    usedLines.add(Set.from(initLines));

    for (final token in tokens) {
      final nextNodes = <String>{};
      final nextLines = <String>{};
      final isLast = token == tokens.last;

      for (final nodeId in current) {
        final node = nodes[nodeId];
        if (node == null) continue;
        if (node.isHaltReject) continue;

        if (node.isHaltAccept) {
          // Immediately terminate the entire simulation.
          states.add({nodeId});
          usedLines.add(Set.from(nextLines));
          step = tokens.length;
          return;
        }

        for (final line in lines.values) {
          if (line.nodeAId != nodeId) continue;
          final alts = line.label.split(RegExp(r'[,\n]')).map((s) => s.trim());
          for (final alt in alts) {
            if (_isEpsilonLabel(alt, false, nullExplicit)) continue;
            if (_normalize(alt) == _normalize(token)) {
              nextNodes.add(line.nodeBId);
              nextLines.add(line.id);
              break;
            }
          }
        }
      }

      final (closure, closureLines) = _epsilonClosure(nextNodes, isLast, nullExplicit);
      current = closure;
      states.add(Set.from(current));
      usedLines.add({...nextLines, ...closureLines});

      if (current.isEmpty) break;
    }
  }
}