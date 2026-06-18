// ─────────────────────────────────────────────────────────────────────────────
//  fa_to_regex.dart
//
//  Converts an NFA or DFA (described as NodeData / LineData maps + a start
//  arrow) to an equivalent regular expression using the state-elimination
//  (GNFA) algorithm:
//
//    1. Build a Generalised NFA (GNFA) with a single new start state and a
//       single new accept state, connected with ε-transitions as required.
//    2. Eliminate states one by one (avoiding the new start / accept).
//       When eliminating state q, for every pair (p, r) with p→q and q→r,
//       add a direct p→r edge whose label is:
//           R(p,q) · R(q,q)* · R(q,r)
//       combined (via union "+") with any existing R(p,r) label.
//    3. After all intermediate states are gone, the single remaining edge
//       from new-start to new-accept IS the regular expression.
//
//  Notation used in the output regex:
//    ~       epsilon (empty string)
//    +       alternation  (a + b  means  a | b)
//    (...)   grouping
//    *       Kleene star (postfix)
//    ·       concatenation (implicit — no symbol emitted)
//
//  The output uses the same operator set that regex_engine.dart parses, so
//  the result can be pasted straight into the Regex Panel and round-tripped.
//
//  Limitations:
//   • Only works for NFA/DFA (AutomataMode.ndfa / .regex).  PDA and TM are
//     not regular and will return an error string.
//   • The resulting expression is correct but not always minimal; the
//     simplification pass handles the most common cases (unit epsilons,
//     dead-branch removal) without full algebraic simplification.
// ─────────────────────────────────────────────────────────────────────────────

import 'models.dart';

// ─── Public API ───────────────────────────────────────────────────────────────

/// Result returned by [faToRegex].
class FaToRegexResult {
  /// The regular expression string, or `null` if conversion failed.
  final String? regex;

  /// Human-readable error message, or `null` on success.
  final String? error;

  const FaToRegexResult.ok(String r)
      : regex = r,
        error = null;

  const FaToRegexResult.err(String e)
      : regex = null,
        error = e;

  bool get isError => error != null;
}

/// Converts the automaton described by [nodes], [lines], and [startArrow]
/// to a regular expression via state elimination.
FaToRegexResult faToRegex({
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? startArrow,
}) {
  // ── Validation ────────────────────────────────────────────────────────────
  if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
    return const FaToRegexResult.err(
        'No start state defined. Add a start arrow (▶) and try again.');
  }
  if (nodes.isEmpty) {
    return const FaToRegexResult.err('The automaton has no states.');
  }

  final acceptIds = nodes.values.where((n) => n.isAccept).map((n) => n.id).toSet();
  if (acceptIds.isEmpty) {
    // An automaton with no accept states accepts the empty language ∅.
    return const FaToRegexResult.ok('∅');
  }

  // ── Build GNFA transition table ───────────────────────────────────────────
  //
  // We use string-keyed maps: gnfa[from][to] = regex-label (String | null).
  // null means no transition (effectively ∅).
  //
  // Special node ids for the new super-start and super-accept:
  const String superStart  = '__S__';
  const String superAccept = '__A__';

  // Collect all original state ids.
  final states = nodes.keys.toSet();

  // gnfa[from][to] = label string (null = no edge).
  final Map<String, Map<String, String?>> gnfa = {};

  void ensureRow(String s) => gnfa.putIfAbsent(s, () => {});

  // Initialise rows for all states + super nodes.
  for (final s in states) ensureRow(s);
  ensureRow(superStart);
  ensureRow(superAccept);

  // Helper: combine two nullable regex labels with union (+).
  String? unionLabels(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a == b) return a;
    return '${_wrap(a)}+${_wrap(b)}';
  }

  // ε as used in labels coming from the line data ('~' means epsilon here).
  const String eps = '~';

  // Fill in transitions from the original NFA/DFA.
  for (final line in lines.values) {
    final from = line.nodeAId;
    final to   = line.nodeBId;
    if (!states.contains(from) || !states.contains(to)) continue;

    // A line label may contain multiple alternatives separated by commas or
    // newlines (as used by the multi-transition display).  Each alternative
    // is treated as a separate symbol in the regex union.
    final alts = line.label
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    String? edgeLabel;
    if (alts.isEmpty) {
      edgeLabel = eps;
    } else {
      // Build union of all alternatives.
      edgeLabel = alts.map((a) => a.isEmpty ? eps : a).reduce(
          (acc, s) => unionLabels(acc, s)!);
    }

    gnfa[from]![to] = unionLabels(gnfa[from]![to], edgeLabel);
  }

  // Super-start → original start state via ε.
  gnfa[superStart]![startArrow.nodeId] = eps;

  // All original accept states → super-accept via ε.
  for (final aId in acceptIds) {
    gnfa[aId]![superAccept] = eps;
  }

  // ── State elimination ─────────────────────────────────────────────────────
  //
  // We will eliminate all original states, leaving only superStart and
  // superAccept.  We eliminate in an order that heuristically keeps the
  // intermediate expressions small: states with fewer in×out products first.

  final toEliminate = states.toList();

  // Heuristic order: fewest (in-degree × out-degree) first.
  toEliminate.sort((a, b) {
    int inOut(String s) {
      int inDeg  = gnfa.values.where((row) => row[s] != null).length;
      int outDeg = gnfa[s]!.values.where((v) => v != null).length;
      return inDeg * outDeg;
    }
    return inOut(a).compareTo(inOut(b));
  });

  for (final elim in toEliminate) {
    // Self-loop label on the state being eliminated.
    final selfLabel = gnfa[elim]![elim]; // may be null

    // For every (pred → elim) edge and (elim → succ) edge, add a shortcut.
    final preds = gnfa.keys
        .where((p) => p != elim && gnfa[p]![elim] != null)
        .toList();
    final succs = gnfa[elim]!.keys
        .where((s) => s != elim && gnfa[elim]![s] != null)
        .toList();

    for (final pred in preds) {
      for (final succ in succs) {
        final rPQ = gnfa[pred]![elim]!;   // pred → elim
        final rQR = gnfa[elim]![succ]!;   // elim → succ

        // New path: rPQ · selfLabel* · rQR
        final middle = selfLabel != null
            ? '${_wrapStar(_wrapStar(selfLabel))}*'
            : '';
        final newPath = _concat(_concat(rPQ, middle), rQR);

        ensureRow(pred);
        gnfa[pred]![succ] = unionLabels(gnfa[pred]![succ], newPath);
      }
    }

    // Remove the eliminated state from the gnfa.
    gnfa.remove(elim);
    for (final row in gnfa.values) {
      row.remove(elim);
    }
  }

  // ── Extract the final regex ───────────────────────────────────────────────
  final result = gnfa[superStart]?[superAccept];

  if (result == null) {
    // No path from start to any accept state → empty language.
    return const FaToRegexResult.ok('∅');
  }

  final simplified = _simplify(result);
  return FaToRegexResult.ok(simplified);
}

// ─── Regex string helpers ─────────────────────────────────────────────────────

/// Wraps [r] in parentheses iff it contains a top-level '+' operator,
/// so it can safely be used as an atom in concatenation.
String _wrap(String r) {
  if (_hasTopLevelUnion(r)) return '($r)';
  return r;
}

/// Wraps [r] for use under a Kleene star:
///   • single char or already-parenthesised → as is
///   • otherwise wrap in parens
String _wrapStar(String r) {
  if (r.isEmpty) return r;
  if (r.length == 1) return r;
  if (r.startsWith('(') && _matchingClose(r, 0) == r.length - 1) return r;
  return '($r)';
}

/// Concatenates two regex strings, omitting epsilon (ε / '~') identities.
String _concat(String left, String right) {
  final l = left.trim();
  final r = right.trim();
  if (l.isEmpty || l == '~') return r.isEmpty ? '~' : r;
  if (r.isEmpty || r == '~') return l;
  return '$l$r';
}

/// Returns true iff [r] contains a '+' that is not inside parentheses.
bool _hasTopLevelUnion(String r) {
  int depth = 0;
  for (int i = 0; i < r.length; i++) {
    final c = r[i];
    if (c == '(') depth++;
    else if (c == ')') depth--;
    else if (c == '+' && depth == 0) return true;
  }
  return false;
}

/// Returns the index of the ')' that closes the '(' at [start], or -1.
int _matchingClose(String r, int start) {
  int depth = 0;
  for (int i = start; i < r.length; i++) {
    if (r[i] == '(') depth++;
    else if (r[i] == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

// ─── Simplification pass ──────────────────────────────────────────────────────
//
// Applies rewriting rules bottom-up to reduce common noise patterns:
//   (~)* → ~           (epsilon-star is epsilon)
//   (∅)*  → ~          (empty-language star is epsilon)
//   ∅ in a union  → drop it
//   ~~ or ~ in concat → collapse
//   ((r)) → (r)        (double wrapping)
//   (r) where r is a single char → r

String _simplify(String r) {
  String prev;
  // Iterate until stable (at most a few passes in practice).
  for (int pass = 0; pass < 8; pass++) {
    prev = r;
    r = _simplifyOnce(r);
    if (r == prev) break;
  }
  return r;
}

String _simplifyOnce(String r) {
  if (r.isEmpty) return r;

  // ── (~)* → ~  and  (∅)* → ~ ───────────────────────────────────────────
  r = r.replaceAll('(~)*', '~');
  r = r.replaceAll('~*', '~');
  r = r.replaceAll('(∅)*', '~');
  r = r.replaceAll('∅*', '~');

  // ── Remove ∅ from unions  (∅+r → r, r+∅ → r) ─────────────────────────
  // Simple string replacements for the common patterns generated by the
  // elimination loop.
  r = r.replaceAll('∅+', '');
  r = r.replaceAll('+∅', '');
  r = r.replaceAll('(∅)', '∅');

  // ── Collapse double-parens: ((x)) → (x) ───────────────────────────────
  final doubleParens = RegExp(r'\(\(([^()]*)\)\)');
  r = r.replaceAllMapped(doubleParens, (m) => '(${m.group(1)})');

  // ── Unwrap singleton parens: (x) → x for single characters ───────────
  final singleParens = RegExp(r'\((.)\)');
  r = r.replaceAllMapped(singleParens, (m) => m.group(1)!);

  // ── Collapse epsilon concatenations: ~x → x, x~ → x ──────────────────
  // _collapseEpsilonConcat handles this carefully (only drops ~ when it
  // is not the entire expression and not followed by *).
  r = _collapseEpsilonConcat(r);

  // ── Collapse (r)* where r is a single char already starred: (a*)* → a* ─
  final redundantStar = RegExp(r'\(([a-zA-Z0-9~])\*\)\*');
  r = r.replaceAllMapped(redundantStar, (m) => '${m.group(1)}*');

  return r;
}

/// Removes standalone '~' that appear in concatenation context
/// (i.e. '~' followed or preceded by a non-operator character or '(').
String _collapseEpsilonConcat(String r) {
  // Remove ~ that is followed by a non-star, non-plus, non-close-paren char.
  // Keep ~ when it is the entire expression.
  if (r == '~') return r;
  // Repeatedly collapse.
  String prev;
  do {
    prev = r;
    // ~X → X  (where X is not *, +, or end)
    r = r.replaceAllMapped(
      RegExp(r'~(?=[^*+\)])'),
      (m) => '',
    );
    // X~ → X  (where X is not +, or beginning)
    r = r.replaceAllMapped(
      RegExp(r'(?<=[^+\(])~'),
      (m) => '',
    );
  } while (r != prev);
  return r.isEmpty ? '~' : r;
}