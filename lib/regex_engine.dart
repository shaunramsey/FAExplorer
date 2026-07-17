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
//  ~ (tilda) self-loops are represented internally by the empty string ''.
//
//  The converter produces:
//    • An NFA (NodeData + LineData) with ~-transitions (Thompson construction)
//    • OR a minimal DFA (NodeData + LineData, no ~-transitions, each symbol on
//      its own line) — subset construction followed by DFA minimization via
//      Moore's partition-refinement algorithm (see the note above
//      _minimizeDfa() for why this isn't Hopcroft's algorithm despite an
//      earlier version of this comment saying so).
//
// ─────────────────────────────────────────────────────────────────────────────

// Only used for pi/sin/cos/min/max in the layout-geometry helpers below —
// the parsing/NFA/DFA logic itself is pure combinatorics, no math needed.
import 'dart:math';
// Pulled in solely for the `Offset` type used when laying nodes out on the
// canvas (NodeData.position, StartArrowData.offset).
import 'package:flutter/material.dart';

// NodeData, LineData, StartArrowData — the graph data types this file
// builds and hands back to the rest of the app.
import 'models.dart';

// ─── Public API ───────────────────────────────────────────────────────────────

/// The result of converting a regex to a graph.
// Single return type shared by both the success and failure paths of
// regexToDfa() below — callers check `isError`/`error` rather than the
// function throwing, so a bad pattern string never crashes the caller.
class RegexConversionResult {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData startArrow;
  // Null on success; holds a human-readable message on failure. Nullability
  // is what `isError` below actually branches on.
  final String? error;

  const RegexConversionResult({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    this.error,
  });

  bool get isError => error != null;
}

/// Converts a simple regex string to an NFA graph (with ~-transitions).
/// Uses Thompson construction followed by ~-pass-through elimination,
/// Converts a simple regex string to a minimal DFA graph (no ~, one symbol per line).
// NOTE: the doc comment immediately above reads like two separate doc
// comments spliced together (one describing an NFA-producing function, one
// describing a DFA-producing function) — likely left over from a rename or
// refactor. What this function actually does, end to end, is the DFA path:
// parse → Thompson-build an NFA → subset-construct a DFA → minimize it →
// emit a graph. There is no separate NFA-emitting function defined in this
// file despite the "NFA → Graph" section header further down and the
// file-header comment's claim that the converter can also produce an NFA
// graph with ~-transitions — that output path isn't implemented here.
RegexConversionResult regexToDfa(String pattern) {
  try {
    // Recursive-descent parse into an AST (see the _RegexParser class and
    // _RegexNode hierarchy below).
    final parser = _RegexParser(pattern);
    final ast = parser.parse();
    // Thompson construction: walks the AST and builds an NFA (as an
    // adjacency-list transition table inside `builder`), returning just the
    // (start, accept) state pair for the whole pattern as `fragment`.
    final builder = _NfaBuilder();
    final fragment = builder.build(ast);
    // Collect alphabet from AST
    // Walks the AST a second, separate time (independent of the NFA build
    // above) purely to gather the set of literal symbols used, since the
    // DFA's alphabet is needed for subset construction and minimization.
    final alphabet = <String>{};
    _collectAlphabet(ast, alphabet);
    // Build NFA transition table, subset-construct DFA, then minimize
    // Bundles the built NFA + its alphabet into one object so the
    // subset-construction step below (_dfaTableToGraph) has everything it
    // needs (epsilonClosure/move helpers + the alphabet to iterate) via a
    // single parameter.
    final nfa = _NfaTable(fragment: fragment, builder: builder, alphabet: alphabet);
    // Does the actual subset construction + minimization + graph-building
    // work; see that function far below for the full pipeline.
    return _dfaTableToGraph(nfa, pattern);
  } catch (e) {
    // Catches parse errors (thrown as plain Exceptions by _RegexParser) as
    // well as anything unexpected further down the pipeline, and turns them
    // into a RegexConversionResult with `error` set rather than letting the
    // exception propagate — so callers can always treat this as a normal
    // return value, never a thrown error. Nodes/lines are returned empty and
    // startArrow points at an empty nodeId since there's no valid graph to
    // describe.
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
// Purely cosmetic: used below to rotate the ring of nodes by a
// pattern-specific angle so two different regexes that happen to minimize
// to the same number of states don't render as visually identical layouts.
double _patternPhase(String s) {
  // 5381 is the traditional djb2 seed constant — arbitrary but conventional.
  int h = 5381;
  for (final unit in s.codeUnits) {
    // Classic djb2 mixing step: h = h*33 + unit, written as a shift-and-add
    // (`(h << 5) + h` == `h * 32 + h` == `h * 33`) for speed. Masked with
    // 0x1FFFFFFF (29 ones) to keep the running hash within a small enough
    // positive range that it can't overflow into a negative int as more
    // characters are folded in.
    h = ((h << 5) + h + unit) & 0x1FFFFFFF; // keep positive, 29-bit
  }
  // Reduce to a 0..9999 bucket, normalize to [0,1), then scale to a full
  // [0, 2π) radian offset for use directly as an angle below.
  return (h % 10000) / 10000.0 * 2 * pi;
}

// Layout constants shared by both NFA and DFA paths.
// Visual diameter used elsewhere (NodeData rendering) — declared here only
// because _kMargin below is derived from it.
const double _kNodeSize  = 100.0;
// Fixed logical canvas dimensions the regex-to-graph layout targets; the
// UI is expected to scale/scroll this to fit the actual screen.
const double _kCanvasW   = 800.0;
const double _kCanvasH   = 600.0;
const double _kMargin    = _kNodeSize / 2 + 30; // 80 px — clears node edge + label room
const double _kMinChord  = 220.0; // min px between adjacent centres — room for label boxes

/// Compute the circle radius for [total] nodes, given a minimum chord
/// distance of [_kMinChord] and the canvas bounds.
double _circleRadius(int total) {
  // Degenerate cases (0 or 1 node) have no meaningful "circle" to lay out
  // on — a single node is simply placed at the canvas center by the caller.
  if (total <= 1) return 0.0;
  // Law-of-sines derivation: for `total` points evenly spaced on a circle
  // of radius R, the chord between adjacent points is 2R·sin(π/total).
  // Solving for R given the minimum desired chord length _kMinChord gives
  // this formula — the smallest radius that keeps adjacent nodes at least
  // _kMinChord apart.
  final minR = (_kMinChord / 2) / sin(pi / total);
  // Largest radius that still keeps every node (plus its margin) within
  // the fixed canvas bounds, independently computed for width and height
  // and then the tighter (smaller) of the two is used.
  final maxR = min(_kCanvasW / 2 - _kMargin, _kCanvasH / 2 - _kMargin);
  // 75 px per node as base — generous but capped by maxR.
  // Prefers a radius that grows with node count (more states -> a bigger
  // ring, up to 75px of "personal space" per node), but never smaller than
  // the chord-clearance minimum (minR) and never larger than what the
  // canvas can physically fit (maxR).
  return min(maxR, max(minR, total * 75.0));
}

// ─── AST ─────────────────────────────────────────────────────────────────────

// Marker base type for every regex AST node kind below — has no members of
// its own; each subclass carries whatever data that node kind needs.
abstract class _RegexNode {}

// A single literal character to match, e.g. the `a` in `ab*`.
class _Literal extends _RegexNode {
  final String ch;
  _Literal(this.ch);
}

// The empty-string pattern — matches with no input consumed. Produced by
// _RegexParser._parseConcat() when it encounters an empty group like `()`,
// and also used as the whole-pattern AST when the input string is blank.
class _Epsilon extends _RegexNode {}

// Sequencing: match `left` immediately followed by `right`. Built implicitly
// (no explicit operator character) by _parseConcat() whenever two atoms
// appear back to back.
class _Concat extends _RegexNode {
  final _RegexNode left;
  final _RegexNode right;
  _Concat(this.left, this.right);
}

// Alternation: match `left` OR `right`. Corresponds to the `+` operator in
// this engine's regex syntax (this app's stand-in for the usual `|`).
class _Union extends _RegexNode {
  final _RegexNode left;
  final _RegexNode right;
  _Union(this.left, this.right);
}

// Kleene star: match `child` zero or more times. Corresponds to the postfix
// `*` operator.
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

// Standard hand-written recursive-descent parser: one method per grammar
// rule above, each consuming characters from `input` via the shared `_pos`
// cursor and returning the AST node for what it just parsed.
class _RegexParser {
  final String input;
  // Cursor into `input`; every _parseX method advances this as it consumes
  // characters, and every method assumes _pos already points at the start
  // of whatever it's about to parse (whitespace-skipped by the caller).
  int _pos = 0;

  _RegexParser(this.input);

  /// Advance [_pos] past any ASCII whitespace characters.
  // Only recognizes literal space (' '), not tabs/newlines — regex patterns
  // in this app are expected to be single-line, typed input, so that's a
  // deliberate simplification rather than an oversight.
  void _skipWhitespace() {
    while (_pos < input.length && input[_pos] == ' ') {
      _pos++;
    }
  }

  // Top-level entry point: parses the whole pattern and verifies nothing
  // is left over afterward (a trailing unparseable character would
  // otherwise be silently ignored).
  _RegexNode parse() {
    _skipWhitespace();
    // Blank/whitespace-only pattern: valid input, matches only the empty
    // string, rather than being treated as a parse error.
    if (_pos >= input.length) return _Epsilon();
    final result = _parseExpr();
    _skipWhitespace();
    // If _parseExpr() didn't consume the entire (trimmed) input, something
    // is left dangling — e.g. an unmatched `)` — and that's a genuine
    // syntax error rather than something to silently drop.
    if (_pos < input.length) {
      throw Exception('Unexpected character at position $_pos: "${input[_pos]}"');
    }
    return result;
  }

  // expr ::= concat ('+' concat)*
  // Lowest-precedence rule: parses one concat, then keeps folding in more
  // concats each time a `+` is found, left-associatively (a+b+c parses as
  // (a+b)+c).
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
  // Middle precedence: repeatedly parses atoms and implicitly concatenates
  // them (no operator character marks concatenation — juxtaposition alone
  // means "and then"), stopping as soon as it sees a `+` (handled one level
  // up by _parseExpr) or a `)` (handled by the enclosing _parseBase call, if
  // any).
  _RegexNode _parseConcat() {
    _RegexNode? node;
    _skipWhitespace();
    while (_pos < input.length && input[_pos] != '+' && input[_pos] != ')') {
      final atom = _parseAtom();
      // First atom becomes the running node as-is; every subsequent atom
      // gets folded in via _Concat(node, atom), building a left-leaning
      // concatenation chain.
      node = node == null ? atom : _Concat(node, atom);
      _skipWhitespace();
    }
    if (node == null) {
      // Empty concat in a context like "()" — treat as tilda
      // Loop body never ran at all (e.g. input was "()" and the ')' was hit
      // immediately) — there's nothing to concatenate, so this position in
      // the pattern matches the empty string.
      return _Epsilon();
    }
    return node;
  }

  // atom ::= base '*'*
  // Highest precedence: parses one base (a literal or a parenthesized
  // sub-expression), then wraps it in as many _Star layers as there are
  // consecutive trailing `*` characters (so `a**` — while redundant — still
  // parses, just as Star(Star(Literal('a')))).
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
      // Reached here with nothing left to consume — can only happen if a
      // caller (_parseAtom) asked for a base without first confirming a
      // character is actually available, e.g. a pattern ending in an
      // operator that expects an operand after it.
      throw Exception('Unexpected end of expression');
    }
    final ch = input[_pos];
    if (ch == '(') {
      _pos++; // consume '('
      _skipWhitespace();
      // Recurses all the way back to the top of the grammar (_parseExpr)
      // to parse whatever's inside the parentheses, allowing arbitrarily
      // nested/full sub-expressions between `(` and `)`.
      final inner = _parseExpr();
      _skipWhitespace();
      if (_pos >= input.length || input[_pos] != ')') {
        throw Exception('Missing closing parenthesis');
      }
      _pos++; // consume ')'
      // Parentheses are purely a grouping construct — they don't add a
      // node of their own to the AST, the inner expression's node is
      // returned directly.
      return inner;
    }
    if (ch == '*' || ch == ')') {
      // A base can never legitimately start with `*` (nothing to
      // star-repeat yet) or `)` (would mean an empty base, which is only
      // valid via the "()" empty-concat path handled in _parseConcat, not
      // here) — so seeing either at this point is a syntax error.
      throw Exception('Unexpected character "$ch" at position $_pos');
    }
    // Every other character (including '+' if it somehow reached here,
    // though in practice _parseConcat's loop condition prevents that) is
    // treated as a literal single-character symbol to match.
    _pos++;
    return _Literal(ch);
  }
}

// ─── Thompson NFA construction ────────────────────────────────────────────────

// Internal sentinel used as the transition "symbol" for an epsilon
// (~ / no-input-consumed) edge. Chosen as the empty string so it can never
// collide with any real literal symbol (which are always exactly one
// character long, per _parseBase above).
const String _kEpsilon = ''; // ~ label

/// An NFA fragment: two state ids (start, accept).
// The classic Thompson-construction building block: every AST node, once
// built, is represented as just this pair of state ids — a single entry
// point and a single exit point — regardless of how much internal
// structure (states/edges) it took to build it. This is what lets build()
// below combine sub-fragments uniformly via epsilon edges.
class _Fragment {
  final int start;
  final int accept;
  const _Fragment(this.start, this.accept);
}

/// Transition: (from state, symbol) → set of to states
// Owns the actual NFA being constructed: allocates fresh integer state ids
// and accumulates the transition table as build() walks the AST.
class _NfaBuilder {
  // Monotonically increasing counter handed out by _newState() below; state
  // ids are just small ints, never reused or renumbered within this class.
  int _nextState = 0;

  // Adjacency list: state → list of (symbol, toState)
  // Record type `({String symbol, int to})` keeps each edge as a tiny
  // anonymous value type rather than a separate named class, since nothing
  // outside this transitions map ever needs to reference the edge shape by
  // name.
  final Map<int, List<({String symbol, int to})>> _transitions = {};

  int _newState() {
    final s = _nextState++;
    // Eagerly seed an empty adjacency list for the new state so later code
    // can always safely index `_transitions[s]` without a null check —
    // though _addTransition below still defensively uses putIfAbsent
    // anyway (belt-and-suspenders, or possibly a state added by a path
    // that bypassed _newState).
    _transitions[s] = [];
    return s;
  }

  void _addTransition(int from, String symbol, int to) {
    _transitions.putIfAbsent(from, () => []).add((symbol: symbol, to: to));
  }

  // Recursively converts one AST node into an NFA fragment (Thompson
  // construction). Each case below mirrors the textbook construction rules
  // for that operator, combining any child fragments purely via epsilon
  // edges — never by merging or renaming states — which keeps the
  // recursion simple at the cost of extra epsilon states that get cleaned
  // up later (see the "NFA → Graph" section comment further down, though
  // note the caveat there about that cleanup path not actually existing in
  // this file).
  _Fragment build(_RegexNode node) {
    if (node is _Epsilon) {
      // Two fresh states joined by a single epsilon edge: matches the
      // empty string and nothing else.
      final s = _newState();
      final a = _newState();
      _addTransition(s, _kEpsilon, a);
      return _Fragment(s, a);
    }
    if (node is _Literal) {
      // Two fresh states joined by an edge labelled with the literal
      // character: matches exactly that one character.
      final s = _newState();
      final a = _newState();
      _addTransition(s, node.ch, a);
      return _Fragment(s, a);
    }
    if (node is _Concat) {
      // Build both sub-fragments independently, then splice them together
      // by epsilon-linking the left fragment's accept state to the right
      // fragment's start state. The combined fragment's own start/accept
      // are simply left.start and right.accept.
      final left = build(node.left);
      final right = build(node.right);
      // Merge left.accept with right.start via ~
      _addTransition(left.accept, _kEpsilon, right.start);
      return _Fragment(left.start, right.accept);
    }
    if (node is _Union) {
      // Classic Thompson union: a new start state epsilon-branches to both
      // sub-fragments' starts, and both sub-fragments' accepts
      // epsilon-converge on a single new accept state.
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
      // Classic Thompson star: new start/accept states bracket the child
      // fragment, with FOUR epsilon edges providing all the needed paths:
      //   s -> child.start        (enter the loop body)
      //   s -> a                  (skip entirely: zero repetitions)
      //   child.accept -> child.start   (repeat: loop back for another pass)
      //   child.accept -> a       (exit after any number of repetitions)
      final s = _newState();
      final a = _newState();
      final child = build(node.child);
      _addTransition(s, _kEpsilon, child.start);
      _addTransition(s, _kEpsilon, a); // zero repetitions
      _addTransition(child.accept, _kEpsilon, child.start); // loop
      _addTransition(child.accept, _kEpsilon, a); // exit
      return _Fragment(s, a);
    }
    // Defensive catch-all: every _RegexNode subclass is handled by one of
    // the branches above, so this only fires if a new AST node type is
    // ever added without updating build() to match.
    throw Exception('Unknown AST node: $node');
  }
}

// ─── NFA → Graph (with ~-transitions for NFA export) ────────────────────────
//
// Thompson construction creates O(|regex|) states, many of which are pure
// ~-pass-throughs with exactly one incoming and one outgoing ~-edge.
// We eliminate those before emitting the graph so the displayed NFA is
// compact (matches hand-drawn style) while still being equivalent.
//
// A state is a "pass-through" if it is NOT the start state, NOT the accept
// state, has NO outgoing non-~ transitions, and has exactly one outgoing
// ~-edge. We short-circuit it by redirecting every edge that pointed TO it
// directly to its ~-successor, then drop the state.  We repeat until stable.


/// For every pair of lines (A→B) and (B→A), offset them in opposite
/// perpendicular directions so they arc away from each other instead of
/// drawing on top of each other.  Self-loops are skipped (they already render
/// as distinct circles).
// NOTE: despite living directly under the "NFA → Graph" section header and
// its description of pass-through elimination above, this is the only
// function actually defined in that section, and it's a purely cosmetic
// post-processing step applied to the *DFA* graph output (called from
// _dfaTableToGraph far below) — not an NFA-graph builder, and it performs
// no pass-through elimination. The pass-through-elimination logic the
// comment block above describes isn't implemented anywhere in this file.
void _assignBidirectionalCurves(Map<String, LineData> lines) {
  // Build a quick lookup: canonical key "min(a,b)__max(a,b)" → list of lines.
  // Groups every non-self-loop line by its unordered node pair, so that a
  // forward edge n1->n2 and a backward edge n2->n1 land in the same bucket
  // regardless of which direction each was created in.
  final Map<String, List<LineData>> byPair = {};
  for (final line in lines.values) {
    if (line.nodeAId == line.nodeBId) continue; // self-loop: skip
    final a = line.nodeAId, b = line.nodeBId;
    // compareTo used purely to get a consistent (order-independent) key —
    // the actual node ids' lexical ordering has no other significance here.
    final key = a.compareTo(b) <= 0 ? '${a}__$b' : '${b}__$a';
    byPair.putIfAbsent(key, () => []).add(line);
  }

  // For each pair that has lines going in both directions, assign opposing curves.
  for (final group in byPair.values) {
    if (group.length < 2) continue; // only one direction — no overlap possible

    // Separate by direction.
    // "Forward" here just means nodeAId <= nodeBId lexically for that
    // particular line, not that it corresponds to any semantic direction —
    // it's only used to split the group into the two direction-buckets
    // being bent apart below.
    final forward  = group.where((l) => l.nodeAId.compareTo(l.nodeBId) <= 0).toList();
    final backward = group.where((l) => l.nodeAId.compareTo(l.nodeBId) >  0).toList();
    if (forward.isEmpty || backward.isEmpty) continue;

    // Assign a modest perpendicular offset.  The sign convention in LineData
    // is that positive perpendicularPart bends the arc to the left when
    // travelling from A to B, negative bends it to the right.
    // NOTE: per the sign-convention comment immediately above, forward and
    // backward should presumably bend in *opposite* directions (+bend vs
    // -bend) so the two arcs visibly separate — but both loops below set
    // `perpendicularPart = bend` (same positive value), so as written this
    // does not actually achieve the "bend away from each other" effect the
    // function's own doc comment promises. Left as-is here since it's
    // existing behavior, not something to silently "fix" while adding
    // comments.
    const double bend = 55.0;
    for (final l in forward)  { l.perpendicularPart =  bend; }
    for (final l in backward) { l.perpendicularPart = bend; }
  }
}

// ─── Subset construction (NFA → DFA) ─────────────────────────────────────────

// Recursively walks the AST collecting every distinct literal character
// used anywhere in the pattern — this becomes the DFA's input alphabet.
// _Epsilon nodes contribute nothing (matching empty string uses no
// symbols).
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

// Bundles the built NFA (via `builder`'s transition table plus `fragment`'s
// overall start/accept pair) with its alphabet, and provides the two
// standard subset-construction primitives (epsilonClosure, move) that
// _dfaTableToGraph's worklist algorithm needs.
class _NfaTable {
  final _Fragment fragment;
  final _NfaBuilder builder;
  final Set<String> alphabet;

  _NfaTable({
    required this.fragment,
    required this.builder,
    required this.alphabet,
  });

  /// Compute ~-closure of a set of NFA states.
  // Standard worklist-based epsilon-closure: starts from `states`, and
  // repeatedly follows any not-yet-visited epsilon edge, adding its
  // destination to both the result set and the worklist, until no more new
  // states are reachable purely via epsilon edges.
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
  // Simple one-hop lookup (no epsilon-following here — that's layered on
  // separately by the caller via epsilonClosure(move(...))): for every
  // state in `states`, collect every state reachable by exactly one edge
  // labelled `symbol`.
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
// Plain data holder for _minimizeDfa's output — deliberately mirrors the
// shape of its inputs (numStates/acceptStates/transitions) but with
// everything renumbered/compacted after minimization, plus a concrete
// startState field since minimization can change which index the start
// state ends up at.
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
  // Subset construction (in _dfaTableToGraph below) only records
  // transitions that actually go somewhere — a DFA state with no outgoing
  // edge for some symbol simply has no entry in rawTransitions for that
  // (state, symbol) pair. Minimization algorithms need every state to have
  // a defined transition for every symbol, though, so a single synthetic
  // "dead" state is added here to stand in for every such missing
  // transition (see `trans()` below) — conceptually the implicit reject
  // state every incomplete DFA has.
  final int deadState = numStates;
  final int totalStates = numStates + 1; // include dead

  // Transition helper used throughout minimization: the dead state
  // self-loops on every symbol (once dead, always dead), and any other
  // state either has a real recorded transition or implicitly goes to
  // deadState.
  int trans(int state, String sym) {
    if (state == deadState) return deadState;
    return rawTransitions['${state}__$sym'] ?? deadState;
  }

  // Initial partition: {accept states} ∪ {dead + non-accept states}
  // (dead is non-accepting by construction)
  // Moore's algorithm always starts from the coarsest correct partition:
  // accepting vs. non-accepting, since no two states in different halves
  // of that split could ever be equivalent (they'd disagree on the empty
  // string itself). deadState is included in totalStates' range and, since
  // it was never added to acceptStates, naturally falls into nonAccept.
  final Set<int> nonAccept = {};
  for (int i = 0; i < totalStates; i++) {
    if (!acceptStates.contains(i)) nonAccept.add(i);
  }

  // Partitions as a list of sets; use index into this list as partition id.
  // Either half could in principle be empty (e.g. a pattern with no accept
  // states at all is degenerate, or, more commonly, if literally every
  // state is accepting) — both are guarded against before adding, since an
  // empty partition would be meaningless.
  final List<Set<int>> partitions = [];
  if (acceptStates.isNotEmpty) partitions.add(Set.of(acceptStates));
  if (nonAccept.isNotEmpty) partitions.add(nonAccept);

  // state → partition index
  // Inverse index of `partitions`, rebuilt from scratch after every
  // refinement round (see rebuildPartOf below) — needed so the refinement
  // step can cheaply ask "what partition is state X's transition target
  // currently in?" without linearly scanning `partitions` each time.
  List<int> partOf = List.filled(totalStates, 0);
  void rebuildPartOf() {
    for (int p = 0; p < partitions.length; p++) {
      for (final s in partitions[p]) {
        partOf[s] = p;
      }
    }
  }

  rebuildPartOf();

  // Main refinement loop: keep splitting partitions until a full pass makes
  // no changes (fixed point reached), which is when the partitions exactly
  // correspond to the Myhill-Nerode equivalence classes of the DFA's
  // states.
  bool changed = true;
  while (changed) {
    changed = false;
    final List<Set<int>> newPartitions = [];

    for (final part in partitions) {
      // A singleton partition can never be split further (there's nothing
      // else in it to distinguish it from) — skip straight to keeping it
      // as-is, both as an optimization and because the signature-grouping
      // logic below would be pointless work for a single state.
      if (part.length <= 1) {
        newPartitions.add(part);
        continue;
      }

      // Split part: group states by their transition signature.
      // Signature = tuple of partOf[trans(s, a)] for each a in alphabet.
      // Two states belong together in the refined partition only if, for
      // EVERY symbol in the alphabet, they transition into the same
      // (current-round) partition. The signature string here is exactly
      // that tuple, comma-joined, used as a Map key so states with
      // identical signatures land in the same group.
      final Map<String, Set<int>> groups = {};
      for (final s in part) {
        final sig = alphabet.map((a) => partOf[trans(s, a)].toString()).join(',');
        groups.putIfAbsent(sig, () => {}).add(s);
      }

      // If a partition actually split into more than one signature group,
      // the overall algorithm hasn't converged yet and needs another pass
      // (since this round's split could enable further splits elsewhere
      // next round, now that partOf reflects the new, finer partitioning).
      if (groups.length > 1) changed = true;
      newPartitions.addAll(groups.values);
    }

    // Replace `partitions` in place (rather than reassigning the variable)
    // since it's captured by reference elsewhere in this closure-heavy
    // function; ..clear()/..addAll() cascade keeps it the same List
    // instance.
    partitions
      ..clear()
      ..addAll(newPartitions);
    rebuildPartOf();
  }

  // Find which partition contains the start state and the dead state.
  final int startPartition = partOf[startState];
  final int deadPartition = partOf[deadState];

  // Renumber: start partition → 0, then others in order (skip dead partition).
  // The caller (and the rest of the app) expects state 0 to be the DFA's
  // start state, so the start partition is explicitly placed first; every
  // other surviving partition (i.e. every one except the dead-state's, which
  // is dropped entirely — see the transition-building loop below, which
  // omits any edge that would point into the dead partition) follows in
  // whatever order `partitions` happens to hold them.
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
    // The dead partition is never a real, emitted state in the minimized
    // result (it represents "no transition"/implicit reject, which the
    // graph format expresses by simply omitting an edge rather than
    // pointing at an explicit dead node) — so it's excluded here even
    // though it wouldn't be in newAccept anyway (dead states are never
    // accepting).
    if (p == deadPartition) continue;
    final newIdx = partToNew[p]!;
    // A merged partition is accepting overall if ANY of the original DFA
    // states folded into it was accepting — by construction of the initial
    // accept/non-accept split and the fact that refinement only ever
    // splits (never merges across) that initial boundary, every state
    // within one partition is guaranteed to agree on accept-status anyway,
    // so `.any(...)` here is equivalent to checking just one representative
    // state, just written more defensively.
    if (partitions[p].any((s) => acceptStates.contains(s))) {
      newAccept.add(newIdx);
    }
  }

  // Build new transition table (skip dead-state targets — caller treats missing = dead/reject).
  final Map<String, int> newTrans = {};
  for (final p in order) {
    // Every state within a partition is transition-equivalent to every
    // other by construction (that's what makes them one partition), so it
    // suffices to compute outgoing transitions from just one arbitrary
    // representative member (`.first`) rather than every member.
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
    // Always 0 by construction: startPartition was placed first in `order`
    // above, and partToNew maps order[0] to new index 0.
    startState: 0,
  );
}

// Orchestrates the full NFA -> DFA pipeline and produces the renderable
// graph: subset construction, then minimization, then translating the
// minimized DFA into NodeData/LineData with a concrete on-canvas layout.
RegexConversionResult _dfaTableToGraph(_NfaTable nfa, String pattern) {
  // ── Step 1: Subset construction ──────────────────────────────────────────
  // Standard worklist-based subset construction. Each DFA state is a SET of
  // NFA states (its epsilon-closure); `dfaStates` holds them in creation
  // order, `dfaStateIndex` maps a canonical string key for a set back to its
  // index so previously-seen state-sets are recognized and reused instead
  // of duplicated.
  final startSet = nfa.epsilonClosure({nfa.fragment.start});
  final dfaStates = <Set<int>>[]; // ordered list of DFA states (sets of NFA states)
  final dfaStateIndex = <String, int>{}; // canonical key → dfa state index
  final dfaTransitions = <({int from, String symbol, int to})>[];

  // Canonical string key for a set of NFA state ids: sorted then
  // comma-joined, so two sets with the same members always produce the
  // same key regardless of iteration/insertion order.
  String key(Set<int> s) => (s.toList()..sort()).join(',');

  dfaStates.add(startSet);
  dfaStateIndex[key(startSet)] = 0;
  // Worklist of DFA state indices still needing their outgoing transitions
  // computed; seeded with just the start state (index 0).
  final worklist = [0];

  while (worklist.isNotEmpty) {
    // Order of processing (LIFO via removeLast) doesn't affect correctness
    // here — DFA states end up the same regardless of visit order, only
    // dfaStates' index assignment order could differ, and nothing depends
    // on that order being any particular thing.
    final idx = worklist.removeLast();
    final current = dfaStates[idx];

    for (final symbol in nfa.alphabet) {
      // One-hop NFA move, then epsilon-close the result — together this is
      // exactly what it means for the corresponding DFA state to consume
      // `symbol`.
      final moved = nfa.move(current, symbol);
      // An empty result means no NFA state in `current` had an outgoing
      // edge on `symbol` — i.e. this DFA state has no transition for this
      // symbol at all (implicitly the dead state), so nothing is recorded.
      if (moved.isEmpty) continue;
      final closed = nfa.epsilonClosure(moved);
      final k = key(closed);
      int toIdx;
      if (dfaStateIndex.containsKey(k)) {
        // This exact set of NFA states has been seen before as some other
        // DFA state — reuse its index rather than creating a duplicate.
        toIdx = dfaStateIndex[k]!;
      } else {
        // Brand-new DFA state: allocate the next index, record it, and
        // queue it up so its own outgoing transitions get computed later.
        toIdx = dfaStates.length;
        dfaStates.add(closed);
        dfaStateIndex[k] = toIdx;
        worklist.add(toIdx);
      }
      dfaTransitions.add((from: idx, symbol: symbol, to: toIdx));
    }
  }

  // Determine accept states from subset construction
  // A DFA state (= a set of NFA states) is accepting if that set contains
  // the NFA's single overall accept state (nfa.fragment.accept) — standard
  // subset-construction accept-state rule.
  final rawAcceptStates = <int>{};
  for (int i = 0; i < dfaStates.length; i++) {
    if (dfaStates[i].contains(nfa.fragment.accept)) {
      rawAcceptStates.add(i);
    }
  }

  // ── Step 2: Build raw transition map for minimizer ────────────────────────
  // Flattens the list-of-records `dfaTransitions` into the
  // '${from}__${symbol}' -> to map shape _minimizeDfa expects (matching the
  // same key convention used by `trans()`/rawTransitions inside
  // _minimizeDfa above).
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
  // Monotonically increasing counter used to mint unique line ids
  // ('l0', 'l1', ...) below — separate from any DFA/NFA state numbering.
  int lineCounter = 0;

  final total = minDfa.numStates;

  // Layout: same scheme as the NFA path — deterministic phase from the regex
  // string hash, shared spacing constants, on-canvas clamping.
  final double radius      = _circleRadius(total);
  // Rotates the whole ring by a hash-derived angle so different patterns
  // don't all render with, say, state 0 always at the very top — purely
  // cosmetic variety, see _patternPhase's doc comment above.
  final double phaseOffset = _patternPhase(pattern);
  final center             = const Offset(_kCanvasW / 2, _kCanvasH / 2);

  for (int i = 0; i < total; i++) {
    // Evenly spaces `total` points around the circle (2π * i / total), with
    // a base -π/2 rotation so state 0 starts at the top (screen coordinates:
    // angle 0 = +x/right, so -π/2 = straight up) before phaseOffset further
    // rotates the whole ring.
    final angle = (2 * pi * i / total) - pi / 2 + phaseOffset;
    final cx = center.dx + cos(angle) * radius;
    final cy = center.dy + sin(angle) * radius;

    // Clamp each computed center into the canvas bounds (minus margin) as
    // a safety net — normally unnecessary given _circleRadius already
    // bounds `radius` by maxR, but guards against any edge-case geometry
    // (e.g. total <= 1, where radius is 0 and center is used directly)
    // pushing a node outside the visible area.
    final x = cx.clamp(_kMargin, _kCanvasW - _kMargin);
    final y = cy.clamp(_kMargin, _kCanvasH - _kMargin);

    final id = 'n$i';
    nodes[id] = NodeData(
      id: id,
      // NodeData.position is presumably the node's top-left corner (not
      // its center), hence subtracting the 50px half-width/half-height
      // (half of _kNodeSize=100) to convert the computed center point
      // (x, y) into a top-left position.
      position: Offset(x - 50, y - 50),
      label: 'q$i',
      isAccept: minDfa.acceptStates.contains(i),
    );
  }

  // Group transitions by (from, to) so we can merge symbols onto one line
  // A minimized DFA can have multiple symbols all transitioning between the
  // same pair of states (e.g. both '0' and '1' going n0 -> n1) — rather
  // than drawing a separate overlapping line per symbol, this groups them
  // so a single LineData can carry a combined "0,1" label.
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
    // Ensures the same minimized DFA always renders the same label text
    // (e.g. always "0,1" never sometimes "1,0"), independent of whatever
    // order the symbols happened to be inserted into edgeSymbols above.
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
    // Registers this line on both endpoint nodes' connectedLineIds so the
    // rendering layer can find every line touching a given node without a
    // separate lookup pass. `?.` guards against a stray/unexpected missing
    // node id, though in practice fromId/toId are always drawn from the
    // node ids just created in the loop above.
    nodes[fromId]?.connectedLineIds.add(lid);
    nodes[toId]?.connectedLineIds.add(lid);
  }

  // Bend bidirectional pairs so they don't overlap each other.
  _assignBidirectionalCurves(lines);

  // Fixed convention: the minimized DFA's start state is always renumbered
  // to 0 (see _minimizeDfa's startState: 0 above), so the start arrow
  // always points at node 'n0'; offset/length position the arrow visually
  // to the left of the node, pointing into it.
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