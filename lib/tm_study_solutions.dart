// Builds canonical reference Turing Machines for study-mode TM challenges.
//
// Each challenge carries a [TmSolutionSpec] describing its language family.
// [buildStudyTmSolution] turns that spec into a [GraphState] for display after
// three wrong attempts — mirrors pda_study_solutions.dart's architecture.
//
// Every construction below was verified against an independent Python model
// of this app's single-tape TM semantics (deterministic step function;
// "stuck" = no matching transition = terminal; accept iff the live state at
// termination has isAccept == true) by exhaustive brute-force testing over
// all strings up to length 9-12 for several different symbol alphabets each
// (plus randomized fuzzing up to length ~30), before being transcribed here.
// See the file-level comment on each builder for the algorithm it implements.
//
// [divisibleBy3] was generalized to [divisibleByK] (a random k per
// challenge instead of a fixed constant), and three brand-new families were
// added — [aToKB], [copyLang], and [unequalCount] — so a study session draws
// from nine language families instead of six. See study_mode_tm.dart for
// how each family picks its random parameters per challenge instance.
//
// Note: an earlier pass also added [unaryMult] (a^i b^j c^(i*j)), but that
// was pulled back out — it requires the player to actually implement
// multiplication of two independently-varying counts on the tape, which is
// a fundamentally different (and much higher) kind of difficulty than every
// other family here. Every other "hard" family (copyLang included) is a
// clever *matching/crossing-off* trick; none of them require the player to
// do real arithmetic between two open-ended quantities. [unequalCount] fills
// that slot instead — same crossing-off skeleton as [equalCount], just with
// the accept/reject roles flipped, so no arithmetic is involved.
//
// [crossingDep] adds a tenth family: the classic "crossing dependencies"
// language s0^n s1^m s2^n s3^m, where two independent counters (n and m)
// each govern two *non-adjacent* blocks. This is a different flavor of
// non-context-free from [anbncn]: anbncn's three blocks all share one
// counter (a single stack phase suffices conceptually, it's the *third*
// simultaneous block that breaks a PDA); here it's two counters whose
// blocks interleave rather than nest, which is what a single stack
// fundamentally can't track (see the comment on [_buildCrossingDepTm] for
// why adjacent same-counter blocks, or nested ones, would in fact be
// context-free, and why interleaved ones aren't). Verified exhaustively
// against an independent Python model — see that comment for details.

import 'package:flutter/material.dart';

import 'import_export.dart';
import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

// ── Marker / blank symbols ──────────────────────────────────────────────────
//
// 'X' is the "already processed" marker used by every crossing-off
// algorithm below. Uppercase, so it can never collide with a symbol drawn
// from kStudySymbolPool (study_mode_symbols.dart), which is lowercase +
// digits only. '#' (used by copyLang as the w#w delimiter) is likewise
// never in that pool.
const String _m = 'X';
const String _delim = '#';

/// Blank tape symbol, as used by the TM label format (kBlank in simulator.dart).
const String _blank = '∅';

/// Which reference TM to build for a study challenge.
enum TmSolutionKind {
  anbn,
  anbncn,
  equalCount,
  palindrome,
  divisibleByK,
  startEndSame,
  aToKB,
  copyLang,
  unequalCount,
  crossingDep,
}

/// Describes which reference TM to build for a study challenge.
class TmSolutionSpec {
  final TmSolutionKind kind;
  final String a;
  final String b;
  final String? c;

  /// 4th presentation-order symbol. Only used by [TmSolutionKind.crossingDep]
  /// (a, b, c, d = the four blocks in presentation order); every other kind
  /// leaves this null the same way they leave [c] null when unused.
  final String? d;
  final int? k;

  /// Per-block multiplier, in the same presentation order as the symbol
  /// fields — i.e. mults[0] is a's multiplier, etc. Block i's length is
  /// mults[i] * n (or, for [TmSolutionKind.crossingDep], mults[i] * n for
  /// blocks 0/2 and mults[i] * m for blocks 1/3 — see that builder). Null
  /// (or omitted) means all-1s: plain a^n b^n c^n for [anbncn], plain
  /// a^n b^m c^n d^m for [crossingDep]. Unused by every other kind.
  final List<int>? mults;

  const TmSolutionSpec.anbn(this.a, this.b)
      : kind = TmSolutionKind.anbn,
        c = null,
        d = null,
        k = null,
        mults = null;

  const TmSolutionSpec.anbncn(this.a, this.b, this.c, {this.mults})
      : kind = TmSolutionKind.anbncn,
        d = null,
        k = null;

  const TmSolutionSpec.equalCount(this.a, this.b)
      : kind = TmSolutionKind.equalCount,
        c = null,
        d = null,
        k = null,
        mults = null;

  const TmSolutionSpec.palindrome(this.a, this.b)
      : kind = TmSolutionKind.palindrome,
        c = null,
        d = null,
        k = null,
        mults = null;

  const TmSolutionSpec.divisibleByK(this.a, this.b, this.k)
      : kind = TmSolutionKind.divisibleByK,
        c = null,
        d = null,
        mults = null;

  const TmSolutionSpec.startEndSame(this.a, this.b)
      : kind = TmSolutionKind.startEndSame,
        c = null,
        d = null,
        k = null,
        mults = null;

  const TmSolutionSpec.aToKB(this.a, this.b, this.k)
      : kind = TmSolutionKind.aToKB,
        c = null,
        d = null,
        mults = null;

  const TmSolutionSpec.copyLang(this.a, this.b)
      : kind = TmSolutionKind.copyLang,
        c = null,
        d = null,
        k = null,
        mults = null;

  const TmSolutionSpec.unequalCount(this.a, this.b)
      : kind = TmSolutionKind.unequalCount,
        c = null,
        d = null,
        k = null,
        mults = null;

  /// [a], [b], [c], [d] are the four blocks in *presentation order* (the
  /// order they appear left-to-right in the string) — not necessarily
  /// "the n-blocks then the m-blocks"; blocks 0/2 always share one counter
  /// and blocks 1/3 always share the other, whatever symbols happen to sit
  /// there. See study_mode_tm.dart's crossing-dependency template for how
  /// the block order and [mults] get chosen per challenge instance.
  const TmSolutionSpec.crossingDep(this.a, this.b, this.c, this.d, {this.mults})
      : kind = TmSolutionKind.crossingDep,
        k = null;
}

GraphState buildStudyTmSolution(TmSolutionSpec spec) {
  return switch (spec.kind) {
    TmSolutionKind.anbn => _buildAnBnTm(spec.a, spec.b),
    TmSolutionKind.anbncn =>
      _buildAnBnCnTm(spec.a, spec.b, spec.c!, spec.mults ?? const [1, 1, 1]),
    TmSolutionKind.equalCount => _buildEqualCountTm(spec.a, spec.b),
    TmSolutionKind.palindrome => _buildPalindromeTm(spec.a, spec.b),
    TmSolutionKind.divisibleByK => _buildDivisibleByKTm(spec.a, spec.b, spec.k!),
    TmSolutionKind.startEndSame => _buildStartEndSameTm(spec.a, spec.b),
    TmSolutionKind.aToKB => _buildAToKBTm(spec.a, spec.b, spec.k!),
    TmSolutionKind.copyLang => _buildCopyLangTm(spec.a, spec.b),
    TmSolutionKind.unequalCount => _buildUnequalCountTm(spec.a, spec.b),
    TmSolutionKind.crossingDep => _buildCrossingDepTm(
        [spec.a, spec.b, spec.c!, spec.d!], spec.mults ?? const [1, 1, 1, 1]),
  };
}

// ── Graph helper ─────────────────────────────────────────────────────────────
//
// Same shape as pda_study_solutions.dart's _graph(): merges parallel
// (from,to) transitions into one \n-joined LineData label (so "read a OR X"
// self-loops render as a single textbox with multiple lines instead of
// stacked separate arrows). TM graphs tend to run larger than PDA ones (up
// to ~10 states for anbncn), so states wrap into rows of 6 instead of a
// single long line.
GraphState _graph({
  required List<(String id, String label, bool accept)> states,
  required List<(String from, String to, String label)> transitions,
  required String startId,
}) {
  final nodes = <String, NodeData>{};
  const perRow = 6;
  for (int i = 0; i < states.length; i++) {
    final (id, label, accept) = states[i];
    final row = i ~/ perRow;
    final col = i % perRow;
    nodes[id] = NodeData(
      id: id,
      label: label,
      position: Offset(220.0 + col * 240.0, 260.0 + row * 300.0),
      isAccept: accept,
    );
  }

  final edgeOrder = <(String, String)>[];
  final edgeLabels = <(String, String), List<String>>{};

  for (final (from, to, label) in transitions) {
    final key = (from, to);
    if (!edgeLabels.containsKey(key)) {
      edgeOrder.add(key);
      edgeLabels[key] = [];
    }
    edgeLabels[key]!.add(label);
  }

  final lines = <String, LineData>{};
  int li = 0;
  for (final key in edgeOrder) {
    final (from, to) = key;
    final mergedLabel = edgeLabels[key]!.join('\n');
    final id = 'l$li';
    lines[id] = LineData(id: id, nodeAId: from, nodeBId: to, label: mergedLabel);
    nodes[from]!.connectedLineIds.add(id);
    if (to != from) nodes[to]!.connectedLineIds.add(id);
    li++;
  }

  return GraphState(
    nodes: nodes,
    lines: lines,
    startArrow: StartArrowData(nodeId: startId),
    nodeCounter: states.length,
    lineCounter: li,
    automataMode: AutomataMode.tm,
  );
}

// ── TM label helpers  — 3-char shorthand: read, write, direction ───────────
//
// Mirrors the format documented in simulator.dart's parseTmLabel: e.g.
// "aXR" = read a, write X, move Right. "∅" (kBlank) stands for blank.
//
//   _tt      : raw (read, write, dir) triple
//   _selfR/L : re-write the same symbol and skip past it (Right/Left) —
//              used to scan over already-seen or irrelevant symbols
//   _mark    : cross a symbol off to the X marker, then move
//   _skipX   : pass over an already-crossed marker (Right/Left)
//   _atBlank : act on the blank cell (used to pivot state at tape ends)
String _tt(String read, String write, String dir) => '$read$write$dir';
String _selfR(String sym) => _tt(sym, sym, 'R');
String _selfL(String sym) => _tt(sym, sym, 'L');
String _selfS(String sym) => _tt(sym, sym, 'S');
String _mark(String sym, String dir) => _tt(sym, _m, dir);
String _skipX(String dir) => _tt(_m, _m, dir);
String _atBlank(String dir) => _tt(_blank, _blank, dir);

// ── Language families ───────────────────────────────────────────────────────

// A) L = { a^n b^n : n ≥ 0 }
//
// Two phases:
//  1. PRECHECK (PA/PB) — verifies the input matches a*b* (no "a" after a
//     "b"); rejects immediately (by getting stuck) otherwise. Without this,
//     the crossing-off phase below would happily match any 'a' with any
//     later 'b' regardless of what's in between, which wrongly accepts
//     interleaved strings like "abab".
//  2. CROSSING-OFF (Q0/Q1/Q2) — repeatedly cross the leftmost unmarked 'a'
//     and the leftmost unmarked 'b' to X, bouncing back to the start after
//     each round. Accept once a full left-to-right scan finds only X's.
GraphState _buildAnBnTm(String a, String b) {
  return _graph(
    states: [
      ('pa', 'A', false),
      ('pb', 'B', false),
      ('rs', 'R', false),
      ('rl', 'R2', false),
      ('q0', 'Q0', false),
      ('q1', 'Q1', false),
      ('q2', 'Q2', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('pa', 'rs', _atBlank('S')),
      ('pa', 'pa', _selfR(a)),
      ('pa', 'pb', _selfR(b)),
      ('pb', 'pb', _selfR(b)),
      ('pb', 'rs', _atBlank('S')),
      ('rs', 'rl', _atBlank('L')),
      ('rl', 'rl', _selfL(a)),
      ('rl', 'rl', _selfL(b)),
      ('rl', 'rl', _skipX('L')),
      ('rl', 'q0', _atBlank('R')),
      ('q0', 'q0', _skipX('R')),
      ('q0', 'q1', _mark(a, 'R')),
      ('q0', 'acc', _atBlank('S')),
      ('q1', 'q1', _selfR(a)),
      ('q1', 'q1', _skipX('R')),
      ('q1', 'q2', _mark(b, 'L')),
      ('q2', 'q2', _skipX('L')),
      ('q2', 'q2', _selfL(a)),
      ('q2', 'q0', _atBlank('R')),
    ],
    startId: 'pa',
  );
}

// B) L = { a^(m0*n) b^(m1*n) c^(m2*n) : n ≥ 0 }  — not context-free; needs a
// TM. Generalizes the plain a^n b^n c^n case (mults = [1,1,1]) to let each
// block carry its own multiplier — e.g. mults = [1,2,1] means the "b" block
// must be exactly twice as long as the "a" and "c" blocks, for the same n.
// (a, b, c) are always given in *presentation order* — i.e. a is whichever
// symbol occupies the string's first block, not necessarily the symbol the
// study challenge happened to draw first — so this same builder handles
// both the "always a-block then b-block then c-block" layout and the
// reordered-block "hard" variant; the caller just passes the three symbols
// in whatever order they should appear.
//
// Verified against an independent Python model of this app's TM semantics:
// exhaustively for all 3-symbol strings up to length 9 across eight
// multiplier combinations (0 failures over 236k cases), plus fuzzing with
// random multipliers (1-4 each) and strings up to length 40 (0 failures over
// 3k trials). Worst-case step count observed (mults=[4,4,4], n=5, 60-char
// input) was 705 steps — well inside kStudyTmMaxSteps (5000).
//
// Two phases, same shape as anbn/the old fixed anbncn:
//  1. PRECHECK (p0/p1/p2) — verifies the input matches a*b*c* in the given
//     presentation order; rejects immediately (by getting stuck) otherwise.
//  2. CROSSING-OFF — one "round" advances n by exactly 1: mark m0 copies of
//     a (chained direct-mark states, no hunting needed since a's own block
//     is always contiguous), then hunt across any leftover unmarked a's to
//     find b and mark m1 copies of it, then hunt across leftover b's to
//     find c and mark m2 copies of it, then bounce back to the start.
//     Accept once a full left-to-right scan from the start finds only X's.
//     Running short on any block's required count during a round means
//     getting stuck mid-chain (reject); leftover unmarked symbols from an
//     earlier block still sitting around when a later round's scan expects
//     that block's symbol also gets stuck (reject) — that's how a block
//     whose count isn't an exact multiple of its multiplier, or isn't in
//     lockstep with the other blocks' n, gets caught.
GraphState _buildAnBnCnTm(String a, String b, String c, List<int> mults) {
  assert(mults.length == 3, 'anbncn needs exactly 3 block multipliers');
  assert(mults.every((m) => m >= 1), 'block multipliers must be >= 1');

  final syms = [a, b, c];
  final states = <(String, String, bool)>[
    ('p0', 'A', false),
    ('p1', 'B', false),
    ('p2', 'C', false),
    ('rs', 'R', false),
    ('rl', 'R2', false),
    ('ret', 'RET', false),
    ('acc', 'OK', true),
  ];
  final transitions = <(String, String, String)>[
    ('p0', 'rs', _atBlank('S')),
    ('p0', 'p0', _selfR(syms[0])),
    ('p0', 'p1', _selfR(syms[1])),
    ('p1', 'p1', _selfR(syms[1])),
    ('p1', 'p2', _selfR(syms[2])),
    ('p1', 'rs', _atBlank('S')),
    ('p2', 'p2', _selfR(syms[2])),
    ('p2', 'rs', _atBlank('S')),
    ('rs', 'rl', _atBlank('L')),
    ('rl', 'rl', _selfL(syms[0])),
    ('rl', 'rl', _selfL(syms[1])),
    ('rl', 'rl', _selfL(syms[2])),
    ('rl', 'rl', _skipX('L')),
    ('rl', 'q0', _atBlank('R')),
  ];

  // 'q0' doubles as the first block's mark-chain head (no earlier block to
  // hunt past). Every other block's first sub-state is a hunt state that
  // self-loops over the *previous* block's raw symbol (any leftover copies
  // not yet due this round) plus already-marked X, until it lands on its
  // own block's symbol.
  String stateName(int i, int j) => (i == 0 && j == 1) ? 'q0' : 'r${i}_$j';
  const blockLabel = ['A', 'B', 'C'];

  for (int i = 0; i < 3; i++) {
    for (int j = 1; j <= mults[i]; j++) {
      final name = stateName(i, j);
      if (name != 'q0') states.add((name, '${blockLabel[i]}$j', false));

      final isFirstOfBlock = j == 1;
      final isLastOfBlock = j == mults[i];
      final isLastOverall = i == 2 && isLastOfBlock;
      final dir = isLastOverall ? 'L' : 'R';
      final target = !isLastOfBlock
          ? stateName(i, j + 1)
          : (i < 2 ? stateName(i + 1, 1) : 'ret');

      transitions.add((name, target, _mark(syms[i], dir)));

      if (name == 'q0') {
        transitions.add(('q0', 'q0', _skipX('R')));
      } else if (isFirstOfBlock) {
        transitions.add((name, name, _selfR(syms[i - 1])));
        transitions.add((name, name, _skipX('R')));
      }
    }
  }

  transitions.add(('q0', 'acc', _atBlank('S')));
  transitions.addAll([
    ('ret', 'ret', _skipX('L')),
    ('ret', 'ret', _selfL(syms[0])),
    ('ret', 'ret', _selfL(syms[1])),
    ('ret', 'q0', _atBlank('R')),
  ]);

  states.add(('q0', 'Q0', false));

  return _graph(states: states, transitions: transitions, startId: 'p0');
}

// C) L = { w ∈ {a,b}* : #a(w) = #b(w) }  — equal counts, any order.
//
// No precheck needed here since order doesn't matter. Each round: cross
// the leftmost unmarked symbol, then hunt right for the nearest unmarked
// symbol of the *other* kind and cross it too, then rewind to the start.
// Accept once a scan from the start finds nothing but X.
GraphState _buildEqualCountTm(String a, String b) {
  return _graph(
    states: [
      ('q0', 'Q0', false),
      ('fb', 'FB', false),
      ('fa', 'FA', false),
      ('ret', 'RET', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('q0', 'q0', _skipX('R')),
      ('q0', 'fb', _mark(a, 'R')),
      ('q0', 'fa', _mark(b, 'R')),
      ('q0', 'acc', _atBlank('S')),
      ('fb', 'fb', _selfR(a)),
      ('fb', 'fb', _skipX('R')),
      ('fb', 'ret', _mark(b, 'L')),
      ('fa', 'fa', _selfR(b)),
      ('fa', 'fa', _skipX('R')),
      ('fa', 'ret', _mark(a, 'L')),
      ('ret', 'ret', _skipX('L')),
      ('ret', 'ret', _selfL(a)),
      ('ret', 'ret', _selfL(b)),
      ('ret', 'q0', _atBlank('R')),
    ],
    startId: 'q0',
  );
}

// D) L = palindromes over {a,b} (any length).
//
// Cross the leftmost unmarked symbol, sweep to the far end, step back over
// any already-crossed X's, and check the last unmarked symbol matches.
// Mismatch ⇒ stuck ⇒ reject. Reaching blank while stepping back over X's
// means everything has been paired off (even case) or only the middle
// character was left (odd case) — either way, accept.
GraphState _buildPalindromeTm(String a, String b) {
  return _graph(
    states: [
      ('q0', 'Q0', false),
      ('seeka', 'SA', false),
      ('seekb', 'SB', false),
      ('checka', 'CA', false),
      ('checkb', 'CB', false),
      ('ret', 'RET', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('q0', 'q0', _skipX('R')),
      ('q0', 'seeka', _mark(a, 'R')),
      ('q0', 'seekb', _mark(b, 'R')),
      ('q0', 'acc', _atBlank('S')),
      ('seeka', 'seeka', _selfR(a)),
      ('seeka', 'seeka', _selfR(b)),
      ('seeka', 'seeka', _skipX('R')),
      ('seeka', 'checka', _atBlank('L')),
      ('seekb', 'seekb', _selfR(a)),
      ('seekb', 'seekb', _selfR(b)),
      ('seekb', 'seekb', _skipX('R')),
      ('seekb', 'checkb', _atBlank('L')),
      ('checka', 'checka', _skipX('L')),
      ('checka', 'ret', _mark(a, 'L')),
      ('checka', 'acc', _atBlank('S')),
      ('checkb', 'checkb', _skipX('L')),
      ('checkb', 'ret', _mark(b, 'L')),
      ('checkb', 'acc', _atBlank('S')),
      ('ret', 'ret', _selfL(a)),
      ('ret', 'ret', _selfL(b)),
      ('ret', 'ret', _skipX('L')),
      ('ret', 'q0', _atBlank('R')),
    ],
    startId: 'q0',
  );
}

// E) L = { w ∈ {a,b}* : #a(w) ≡ 0 (mod k) }.  (generalizes divisibleBy3)
//
// A k-state counter m0..m(k-1): reading 'a' advances the state mod k (never
// touching the tape); 'b' is a self-loop in every state. Accept only if the
// machine reaches the end of the tape while in the "0 mod k" state.
GraphState _buildDivisibleByKTm(String a, String b, int k) {
  final states = [
    for (int i = 0; i < k; i++) ('m$i', 'M$i', false),
    ('acc', 'OK', true),
  ];
  final transitions = <(String, String, String)>[
    for (int i = 0; i < k; i++) ('m$i', 'm$i', _selfR(b)),
    for (int i = 0; i < k; i++) ('m$i', 'm${(i + 1) % k}', _selfR(a)),
    ('m0', 'acc', _atBlank('S')),
  ];
  return _graph(states: states, transitions: transitions, startId: 'm0');
}

// F) L = { w : w is empty, or the first and last symbol of w are equal }.
//
// Remember the first symbol via which state we're in, scan to the far end,
// step back one, and check for a match. No marking needed since nothing
// gets removed from the tape.
GraphState _buildStartEndSameTm(String a, String b) {
  return _graph(
    states: [
      ('start', 'ST', false),
      ('seeka', 'SA', false),
      ('seekb', 'SB', false),
      ('checka', 'CA', false),
      ('checkb', 'CB', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('start', 'acc', _atBlank('S')),
      ('start', 'seeka', _selfR(a)),
      ('start', 'seekb', _selfR(b)),
      ('seeka', 'seeka', _selfR(a)),
      ('seeka', 'seeka', _selfR(b)),
      ('seeka', 'checka', _atBlank('L')),
      ('seekb', 'seekb', _selfR(a)),
      ('seekb', 'seekb', _selfR(b)),
      ('seekb', 'checkb', _atBlank('L')),
      ('checka', 'acc', _selfS(a)),
      ('checkb', 'acc', _selfS(b)),
    ],
    startId: 'start',
  );
}

// G) L = { a^n b^(k*n) : n ≥ 0 }.  (generalizes anbn — k=1 is exactly anbn)
//
// Same PRECHECK + CROSSING-OFF shape as anbn, except each round marks one
// 'a' and then chains through k "b hunter" states in sequence (seek1..seekK)
// to cross off k unmarked b's — instead of anbn's single hunter — before
// bouncing back to the start.
GraphState _buildAToKBTm(String a, String b, int k) {
  final states = [
    ('pa', 'A', false),
    ('pb', 'B', false),
    ('rs', 'R', false),
    ('rl', 'R2', false),
    ('q0', 'Q0', false),
    for (int i = 1; i <= k; i++) ('seek$i', 'S$i', false),
    ('ret', 'RET', false),
    ('acc', 'OK', true),
  ];
  final transitions = <(String, String, String)>[
    ('pa', 'rs', _atBlank('S')),
    ('pa', 'pa', _selfR(a)),
    ('pa', 'pb', _selfR(b)),
    ('pb', 'pb', _selfR(b)),
    ('pb', 'rs', _atBlank('S')),
    ('rs', 'rl', _atBlank('L')),
    ('rl', 'rl', _selfL(a)),
    ('rl', 'rl', _selfL(b)),
    ('rl', 'rl', _skipX('L')),
    ('rl', 'q0', _atBlank('R')),
    ('q0', 'q0', _skipX('R')),
    ('q0', 'seek1', _mark(a, 'R')),
    ('q0', 'acc', _atBlank('S')),
    for (int i = 1; i <= k; i++) ...[
      ('seek$i', 'seek$i', _selfR(a)),
      ('seek$i', 'seek$i', _skipX('R')),
      if (i < k)
        ('seek$i', 'seek${i + 1}', _mark(b, 'R'))
      else
        ('seek$i', 'ret', _mark(b, 'L')),
    ],
    ('ret', 'ret', _skipX('L')),
    ('ret', 'ret', _selfL(a)),
    ('ret', 'q0', _atBlank('R')),
  ];
  return _graph(states: states, transitions: transitions, startId: 'pa');
}

// H) L = { w#w : w ∈ {a,b}* }  — the "copy language".
//
// Not context-free (unlike w#w^R, which a PDA handles with a stack): this
// is the family that shows off what a TM can do that a PDA fundamentally
// can't. Each round crosses off the leftmost unmarked symbol on the *left*
// side of '#', then hops the delimiter and crosses off the matching
// leftmost unmarked symbol on the *right* side — rejecting (by getting
// stuck) on any mismatch — then rewinds to the start. Once the left side is
// exhausted, a final pass (checkEnd) confirms nothing unmarked is left
// dangling on the right (which would mean the right side was longer).
//
// Note there's no direct q0-on-blank acceptance: an entirely empty tape (no
// '#' at all) is not of the form w#w for any w, and must be rejected — the
// empty-w case is instead handled correctly as the single-character string
// "#", via q0 → checkEnd → blank.
GraphState _buildCopyLangTm(String a, String b) {
  return _graph(
    states: [
      ('q0', 'Q0', false),
      ('seekAL', 'AL', false),
      ('seekAR', 'AR', false),
      ('seekBL', 'BL', false),
      ('seekBR', 'BR', false),
      ('ret', 'RET', false),
      ('checkEnd', 'CE', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('q0', 'q0', _skipX('R')),
      ('q0', 'seekAL', _mark(a, 'R')),
      ('q0', 'seekBL', _mark(b, 'R')),
      ('q0', 'checkEnd', _selfR(_delim)),
      ('seekAL', 'seekAL', _selfR(a)),
      ('seekAL', 'seekAL', _selfR(b)),
      ('seekAL', 'seekAL', _skipX('R')),
      ('seekAL', 'seekAR', _selfR(_delim)),
      ('seekAR', 'seekAR', _skipX('R')),
      ('seekAR', 'ret', _mark(a, 'L')),
      ('seekBL', 'seekBL', _selfR(a)),
      ('seekBL', 'seekBL', _selfR(b)),
      ('seekBL', 'seekBL', _skipX('R')),
      ('seekBL', 'seekBR', _selfR(_delim)),
      ('seekBR', 'seekBR', _skipX('R')),
      ('seekBR', 'ret', _mark(b, 'L')),
      ('ret', 'ret', _selfL(a)),
      ('ret', 'ret', _selfL(b)),
      ('ret', 'ret', _skipX('L')),
      ('ret', 'ret', _selfL(_delim)),
      ('ret', 'q0', _atBlank('R')),
      ('checkEnd', 'checkEnd', _skipX('R')),
      ('checkEnd', 'acc', _atBlank('S')),
    ],
    startId: 'q0',
  );
}

// I) L = { w ∈ {a,b}* : #a(w) ≠ #b(w) }  — the complement of equalCount.
//
// Exactly the same crossing-off skeleton as equalCount (pair off the
// leftmost unmarked symbol with one of the other kind, repeat), with the
// accept/reject outcomes flipped:
//   - if a hunt for the "other" symbol ever runs off the end of the tape
//     (fb/fa hit blank without finding their match), that proves the two
//     counts are unequal — accept right there.
//   - if every symbol gets fully paired off (q0 reaches blank with nothing
//     left unmarked), that proves the counts were equal — and since there's
//     deliberately no q0-on-blank transition, the machine just gets stuck
//     there and rejects.
GraphState _buildUnequalCountTm(String a, String b) {
  return _graph(
    states: [
      ('q0', 'Q0', false),
      ('fb', 'FB', false),
      ('fa', 'FA', false),
      ('ret', 'RET', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('q0', 'q0', _skipX('R')),
      ('q0', 'fb', _mark(a, 'R')),
      ('q0', 'fa', _mark(b, 'R')),
      // no ('q0', blank, ...): everything paired off => stuck => reject.
      ('fb', 'fb', _selfR(a)),
      ('fb', 'fb', _skipX('R')),
      ('fb', 'ret', _mark(b, 'L')),
      ('fb', 'acc', _atBlank('S')),
      ('fa', 'fa', _selfR(b)),
      ('fa', 'fa', _skipX('R')),
      ('fa', 'ret', _mark(a, 'L')),
      ('fa', 'acc', _atBlank('S')),
      ('ret', 'ret', _skipX('L')),
      ('ret', 'ret', _selfL(a)),
      ('ret', 'ret', _selfL(b)),
      ('ret', 'q0', _atBlank('R')),
    ],
    startId: 'q0',
  );
}
// J) L = { s0^(m0*n) s1^(m1*m) s2^(m2*n) s3^(m3*m) : n, m ≥ 0 }
//    — "crossing dependencies", the classic non-context-free example built
//    from two *independent* counters whose blocks interleave rather than
//    nest or sit adjacent.
//
// (a, b, c, d) — renamed s0..s3 below — are always given in presentation
// order (left to right in the string), exactly like anbncn's (a, b, c).
// Blocks 0 and 2 always share one counter (called n below); blocks 1 and 3
// always share the other (m). That pairing-by-position is what makes this
// builder correct for *any* permutation of four symbols the caller passes
// in — "shuffling the block order" for hard mode just means picking a
// different permutation for (s0,s1,s2,s3); the crossing structure itself is
// fixed by which slot (0/2 vs 1/3) a symbol lands in, not by which literal
// symbol it is.
//
// Why "crossing" specifically requires a TM, unlike anbncn or a nested
// shape: a single stack can verify two counters that are either (i)
// adjacent — s0^n s2^n directly next to each other, push-then-pop, or (ii)
// nested — s0^n s1^m s1^m s2^n, push both, pop both in reverse. What a
// stack cannot do is verify two *simultaneously open* counters that close
// in the same order they opened (s0^n s1^m s2^n s3^m): by the time s2's
// block needs matching against s0's count, s1's count is still buried
// under it with no way to check s1 against s3 later without first
// disturbing the s0/s2 pairing. Provable non-context-free by the pumping
// lemma — this is the textbook a^n b^m c^n d^m example, with symbols
// renamed to whatever the study alphabet drew.
//
// Verified against an independent Python model of this app's TM semantics:
// exhaustively for all 4-symbol strings up to length 10 in the plain
// mults=[1,1,1,1] case (0 failures over ~1.4M cases), exhaustively again
// across 15 randomized (block-order, multiplier) combinations up to length
// 8 (0 failures over ~1.3M cases), and fuzzed with longer strings (n,m up
// to 4, multipliers up to 4, string lengths up to 60) including single-
// character perturbations of valid strings (0 failures over 400 trials).
// Worst-case step count observed (mults up to 4, n=m=6, 60-char input) was
// 1402 steps — well inside kStudyTmMaxSteps (5000).
//
// Construction, in two independent crossing-off phases run one after the
// other on the same tape:
//
//  0. PRECHECK (p0..p3) — verifies the input matches s0* s1* s2* s3* in
//     that exact presentation order (any block may be empty, independently
//     — unlike anbncn, blocks 0/2 and blocks 1/3 are governed by different
//     counters, so e.g. n=0 while m>0 must skip straight past the empty
//     s0/s2 blocks to s1). Rejects immediately (by getting stuck) on any
//     other symbol arrangement.
//
//  1. PHASE 1 (g0/h1/ret1) — matches blocks 0 and 2 (counter n). Each round:
//     mark m0 copies of s0 from the head (g0, chained like anbncn's
//     within-block marking), hunt right past any remaining raw s0, all of
//     block 1's raw s1 (untouched — this phase doesn't touch it), and any
//     already-marked X (from block 2's earlier rounds), then mark m2
//     copies of s2, then rewind to the start for the next round. Once the
//     head finds no more unmarked s0 (it lands on s1 instead, or blank if
//     block 1 is also empty), phase 1 is done — pivot straight into phase 2
//     without rewinding, since the head is already sitting exactly where
//     block 1 begins.
//
//  2. PHASE 2 (g1/h2/ret2) — matches blocks 1 and 3 (counter m), same
//     crossing-off shape as phase 1: mark m1 copies of s1, hunt past
//     remaining raw s1 and the now-fully-marked block 2 (pure X at this
//     point), mark m3 copies of s3, rewind, repeat. Accept once the head
//     finds only X out to the end of the tape.
//
// Any block-count mismatch (n1 ≠ n2 for blocks 0/2, or m1 ≠ m3 for blocks
// 1/3, or leftover/missing symbols from a broken block order) is caught by
// getting stuck mid-round — there's deliberately no fallback transition for
// an unexpected symbol at any hunt/chain state, exactly like every other
// crossing-off construction in this file.
GraphState _buildCrossingDepTm(List<String> order, List<int> mults) {
  assert(order.length == 4, 'crossingDep needs exactly 4 blocks');
  assert(mults.length == 4, 'crossingDep needs exactly 4 block multipliers');
  assert(mults.every((m) => m >= 1), 'block multipliers must be >= 1');

  final s0 = order[0], s1 = order[1], s2 = order[2], s3 = order[3];
  final m0 = mults[0], m1 = mults[1], m2 = mults[2], m3 = mults[3];

  String chainName(String prefix, int j) => j == 1 ? prefix : '${prefix}_$j';

  final states = <(String, String, bool)>[
    ('p0', 'P0', false),
    ('p1', 'P1', false),
    ('p2', 'P2', false),
    ('p3', 'P3', false),
    ('rs', 'R', false),
    ('rl', 'R2', false),
    ('g0', 'N0', false),
    ('h1', 'H1', false),
    ('ret1', 'RET1', false),
    ('g1', 'M0', false),
    ('h2', 'H2', false),
    ('ret2', 'RET2', false),
    ('acc', 'OK', true),
  ];
  final transitions = <(String, String, String)>[];

  // ── Precheck: s0* s1* s2* s3*, any block(s) may be empty ───────────────────────
  for (int i = 0; i < 4; i++) {
    final pi = 'p$i';
    transitions.add((pi, pi, _selfR(order[i])));
    for (int j = i + 1; j < 4; j++) {
      transitions.add((pi, 'p$j', _selfR(order[j])));
    }
    transitions.add((pi, 'rs', _atBlank('S')));
  }
  transitions.add(('rs', 'rl', _atBlank('L')));
  for (final sym in order) {
    transitions.add(('rl', 'rl', _selfL(sym)));
  }
  transitions.add(('rl', 'rl', _skipX('L')));
  transitions.add(('rl', 'g0', _atBlank('R')));

  // ── Phase 1: blocks 0 & 2 (counter n) ────────────────────────────────
  for (int j = 1; j <= m0; j++) {
    final name = chainName('g0', j);
    if (name != 'g0') states.add((name, 'N0_$j', false));
    final next = j < m0 ? chainName('g0', j + 1) : 'h1';
    transitions.add((name, next, _mark(s0, 'R')));
  }
  transitions.add(('g0', 'g0', _skipX('R')));
  transitions.add(('g0', 'g1', _selfS(s1)));
  transitions.add(('g0', 'g1', _atBlank('S')));

  transitions.add(('h1', 'h1', _selfR(s0)));
  transitions.add(('h1', 'h1', _selfR(s1)));
  transitions.add(('h1', 'h1', _skipX('R')));

  for (int j = 1; j <= m2; j++) {
    final from = j == 1 ? 'h1' : chainName('n2', j);
    final name = chainName('n2', j);
    if (j > 1) states.add((name, 'N2_$j', false));
    final next = j < m2 ? chainName('n2', j + 1) : 'ret1';
    final dir = j < m2 ? 'R' : 'L';
    transitions.add((from, next, _mark(s2, dir)));
  }

  transitions.add(('ret1', 'ret1', _selfL(s0)));
  transitions.add(('ret1', 'ret1', _selfL(s1)));
  transitions.add(('ret1', 'ret1', _skipX('L')));
  transitions.add(('ret1', 'g0', _atBlank('R')));

  // ── Phase 2: blocks 1 & 3 (counter m) ────────────────────────────────
  for (int j = 1; j <= m1; j++) {
    final name = chainName('g1', j);
    if (name != 'g1') states.add((name, 'M0_$j', false));
    final next = j < m1 ? chainName('g1', j + 1) : 'h2';
    transitions.add((name, next, _mark(s1, 'R')));
  }
  transitions.add(('g1', 'g1', _skipX('R')));
  transitions.add(('g1', 'acc', _atBlank('S')));

  transitions.add(('h2', 'h2', _selfR(s1)));
  transitions.add(('h2', 'h2', _skipX('R')));

  for (int j = 1; j <= m3; j++) {
    final from = j == 1 ? 'h2' : chainName('n3', j);
    final name = chainName('n3', j);
    if (j > 1) states.add((name, 'M2_$j', false));
    final next = j < m3 ? chainName('n3', j + 1) : 'ret2';
    final dir = j < m3 ? 'R' : 'L';
    transitions.add((from, next, _mark(s3, dir)));
  }

  transitions.add(('ret2', 'ret2', _selfL(s1)));
  transitions.add(('ret2', 'ret2', _skipX('L')));
  transitions.add(('ret2', 'g1', _atBlank('R')));

  return _graph(states: states, transitions: transitions, startId: 'p0');
}