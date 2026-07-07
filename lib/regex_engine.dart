// ─────────────────────────────────────────────────────────────────────────────
//  regex_engine.dart
//
//  Parses a simple regular expression where:
//    *  = Kleene star (zero or more of the preceding atom)
//    +  = union / alternation (either side), equivalent to | in standard regex
//
//  Operator precedence (highest → lowest):
//    1. * (postfix)
//    2. concatenation (implicit)
//    3. + (infix alternation)
//
//  Parentheses group sub-expressions.
//
//  All other characters are treated as literal single-character symbols.
//  ε (epsilon) self-loops are represented internally by the empty string ''.
//
//  The converter produces:
//    • An NFA (NodeData + LineData) with ε-transitions (Thompson construction)
//    • OR a minimal DFA (NodeData + LineData, no ε-transitions, each symbol on
//      its own line) — subset construction followed by DFA minimization via
//      Moore's partition-refinement algorithm (see the note above
//      _minimizeDfa() for why this isn't Hopcroft's algorithm despite an
//      earlier version of this comment saying so).
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';

import 'models.dart';

// ─── Public API ───────────────────────────────────────────────────────────────

/// The result of converting a regex to a graph.
class RegexConversionResult {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData startArrow;
  final String? error;

  const RegexConversionResult({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    this.error,
  });

  bool get isError => error != null;
}

/// Converts a simple regex string to an NFA graph (with ε-transitions).
/// Uses Thompson construction followed by ε-pass-through elimination,
/// Converts a simple regex string to a minimal DFA graph (no ε, one symbol per line).
RegexConversionResult regexToDfa(String pattern) {
  try {
    final parser = _RegexParser(pattern);
    final ast = parser.parse();
    final builder = _NfaBuilder();
    final fragment = builder.build(ast);
    // Collect alphabet from AST
    final alphabet = <String>{};
    _collectAlphabet(ast, alphabet);
    // Build NFA transition table, subset-construct DFA, then minimize
    final nfa = _NfaTable(fragment: fragment, builder: builder, alphabet: alphabet);
    return _dfaTableToGraph(nfa, pattern);
  } catch (e) {
    return RegexConversionResult(
      nodes: {},
      lines: {},
      startArrow: StartArrowData(nodeId: ''),
      error: 'Parse error: $e',
    );
  }
}

// ─── Layout helpers ───────────────────────────────────────────────────────────

/// Deterministic hash of [s] → a value in [0, 1).
///
/// Uses a simple djb2-style integer hash so the same regex always produces
/// the same phase offset, but structurally different regexes (even with the
/// same node count after minimization) produce different offsets.
double _patternPhase(String s) {
  int h = 5381;
  for (final unit in s.codeUnits) {
    h = ((h << 5) + h + unit) & 0x1FFFFFFF; // keep positive, 29-bit
  }
  return (h % 10000) / 10000.0 * 2 * pi;
}

// Layout constants shared by both NFA and DFA paths.
const double _kNodeSize  = 100.0;
const double _kCanvasW   = 800.0;
const double _kCanvasH   = 600.0;
const double _kMargin    = _kNodeSize / 2 + 30; // 80 px — clears node edge + label room
const double _kMinChord  = 220.0; // min px between adjacent centres — room for label boxes

/// Compute the circle radius for [total] nodes, given a minimum chord
/// distance of [_kMinChord] and the canvas bounds.
double _circleRadius(int total) {
  if (total <= 1) return 0.0;
  final minR = (_kMinChord / 2) / sin(pi / total);
  final maxR = min(_kCanvasW / 2 - _kMargin, _kCanvasH / 2 - _kMargin);
  // 75 px per node as base — generous but capped by maxR.
  return min(maxR, max(minR, total * 75.0));
}

// ─── AST ─────────────────────────────────────────────────────────────────────

abstract class _RegexNode {}

class _Literal extends _RegexNode {
  final String ch;
  _Literal(this.ch);
}

class _Epsilon extends _RegexNode {}

class _Concat extends _RegexNode {
  final _RegexNode left;
  final _RegexNode right;
  _Concat(this.left, this.right);
}

class _Union extends _RegexNode {
  final _RegexNode left;
  final _RegexNode right;
  _Union(this.left, this.right);
}

class _Star extends _RegexNode {
  final _RegexNode child;
  _Star(this.child);
}

// ─── Parser ──────────────────────────────────────────────────────────────────
//
//  Grammar:
//    expr   ::= concat ('+' concat)*
//    concat ::= atom+
//    atom   ::= base '*'*
//    base   ::= CHAR | '(' expr ')'

class _RegexParser {
  final String input;
  int _pos = 0;

  _RegexParser(this.input);

  /// Advance [_pos] past any ASCII whitespace characters.
  void _skipWhitespace() {
    while (_pos < input.length && input[_pos] == ' ') {
      _pos++;
    }
  }

  _RegexNode parse() {
    _skipWhitespace();
    if (_pos >= input.length) return _Epsilon();
    final result = _parseExpr();
    _skipWhitespace();
    if (_pos < input.length) {
      throw Exception('Unexpected character at position $_pos: "${input[_pos]}"');
    }
    return result;
  }

  // expr ::= concat ('+' concat)*
  _RegexNode _parseExpr() {
    var node = _parseConcat();
    _skipWhitespace();
    while (_pos < input.length && input[_pos] == '+') {
      _pos++; // consume '+'
      _skipWhitespace();
      final right = _parseConcat();
      _skipWhitespace();
      node = _Union(node, right);
    }
    return node;
  }

  // concat ::= atom+
  _RegexNode _parseConcat() {
    _RegexNode? node;
    _skipWhitespace();
    while (_pos < input.length && input[_pos] != '+' && input[_pos] != ')') {
      final atom = _parseAtom();
      node = node == null ? atom : _Concat(node, atom);
      _skipWhitespace();
    }
    if (node == null) {
      // Empty concat in a context like "()" — treat as epsilon
      return _Epsilon();
    }
    return node;
  }

  // atom ::= base '*'*
  _RegexNode _parseAtom() {
    var node = _parseBase();
    while (_pos < input.length && input[_pos] == '*') {
      _pos++;
      node = _Star(node);
    }
    return node;
  }

  // base ::= CHAR | '(' expr ')'
  _RegexNode _parseBase() {
    if (_pos >= input.length) {
      throw Exception('Unexpected end of expression');
    }
    final ch = input[_pos];
    if (ch == '(') {
      _pos++; // consume '('
      _skipWhitespace();
      final inner = _parseExpr();
      _skipWhitespace();
      if (_pos >= input.length || input[_pos] != ')') {
        throw Exception('Missing closing parenthesis');
      }
      _pos++; // consume ')'
      return inner;
    }
    if (ch == '*' || ch == ')') {
      throw Exception('Unexpected character "$ch" at position $_pos');
    }
    _pos++;
    return _Literal(ch);
  }
}

// ─── Thompson NFA construction ────────────────────────────────────────────────

const String _kEpsilon = ''; // ε label

/// An NFA fragment: two state ids (start, accept).
class _Fragment {
  final int start;
  final int accept;
  const _Fragment(this.start, this.accept);
}

/// Transition: (from state, symbol) → set of to states
class _NfaBuilder {
  int _nextState = 0;

  // Adjacency list: state → list of (symbol, toState)
  final Map<int, List<({String symbol, int to})>> _transitions = {};

  int _newState() {
    final s = _nextState++;
    _transitions[s] = [];
    return s;
  }

  void _addTransition(int from, String symbol, int to) {
    _transitions.putIfAbsent(from, () => []).add((symbol: symbol, to: to));
  }

  _Fragment build(_RegexNode node) {
    if (node is _Epsilon) {
      final s = _newState();
      final a = _newState();
      _addTransition(s, _kEpsilon, a);
      return _Fragment(s, a);
    }
    if (node is _Literal) {
      final s = _newState();
      final a = _newState();
      _addTransition(s, node.ch, a);
      return _Fragment(s, a);
    }
    if (node is _Concat) {
      final left = build(node.left);
      final right = build(node.right);
      // Merge left.accept with right.start via ε
      _addTransition(left.accept, _kEpsilon, right.start);
      return _Fragment(left.start, right.accept);
    }
    if (node is _Union) {
      final s = _newState();
      final a = _newState();
      final left = build(node.left);
      final right = build(node.right);
      _addTransition(s, _kEpsilon, left.start);
      _addTransition(s, _kEpsilon, right.start);
      _addTransition(left.accept, _kEpsilon, a);
      _addTransition(right.accept, _kEpsilon, a);
      return _Fragment(s, a);
    }
    if (node is _Star) {
      final s = _newState();
      final a = _newState();
      final child = build(node.child);
      _addTransition(s, _kEpsilon, child.start);
      _addTransition(s, _kEpsilon, a); // zero repetitions
      _addTransition(child.accept, _kEpsilon, child.start); // loop
      _addTransition(child.accept, _kEpsilon, a); // exit
      return _Fragment(s, a);
    }
    throw Exception('Unknown AST node: $node');
  }
}

// ─── NFA → Graph (with ε-transitions for NFA export) ────────────────────────
//
// Thompson construction creates O(|regex|) states, many of which are pure
// ε-pass-throughs with exactly one incoming and one outgoing ε-edge.
// We eliminate those before emitting the graph so the displayed NFA is
// compact (matches hand-drawn style) while still being equivalent.
//
// A state is a "pass-through" if it is NOT the start state, NOT the accept
// state, has NO outgoing non-ε transitions, and has exactly one outgoing
// ε-edge. We short-circuit it by redirecting every edge that pointed TO it
// directly to its ε-successor, then drop the state.  We repeat until stable.


/// For every pair of lines (A→B) and (B→A), offset them in opposite
/// perpendicular directions so they arc away from each other instead of
/// drawing on top of each other.  Self-loops are skipped (they already render
/// as distinct circles).
void _assignBidirectionalCurves(Map<String, LineData> lines) {
  // Build a quick lookup: canonical key "min(a,b)__max(a,b)" → list of lines.
  final Map<String, List<LineData>> byPair = {};
  for (final line in lines.values) {
    if (line.nodeAId == line.nodeBId) continue; // self-loop: skip
    final a = line.nodeAId, b = line.nodeBId;
    final key = a.compareTo(b) <= 0 ? '${a}__$b' : '${b}__$a';
    byPair.putIfAbsent(key, () => []).add(line);
  }

  // For each pair that has lines going in both directions, assign opposing curves.
  for (final group in byPair.values) {
    if (group.length < 2) continue; // only one direction — no overlap possible

    // Separate by direction.
    final forward  = group.where((l) => l.nodeAId.compareTo(l.nodeBId) <= 0).toList();
    final backward = group.where((l) => l.nodeAId.compareTo(l.nodeBId) >  0).toList();
    if (forward.isEmpty || backward.isEmpty) continue;

    // Assign a modest perpendicular offset.  The sign convention in LineData
    // is that positive perpendicularPart bends the arc to the left when
    // travelling from A to B, negative bends it to the right.
    const double bend = 55.0;
    for (final l in forward)  { l.perpendicularPart =  bend; }
    for (final l in backward) { l.perpendicularPart = bend; }
  }
}

// ─── Subset construction (NFA → DFA) ─────────────────────────────────────────

void _collectAlphabet(_RegexNode node, Set<String> out) {
  if (node is _Literal) {
    out.add(node.ch);
  } else if (node is _Concat) {
    _collectAlphabet(node.left, out);
    _collectAlphabet(node.right, out);
  } else if (node is _Union) {
    _collectAlphabet(node.left, out);
    _collectAlphabet(node.right, out);
  } else if (node is _Star) {
    _collectAlphabet(node.child, out);
  }
}

class _NfaTable {
  final _Fragment fragment;
  final _NfaBuilder builder;
  final Set<String> alphabet;

  _NfaTable({
    required this.fragment,
    required this.builder,
    required this.alphabet,
  });

  /// Compute ε-closure of a set of NFA states.
  Set<int> epsilonClosure(Set<int> states) {
    final result = <int>{...states};
    final worklist = [...states];
    while (worklist.isNotEmpty) {
      final s = worklist.removeLast();
      for (final edge in builder._transitions[s] ?? []) {
        if (edge.symbol == _kEpsilon && !result.contains(edge.to)) {
          result.add(edge.to);
          worklist.add(edge.to);
        }
      }
    }
    return result;
  }

  /// Move: set of NFA states reachable from [states] by consuming [symbol].
  Set<int> move(Set<int> states, String symbol) {
    final result = <int>{};
    for (final s in states) {
      for (final edge in builder._transitions[s] ?? []) {
        if (edge.symbol == symbol) {
          result.add(edge.to);
        }
      }
    }
    return result;
  }
}

// ─── DFA minimization (Moore's partition-refinement algorithm) ────────────────
//
//  NOTE ON NAMING: earlier comments in this file called this "Hopcroft
//  minimization" / "Hopcroft's algorithm". That was inaccurate and has been
//  corrected. What's implemented below is Moore's algorithm: each round,
//  every partition is split by grouping its states according to which
//  partition each transition leads to, and this repeats until no partition
//  splits any further. That's the simple O(n² · |alphabet|) minimization
//  algorithm taught alongside Hopcroft's in most automata courses — it is
//  NOT Hopcroft's algorithm, which instead maintains an explicit worklist of
//  (partition, symbol) pairs and only reprocesses the specific partitions
//  affected by the smaller half of each split, giving it its better
//  O(n log n) bound. If you came here expecting Hopcroft's specific
//  worklist/"process the smaller half" technique, it isn't here — this is
//  the more approachable (if asymptotically slower) alternative, which is a
//  reasonable choice for the state counts this app deals with.
// ─────────────────────────────────────────────────────────────────────────────

/// Minimizes a DFA given as a transition table, via Moore's partition-
/// refinement algorithm (see the note above — this is not Hopcroft's
/// algorithm, despite this function having previously been mislabeled as
/// such).
///
/// [numStates]   — total number of DFA states (0..numStates-1).
/// [acceptStates] — set of accepting state indices.
/// [transitions]  — map from (stateIndex, symbol) → stateIndex; missing keys
///                  mean the transition goes to an implicit dead state.
/// [alphabet]     — the set of input symbols.
///
/// Returns a [_MinDfa] with the minimized transition table, start state
/// index (always 0 in the renumbered result), and accept-state set.
class _MinDfa {
  final int numStates;
  final Set<int> acceptStates;
  final Map<String, int> transitions; // 'fromIdx__symbol' -> toIdx
  final int startState;

  _MinDfa({
    required this.numStates,
    required this.acceptStates,
    required this.transitions,
    required this.startState,
  });
}

_MinDfa _minimizeDfa({
  required int numStates,
  required Set<int> acceptStates,
  required Map<String, int> rawTransitions, // 'from__sym' -> to
  required Set<String> alphabet,
  required int startState,
}) {
  // Add an explicit dead/sink state for missing transitions.
  // Dead state = numStates (index).
  final int deadState = numStates;
  final int totalStates = numStates + 1; // include dead

  int trans(int state, String sym) {
    if (state == deadState) return deadState;
    return rawTransitions['${state}__$sym'] ?? deadState;
  }

  // Initial partition: {accept states} ∪ {dead + non-accept states}
  // (dead is non-accepting by construction)
  final Set<int> nonAccept = {};
  for (int i = 0; i < totalStates; i++) {
    if (!acceptStates.contains(i)) nonAccept.add(i);
  }

  // Partitions as a list of sets; use index into this list as partition id.
  final List<Set<int>> partitions = [];
  if (acceptStates.isNotEmpty) partitions.add(Set.of(acceptStates));
  if (nonAccept.isNotEmpty) partitions.add(nonAccept);

  // state → partition index
  List<int> partOf = List.filled(totalStates, 0);
  void rebuildPartOf() {
    for (int p = 0; p < partitions.length; p++) {
      for (final s in partitions[p]) {
        partOf[s] = p;
      }
    }
  }

  rebuildPartOf();

  bool changed = true;
  while (changed) {
    changed = false;
    final List<Set<int>> newPartitions = [];

    for (final part in partitions) {
      if (part.length <= 1) {
        newPartitions.add(part);
        continue;
      }

      // Split part: group states by their transition signature.
      // Signature = tuple of partOf[trans(s, a)] for each a in alphabet.
      final Map<String, Set<int>> groups = {};
      for (final s in part) {
        final sig = alphabet.map((a) => partOf[trans(s, a)].toString()).join(',');
        groups.putIfAbsent(sig, () => {}).add(s);
      }

      if (groups.length > 1) changed = true;
      newPartitions.addAll(groups.values);
    }

    partitions
      ..clear()
      ..addAll(newPartitions);
    rebuildPartOf();
  }

  // Find which partition contains the start state and the dead state.
  final int startPartition = partOf[startState];
  final int deadPartition = partOf[deadState];

  // Renumber: start partition → 0, then others in order (skip dead partition).
  final List<int> order = [startPartition];
  for (int p = 0; p < partitions.length; p++) {
    if (p != startPartition && p != deadPartition) order.add(p);
  }
  // Map old partition index → new state index
  final Map<int, int> partToNew = {};
  for (int i = 0; i < order.length; i++) {
    partToNew[order[i]] = i;
  }

  final int newNumStates = order.length;
  final Set<int> newAccept = {};
  for (int p = 0; p < partitions.length; p++) {
    if (p == deadPartition) continue;
    final newIdx = partToNew[p]!;
    if (partitions[p].any((s) => acceptStates.contains(s))) {
      newAccept.add(newIdx);
    }
  }

  // Build new transition table (skip dead-state targets — caller treats missing = dead/reject).
  final Map<String, int> newTrans = {};
  for (final p in order) {
    final rep = partitions[p].first; // representative state
    final newFrom = partToNew[p]!;
    for (final sym in alphabet) {
      final toOld = trans(rep, sym);
      final toPart = partOf[toOld];
      if (toPart == deadPartition) continue; // omit dead-state transitions
      final newTo = partToNew[toPart]!;
      newTrans['${newFrom}__$sym'] = newTo;
    }
  }

  return _MinDfa(
    numStates: newNumStates,
    acceptStates: newAccept,
    transitions: newTrans,
    startState: 0,
  );
}

RegexConversionResult _dfaTableToGraph(_NfaTable nfa, String pattern) {
  // ── Step 1: Subset construction ──────────────────────────────────────────
  final startSet = nfa.epsilonClosure({nfa.fragment.start});
  final dfaStates = <Set<int>>[]; // ordered list of DFA states (sets of NFA states)
  final dfaStateIndex = <String, int>{}; // canonical key → dfa state index
  final dfaTransitions = <({int from, String symbol, int to})>[];

  String key(Set<int> s) => (s.toList()..sort()).join(',');

  dfaStates.add(startSet);
  dfaStateIndex[key(startSet)] = 0;
  final worklist = [0];

  while (worklist.isNotEmpty) {
    final idx = worklist.removeLast();
    final current = dfaStates[idx];

    for (final symbol in nfa.alphabet) {
      final moved = nfa.move(current, symbol);
      if (moved.isEmpty) continue;
      final closed = nfa.epsilonClosure(moved);
      final k = key(closed);
      int toIdx;
      if (dfaStateIndex.containsKey(k)) {
        toIdx = dfaStateIndex[k]!;
      } else {
        toIdx = dfaStates.length;
        dfaStates.add(closed);
        dfaStateIndex[k] = toIdx;
        worklist.add(toIdx);
      }
      dfaTransitions.add((from: idx, symbol: symbol, to: toIdx));
    }
  }

  // Determine accept states from subset construction
  final rawAcceptStates = <int>{};
  for (int i = 0; i < dfaStates.length; i++) {
    if (dfaStates[i].contains(nfa.fragment.accept)) {
      rawAcceptStates.add(i);
    }
  }

  // ── Step 2: Build raw transition map for minimizer ────────────────────────
  final Map<String, int> rawTransMap = {};
  for (final t in dfaTransitions) {
    rawTransMap['${t.from}__${t.symbol}'] = t.to;
  }

  // ── Step 3: DFA minimization (Moore's algorithm — see note above _minimizeDfa) ──
  final minDfa = _minimizeDfa(
    numStates: dfaStates.length,
    acceptStates: rawAcceptStates,
    rawTransitions: rawTransMap,
    alphabet: nfa.alphabet,
    startState: 0,
  );

  // ── Step 4: Build graph from minimized DFA ────────────────────────────────
  final nodes = <String, NodeData>{};
  final lines = <String, LineData>{};
  int lineCounter = 0;

  final total = minDfa.numStates;

  // Layout: same scheme as the NFA path — deterministic phase from the regex
  // string hash, shared spacing constants, on-canvas clamping.
  final double radius      = _circleRadius(total);
  final double phaseOffset = _patternPhase(pattern);
  final center             = const Offset(_kCanvasW / 2, _kCanvasH / 2);

  for (int i = 0; i < total; i++) {
    final angle = (2 * pi * i / total) - pi / 2 + phaseOffset;
    final cx = center.dx + cos(angle) * radius;
    final cy = center.dy + sin(angle) * radius;

    final x = cx.clamp(_kMargin, _kCanvasW - _kMargin);
    final y = cy.clamp(_kMargin, _kCanvasH - _kMargin);

    final id = 'n$i';
    nodes[id] = NodeData(
      id: id,
      position: Offset(x - 50, y - 50),
      label: 'q$i',
      isAccept: minDfa.acceptStates.contains(i),
    );
  }

  // Group transitions by (from, to) so we can merge symbols onto one line
  final Map<String, List<String>> edgeSymbols = {};
  for (final entry in minDfa.transitions.entries) {
    final parts = entry.key.split('__');
// from__sym, but we want from__to
    // Rebuild as from__to
    final fromIdx = parts[0];
    final sym = parts[1];
    final toIdx = entry.value.toString();
    edgeSymbols.putIfAbsent('${fromIdx}__$toIdx', () => []).add(sym);
  }

  for (final entry in edgeSymbols.entries) {
    final parts = entry.key.split('__');
    final fromId = 'n${parts[0]}';
    final toId = 'n${parts[1]}';
    // Sort symbols for determinism
    final symbols = entry.value..sort();
    final label = symbols.join(',');
    final lid = 'l${lineCounter++}';
    final line = LineData(
      id: lid,
      nodeAId: fromId,
      nodeBId: toId,
      label: label,
    );
    lines[lid] = line;
    nodes[fromId]?.connectedLineIds.add(lid);
    nodes[toId]?.connectedLineIds.add(lid);
  }

  // Bend bidirectional pairs so they don't overlap each other.
  _assignBidirectionalCurves(lines);

  final startArrow = StartArrowData(
    nodeId: 'n0',
    offset: const Offset(-1, 0),
    length: 100,
  );

  return RegexConversionResult(
    nodes: nodes,
    lines: lines,
    startArrow: startArrow,
  );
}