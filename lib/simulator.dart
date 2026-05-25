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

// ─────────────────────────────────────────────────────────────────────────────
// Automata Simulator
// ─────────────────────────────────────────────────────────────────────────────

class AutomataSimulator {
  AutomataSimulator({
    required this.nodes,
    required this.lines,
  }) {
    _buildAdjacency();
  }

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  late final Map<String, List<LineData>> outgoing;

  // ───────────────────────────────────────────────────────────────────────────
  // Simulation State
  // ───────────────────────────────────────────────────────────────────────────

  List<String> tokens = [];

  final List<Set<String>> states = [];

  final List<Set<String>> usedLines = [];

  int step = -1;

  // ───────────────────────────────────────────────────────────────────────────
  // Public Getters
  // ───────────────────────────────────────────────────────────────────────────

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

  // ───────────────────────────────────────────────────────────────────────────
  // Public API
  // ───────────────────────────────────────────────────────────────────────────

  void rebuild(
    String input, {
    StartArrowData? startArrow,
  }) {
    tokens = _tokenize(input);
    _build(startArrow: startArrow);

    if (step > tokens.length) {
      step = tokens.length;
    }
  }

  void rebuildGraph({
    StartArrowData? startArrow,
  }) {
    _buildAdjacency();
    _build(startArrow: startArrow);

    if (step > tokens.length) {
      step = tokens.length;
    }
  }

  SimResult finalResult() {
    if (states.isEmpty) {
      return SimResult.reject;
    }

    final finalStates = states.last;

    if (finalStates.isEmpty) {
      return SimResult.reject;
    }

    // Halt-accept anywhere immediately wins.
    for (final s in states) {
      for (final nid in s) {
        final node = nodes[nid];

        if (node?.isHaltAccept == true) {
          return SimResult.accept;
        }
      }
    }

    bool anyAccept = false;
    bool anyReject = false;

    for (final nid in finalStates) {
      final node = nodes[nid];

      if (node == null) continue;

      if (node.isHaltAccept) {
        return SimResult.accept;
      }

      if (node.isHaltReject) {
        return SimResult.reject;
      }

      if (node.isAccept) {
        anyAccept = true;
      } else {
        anyReject = true;
      }
    }

    if (anyAccept && anyReject) {
      return SimResult.mixed;
    }

    return anyAccept
        ? SimResult.accept
        : SimResult.reject;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Adjacency
  // ───────────────────────────────────────────────────────────────────────────

  void _buildAdjacency() {
    outgoing = {};

    for (final line in lines.values) {
      outgoing.putIfAbsent(
        line.nodeAId,
        () => [],
      ).add(line);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Tokenization
  // ───────────────────────────────────────────────────────────────────────────

  List<String> _tokenize(String input) {
    final result = <String>[];

    int i = 0;

    while (i < input.length) {
      if (input[i].trim().isEmpty) {
        i++;
        continue;
      }

      // [[COMMAND]]
      if (
          i + 1 < input.length &&
          input[i] == '[' &&
          input[i + 1] == '['
      ) {
        final close = input.indexOf(']]', i + 2);

        if (close >= 0) {
          final raw = input.substring(i, close + 2);

          result.add(_resolveCommand(raw));

          i = close + 2;
          continue;
        }
      }

      // "quoted token"
      if (input[i] == '"') {
        final close = input.indexOf('"', i + 1);

        if (close >= 0) {
          result.add(
            input.substring(i + 1, close),
          );

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

    if (
        !trimmed.startsWith('[[') ||
        !trimmed.endsWith(']]')
    ) {
      return token;
    }

    final inner = trimmed
        .substring(2, trimmed.length - 2)
        .trim()
        .toUpperCase();

    return kTokenReplacements[inner] ?? token;
  }

  String _normalize(String token) {
    return _resolveCommand(token.trim());
  }

  bool _isNullToken(String token) {
    return _normalize(token) == '∅';
  }

  bool _isEpsilonLabel(
    String label,
    bool atEnd,
    bool nullExplicit,
  ) {
    final n = _normalize(label);

    if (n.isEmpty || n == '~') {
      return true;
    }

    if (n == '∅') {
      return atEnd && !nullExplicit;
    }

    return false;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Epsilon Closure
  // ───────────────────────────────────────────────────────────────────────────

  (
    Set<String>,
    Set<String>,
  ) _epsilonClosure(
    Set<String> start,
    bool atEnd,
    bool nullExplicit,
  ) {
    final visited = <String>{...start};

    final used = <String>{};

    final queue = <({
      String nodeId,
      bool usedNull,
    })>[
      for (final n in start)
        (
          nodeId: n,
          usedNull: false,
        ),
    ];

    final seen = <String>{};

    while (queue.isNotEmpty) {
      final cur = queue.removeLast();

      final key = '${cur.nodeId}:${cur.usedNull}';

      if (!seen.add(key)) {
        continue;
      }

      final node = nodes[cur.nodeId];

      if (node == null) continue;

      if (
          node.isHaltAccept ||
          node.isHaltReject
      ) {
        continue;
      }

      for (final line in outgoing[cur.nodeId] ?? const <LineData>[]) {
        bool normalEps = false;
        bool nullJump = false;

        final alts = line.label
            .split(RegExp(r'[,\n]'))
            .map((s) => s.trim());

        for (final alt in alts) {
          final n = _normalize(alt);

          if (n.isEmpty || n == '~') {
            normalEps = true;
          }

          if (
              n == '∅' &&
              atEnd &&
              !nullExplicit
          ) {
            nullJump = true;
          }
        }

        if (cur.usedNull) {
          continue;
        }

        if (!normalEps && !nullJump) {
          continue;
        }

        used.add(line.id);

        visited.add(line.nodeBId);

        queue.add((
          nodeId: line.nodeBId,
          usedNull: nullJump,
        ));
      }
    }

    return (visited, used);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build Simulation
  // ───────────────────────────────────────────────────────────────────────────

  void _build({
    StartArrowData? startArrow,
  }) {
    final nullExplicit = tokens.any(_isNullToken);

    states.clear();
    usedLines.clear();

    if (
        startArrow == null ||
        !nodes.containsKey(startArrow.nodeId)
    ) {
      states.add({});
      usedLines.add({});
      return;
    }

    final startNode = startArrow.nodeId;

    final (
      initialClosure,
      initialLines,
    ) = _epsilonClosure(
      {startNode},
      tokens.isEmpty,
      nullExplicit,
    );

    Set<String> current = initialClosure;

    states.add({...current});
    usedLines.add({...initialLines});

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];

      final isLast = i == tokens.length - 1;

      final nextNodes = <String>{};

      final nextLines = <String>{};

      for (final nodeId in current) {
        final node = nodes[nodeId];

        if (node == null) {
          continue;
        }

        if (node.isHaltReject) {
          continue;
        }

        if (node.isHaltAccept) {
          states.add({nodeId});
          usedLines.add({...nextLines});
          step = tokens.length;
          return;
        }

        for (final line in outgoing[nodeId] ?? const <LineData>[]) {
          final alts = line.label
              .split(RegExp(r'[,\n]'))
              .map((s) => s.trim());

          for (final alt in alts) {
            if (
                _isEpsilonLabel(
                  alt,
                  false,
                  nullExplicit,
                )
            ) {
              continue;
            }

            if (
                _normalize(alt) ==
                _normalize(token)
            ) {
              nextNodes.add(line.nodeBId);
              nextLines.add(line.id);
              break;
            }
          }
        }
      }

      final (
        closure,
        closureLines,
      ) = _epsilonClosure(
        nextNodes,
        isLast,
        nullExplicit,
      );

      current = closure;

      states.add({...current});

      usedLines.add({
        ...nextLines,
        ...closureLines,
      });

      if (current.isEmpty) {
        break;
      }
    }
  }
}