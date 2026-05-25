import 'dart:collection';

import 'models.dart';
import 'token_replacements.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Simulation Result
// ─────────────────────────────────────────────────────────────────────────────

enum SimResult {
  accept,
  reject,
  mixed,
}

// Matches original_main.dart transition-label splitting (comma, backslash, or "n").
final _transitionLabelSplitter = RegExp(r'[,\\n]');

// Matches original_main.dart epsilon-closure splitting (comma or newline).
final _epsilonLabelSplitter = RegExp(r'[,\n]');

// ─────────────────────────────────────────────────────────────────────────────
// Automata Simulator — logic ported from original_main.dart
// ─────────────────────────────────────────────────────────────────────────────

class AutomataSimulator {
  AutomataSimulator({
    required this.nodes,
    required this.lines,
  });

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  List<String> tokens = [];
  final List<Set<String>> states = [];
  final List<Set<String>> usedLines = [];

  /// -1 = before any input; 0..n = after consuming token[0..n-1]
  int step = -1;

  Set<String> get activeNodes {
    if (states.isEmpty) return {};
    final idx = step + 1;
    if (idx < 0 || idx >= states.length) return {};
    return UnmodifiableSetView(states[idx]);
  }

  Set<String> get activeLines {
    if (usedLines.isEmpty) return {};
    final idx = step + 1;
    if (idx < 0 || idx >= usedLines.length) return {};
    return UnmodifiableSetView(usedLines[idx]);
  }

  void rebuild(
    String input, {
    StartArrowData? startArrow,
  }) {
    tokens = _tokenize(input);
    _buildSimulation(startArrow: startArrow);
    if (step > tokens.length) {
      step = tokens.length;
    }
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _buildSimulation(startArrow: startArrow);
    if (step > tokens.length) {
      step = tokens.length;
    }
  }

  SimResult finalResult() {
    if (states.isEmpty) return SimResult.reject;

    final finalStates = states.last;
    if (finalStates.isEmpty) return SimResult.reject;

    for (final snapshot in states) {
      for (final nid in snapshot) {
        if (nodes[nid]?.isHaltAccept == true) {
          return SimResult.accept;
        }
      }
    }

    bool anyAccept = false;
    bool anyReject = false;

    for (final nid in finalStates) {
      final node = nodes[nid];
      if (node == null) continue;

      if (node.isHaltAccept) return SimResult.accept;
      if (node.isHaltReject) return SimResult.reject;

      if (node.isAccept) {
        anyAccept = true;
      } else {
        anyReject = true;
      }
    }

    if (anyAccept && anyReject) return SimResult.mixed;
    return anyAccept ? SimResult.accept : SimResult.reject;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Tokenization (original_main.dart)
  // ───────────────────────────────────────────────────────────────────────────

  List<String> _tokenize(String input) {
    final result = <String>[];
    int i = 0;

    while (i < input.length) {
      if (input[i].trim().isEmpty) {
        i++;
        continue;
      }

      if (i + 1 < input.length && input[i] == '[' && input[i + 1] == '[') {
        final close = input.indexOf(']]', i + 2);
        if (close >= 0) {
          result.add(_resolveCommand(input.substring(i, close + 2)));
          i = close + 2;
          continue;
        }
      }

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

  String _resolveCommand(String token) {
    final trimmed = token.trim();
    if (!trimmed.startsWith('[[') || !trimmed.endsWith(']]')) {
      return token;
    }
    final inner = trimmed.substring(2, trimmed.length - 2).trim().toUpperCase();
    return kTokenReplacements[inner] ?? token;
  }

  String _normalizeSimToken(String token) {
    return _resolveCommand(token.trim());
  }

  bool _isNullToken(String token) => _normalizeSimToken(token) == '∅';

  bool _isEpsilonLabel(String label, bool atEndOfInput, bool nullWasExplicitlyTyped) {
    final normalized = _normalizeSimToken(label);
    if (normalized.isEmpty || normalized == '~') return true;
    if (normalized == '∅') {
      return atEndOfInput && !nullWasExplicitlyTyped;
    }
    return false;
  }

  Iterable<String> _epsilonAlternatives(String label) =>
      label.split(_epsilonLabelSplitter).map((s) => s.trim());

  Iterable<String> _transitionAlternatives(String label) =>
      label.split(_transitionLabelSplitter).map((s) => s.trim());

  (Set<String>, Set<String>) _epsilonClosure(
    Set<String> startNodes,
    bool atEndOfInput,
    bool nullWasExplicitlyTyped,
  ) {
    final visitedNodes = <String>{...startNodes};
    final linesUsed = <String>{};

    final queue = <({String nodeId, bool usedNull})>[
      for (final node in startNodes) (nodeId: node, usedNull: false),
    ];
    final visitedStates = <String>{};

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final stateKey = '${current.nodeId}:${current.usedNull}';
      if (visitedStates.contains(stateKey)) continue;
      visitedStates.add(stateKey);

      final currentNode = nodes[current.nodeId];
      if (currentNode == null) continue;

      if (currentNode.isHaltAccept || currentNode.isHaltReject) {
        continue;
      }

      for (final line in lines.values) {
        if (line.nodeAId != current.nodeId) continue;

        bool isNormalEpsilon = false;
        bool isNullJump = false;

        for (final alt in _epsilonAlternatives(line.label)) {
          final normalized = _normalizeSimToken(alt);
          if (normalized.isEmpty || normalized == '~') {
            isNormalEpsilon = true;
          }
          if (normalized == '∅' && atEndOfInput && !nullWasExplicitlyTyped) {
            isNullJump = true;
          }
        }

        if (current.usedNull) continue;
        if (!isNormalEpsilon && !isNullJump) continue;

        linesUsed.add(line.id);
        visitedNodes.add(line.nodeBId);
        queue.add((nodeId: line.nodeBId, usedNull: isNullJump));
      }
    }

    return (visitedNodes, linesUsed);
  }

  void _buildSimulation({StartArrowData? startArrow}) {
    final nullWasExplicitlyTyped = tokens.any(_isNullToken);
    states.clear();
    usedLines.clear();

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      states.add({});
      usedLines.add({});
      return;
    }

    final initialNode = startArrow.nodeId;
    final (initialClosure, initialLines) = _epsilonClosure(
      {initialNode},
      tokens.isEmpty,
      nullWasExplicitlyTyped,
    );

    Set<String> current = initialClosure;
    states.add(Set.from(current));
    usedLines.add(Set.from(initialLines));

    for (final token in tokens) {
      final nextNodes = <String>{};
      final stepLines = <String>{};
      final isLastToken = token == tokens.last;

      for (final nodeId in current) {
        final currentNode = nodes[nodeId];
        if (currentNode == null) continue;

        if (currentNode.isHaltReject) continue;

        if (currentNode.isHaltAccept) {
          current = {nodeId};

          while (states.length > step + 2) {
            states.removeLast();
          }
          while (usedLines.length > step + 2) {
            usedLines.removeLast();
          }

          states.add({nodeId});
          usedLines.add(Set.from(stepLines));
          step = tokens.length;
          return;
        }

        for (final line in lines.values) {
          if (line.nodeAId != nodeId) continue;

          for (final alt in _transitionAlternatives(line.label)) {
            if (_isEpsilonLabel(alt, false, nullWasExplicitlyTyped)) {
              continue;
            }
            if (_normalizeSimToken(alt) == _normalizeSimToken(token)) {
              nextNodes.add(line.nodeBId);
              stepLines.add(line.id);
              break;
            }
          }
        }
      }

      final (closureNodes, closureLines) = _epsilonClosure(
        nextNodes,
        isLastToken,
        nullWasExplicitlyTyped,
      );

      current = closureNodes;
      states.add(Set.from(current));
      usedLines.add({...stepLines, ...closureLines});

      if (current.isEmpty) break;
    }
  }
}
