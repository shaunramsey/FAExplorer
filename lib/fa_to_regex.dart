// ─────────────────────────────────────────────────────────────────────────────
//  fa_to_regex.dart
//
//  Converts an NFA or DFA to an equivalent regular expression using the
//  state-elimination (GNFA) algorithm, operating on a proper regex AST
//  throughout so that simplification is structural rather than string-based.
//
//  Notation used in the output string:
//    ~       epsilon (empty string)
//    +       alternation  (a + b  means  a | b)
//    (...)   grouping
//    *       Kleene star (postfix)
//    ∅       empty language (no strings accepted)
//
//  The output uses the same operator set that regex_engine.dart parses.
// ─────────────────────────────────────────────────────────────────────────────

import 'models.dart';

// ─── Public API ───────────────────────────────────────────────────────────────

class FaToRegexResult {
  final String? regex;
  final String? error;

  const FaToRegexResult.ok(String r) : regex = r, error = null;
  const FaToRegexResult.err(String e) : regex = null, error = e;

  bool get isError => error != null;
}

FaToRegexResult faToRegex({
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? startArrow,
}) {
  if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
    return const FaToRegexResult.err(
        'No start state defined. Add a start arrow (▶) and try again.');
  }
  if (nodes.isEmpty) {
    return const FaToRegexResult.err('The automaton has no states.');
  }

  final acceptIds =
      nodes.values.where((n) => n.isAccept).map((n) => n.id).toSet();
  if (acceptIds.isEmpty) {
    return const FaToRegexResult.ok('∅');
  }

  // ── Build GNFA as AST-valued transition table ─────────────────────────────
  const String superStart  = '__S__';
  const String superAccept = '__A__';

  final allStates = nodes.keys.toSet();

  // gnfa[from][to] = _RE node (null = ∅ / no edge)
  final Map<String, Map<String, _RE?>> gnfa = {};

  void ensureRow(String s) => gnfa.putIfAbsent(s, () => {});
  for (final s in allStates) ensureRow(s);
  ensureRow(superStart);
  ensureRow(superAccept);

  // Fill transitions from the original automaton edges.
  for (final line in lines.values) {
    final from = line.nodeAId;
    final to   = line.nodeBId;
    if (!allStates.contains(from) || !allStates.contains(to)) continue;

    final alts = line.label
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    _RE? edgeRe;
    if (alts.isEmpty) {
      edgeRe = const _Eps();
    } else {
      for (final sym in alts) {
        final atom = sym == '~' ? const _Eps() : _Lit(sym);
        edgeRe = edgeRe == null ? atom : _union(edgeRe, atom);
      }
    }

    gnfa[from]![to] = _union(gnfa[from]![to], edgeRe);
  }

  // Super-start → original start via ε.
  gnfa[superStart]![startArrow.nodeId] = const _Eps();

  // All accept states → super-accept via ε.
  for (final aId in acceptIds) {
    gnfa[aId]![superAccept] = _union(gnfa[aId]![superAccept], const _Eps());
  }

  // ── State elimination ─────────────────────────────────────────────────────
  final toEliminate = allStates.toList();

  // Re-score and pick the best state to eliminate each round (greedy).
  // Score = sum of string lengths of the new edges that would be created,
  // minus the edges that would be removed.  Lower is better.
  int _score(String q) {
    final preds = gnfa.keys
        .where((p) => p != q && (gnfa[p]?[q]) != null)
        .toList();
    final succs = (gnfa[q] ?? {})
        .entries
        .where((e) => e.key != q && e.value != null)
        .map((e) => e.key)
        .toList();
    final self = gnfa[q]?[q];

    int cost = 0;
    for (final p in preds) {
      for (final s in succs) {
        final rPQ = gnfa[p]![q]!;
        final rQR = gnfa[q]![s]!;
        final newEdge = _seq(rPQ, _seq(self != null ? _star(self) : null, rQR));
        final existing = gnfa[p]?[s];
        final merged = _union(existing, newEdge);
        cost += _size(merged) - _size(existing);
      }
    }
    return cost;
  }

  final remaining = toEliminate.toSet();

  while (remaining.isNotEmpty) {
    // Pick the state with minimum elimination cost.
    String best = remaining.first;
    int bestScore = _score(best);
    for (final q in remaining) {
      final s = _score(q);
      if (s < bestScore) {
        bestScore = s;
        best = q;
      }
    }

    final elim = best;
    remaining.remove(elim);

    final selfLabel = gnfa[elim]?[elim];

    final preds = gnfa.keys
        .where((p) => p != elim && (gnfa[p]?[elim]) != null)
        .toList();
    final succs = (gnfa[elim] ?? {})
        .entries
        .where((e) => e.key != elim && e.value != null)
        .map((e) => e.key)
        .toList();

    for (final pred in preds) {
      for (final succ in succs) {
        final rPQ = gnfa[pred]![elim]!;
        final rQR = gnfa[elim]![succ]!;
        final middle = selfLabel != null ? _star(selfLabel) : null;
        final newPath = _seq(rPQ, _seq(middle, rQR));
        ensureRow(pred);
        gnfa[pred]![succ] = _union(gnfa[pred]![succ], newPath);
      }
    }

    gnfa.remove(elim);
    for (final row in gnfa.values) {
      row.remove(elim);
    }
  }

  final result = gnfa[superStart]?[superAccept];
  if (result == null) return const FaToRegexResult.ok('∅');

  return FaToRegexResult.ok(_print(result));
}

// ─── Regex AST ────────────────────────────────────────────────────────────────

abstract class _RE {
  const _RE();
}

/// Empty language ∅ — never matches anything.
class _Empty extends _RE {
  const _Empty();
}

/// Epsilon ~ — matches the empty string.
class _Eps extends _RE {
  const _Eps();
}

/// Literal symbol (single character or multi-char token like "ab").
class _Lit extends _RE {
  final String sym;
  const _Lit(this.sym);
}

/// Alternation: left + right.
class _Union extends _RE {
  final _RE left;
  final _RE right;
  const _Union(this.left, this.right);
}

/// Concatenation: left · right.
class _Cat extends _RE {
  final _RE left;
  final _RE right;
  const _Cat(this.left, this.right);
}

/// Kleene star: child*.
class _Star extends _RE {
  final _RE child;
  const _Star(this.child);
}

// ─── Smart constructors (simplify on build) ───────────────────────────────────

/// Union of two nullable REs (null = ∅).
_RE? _union(_RE? a, _RE? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _unionNN(a, b);
}

_RE _unionNN(_RE a, _RE b) {
  // ∅ identity
  if (a is _Empty) return b;
  if (b is _Empty) return a;

  // Idempotence: a + a → a
  if (_eq(a, b)) return a;

  // r + r* → r*  and  r* + r → r*
  if (b is _Star && _eq(a, b.child)) return b;
  if (a is _Star && _eq(b, a.child)) return a;

  // r* + ~ → r*  and  ~ + r* → r*  (star already includes epsilon)
  if (a is _Star && b is _Eps) return a;
  if (b is _Star && a is _Eps) return b;

  // Flatten nested unions for deduplication:
  // collect all arms, deduplicate, rebuild.
  final arms = <_RE>[];
  void collectArms(_RE r) {
    if (r is _Union) {
      collectArms(r.left);
      collectArms(r.right);
    } else {
      // Only add if not already present.
      if (!arms.any((x) => _eq(x, r))) arms.add(r);
    }
  }
  collectArms(a);
  // Add arms from b that aren't already in the list.
  void collectNewArms(_RE r) {
    if (r is _Union) {
      collectNewArms(r.left);
      collectNewArms(r.right);
    } else {
      if (!arms.any((x) => _eq(x, r))) arms.add(r);
    }
  }
  collectNewArms(b);

  // Apply r + r* → r* reduction on the flat list.
  final reduced = <_RE>[];
  for (final arm in arms) {
    // If a star of this arm is already in the list, skip this arm.
    if (reduced.any((x) => x is _Star && _eq(x.child, arm))) continue;
    // If this is a star and its child is in the list, replace the child.
    if (arm is _Star) {
      reduced.removeWhere((x) => _eq(x, arm.child));
    }
    // If ~ and a star is present, skip ~.
    if (arm is _Eps && reduced.any((x) => x is _Star)) continue;
    reduced.add(arm);
  }

  if (reduced.isEmpty) return const _Empty();
  return reduced.reduce((acc, r) => _Union(acc, r));
}

/// Sequence (concatenation) of two nullable REs (null = identity/skip).
_RE? _seq(_RE? a, _RE? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _seqNN(a, b);
}

_RE _seqNN(_RE a, _RE b) {
  // ∅ annihilates
  if (a is _Empty || b is _Empty) return const _Empty();
  // ε identity
  if (a is _Eps) return b;
  if (b is _Eps) return a;
  return _Cat(a, b);
}

/// Kleene star.
_RE _star(_RE r) {
  if (r is _Empty) return const _Eps(); // ∅* = ε
  if (r is _Eps)   return const _Eps(); // ε* = ε
  if (r is _Star)  return r;            // (r*)* = r*
  // (r+ε)* → r*   (adding ε inside a star is redundant)
  if (r is _Union) {
    final withoutEps = _removeEpsFromUnion(r);
    if (withoutEps != null && !_eq(withoutEps, r)) return _star(withoutEps);
  }
  return _Star(r);
}

/// Remove ε arms from a union; returns null if the whole union collapses.
_RE? _removeEpsFromUnion(_RE r) {
  if (r is _Eps) return null;
  if (r is _Union) {
    final l = _removeEpsFromUnion(r.left);
    final rr = _removeEpsFromUnion(r.right);
    if (l == null) return rr;
    if (rr == null) return l;
    return _Union(l, rr);
  }
  return r;
}

// ─── Structural equality ──────────────────────────────────────────────────────

bool _eq(_RE a, _RE b) {
  if (identical(a, b)) return true;
  if (a is _Empty && b is _Empty) return true;
  if (a is _Eps   && b is _Eps)   return true;
  if (a is _Lit   && b is _Lit)   return a.sym == b.sym;
  if (a is _Star  && b is _Star)  return _eq(a.child, b.child);
  if (a is _Cat   && b is _Cat)   return _eq(a.left, b.left) && _eq(a.right, b.right);
  if (a is _Union && b is _Union) return _eq(a.left, b.left) && _eq(a.right, b.right);
  return false;
}

// ─── AST size (used for elimination ordering) ─────────────────────────────────

int _size(_RE? r) {
  if (r == null) return 0;
  if (r is _Empty || r is _Eps || r is _Lit) return 1;
  if (r is _Star)  return 1 + _size(r.child);
  if (r is _Cat)   return _size(r.left) + _size(r.right);
  if (r is _Union) return _size((r as _Union).left) + _size(r.right);
  return 1;
}

// ─── Pretty-printer ───────────────────────────────────────────────────────────

/// Converts an AST node to the string syntax understood by regex_engine.dart.
String _print(_RE r) {
  return _printPrec(r, 0);
}

/// [prec] context: 0 = top/union, 1 = concat, 2 = atom (under star)
String _printPrec(_RE r, int prec) {
  if (r is _Empty) return '∅';
  if (r is _Eps)   return '~';
  if (r is _Lit)   return r.sym.length == 1 ? r.sym : '(${r.sym})';

  if (r is _Star) {
    final inner = _printPrec(r.child, 2);
    final starred = '$inner*';
    return starred;
  }

  if (r is _Cat) {
    final left  = _printPrec(r.left,  1);
    final right = _printPrec(r.right, 1);
    final s = '$left$right';
    // Wrap if we're inside a star context and the concat has more than one char.
    if (prec >= 2) return '($s)';
    return s;
  }

  if (r is _Union) {
    // Collect all union arms for flat printing.
    final arms = <_RE>[];
    void collect(_RE node) {
      if (node is _Union) { collect(node.left); collect(node.right); }
      else arms.add(node);
    }
    collect(r);
    final s = arms.map((a) => _printPrec(a, 0)).join('+');
    // Wrap if we're in a concat or star context.
    if (prec >= 1) return '($s)';
    return s;
  }

  return '?';
}