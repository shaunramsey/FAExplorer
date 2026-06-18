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
/// Uses Thompson construction followed by ε-pass-through elimination,
/// producing a compact NFA that still carries ε-edges where needed.
RegexConversionResult regexToNfa(String pattern) {
  try {
    final parser = _RegexParser(pattern);
    final ast = parser.parse();
    final builder = _NfaBuilder();
    final fragment = builder.build(ast);
    // _fragmentToGraph eliminates trivial ε-pass-throughs and lays the NFA
    // out on a circle — no subset construction, so ε-transitions are preserved.
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

RegexConversionResult _fragmentToGraph(_Fragment fragment, _NfaBuilder builder) {
  // Work on a mutable copy of the transition table.
  // trans[s] = list of (symbol, to) pairs.
  final trans = <int, List<({String symbol, int to})>>{};
  builder._transitions.forEach((s, edges) {
    trans[s] = List.of(edges);
  });

  final int startState  = fragment.start;
  final int acceptState = fragment.accept;

  // Iteratively eliminate pure pass-through states.
  bool changed = true;
  while (changed) {
    changed = false;

    // Find a candidate pass-through state.
    int? candidate;
    outer:
    for (final s in trans.keys) {
      if (s == startState || s == acceptState) continue;
      final out = trans[s] ?? [];
      // Must have exactly one outgoing ε-edge and no non-ε outgoing edges.
      if (out.length != 1 || out[0].symbol != _kEpsilon) continue;
      // Must not be the target of any non-ε edge coming back to itself
      // (self-ε would collapse to a no-op, safe to remove).
      candidate = s;
      break outer;
    }

    if (candidate == null) break;

    final successor = trans[candidate]!.first.to;

    // Redirect every edge that points to candidate so it points to successor.
    for (final edges in trans.values) {
      for (int i = 0; i < edges.length; i++) {
        if (edges[i].to == candidate) {
          edges[i] = (symbol: edges[i].symbol, to: successor);
        }
      }
    }

    // Remove the eliminated state entirely.
    trans.remove(candidate);
    changed = true;
  }

  // Deduplicate self-loops that collapse to nothing (s → s via ε).
  for (final s in trans.keys) {
    trans[s]!.removeWhere((e) => e.symbol == _kEpsilon && e.to == s);
  }

  // ── Start-ε-collapse ───────────────────────────────────────────────────────
  // If the start state has ONLY ε-outgoing edges (e.g. it is the Union or Star
  // wrapper added by Thompson construction), merge its entire ε-closure into
  // a single new start state.  This eliminates the overhead states that appear
  // in patterns like "00+11" (2 extra states from the Union wrapper).
  int effectiveStart  = startState;
  int effectiveAccept = acceptState;

  final _startOut = trans[startState] ?? [];
  if (_startOut.isNotEmpty && _startOut.every((e) => e.symbol == _kEpsilon)) {
    // Compute ε-closure of the start state.
    final closure = <int>{startState};
    final wl = <int>[startState];
    while (wl.isNotEmpty) {
      final s = wl.removeLast();
      for (final e in trans[s] ?? []) {
        if (e.symbol == _kEpsilon && closure.add(e.to)) wl.add(e.to);
      }
    }

    // Gather non-ε edges from the closure that leave the closure.
    final newEdgeSet = <({String symbol, int to})>{};
    for (final s in closure) {
      for (final e in trans[s] ?? []) {
        if (e.symbol != _kEpsilon && !closure.contains(e.to)) {
          newEdgeSet.add(e);
        }
      }
    }

    // Replace start's edges with the collected real edges.
    trans[startState] = newEdgeSet.toList();

    // Remove all other states in the closure.
    for (final s in closure) {
      if (s != startState) trans.remove(s);
    }

    // Redirect any remaining edges that point into the removed closure states.
    for (final edges in trans.values) {
      for (int i = 0; i < edges.length; i++) {
        if (edges[i].to != startState && closure.contains(edges[i].to)) {
          edges[i] = (symbol: edges[i].symbol, to: startState);
        }
      }
    }

    // If the original accept state was inside the closure, start IS now accepting.
    if (closure.contains(acceptState)) {
      effectiveAccept = startState;
    }

    // Second pass-through elimination: the collapse may have created new
    // single-ε-edge states (e.g. Kleene back-edge intermediaries).
    bool changed2 = true;
    while (changed2) {
      changed2 = false;
      int? candidate2;
      outer2:
      for (final s in trans.keys) {
        if (s == effectiveStart || s == effectiveAccept) continue;
        final out = trans[s] ?? [];
        if (out.length == 1 && out[0].symbol == _kEpsilon) {
          candidate2 = s;
          break outer2;
        }
      }
      if (candidate2 == null) break;
      final successor = trans[candidate2]!.first.to;
      for (final edges in trans.values) {
        for (int i = 0; i < edges.length; i++) {
          if (edges[i].to == candidate2) {
            edges[i] = (symbol: edges[i].symbol, to: successor);
          }
        }
      }
      trans.remove(candidate2);
      changed2 = true;
    }

    // Remove self-ε loops introduced by the redirect.
    for (final s in trans.keys) {
      trans[s]!.removeWhere((e) => e.symbol == _kEpsilon && e.to == s);
    }

    // Deduplicate edges (the redirect can create identical duplicates).
    for (final s in trans.keys) {
      final seen = <({String symbol, int to})>{};
      trans[s] = trans[s]!.where(seen.add).toList();
    }
  }
  // ── End start-ε-collapse ───────────────────────────────────────────────────

  // Collect surviving states (reachable from start via BFS).
  final surviving = <int>{};
  final queue = [effectiveStart];
  surviving.add(effectiveStart);
  while (queue.isNotEmpty) {
    final s = queue.removeLast();
    for (final e in trans[s] ?? []) {
      if (surviving.add(e.to)) queue.add(e.to);
    }
  }

  // Renumber: start → 0, accept → 1 (if different), rest in order.
  final order = <int>[effectiveStart];
  if (effectiveAccept != effectiveStart && surviving.contains(effectiveAccept)) {
    order.add(effectiveAccept);
  }
  for (final s in surviving) {
    if (s != effectiveStart && s != effectiveAccept) order.add(s);
  }
  final remap = <int, int>{};
  for (int i = 0; i < order.length; i++) {
    remap[order[i]] = i;
  }

  final total  = order.length;
  final nodes  = <String, NodeData>{};
  final lines  = <String, LineData>{};
  int lineCounter = 0;

  // Layout surviving states in a circle.
  final radius = max(120.0, total * 40.0);
  final center = const Offset(400, 350);

  for (int i = 0; i < total; i++) {
    final angle = (2 * pi * i / total) - pi / 2;
    final x     = center.dx + cos(angle) * radius;
    final y     = center.dy + sin(angle) * radius;
    final newId = remap[order[i]]!;
    final id    = 'n$newId';
    nodes[id]   = NodeData(
      id:       id,
      position: Offset(x - 50, y - 50),
      label:    'q$newId',
      isAccept: order[i] == effectiveAccept,
    );
  }

  // Emit edges (using renumbered ids).
  for (final oldFrom in order) {
    for (final edge in trans[oldFrom] ?? []) {
      final oldTo = edge.to;
      if (!remap.containsKey(oldTo)) continue; // pruned unreachable
      final fromId = 'n${remap[oldFrom]!}';
      final toId   = 'n${remap[oldTo]!}';
      final label  = edge.symbol.isEmpty ? '~' : edge.symbol;
      final lid    = 'l${lineCounter++}';
      final line   = LineData(id: lid, nodeAId: fromId, nodeBId: toId, label: label);
      lines[lid]   = line;
      nodes[fromId]?.connectedLineIds.add(lid);
      nodes[toId]?.connectedLineIds.add(lid);
    }
  }

  // Merge parallel edges (same from→to, different labels) into one line.
  final deduped = _deduplicateParallelEdges(lines, nodes, lineCounter);

  final startArrow = StartArrowData(
    nodeId: 'n0', // always renumbered to 0
    offset: const Offset(-1, 0),
    length: 100,
  );

  return RegexConversionResult(
    nodes:      nodes,
    lines:      deduped.$1,
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