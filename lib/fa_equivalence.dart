// Decides whether two finite automata (NFAs with ~-transitions) accept exactly
// the same language, and produces a short distinguishing witness string when
// they differ.
//
// Algorithm
// ─────────
//  1. Build the ~-closure of each NFA's start state.
//  2. Run a BFS over the *product* of the two NFA's powerset constructions
//     simultaneously (standard cross-product / table-filling approach).
//     Each BFS node is a pair (S₁, S₂) where S₁ ⊆ states(NFA₁) and
//     S₂ ⊆ states(NFA₂).
//  3. At each step, collect every symbol that appears on any outgoing
//     transition from any state in the current pair, then advance each side
//     independently (NFA powerset step + ~-closure).
//  4. A distinguishing string is found when a pair (S₁, S₂) is reached where
//     exactly one side contains an accept state.
//  5. The BFS tracks the path taken so we can reconstruct the witness string.
//
// Limitations
// ───────────
//  • Only NFA (ndfa) mode is supported.  PDAs and TMs are undecidable in
//    general; the caller is expected to gate on AutomataMode.ndfa.
//  • The alphabet is inferred from the transition labels of both machines
//    combined.  ε / ~ / empty labels are treated as epsilon (not a symbol).
//  • The state-space is exponential in the worst case; a hard cap of 8 000
//    BFS nodes is applied.  If the cap is hit the result is "unknown".
//  • The null / ? transition and black-box nodes are NOT modelled here
//    (they belong to the TM / black-box layer).  Transitions whose label
//    normalises to '?' or that start from a black-box node are skipped.

import 'models.dart';
import 'pda_simulator.dart';
import 'tm_simulator.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Public result types
// ─────────────────────────────────────────────────────────────────────────────

enum EquivalenceStatus {
  equivalent,
  notEquivalent,
  unknownCapReached,
  noStartState,
}

class EquivalenceResult {
  final EquivalenceStatus status;

  /// Non-null iff [status] == [EquivalenceStatus.notEquivalent].
  /// The string accepted by exactly one of the two machines.
  /// An empty string means ε is the witness (one machine accepts ε, the
  /// other does not).
  final String? witness;

  /// Which machine accepts the witness (1 or 2), or 0 if unknown.
  final int acceptedByMachine;

  const EquivalenceResult.equivalent()
      : status = EquivalenceStatus.equivalent,
        witness = null,
        acceptedByMachine = 0;

  const EquivalenceResult.notEquivalent(String this.witness, this.acceptedByMachine)
      : status = EquivalenceStatus.notEquivalent;

  const EquivalenceResult.capReached()
      : status = EquivalenceStatus.unknownCapReached,
        witness = null,
        acceptedByMachine = 0;

  const EquivalenceResult.noStart()
      : status = EquivalenceStatus.noStartState,
        witness = null,
        acceptedByMachine = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top-level entry point
// ─────────────────────────────────────────────────────────────────────────────

EquivalenceResult checkEquivalence({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
}) {
  if (startArrow1 == null || !nodes1.containsKey(startArrow1.nodeId)) {
    return const EquivalenceResult.noStart();
  }
  if (startArrow2 == null || !nodes2.containsKey(startArrow2.nodeId)) {
    return const EquivalenceResult.noStart();
  }

  final nfa1 = _NfaAdapter(nodes: nodes1, lines: lines1);
  final nfa2 = _NfaAdapter(nodes: nodes2, lines: lines2);

  final alphabet = <String>{...nfa1.alphabet, ...nfa2.alphabet};

  // Initial powerset states after ε-closure of each start node.
  final init1 = nfa1.epsilonClosure({startArrow1.nodeId});
  final init2 = nfa2.epsilonClosure({startArrow2.nodeId});

  return _bfs(nfa1, nfa2, init1, init2, alphabet);
}

// ─────────────────────────────────────────────────────────────────────────────
//  BFS over the cross-product of the two NFAs' powerset constructions
// ─────────────────────────────────────────────────────────────────────────────

const int _kBfsCap = 8000;

EquivalenceResult _bfs(
  _NfaAdapter nfa1,
  _NfaAdapter nfa2,
  Set<String> init1,
  Set<String> init2,
  Set<String> alphabet,
) {
  // BFS node: (frozenSet1, frozenSet2, pathSoFar)
  // We encode a Set<String> as a sorted joined string for use as a map key.
  String freeze(Set<String> s) => (s.toList()..sort()).join('\x00');

  final initKey = '${freeze(init1)}|${freeze(init2)}';
  // Map from encoded pair → path of symbols taken to reach it.
  final visited = <String, List<String>>{initKey: const []};
  final queue = <({Set<String> s1, Set<String> s2, List<String> path})>[
    (s1: init1, s2: init2, path: const []),
  ];

  // Check starting pair immediately (handles ε-only acceptance).
  final initCheck = _checkAcceptance(nfa1, nfa2, init1, init2, const []);
  if (initCheck != null) return initCheck;

  while (queue.isNotEmpty) {
    if (visited.length > _kBfsCap) return const EquivalenceResult.capReached();

    final (:s1, :s2, :path) = queue.removeAt(0);

    for (final symbol in alphabet) {
      final next1 = nfa1.epsilonClosure(nfa1.step(s1, symbol));
      final next2 = nfa2.epsilonClosure(nfa2.step(s2, symbol));

      final key = '${freeze(next1)}|${freeze(next2)}';
      if (visited.containsKey(key)) continue;

      final newPath = [...path, symbol];
      visited[key] = newPath;

      final check = _checkAcceptance(nfa1, nfa2, next1, next2, newPath);
      if (check != null) return check;

      queue.add((s1: next1, s2: next2, path: newPath));
    }
  }

  return const EquivalenceResult.equivalent();
}

/// Returns a non-null [EquivalenceResult] iff [s1] and [s2] differ in
/// acceptance, otherwise null (both accept or both reject → keep searching).
EquivalenceResult? _checkAcceptance(
  _NfaAdapter nfa1,
  _NfaAdapter nfa2,
  Set<String> s1,
  Set<String> s2,
  List<String> path,
) {
  final acc1 = nfa1.anyAccepts(s1);
  final acc2 = nfa2.anyAccepts(s2);

  if (acc1 == acc2) return null;

  final witness = path.join();
  final acceptedBy = acc1 ? 1 : 2;
  return EquivalenceResult.notEquivalent(witness, acceptedBy);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Best-effort PDA/TM equivalence checking by bounded input search
// ─────────────────────────────────────────────────────────────────────────────

enum _AcceptanceOutcome { accept, reject, unknown }

EquivalenceResult checkPdaEquivalence({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
  int maxInputLength = 4,
  int maxTests = 400,
}) {
  if (startArrow1 == null || !nodes1.containsKey(startArrow1.nodeId)) {
    return const EquivalenceResult.noStart();
  }
  if (startArrow2 == null || !nodes2.containsKey(startArrow2.nodeId)) {
    return const EquivalenceResult.noStart();
  }

  final alphabet = <String>{
    ..._pdaAlphabet(lines1),
    ..._pdaAlphabet(lines2),
  };

  return _checkEquivalenceByTestingInputs(
    nodes1: nodes1,
    lines1: lines1,
    startArrow1: startArrow1,
    nodes2: nodes2,
    lines2: lines2,
    startArrow2: startArrow2,
    alphabet: alphabet,
    maxInputLength: maxInputLength,
    maxTests: maxTests,
    simulate1: (input) => _simulatePda(nodes1, lines1, startArrow1, input),
    simulate2: (input) => _simulatePda(nodes2, lines2, startArrow2, input),
  );
}

EquivalenceResult checkTmEquivalence({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
  int maxInputLength = 4,
  int maxTests = 400,
  int maxStepsPerInput = 300,
}) {
  if (startArrow1 == null || !nodes1.containsKey(startArrow1.nodeId)) {
    return const EquivalenceResult.noStart();
  }
  if (startArrow2 == null || !nodes2.containsKey(startArrow2.nodeId)) {
    return const EquivalenceResult.noStart();
  }

  final alphabet = <String>{
    ..._tmAlphabet(lines1),
    ..._tmAlphabet(lines2),
  };

  return _checkEquivalenceByTestingInputs(
    nodes1: nodes1,
    lines1: lines1,
    startArrow1: startArrow1,
    nodes2: nodes2,
    lines2: lines2,
    startArrow2: startArrow2,
    alphabet: alphabet,
    maxInputLength: maxInputLength,
    maxTests: maxTests,
    simulate1: (input) => _simulateTm(nodes1, lines1, startArrow1, input, maxStepsPerInput),
    simulate2: (input) => _simulateTm(nodes2, lines2, startArrow2, input, maxStepsPerInput),
  );
}

typedef _SimulatorFn = _AcceptanceOutcome Function(String input);

EquivalenceResult _checkEquivalenceByTestingInputs({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
  required Set<String> alphabet,
  required int maxInputLength,
  required int maxTests,
  required _SimulatorFn simulate1,
  required _SimulatorFn simulate2,
}) {
  final inputs = _generateInputCandidates(alphabet, maxInputLength, maxTests);
  for (final input in inputs) {
    final outcome1 = simulate1(input);
    final outcome2 = simulate2(input);

    if (outcome1 == _AcceptanceOutcome.unknown || outcome2 == _AcceptanceOutcome.unknown) {
      continue;
    }

    if (outcome1 != outcome2) {
      final acceptedBy = outcome1 == _AcceptanceOutcome.accept ? 1 : 2;
      return EquivalenceResult.notEquivalent(input, acceptedBy);
    }
  }

  return const EquivalenceResult.capReached();
}

_AcceptanceOutcome _simulatePda(
  Map<String, NodeData> nodes,
  Map<String, LineData> lines,
  StartArrowData? startArrow,
  String input,
) {
  final sim = PdaSimulator(nodes: nodes, lines: lines);
  sim.rebuild(input, startArrow: startArrow);
  if (sim.stackGrowthLoopDetected) return _AcceptanceOutcome.unknown;
  return sim.finalResult() == PdaSimResult.accept
      ? _AcceptanceOutcome.accept
      : _AcceptanceOutcome.reject;
}

_AcceptanceOutcome _simulateTm(
  Map<String, NodeData> nodes,
  Map<String, LineData> lines,
  StartArrowData? startArrow,
  String input,
  int maxStepsPerInput,
) {
  final sim = TmSimulator(nodes: nodes, lines: lines);
  sim.rebuild(input, startArrow: startArrow);

  for (int step = 0; step < maxStepsPerInput; step++) {
    if (sim.result != TmResult.running) break;
    if (!sim.computeNext()) break;
  }

  if (sim.result == TmResult.running) return _AcceptanceOutcome.unknown;
  return sim.result == TmResult.accept
      ? _AcceptanceOutcome.accept
      : _AcceptanceOutcome.reject;
}

Set<String> _pdaAlphabet(Map<String, LineData> lines) {
  final alphabet = <String>{};
  for (final line in lines.values) {
    for (final alt in line.label.split('\n')) {
      final t = parsePdaLabel(alt);
      if (t.read.isNotEmpty && t.read != kStackBottom) {
        alphabet.add(t.read);
      }
    }
  }
  return alphabet;
}

Set<String> _tmAlphabet(Map<String, LineData> lines) {
  final alphabet = <String>{};
  for (final line in lines.values) {
    for (final alt in line.label.split('\n')) {
      final t = parseTmLabel(alt);
      if (t.read.isNotEmpty) {
        alphabet.add(t.read);
      }
    }
  }
  return alphabet;
}

Iterable<String> _generateInputCandidates(
  Set<String> alphabet,
  int maxInputLength,
  int maxTests,
) sync* {
  yield '';
  if (alphabet.isEmpty) return;

  final symbols = alphabet.toList()..sort();
  final queue = <List<String>>[];
  for (final symbol in symbols) {
    queue.add([symbol]);
  }

  while (queue.isNotEmpty && maxTests > 1) {
    final tokenSeq = queue.removeAt(0);
    yield _encodeInputTokens(tokenSeq);
    maxTests--;
    if (tokenSeq.length < maxInputLength) {
      for (final symbol in symbols) {
        queue.add([...tokenSeq, symbol]);
      }
    }
  }
}

String _encodeInputTokens(List<String> tokens) {
  if (tokens.isEmpty) return '';
  final buffer = StringBuffer();
  for (final token in tokens) {
    if (token.length == 1 && token != '"') {
      buffer.write(token);
    } else {
      buffer.write('"');
      buffer.write(token.replaceAll('"', ''));
      buffer.write('"');
    }
  }
  return buffer.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lightweight NFA adapter that operates on the existing model classes
// ─────────────────────────────────────────────────────────────────────────────

final _labelSplit = RegExp(r'[,\n]');

class _NfaAdapter {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  late final Set<String> alphabet;

  _NfaAdapter({required this.nodes, required this.lines}) {
    final syms = <String>{};
    for (final line in lines.values) {
      for (final alt in line.label.split(_labelSplit)) {
        final s = _normalise(alt);
        if (s.isNotEmpty && s != '~' && s != '?') {
          syms.add(s);
        }
      }
    }
    alphabet = syms;
  }

  static String _normalise(String s) {
    s = s.trim();
    // Resolve [[TOKEN]] commands to their unicode equivalents the same way
    // the simulator does, so that ∅, ε, etc. are treated as single symbols.
    if (s.startsWith('[[') && s.endsWith(']]')) {
      final inner = s.substring(2, s.length - 2).trim().toUpperCase();
      return kTokenReplacements[inner] ?? s;
    }
    return s;
  }

  /// ε-transitions: label is empty, '~', or a normalised empty string.
  bool _isEpsilon(String label) {
    final n = _normalise(label);
    return n.isEmpty || n == '~';
  }

  /// Compute the ε-closure of a set of NFA states.
  Set<String> epsilonClosure(Set<String> states) {
    final closure = <String>{...states};
    final stack = [...states];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final node = nodes[cur];
      if (node == null || node.isHaltState || node.isBlackBox) continue;
      for (final line in lines.values) {
        if (line.nodeAId != cur) continue;
        for (final alt in line.label.split(_labelSplit)) {
          if (_isEpsilon(alt)) {
            if (closure.add(line.nodeBId)) {
              stack.add(line.nodeBId);
            }
          }
        }
      }
    }
    return closure;
  }

  /// Given a set of NFA states and a symbol, return the set of states
  /// reachable by consuming exactly [symbol] (before ε-closure).
  Set<String> step(Set<String> states, String symbol) {
    final result = <String>{};
    for (final cur in states) {
      final node = nodes[cur];
      if (node == null || node.isHaltState || node.isBlackBox) continue;
      for (final line in lines.values) {
        if (line.nodeAId != cur) continue;
        for (final alt in line.label.split(_labelSplit)) {
          if (_normalise(alt) == symbol) {
            result.add(line.nodeBId);
          }
        }
      }
    }
    return result;
  }

  /// True if any state in [states] is an accepting state.
  bool anyAccepts(Set<String> states) {
    for (final id in states) {
      final n = nodes[id];
      if (n == null) continue;
      if (n.isHaltAccept) return true;
      if (n.isAccept && !n.isHaltState) return true;
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Token replacement map (mirrors token_replacements.dart)
//  Duplicated here so this file has no extra import dependency.
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, String> kTokenReplacements = {
  'EPSILON': 'ε',
  'EPS': 'ε',
  'LAMBDA': 'λ',
  'EMPTY': '∅',
  'EMPTYSET': '∅',
  'NULL': '∅',
  'BLANK': '⊔',
  'DELTA': 'δ',
  'SIGMA': 'Σ',
  'GAMMA': 'Γ',
  'ARROW': '→',
  'RIGHT': '→',
  'LEFT': '←',
  'UP': '↑',
  'DOWN': '↓',
  'STAR': '*',
  'PLUS': '+',
};