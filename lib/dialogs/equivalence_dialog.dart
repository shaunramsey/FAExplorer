// ─────────────────────────────────────────────────────────────────────────────
//  equivalence_dialog.dart
//
//  Everything related to validating a player/user's automaton against
//  another automaton or a required shape, in one place:
//
//    1. EQUIVALENCE ALGORITHMS — decide whether two automata accept exactly
//       the same language:
//         • checkEquivalence()    — NFA/DFA: exact BFS over the product of
//           both machines' powerset constructions. Produces a short
//           distinguishing witness string when the languages differ.
//         • checkPdaEquivalence() / checkTmEquivalence() — PDA/TM: bounded
//           search over candidate input strings (equivalence is undecidable
//           in general for these models), so the result may come back as
//           unknownCapReached rather than a proof of equivalence.
//
//    2. AUTOMATON TYPE CHECKING — AutomatonTypeChecker.check() classifies a
//       *single* automaton as a DFA or NFA (no comparison to another
//       automaton involved) and produces human-readable violation messages
//       when a puzzle requires a specific type the player didn't build.
//
//    3. DIALOG — showEquivalenceDialog() opens a bottom sheet / dialog that
//       lets the user paste or type two DSL strings and runs the equivalence
//       algorithms above, displaying the result (equivalent / not equivalent
//       + witness / unknown / missing start state).
//
//  NOTE: everything in sections 1 and 2 is plain Dart with no dependency on
//  section 3's dialog UI — game_puzzle.dart, game_data.dart, and
//  game_level.dart import this file for algorithm/type-checking access only,
//  never touching the dialog.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../import_export.dart';
import '../models.dart';
import '../simulator.dart';
import '../widgets/app_theme.dart';
import '../widgets/automata_drawer.dart' show AutomataMode;

// ═════════════════════════════════════════════════════════════════════════════
//  1. EQUIVALENCE ALGORITHMS
// ═════════════════════════════════════════════════════════════════════════════

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

  // Build the combined concrete alphabet from both machines, then share it so
  // that `.` and `.-X` expand correctly relative to all declared symbols.
  final alphabet = <String>{
    ...nfa1.collectConcreteSymbols(),
    ...nfa2.collectConcreteSymbols(),
  };
  nfa1.alphabet = alphabet;
  nfa2.alphabet = alphabet;

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

/// Splits a raw transition label into individual symbol tokens, correctly
/// handling quoted multi-character tokens such as `"Green Leaf"` and
/// negation prefixes like `.-"Green Leaf","Bar"`.
///
/// Commas and newlines are delimiters only when outside double-quotes.
List<String> _splitLabel(String label) {
  if (label.trim().isEmpty) return const [''];
  final tokens = <String>[];
  final buf = StringBuffer();
  bool inQuote = false;
  for (int i = 0; i < label.length; i++) {
    final ch = label[i];
    if (ch == '"') {
      inQuote = !inQuote;
      buf.write(ch);
    } else if (!inQuote && (ch == ',' || ch == '\n')) {
      final t = buf.toString().trim();
      if (t.isNotEmpty) tokens.add(t);
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  final t = buf.toString().trim();
  if (t.isNotEmpty) tokens.add(t);
  return tokens;
}

class _NfaAdapter {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  /// The combined alphabet of both NFAs. Set externally by [checkEquivalence]
  /// after both adapters are constructed, so that `.` and `.-X` expand
  /// relative to the full symbol set.
  Set<String> alphabet = {};

  _NfaAdapter({required this.nodes, required this.lines});

  /// Collect every concrete (non-wildcard) input symbol used on transitions.
  /// `.` and `.-…` tokens are excluded here; they are expanded at step-time
  /// against [alphabet].
  Set<String> collectConcreteSymbols() {
    final syms = <String>{};
    for (final line in lines.values) {
      for (final raw in _splitLabel(line.label)) {
        final s = _normalise(raw);
        if (s.isEmpty || s == '~' || s == '?' || s == '.') continue;
        if (s.startsWith('.-')) continue;
        syms.add(s);
      }
    }
    return syms;
  }

  static String _normalise(String s) {
    s = s.trim();
    if (s.startsWith('[[') && s.endsWith(']]')) {
      final inner = s.substring(2, s.length - 2).trim().toUpperCase();
      return kTokenReplacements[inner] ?? s;
    }
    return s;
  }

  /// ε-transitions: label normalises to empty or '~'.
  bool _isEpsilon(String raw) {
    final n = _normalise(raw);
    return n.isEmpty || n == '~';
  }

  /// Null jumps fire only after the current input prefix is fully consumed.
  /// Matches [AutomataSimulator]'s end-of-input `?` / `\0` handling.
  bool _isNullJump(String raw) {
    final n = _normalise(raw);
    return n == '?' || n == r'\0';
  }

  /// For a `.-X,"Y",...` token, returns the set of excluded symbols.
  /// For a bare `.` the excluded set is empty (matches everything in alphabet).
  Set<String> _negationExcludes(String token) {
    if (token == '.') return const {};
    final rest = token.substring(2); // strip leading '.-'
    final excludes = <String>{};
    for (final part in _splitLabel(rest)) {
      final sym = _stripQuotes(part.trim());
      if (sym.isNotEmpty) excludes.add(sym);
    }
    return excludes;
  }

  static String _stripQuotes(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// Returns true if the normalised label token [norm] fires on [symbol].
  ///
  /// - Exact match always fires.
  /// - `.` fires on every symbol in [alphabet].
  /// - `.-X` fires on every alphabet symbol NOT in the exclusion list.
  ///   Symbols outside [alphabet] are silently excluded, so `.-y` over
  ///   alphabet {a,b,c} only fires on {a,b,c}, not on 'y' or 'z'.
  bool _labelMatchesSymbol(String norm, String symbol) {
    if (norm == symbol) return true;
    if (norm == '.' || norm.startsWith('.-')) {
      if (!alphabet.contains(symbol)) return false;
      if (norm == '.') return true;
      return !_negationExcludes(norm).contains(symbol);
    }
    return false;
  }

  /// ε-closure plus end-of-input null jumps (`?`, `\0`) of a set of NFA states.
  ///
  /// The BFS only calls this after the entire current witness prefix has been
  /// consumed, which is exactly when null jumps are allowed in the simulator.
  Set<String> epsilonClosure(Set<String> states) {
    final closure = <String>{...states};
    final stack = [...states];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final node = nodes[cur];
      if (node == null || node.isHaltState || node.isBlackBox) continue;
      for (final line in lines.values) {
        if (line.nodeAId != cur) continue;
        for (final alt in _splitLabel(line.label)) {
          if (_isEpsilon(alt) || _isNullJump(alt)) {
            if (closure.add(line.nodeBId)) stack.add(line.nodeBId);
          }
        }
      }
    }
    return closure;
  }

  /// States reachable from [states] by consuming [symbol] (before ε-closure).
  ///
  /// An empty result means the machine fell off — the BFS visits the empty
  /// powerset node, which correctly rejects any remaining input.
  Set<String> step(Set<String> states, String symbol) {
    final result = <String>{};
    for (final cur in states) {
      final node = nodes[cur];
      if (node == null || node.isHaltState || node.isBlackBox) continue;
      for (final line in lines.values) {
        if (line.nodeAId != cur) continue;
        for (final alt in _splitLabel(line.label)) {
          if (_labelMatchesSymbol(_normalise(alt), symbol)) {
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

// ═════════════════════════════════════════════════════════════════════════════
//  2. AUTOMATON TYPE CHECKING (DFA vs NFA)
// ═════════════════════════════════════════════════════════════════════════════

// ─── Public contract ──────────────────────────────────────────────────────────

/// Which automaton type a puzzle requires.
enum RequiredAutomatonType {
  /// Every state must have exactly one transition per alphabet symbol,
  /// no epsilon (ε / ~) transitions, and exactly one start state.
  dfa,

  /// Any nondeterministic finite automaton is acceptable (includes DFAs,
  /// since every DFA is trivially an NFA).
  nfa,
}

/// Severity level of a single violation.
enum ViolationSeverity { error, warning }

/// One concrete reason why the automaton is not of the required type.
class AutomatonViolation {
  const AutomatonViolation({
    required this.severity,
    required this.message,
    this.affectedStateId,
    this.affectedLineId,
  });

  final ViolationSeverity severity;

  /// Plain-English explanation shown to the player.
  final String message;

  /// Optional: which state node this violation is about (for UI highlighting).
  final String? affectedStateId;

  /// Optional: which transition line this violation is about.
  final String? affectedLineId;

  @override
  String toString() => '[${severity.name.toUpperCase()}] $message';
}

/// The full result returned by [AutomatonTypeChecker.check].
class AutomatonTypeResult {
  const AutomatonTypeResult._({
    required this.detectedType,
    required this.requiredType,
    required this.violations,
  });

  /// What we detected the player's automaton to actually be.
  final RequiredAutomatonType detectedType;

  /// What the puzzle requires.
  final RequiredAutomatonType requiredType;

  /// All reasons why the automaton fails to be the required type.
  /// Empty when [isCorrectType] is true.
  final List<AutomatonViolation> violations;

  /// True when the player's automaton satisfies the puzzle requirement.
  bool get isCorrectType => violations.isEmpty;

  /// A single top-level message to show the player (e.g. in a snack-bar or
  /// banner).  Only meaningful when [isCorrectType] is false.
  String get primaryMessage {
    switch (requiredType) {
      case RequiredAutomatonType.dfa:
        return 'Your automaton is an NFA, but this puzzle requires a DFA.';
      case RequiredAutomatonType.nfa:
        // A DFA is always a valid NFA, so this branch fires only when the
        // puzzle explicitly requires a *proper* NFA (i.e. nondeterminism is
        // mandatory — uncommon but supported).
        return 'Your automaton is a DFA, but this puzzle requires a proper NFA '
            '(it must include at least one nondeterministic feature).';
    }
  }

  /// Bullet-point list of violations suitable for an expanded error panel.
  List<String> get detailedViolations =>
      violations.map((v) => v.message).toList();
}

// ─── Checker implementation ───────────────────────────────────────────────────

class AutomatonTypeChecker {
  AutomatonTypeChecker._();

  // ── Epsilon label detection ────────────────────────────────────────────────

  // Labels are split on commas OR newlines.
  // The simulator stores the literal two-character sequence `\n` in DSL strings
  // (not a real newline), so we match both real newlines AND the escaped form.
  static final _labelSplitter = RegExp(r'[,\n]|\\n');

  /// Returns true if [raw] encodes an epsilon (ε / ~ / empty) transition.
  /// Mirrors the logic in AutomataSimulator._isEpsilonLabel.
  ///
  /// NOTE: `?` and `\0` are "null-jump" epsilons that fire only at end-of-input
  /// in the simulator, but for DFA type-checking purposes any unconditional
  /// free-jump counts as an NFA feature.
  static bool _isEpsilonSymbol(String raw) {
    final s = raw.trim();
    return s.isEmpty || s == '~' || s == 'ε' || s == '?' || s == r'\0';
  }

  /// Splits a compound label (e.g. "a,b" or "a\nb") into individual symbols.
  static List<String> _splitLabel(String label) =>
      label.split(_labelSplitter).map((s) => s.trim()).toList();

  // ── Public entry point ────────────────────────────────────────────────────

  /// Checks the player's automaton against [required] and returns a result
  /// describing every violation (if any).
  ///
  /// [startArrow] is the screen's current [StartArrowData?].  The app allows
  /// at most one start arrow, so the only start-state DFA violation possible
  /// is a missing start arrow entirely.
  ///
  /// [alphabet] is the set of input symbols the puzzle defines.  Used to
  /// detect missing transitions (an important DFA violation).  Pass an empty
  /// set to skip that check.
  static AutomatonTypeResult check({
    required Map<String, NodeData> nodes,
    required Map<String, LineData> lines,
    required StartArrowData? startArrow,
    required Set<String> alphabet,
    required RequiredAutomatonType required,
  }) {
    final nfaViolations = _collectNfaFeatures(
      nodes: nodes,
      lines: lines,
      startArrow: startArrow,
      alphabet: alphabet,
    );

    // A graph is a DFA when it has zero NFA features.
    final detectedType = nfaViolations.isEmpty
        ? RequiredAutomatonType.dfa
        : RequiredAutomatonType.nfa;

    switch (required) {
      case RequiredAutomatonType.dfa:
        return AutomatonTypeResult._(
          detectedType: detectedType,
          requiredType: required,
          violations: nfaViolations,
        );

      case RequiredAutomatonType.nfa:
        // Player must have built a *proper* NFA.  A DFA is the only violation.
        if (detectedType == RequiredAutomatonType.dfa) {
          return AutomatonTypeResult._(
            detectedType: detectedType,
            requiredType: required,
            violations: const [
              AutomatonViolation(
                severity: ViolationSeverity.error,
                message:
                    'Your automaton is deterministic (a DFA). This puzzle '
                    'requires nondeterminism — add an ε-transition or give a '
                    'state more than one transition for the same symbol.',
              ),
            ],
          );
        }
        return AutomatonTypeResult._(
          detectedType: detectedType,
          requiredType: required,
          violations: const [],
        );
    }
  }

  // ── NFA feature detection ─────────────────────────────────────────────────

  /// Collects every feature that makes the automaton an NFA rather than a DFA.
  /// Returns an empty list when the automaton qualifies as a valid DFA.
  static List<AutomatonViolation> _collectNfaFeatures({
    required Map<String, NodeData> nodes,
    required Map<String, LineData> lines,
    required StartArrowData? startArrow,
    required Set<String> alphabet,
  }) {
    final violations = <AutomatonViolation>[];

    // ── 1. Missing start state ─────────────────────────────────────────────
    // The app uses a single StartArrowData to designate the start state.
    // If it is absent the automaton has no start state, which is invalid for
    // both DFAs and NFAs, but we report it as a DFA violation here.
    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      violations.add(const AutomatonViolation(
        severity: ViolationSeverity.error,
        message:
            'No start state is set. A DFA must have exactly one start state — '
            'place the start arrow on the initial state.',
      ));
    }

    // Build a lookup: stateId → { symbol → [target state ids] }
    final Map<String, Map<String, List<String>>> transitionMap = {};
    final Map<String, List<String>> epsilonTargets = {};

    for (final line in lines.values) {
      final from = line.nodeAId;
      final to = line.nodeBId;

      for (final symbol in _splitLabel(line.label)) {
        if (_isEpsilonSymbol(symbol)) {
          // ── 2. Epsilon transitions ───────────────────────────────────────
          epsilonTargets.putIfAbsent(from, () => []).add(to);
        } else {
          transitionMap
              .putIfAbsent(from, () => {})
              .putIfAbsent(symbol, () => [])
              .add(to);
        }
      }
    }

    // Report epsilon transitions — one violation per source state.
    epsilonTargets.forEach((stateId, targets) {
      final uniqueTargets = targets.toSet();
      violations.add(AutomatonViolation(
        severity: ViolationSeverity.error,
        affectedStateId: stateId,
        message:
            'State ${_stateNameById(stateId, nodes)} has an ε-transition '
            '(epsilon / empty-string transition) to '
            '${uniqueTargets.map((t) => _stateNameById(t, nodes)).join(', ')}. '
            'DFAs do not allow ε-transitions — every transition must consume '
            'exactly one input symbol.',
      ));
    });

    // ── 3. Nondeterminism: multiple transitions for the same symbol ────────
    transitionMap.forEach((stateId, bySymbol) {
      bySymbol.forEach((symbol, targets) {
        if (targets.length > 1) {
          violations.add(AutomatonViolation(
            severity: ViolationSeverity.error,
            affectedStateId: stateId,
            message:
                'State ${_stateNameById(stateId, nodes)} has '
                '${targets.length} transitions for symbol "$symbol" '
                '(to ${targets.map((t) => _stateNameById(t, nodes)).join(', ')}). '
                'A DFA must have exactly one transition per symbol per state — '
                'this creates nondeterminism.',
          ));
        }
      });
    });

    // ── 4. Missing transitions (incomplete transition function) ────────────
    // Only checked when the caller supplied the puzzle alphabet.
    if (alphabet.isNotEmpty) {
      for (final node in nodes.values) {
        // Halt states intentionally have no outgoing transitions — skip them.
        if (node.isHaltAccept || node.isHaltReject) continue;

        final bySymbol = transitionMap[node.id] ?? {};
        for (final symbol in alphabet) {
          if ((bySymbol[symbol] ?? []).isEmpty) {
            violations.add(AutomatonViolation(
              severity: ViolationSeverity.warning,
              affectedStateId: node.id,
              message:
                  'State ${_stateName(node)} has no transition for symbol '
                  '"$symbol". A complete DFA must define exactly one transition '
                  'for every symbol in every state. '
                  'Consider adding a transition to a dead/trap state.',
            ));
          }
        }
      }
    }

    return violations;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _stateName(NodeData node) =>
      node.label.trim().isNotEmpty ? '"${node.label.trim()}"' : node.id;

  static String _stateNameById(String id, Map<String, NodeData> nodes) {
    final node = nodes[id];
    if (node == null) return id;
    return _stateName(node);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  3. DIALOG UI
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showEquivalenceDialog(
  BuildContext context, {
  String? initialDsl,
}) {
  return showDialog(
    context: context,
    builder: (_) => _EquivalenceDialog(initialDsl: initialDsl),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _EquivalenceDialog extends StatefulWidget {
  final String? initialDsl;
  const _EquivalenceDialog({this.initialDsl});

  @override
  State<_EquivalenceDialog> createState() => _EquivalenceDialogState();
}

class _EquivalenceDialogState extends State<_EquivalenceDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _ctrlA;
  late final TextEditingController _ctrlB;
  late final TabController _tabController;

  EquivalenceResult? _result;
  String? _errorA;
  String? _errorB;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _ctrlA = TextEditingController(text: widget.initialDsl ?? '');
    _ctrlB = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _ctrlA.dispose();
    _ctrlB.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Check ─────────────────────────────────────────────────────────────────

  void _check() {
    setState(() {
      _errorA = null;
      _errorB = null;
      _result = null;
      _checking = true;
    });

    late final GraphState g1, g2;
    try {
      g1 = DslCodec.importFromDsl(_ctrlA.text);
    } catch (e) {
      setState(() {
        _errorA = 'Parse error: $e';
        _checking = false;
      });
      return;
    }
    try {
      g2 = DslCodec.importFromDsl(_ctrlB.text);
    } catch (e) {
      setState(() {
        _errorB = 'Parse error: $e';
        _checking = false;
      });
      return;
    }

    if (g1.automataMode != g2.automataMode) {
      setState(() {
        _errorA = 'Automaton A is in ${g1.automataMode.name.toUpperCase()} mode.';
        _errorB = 'Automaton B is in ${g2.automataMode.name.toUpperCase()} mode.';
        _checking = false;
      });
      return;
    }

    late final EquivalenceResult result;
    switch (g1.automataMode) {
      case AutomataMode.ndfa:
      case AutomataMode.regex:
        result = checkEquivalence(
          nodes1: g1.nodes, lines1: g1.lines, startArrow1: g1.startArrow,
          nodes2: g2.nodes, lines2: g2.lines, startArrow2: g2.startArrow,
        );
        break;
      case AutomataMode.pda:
        result = checkPdaEquivalence(
          nodes1: g1.nodes, lines1: g1.lines, startArrow1: g1.startArrow,
          nodes2: g2.nodes, lines2: g2.lines, startArrow2: g2.startArrow,
        );
        break;
      case AutomataMode.tm:
        result = checkTmEquivalence(
          nodes1: g1.nodes, lines1: g1.lines, startArrow1: g1.startArrow,
          nodes2: g2.nodes, lines2: g2.lines, startArrow2: g2.startArrow,
        );
        break;
    }

    setState(() {
      _result = result;
      _checking = false;
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Widget _dslEditor(
    AppThemeNotifier theme,
    TextEditingController ctrl,
    String label,
    String? error,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: GoogleFonts.courierPrime(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: theme.textLight,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: theme.bg,
            border: Border.all(
              color: error != null ? const Color(0xFFFF1744) : theme.borderMid,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: 14,
            style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
            cursorColor: theme.accent,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(10),
              border: InputBorder.none,
              hintText: 'Paste DSL here…',
              hintStyle: GoogleFonts.courierPrime(color: theme.textDim, fontSize: 13),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: const TextStyle(color: Color(0xFFFF1744), fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _resultBanner() {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final r = _result;
    if (r == null) return const SizedBox.shrink();

    switch (r.status) {
      case EquivalenceStatus.equivalent:
        return _Banner(
          color: const Color(0xFF051A10),
          borderColor: const Color(0xFF1FD99A),
          icon: Icons.check_circle_outline,
          iconColor: const Color(0xFF1FD99A),
          title: 'Equivalent',
          body: 'Both automata accept exactly the same language.',
        );

      case EquivalenceStatus.notEquivalent:
        final w = r.witness!;
        final wDisplay = w.isEmpty ? '\0 (the empty string)' : '"$w"';
        final other = r.acceptedByMachine == 1 ? 'B' : 'A';
        final accepted = r.acceptedByMachine == 1 ? 'A' : 'B';
        return _Banner(
          color: const Color(0xFF1A0D00),
          borderColor: const Color(0xFFFF6D00),
          icon: Icons.highlight_off,
          iconColor: const Color(0xFFFF9E40),
          title: 'Not Equivalent',
          body: 'Distinguishing witness: $wDisplay\n'
              'Automaton $accepted accepts this string, automaton $other does not.',
        );

      case EquivalenceStatus.unknownCapReached:
        return _Banner(
          color: const Color(0xFF051A10),
          borderColor: const Color(0xFF1FD99A),
          icon: Icons.check,
          iconColor: const Color(0xFF1FD99A),
          title: 'Likely Equivalent',
          body: 'No distinguishing string was found within the checked bounds. '
              'For NFA/DFA, this means the algorithm could not prove inequivalence. '
              'For PDA/TM, the search is intentionally bounded.',
        );

      case EquivalenceStatus.noStartState:
        return _Banner(
          color: const Color(0xFF1A0005),
          borderColor: const Color(0xFFFF1744),
          icon: Icons.warning_amber_outlined,
          iconColor: const Color(0xFFFF1744),
          title: 'Missing start state',
          body: 'One or both automata have no start state defined. '
              'Add a start arrow (▶) and try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Dialog(
      backgroundColor: theme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows, color: theme.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Compare Automata',
                    style: GoogleFonts.courierPrime(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.textLight),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.textMid),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Divider(height: 16, color: theme.borderMid),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Instruction blurb
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF080D14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.borderMid),
                      ),
                      child: Text(
                        'Paste the DSL for two automata. For NFA/DFA, the checker can prove equivalence exactly. '
                        'For PDA/TM, it performs a bounded search for a distinguishing input string. '
                        'If no counterexample is found within the search bound, equivalence remains unknown.',
                        style: GoogleFonts.courierPrime(fontSize: 12, color: theme.textMid),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Two-column layout on wide screens ──
                    LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth > 500;
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _dslEditor(theme, _ctrlA, 'Automaton A', _errorA)),
                            const SizedBox(width: 16),
                            Expanded(child: _dslEditor(theme, _ctrlB, 'Automaton B', _errorB)),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _dslEditor(theme, _ctrlA, 'Automaton A', _errorA),
                          const SizedBox(height: 16),
                          _dslEditor(theme, _ctrlB, 'Automaton B', _errorB),
                        ],
                      );
                    }),

                    const SizedBox(height: 20),
                    _resultBanner(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            Divider(height: 1, color: theme.borderMid),

            // ── Actions ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: theme.textMid),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _checking ? null : _check,
                    icon: const Icon(Icons.compare),
                    label: const Text('Check equivalence'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small reusable banner widget
// ─────────────────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _Banner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.courierPrime(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.courierPrime(
                    fontSize: 13,
                    color: context.watch<AppThemeNotifier>().textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}