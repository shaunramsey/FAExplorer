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
//      its own line) — subset construction followed by Hopcroft minimization.
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
RegexConversionResult regexToNfa(String pattern) {
  try {
    final parser = _RegexParser(pattern);
    final ast = parser.parse();
    final builder = _NfaBuilder();
    final fragment = builder.build(ast);
    return _fragmentToGraph(fragment, builder);
  } catch (e) {
    return RegexConversionResult(
      nodes: {},
      lines: {},
      startArrow: StartArrowData(nodeId: ''),
      error: 'Parse error: $e',
    );
  }
}

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
    return _dfaTableToGraph(nfa);
  } catch (e) {
    return RegexConversionResult(
      nodes: {},
      lines: {},
      startArrow: StartArrowData(nodeId: ''),
      error: 'Parse error: $e',
    );
  }
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

  _RegexNode parse() {
    if (input.trim().isEmpty) return _Epsilon();
    final result = _parseExpr();
    if (_pos < input.length) {
      throw Exception('Unexpected character at position $_pos: "${input[_pos]}"');
    }
    return result;
  }

  // expr ::= concat ('+' concat)*
  _RegexNode _parseExpr() {
    var node = _parseConcat();
    while (_pos < input.length && input[_pos] == '+') {
      _pos++; // consume '+'
      final right = _parseConcat();
      node = _Union(node, right);
    }
    return node;
  }

  // concat ::= atom+
  _RegexNode _parseConcat() {
    _RegexNode? node;
    while (_pos < input.length && input[_pos] != '+' && input[_pos] != ')') {
      final atom = _parseAtom();
      node = node == null ? atom : _Concat(node, atom);
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
      final inner = _parseExpr();
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

RegexConversionResult _fragmentToGraph(_Fragment fragment, _NfaBuilder builder) {
  final nodes = <String, NodeData>{};
  final lines = <String, LineData>{};
  int lineCounter = 0;

  // Layout states in a nice circular arrangement
  final total = builder._nextState;
  final radius = max(120.0, total * 30.0);
  final center = const Offset(400, 350);

  for (int i = 0; i < total; i++) {
    final angle = (2 * pi * i / total) - pi / 2;
    final x = center.dx + cos(angle) * radius;
    final y = center.dy + sin(angle) * radius;
    final id = 'n$i';
    nodes[id] = NodeData(
      id: id,
      position: Offset(x - 50, y - 50),
      label: 'q$i',
      isAccept: i == fragment.accept,
    );
  }

  // Add transitions
  builder._transitions.forEach((fromState, outEdges) {
    for (final edge in outEdges) {
      final lid = 'l${lineCounter++}';
      final fromId = 'n$fromState';
      final toId = 'n${edge.to}';
      // ε transitions use '~' which is the app's epsilon symbol
      final label = edge.symbol.isEmpty ? '~' : edge.symbol;
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
  });

  // Deduplicate parallel edges: merge labels into comma-separated
  final deduped = _deduplicateParallelEdges(lines, nodes, lineCounter);

  final startArrow = StartArrowData(
    nodeId: 'n${fragment.start}',
    offset: const Offset(-1, 0),
    length: 100,
  );

  return RegexConversionResult(
    nodes: nodes,
    lines: deduped.$1,
    startArrow: startArrow,
  );
}

(Map<String, LineData>, int) _deduplicateParallelEdges(
  Map<String, LineData> lines,
  Map<String, NodeData> nodes,
  int lineCounter,
) {
  // Group lines by (fromId, toId)
  final Map<String, List<LineData>> groups = {};
  for (final line in lines.values) {
    final key = '${line.nodeAId}__${line.nodeBId}';
    groups.putIfAbsent(key, () => []).add(line);
  }

  final result = <String, LineData>{};
  int counter = lineCounter;

  for (final group in groups.values) {
    if (group.length == 1) {
      result[group[0].id] = group[0];
    } else {
      // Merge labels — sort for determinism, deduplicate
      final labels = group.map((l) => l.label).toSet().toList()..sort();
      final mergedLabel = labels.join(',');
      final lid = 'l${counter++}';
      final merged = LineData(
        id: lid,
        nodeAId: group[0].nodeAId,
        nodeBId: group[0].nodeBId,
        label: mergedLabel,
      );
      result[lid] = merged;
      // Update node connectivity
      nodes[merged.nodeAId]?.connectedLineIds.clear();
      nodes[merged.nodeBId]?.connectedLineIds.clear();
    }
  }

  // Rebuild connectivity cleanly
  for (final node in nodes.values) {
    node.connectedLineIds.clear();
  }
  for (final line in result.values) {
    nodes[line.nodeAId]?.connectedLineIds.add(line.id);
    nodes[line.nodeBId]?.connectedLineIds.add(line.id);
  }

  return (result, counter);
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

// ─── DFA minimization (Hopcroft's algorithm) ──────────────────────────────────

/// Minimizes a DFA given as a transition table.
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

RegexConversionResult _dfaTableToGraph(_NfaTable nfa) {
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

  // ── Step 3: Hopcroft minimization ─────────────────────────────────────────
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
  final radius = max(140.0, total * 35.0);
  final center = const Offset(400, 350);

  for (int i = 0; i < total; i++) {
    final angle = (2 * pi * i / total) - pi / 2;
    final x = center.dx + cos(angle) * radius;
    final y = center.dy + sin(angle) * radius;
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
    final ek = '${parts[0]}__${parts[1]}'; // from__sym, but we want from__to
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