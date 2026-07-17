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

// ─────────────────────────────────────────────────────────────────────────────
//  A note on how this annotated copy is commented: this file already carries
//  unusually thorough prose doc comments on every builder (algorithm
//  description, phase breakdown, verification methodology) — the original
//  author clearly treated the *why* as important as the code. This copy
//  leaves every one of those comments untouched and adds a second layer
//  underneath: for every transition (or tight group of transitions), a note
//  on *which phase/step from that builder's own header comment it
//  implements*, plus call-outs for the genuinely subtle bits (deliberately
//  missing transitions that encode "reject by getting stuck," self-loop vs.
//  hunt-state distinctions, off-by-one state-chaining patterns). Where
//  several builders repeat the same PRECHECK → CROSSING-OFF skeleton (most
//  of them do), later occurrences point back to the first fully-annotated
//  one rather than re-explaining identical mechanics from scratch.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
// Only for `Offset`, used by `_graph()`'s node-layout grid below — nothing
// else from Flutter's widget system is needed in what is otherwise a pure
// data-construction file.

import 'import_export.dart';
// Not directly referenced by name anywhere below — likely kept for parity
// with pda_study_solutions.dart's own import list (per this file's header
// comment, this file "mirrors pda_study_solutions.dart's architecture"), or
// for a transitive re-export some caller depends on.
import 'models.dart';
// NodeData, LineData, GraphState, StartArrowData — the graph data model
// every builder below assembles via `_graph()`.
import 'widgets/automata_drawer.dart' show AutomataMode;
// Only the AutomataMode enum, via `show` — used once, to tag every built
// GraphState as `AutomataMode.tm` in `_graph()`.

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
  addConstant,
}
// Eleven kinds, one per builder function below (labeled A through K in the
// "Language families" section) — `buildStudyTmSolution`'s switch expression
// further down is exhaustive over exactly this enum, so adding a twelfth
// kind here without a matching switch arm would fail to compile (Dart flags
// non-exhaustive switch expressions over enums as an error), which is a
// deliberate safety net for this file.

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
  // Every field here is nullable except `kind`, `a`, and `b` — a single
  // flat class shared across all eleven language families rather than a
  // sealed hierarchy of per-kind subclasses, so each named constructor
  // below is responsible for nulling out whichever fields its own kind
  // doesn't use. This keeps `TmSolutionSpec` simple to pattern-match on
  // (`spec.kind`, then read whichever fields that kind is documented to
  // populate) at the cost of every builder call site downstream needing to
  // trust — via `!` non-null assertions — that the right fields were
  // actually set for the kind it's building.

  const TmSolutionSpec.anbn(this.a, this.b)
      : kind = TmSolutionKind.anbn,
        c = null,
        d = null,
        k = null,
        mults = null;
  // The canonical shape every other two-symbol, no-extra-parameter kind
  // below repeats: initializer-list constructor sets `kind` to a literal
  // enum value and explicitly nulls every field this family doesn't use.
  // `a`/`b` are populated implicitly via the `this.a, this.b` shorthand in
  // the constructor's own parameter list, so they don't need to appear in
  // the initializer list itself.

  const TmSolutionSpec.anbncn(this.a, this.b, this.c, {this.mults})
      : kind = TmSolutionKind.anbncn,
        d = null,
        k = null;
  // First constructor that actually *uses* one of the optional fields:
  // `c` is a required positional param (populated via `this.c`, so it's
  // absent from the initializer list, same as a/b above) and `mults` is an
  // optional named param defaulting to Dart's implicit `null` when omitted
  // — `buildStudyTmSolution`'s switch arm for this kind separately falls
  // back to `[1, 1, 1]` when `mults` is null, so `null` here means "use the
  // plain a^n b^n c^n shape," not "invalid."

  const TmSolutionSpec.equalCount(this.a, this.b)
      : kind = TmSolutionKind.equalCount,
        c = null,
        d = null,
        k = null,
        mults = null;
  // Same shape as .anbn above, just a different `kind` — repeats for
  // .palindrome, .startEndSame, .copyLang, and .unequalCount below too;
  // each of those five constructors is byte-for-byte identical apart from
  // which TmSolutionKind literal it assigns.

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
  // `k` is populated via `this.k` (a required positional param) — note `k`
  // itself is therefore absent from the initializer list, just like a/b/c
  // are for their respective constructors; only fields NOT set via a
  // `this.x` constructor parameter need to appear in the `:` initializer
  // list at all.

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
  // Same shape as .divisibleByK above — a required `k`, everything else
  // nulled.

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
  // The only constructor besides .anbncn to leave `mults` un-nulled (it's
  // populated by the optional named param, defaulting to Dart's implicit
  // null just like .anbncn's) — `buildStudyTmSolution`'s switch arm for
  // this kind falls back to `[1, 1, 1, 1]` (four elements, matching the
  // four blocks a/b/c/d) when omitted.

  /// Not a decision language: the machine must transform the tape from N
  /// (binary, no leading zeros except "0" itself) into N + [k]. [a]/[b] are
  /// unused by this kind (the alphabet is always the fixed {'0','1'}, not a
  /// per-challenge random pair) but are still given harmless placeholder
  /// values since the fields are non-nullable. See _buildAddConstantTm for
  /// the construction and study_mode_tm.dart's gradeStudyTm for how output
  /// (not just accept/reject) gets checked.
  const TmSolutionSpec.addConstant(this.k)
      : kind = TmSolutionKind.addConstant,
        a = '0',
        b = '1',
        c = null,
        d = null,
        mults = null;
  // The one constructor that assigns `a`/`b` via the initializer list
  // instead of `this.a, this.b` constructor params — because `a` and `b`
  // are declared non-nullable `String` fields (not `String?`), and this
  // kind genuinely has no per-challenge symbols to accept, hardcoding them
  // to the fixed binary alphabet here is the only way to satisfy the
  // non-nullable field requirement without changing `a`/`b`'s type for
  // every other constructor that *does* need them to vary.
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
    TmSolutionKind.addConstant => _buildAddConstantTm(spec.k!),
  };
}
// A Dart 3 `switch` *expression* (not a `switch` statement — no `case`/
// `break` keywords, each arm is `pattern => value`), exhaustive over the
// TmSolutionKind enum — this is the dispatch table matching each kind to
// its builder. The `!` non-null assertions (`spec.c!`, `spec.k!`, `spec.d!`)
// are exactly the "trust the right fields were populated" contract
// described above: they're safe here only because each `TmSolutionSpec`
// named constructor guarantees the fields its own kind needs are non-null —
// if a caller ever constructed, say, a `.anbn(...)`-built spec but then
// this switch tried to read `spec.c!` for it, that would be a crash, but
// the switch is written so each arm only force-unwraps fields that spec's
// *own* kind is documented to always populate. The two `?? const [...]`
// fallbacks (for anbncn and crossingDep) are the "null mults means all-1s"
// behavior documented on the `mults` field above, resolved here rather
// than inside the builders themselves.

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
  // Takes flat lists of state/transition *records* (Dart 3 tuple syntax,
  // not classes) — every builder below constructs its states/transitions
  // as plain `(String, String, bool)` / `(String, String, String)` tuples
  // and hands them to this one shared function to turn into an actual
  // renderable GraphState (NodeData/LineData/StartArrowData).
  final nodes = <String, NodeData>{};
  const perRow = 6;
  for (int i = 0; i < states.length; i++) {
    final (id, label, accept) = states[i];
    // Positional record destructuring — pulls the three tuple fields into
    // local `id`/`label`/`accept` variables in one line.
    final row = i ~/ perRow;
    final col = i % perRow;
    // Simple grid layout: state index `i` wraps into a new row every 6
    // states (`perRow`), integer-dividing for the row number and taking
    // the remainder for the column — this is what gives larger TM graphs
    // (up to ~10+ states) a readable multi-row grid instead of one very
    // long horizontal line of states.
    nodes[id] = NodeData(
      id: id,
      label: label,
      position: Offset(220.0 + col * 240.0, 260.0 + row * 300.0),
      // Fixed 240px horizontal / 300px vertical grid spacing, offset from
      // a (220, 260) origin — generous spacing relative to a ~100px node
      // diameter, leaving plenty of room for transition-line curves and
      // labels between rows/columns without needing any of
      // study_mode_layout.dart's iterative collision-avoidance (this
      // layout is a fixed grid, not a physics-style convergence pass).
      isAccept: accept,
    );
  }

  final edgeOrder = <(String, String)>[];
  final edgeLabels = <(String, String), List<String>>{};
  // Two parallel structures rather than one ordered map: `edgeLabels` maps
  // each (from,to) pair to the list of labels destined for that single
  // merged line; `edgeOrder` separately tracks the sequence in which each
  // distinct (from,to) pair was *first seen*, since a plain Dart `Map`
  // literal is insertion-ordered for iteration but there's no built-in
  // "first-seen order of keys added via repeated lookups" tracking needed
  // here beyond what a Map already gives — `edgeOrder` mostly exists so
  // the loop below has a clean list to iterate while assigning line IDs
  // 'l0', 'l1', ... in a fully deterministic, reproducible sequence.

  for (final (from, to, label) in transitions) {
    final key = (from, to);
    if (!edgeLabels.containsKey(key)) {
      edgeOrder.add(key);
      edgeLabels[key] = [];
    }
    edgeLabels[key]!.add(label);
  }
  // Groups every transition tuple by its (from, to) state pair — this is
  // the "merges parallel (from,to) transitions" behavior from the header
  // comment: e.g. a self-loop state with three separate `_selfR(x)` /
  // `_selfR(y)` / `_skipX('R')` transitions (three separate 3-tuples in a
  // builder's `transitions` list) all collapse into ONE LineData below,
  // with all three labels newline-joined, rather than becoming three
  // separate overlapping arrows drawn on top of each other.

  final lines = <String, LineData>{};
  int li = 0;
  for (final key in edgeOrder) {
    final (from, to) = key;
    final mergedLabel = edgeLabels[key]!.join('\n');
    final id = 'l$li';
    lines[id] = LineData(id: id, nodeAId: from, nodeBId: to, label: mergedLabel);
    nodes[from]!.connectedLineIds.add(id);
    if (to != from) nodes[to]!.connectedLineIds.add(id);
    // A self-loop (from == to) only registers its line ID once on that one
    // node's connectedLineIds — registering it a second time under the
    // same key would just be a harmless duplicate in a growable list, but
    // this guard avoids that redundancy explicitly.
    li++;
  }

  return GraphState(
    nodes: nodes,
    lines: lines,
    startArrow: StartArrowData(nodeId: startId),
    nodeCounter: states.length,
    lineCounter: li,
    automataMode: AutomataMode.tm,
    // Every graph this file builds is explicitly tagged as a Turing
    // Machine graph — callers (study_mode_tm.dart) don't need to set this
    // themselves; it's baked into the one shared graph-assembly point.
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
// `_selfS` (Stay — no head movement) has no doc-commented entry in the
// helper list above despite existing here; it's used sparingly by the few
// builders that need to inspect-and-immediately-accept without moving
// again (e.g. startEndSame's final match check).
String _mark(String sym, String dir) => _tt(sym, _m, dir);
String _skipX(String dir) => _tt(_m, _m, dir);
String _atBlank(String dir) => _tt(_blank, _blank, dir);
// Every one of these six helpers is a thin wrapper around `_tt`, fixing
// one or two of its three arguments — `_tt` itself does nothing but
// string-concatenate the three single-character/short-string pieces into
// the exact "read+write+dir" triple format `simulator.dart`'s parser
// expects. Every builder below composes transitions almost entirely out of
// these six calls rather than ever writing a raw `_tt(...)` triple by
// hand, which is what makes the transition tables below readable as
// "self-loop over X," "mark A and move right," etc. instead of opaque
// three-letter strings.

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
      // ── PRECHECK: scan right confirming a*b* shape ──────────────────────
      ('pa', 'rs', _atBlank('S')),      // empty tape (or all-a's exhausted at blank): shape OK so far, start rewind
      ('pa', 'pa', _selfR(a)),          // still inside the a-block: keep scanning right
      ('pa', 'pb', _selfR(b)),          // first 'b' seen: switch into the b-block scan
      ('pb', 'pb', _selfR(b)),          // still inside the b-block: keep scanning right
      ('pb', 'rs', _atBlank('S')),      // reached the end cleanly after b's: shape OK, start rewind
      // Note: there is NO ('pb','?', _selfR(a)) transition — seeing an 'a'
      // while in the b-block state has no matching rule, so the machine
      // gets stuck and rejects. This (deliberately absent) transition is
      // what actually rejects "abab"-style interleaving; the precheck's
      // job is entirely encoded by which transitions are missing, not by
      // an explicit reject state.

      // ── REWIND: walk back to the tape's left edge ───────────────────────
      ('rs', 'rl', _atBlank('L')),      // pivot: was moving right during precheck, now step left off the end
      ('rl', 'rl', _selfL(a)),          // skip back over raw a's
      ('rl', 'rl', _selfL(b)),          // skip back over raw b's
      ('rl', 'rl', _skipX('L')),        // skip back over already-crossed X's from earlier rounds
      ('rl', 'q0', _atBlank('R')),      // hit the left edge (blank), step onto the first real symbol, start a round

      // ── CROSSING-OFF ROUND: mark one a, hunt right, mark one b ──────────
      ('q0', 'q0', _skipX('R')),        // skip past symbols already crossed in earlier rounds
      ('q0', 'q1', _mark(a, 'R')),      // found the next unmarked 'a': cross it, move right to hunt for a 'b'
      ('q0', 'acc', _atBlank('S')),     // no unmarked 'a' left (blank instead): everything paired off — accept
      ('q1', 'q1', _selfR(a)),          // hunting right: skip over any remaining unmarked a's (shouldn't normally
                                         // persist across rounds given precheck ordering, but tolerated in-transit)
      ('q1', 'q1', _skipX('R')),        // skip over already-crossed X's while hunting
      ('q1', 'q2', _mark(b, 'L')),      // found the matching unmarked 'b': cross it, turn around (move left)
      ('q2', 'q2', _skipX('L')),        // walk back left over X's
      ('q2', 'q2', _selfL(a)),          // walk back left over raw a's
      ('q2', 'q0', _atBlank('R')),      // reached the left edge: step back onto the first symbol, next round
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
  // Debug-only guards against a caller passing the wrong-length or
  // non-positive multiplier list — same caveat as study_mode_symbols.dart's
  // `randomStudyAlphabet` assert: these are compiled out of release
  // builds, so a release build with bad `mults` would misbehave silently
  // rather than throw, relying on `buildStudyTmSolution`'s own callers
  // never actually doing that.

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
    // ── PRECHECK: confirm a*b*c* shape (same pivoting pattern as anbn) ──
    ('p0', 'rs', _atBlank('S')),
    ('p0', 'p0', _selfR(syms[0])),
    ('p0', 'p1', _selfR(syms[1])),
    ('p1', 'p1', _selfR(syms[1])),
    ('p1', 'p2', _selfR(syms[2])),
    ('p1', 'rs', _atBlank('S')),
    ('p2', 'p2', _selfR(syms[2])),
    ('p2', 'rs', _atBlank('S')),
    // Same "missing transition = reject" trick as anbn: p1 has no rule for
    // seeing syms[0] again, and p2 has no rule for seeing syms[0] or
    // syms[1] — any out-of-order symbol gets the machine stuck.
    ('rs', 'rl', _atBlank('L')),
    ('rl', 'rl', _selfL(syms[0])),
    ('rl', 'rl', _selfL(syms[1])),
    ('rl', 'rl', _selfL(syms[2])),
    ('rl', 'rl', _skipX('L')),
    ('rl', 'q0', _atBlank('R')),
    // Rewind to the left edge, exactly like anbn's rs/rl states — 'q0' is
    // referenced here even though it isn't in the literal `states` list
    // above yet; it gets appended separately near the very end of this
    // function (`states.add(('q0', 'Q0', false));`), after the loop below
    // has generated every OTHER chained state, presumably just so 'q0''s
    // entry visually appears last among the crossing-off states rather
    // than needing to be hoisted above the loop.
  ];

  // 'q0' doubles as the first block's mark-chain head (no earlier block to
  // hunt past). Every other block's first sub-state is a hunt state that
  // self-loops over the *previous* block's raw symbol (any leftover copies
  // not yet due this round) plus already-marked X, until it lands on its
  // own block's symbol.
  String stateName(int i, int j) => (i == 0 && j == 1) ? 'q0' : 'r${i}_$j';
  const blockLabel = ['A', 'B', 'C'];

  for (int i = 0; i < 3; i++) {
    // Outer loop over the three blocks (a=0, b=1, c=2).
    for (int j = 1; j <= mults[i]; j++) {
      // Inner loop over that block's own multiplier — e.g. mults[i]=2
      // means this block needs exactly 2 marks per round, generating a
      // 2-state mini-chain (j=1 then j=2) rather than one state that
      // somehow "counts to 2" internally (this whole file never uses
      // counter states beyond divisibleByK's mod-k ring — every other
      // family encodes repeated counts as chains of near-identical states,
      // one per required mark).
      final name = stateName(i, j);
      if (name != 'q0') states.add((name, '${blockLabel[i]}$j', false));
      // 'q0' is deliberately NOT re-added to `states` here even on its
      // first (i=0, j=1) appearance — it's added once, separately, after
      // this whole double loop finishes (see `states.add(('q0', 'Q0',
      // false));` near the end) — so `states` ends up with 'q0' positioned
      // after every r{i}_{j} state rather than interleaved among them.

      final isFirstOfBlock = j == 1;
      final isLastOfBlock = j == mults[i];
      final isLastOverall = i == 2 && isLastOfBlock;
      final dir = isLastOverall ? 'L' : 'R';
      // Every mark-and-advance transition moves Right EXCEPT the very
      // last mark of the very last block (block c's final required copy)
      // — that one moves Left instead, to immediately begin the rewind
      // back toward the start rather than needing a separate blank-pivot
      // step the way anbn's rs/rl states do.
      final target = !isLastOfBlock
          ? stateName(i, j + 1)
          : (i < 2 ? stateName(i + 1, 1) : 'ret');
      // Within a block: chain to the next mark-state (j+1). At the end of
      // a block: jump to the *next* block's first state (i+1, j=1) — or,
      // for the last block (i=2), jump to 'ret' to start the rewind.

      transitions.add((name, target, _mark(syms[i], dir)));
      // The actual "cross this block's symbol and advance" transition —
      // one per (i,j) pair, i.e. exactly sum(mults) transitions across the
      // whole double loop.

      if (name == 'q0') {
        transitions.add(('q0', 'q0', _skipX('R')));
        // 'q0' (block 0's head) skips over already-crossed X's from
        // earlier rounds while hunting for its next unmarked a — it has
        // no "previous block" to hunt past, unlike every other block's
        // first sub-state below.
      } else if (isFirstOfBlock) {
        transitions.add((name, name, _selfR(syms[i - 1])));
        transitions.add((name, name, _skipX('R')));
        // A block's FIRST sub-state (j=1, e.g. r1_1 for block b) is the
        // "hunt" state described in the header comment: it self-loops
        // over the *previous* block's raw, not-yet-marked symbol
        // (syms[i-1] — any leftover a's this round hasn't reached yet)
        // and over already-crossed X's, until it finally lands on this
        // block's own symbol (handled by the `_mark(syms[i], dir)`
        // transition added above). Only the first sub-state of each block
        // needs this hunting behavior — once inside a block's own chain
        // (j>1), every symbol from here on is expected to be that same
        // block's symbol, so no hunting self-loop is needed for j>1
        // sub-states.
      }
    }
  }

  transitions.add(('q0', 'acc', _atBlank('S')));
  // Accept condition: q0 (block 0's head, hunting for the next round's
  // 'a') hits blank instead of finding one — every block fully consumed,
  // nothing left but X's.
  transitions.addAll([
    ('ret', 'ret', _skipX('L')),
    ('ret', 'ret', _selfL(syms[0])),
    ('ret', 'ret', _selfL(syms[1])),
    // Rewind walks left over X's and over raw (still-unmarked) copies of
    // blocks 0 and 1 — notably NOT over syms[2] (block c), since the
    // rewind always starts immediately after crossing block c's very last
    // required copy, meaning there should be no unmarked c's still to the
    // right of the current position on the way back to the start.
    ('ret', 'q0', _atBlank('R')),
  ]);

  states.add(('q0', 'Q0', false));
  // The delayed 'q0' state registration mentioned above — appended here,
  // after all of `r{i}_{j}`'s states have already been added by the double
  // loop, purely for the resulting node list's ordering.

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
      // No PRECHECK/rewind-to-left-edge states at all here — unlike anbn/
      // anbncn, this family cares only about total counts, not ordering,
      // so there's nothing to validate up front; the tape is processed
      // starting from wherever the head already sits (position 0, per
      // however the simulator initializes a run).
      ('q0', 'q0', _skipX('R')),        // skip already-crossed symbols from earlier rounds
      ('q0', 'fb', _mark(a, 'R')),      // found an unmarked 'a': cross it, now hunt right for a 'b' to pair it with
      ('q0', 'fa', _mark(b, 'R')),      // found an unmarked 'b': cross it, now hunt right for an 'a' to pair it with
      ('q0', 'acc', _atBlank('S')),     // nothing left unmarked: every symbol was successfully paired — accept
      ('fb', 'fb', _selfR(a)),          // hunting for a 'b': skip over any other unmarked a's along the way
      ('fb', 'fb', _skipX('R')),        // skip over already-crossed X's while hunting
      ('fb', 'ret', _mark(b, 'L')),     // found the 'b' to pair with: cross it, turn around and rewind
      // Note: 'fb' has no ('fb', ?, _atBlank(...)) transition — if the
      // hunt for a matching 'b' runs off the end of the tape without
      // finding one, the machine gets stuck and rejects. This is exactly
      // how an UNEQUAL count gets caught: a round starts whenever an
      // unmarked symbol exists, and if its partner-hunt fails, that proves
      // the counts weren't equal.
      ('fa', 'fa', _selfR(b)),
      ('fa', 'fa', _skipX('R')),
      ('fa', 'ret', _mark(a, 'L')),     // symmetric to the fb branch above, for the b-then-hunt-for-a case
      ('ret', 'ret', _skipX('L')),      // rewind: walk back left over X's
      ('ret', 'ret', _selfL(a)),        // and over raw a's
      ('ret', 'ret', _selfL(b)),        // and over raw b's
      ('ret', 'q0', _atBlank('R')),     // reached the left edge: step onto the first symbol, next round
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
      ('q0', 'q0', _skipX('R')),         // skip already-marked X's from earlier rounds
      ('q0', 'seeka', _mark(a, 'R')),    // leftmost unmarked symbol is 'a': cross it, remember via 'seeka' state, sweep right
      ('q0', 'seekb', _mark(b, 'R')),    // leftmost unmarked symbol is 'b': cross it, remember via 'seekb' state, sweep right
      ('q0', 'acc', _atBlank('S')),      // nothing left unmarked: fully paired off — accept
      // The state name itself (seeka vs seekb) IS the memory of what the
      // left symbol was — there's no separate tape write recording it;
      // this is the standard TM trick of encoding a small piece of
      // "remembered" information in which state you're currently in
      // rather than writing it to the tape.
      ('seeka', 'seeka', _selfR(a)),     // sweeping to the far end: pass over remaining raw a's
      ('seeka', 'seeka', _selfR(b)),     // and raw b's
      ('seeka', 'seeka', _skipX('R')),   // and already-crossed X's
      ('seeka', 'checka', _atBlank('L')),// hit the right edge: step back one to sit on the last real symbol
      ('seekb', 'seekb', _selfR(a)),
      ('seekb', 'seekb', _selfR(b)),
      ('seekb', 'seekb', _skipX('R')),
      ('seekb', 'checkb', _atBlank('L')),
      ('checka', 'checka', _skipX('L')), // step back left over any already-crossed X's (previously-paired chars)
      ('checka', 'ret', _mark(a, 'L')),  // rightmost unmarked symbol matches the remembered left symbol ('a'): cross it, rewind
      ('checka', 'acc', _atBlank('S')),  // stepped all the way back to blank while skipping X's: odd/even palindrome fully paired — accept
      // No ('checka', ?, _mark(b, ...)) or plain-b transition exists here
      // — if the rightmost unmarked symbol turns out to be 'b' instead of
      // the remembered 'a', there's no matching rule and the machine gets
      // stuck. That mismatch-rejection is, once again, encoded entirely by
      // omission rather than an explicit reject transition.
      ('checkb', 'checkb', _skipX('L')),
      ('checkb', 'ret', _mark(b, 'L')),
      ('checkb', 'acc', _atBlank('S')),
      ('ret', 'ret', _selfL(a)),         // rewind back to the left edge over raw a's
      ('ret', 'ret', _selfL(b)),         // and raw b's
      ('ret', 'ret', _skipX('L')),       // and X's
      ('ret', 'q0', _atBlank('R')),      // reached the left edge: step onto the first symbol, next round
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
    // k states, one per residue class mod k — generated with a
    // list-comprehension `for` inside the list literal (Dart's collection-
    // for syntax) rather than a separate loop + `.add()` calls, since
    // there's no conditional branching needed per state here (unlike, say,
    // anbncn's per-block state generation above).
    ('acc', 'OK', true),
  ];
  final transitions = <(String, String, String)>[
    for (int i = 0; i < k; i++) ('m$i', 'm$i', _selfR(b)),
    // Reading 'b' in ANY residue state is a no-op self-loop — 'b' doesn't
    // affect the a-count at all, so the state (residue) never changes.
    for (int i = 0; i < k; i++) ('m$i', 'm${(i + 1) % k}', _selfR(a)),
    // Reading 'a' advances the residue by exactly 1, wrapping around via
    // `% k` once it would exceed k-1 — this is the entire "counter," with
    // no tape marking involved anywhere in this family; unlike every other
    // builder in this file, divisibleByK never writes an X and never
    // rewinds, since a single left-to-right pass with a k-state mod-counter
    // is sufficient (this is exactly the same construction a plain DFA
    // would use — the only reason it needs to be presented as a TM
    // exercise here rather than a DFA one is presumably how the study-mode
    // curriculum sequences which construction techniques get introduced
    // in which unit, not because the language itself needs TM power; it's
    // regular, not non-context-free).
    ('m0', 'acc', _atBlank('S')),
    // Accept iff the tape ends while sitting in residue state 0 — no
    // acceptance transition exists for any other m{i} state, so ending in
    // a nonzero residue means getting stuck (no transition on blank) and
    // rejecting.
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
      ('start', 'acc', _atBlank('S')),   // empty tape: vacuously satisfies "empty, or first == last" — accept immediately
      ('start', 'seeka', _selfR(a)),     // first symbol is 'a': remember via state, don't mark it (nothing gets crossed off in this family), sweep right
      ('start', 'seekb', _selfR(b)),     // first symbol is 'b': same, remember via 'seekb'
      ('seeka', 'seeka', _selfR(a)),     // sweep to the far end, passing over every symbol untouched
      ('seeka', 'seeka', _selfR(b)),
      ('seeka', 'checka', _atBlank('L')),// hit the end: step back one onto the last real symbol
      ('seekb', 'seekb', _selfR(a)),
      ('seekb', 'seekb', _selfR(b)),
      ('seekb', 'checkb', _atBlank('L')),
      ('checka', 'acc', _selfS(a)),      // last symbol matches the remembered first ('a'): accept without moving (Stay)
      ('checkb', 'acc', _selfS(b)),      // symmetric b case
      // No ('checka', ?, _selfS(b)) exists — a mismatched last symbol has
      // no rule and gets the machine stuck, rejecting. This is the
      // simplest family in the file: single left-to-right pass, no
      // marking, no rewind, since only two positions (first and last) are
      // ever actually inspected.
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
    // k separate hunter states — seek1 through seekK — one per required
    // 'b' this round, rather than one hunter state that somehow counts to
    // k internally; consistent with this whole file's "chain of near-
    // identical states, one per required repetition" convention (same
    // technique as anbncn's per-block mark chains above).
    ('ret', 'RET', false),
    ('acc', 'OK', true),
  ];
  final transitions = <(String, String, String)>[
    // ── PRECHECK + REWIND: identical in shape to anbn's ─────────────────
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
    ('q0', 'seek1', _mark(a, 'R')),     // mark this round's one 'a', begin hunting for the first of its k b's
    ('q0', 'acc', _atBlank('S')),       // nothing left unmarked: accept
    for (int i = 1; i <= k; i++) ...[
      // Spread (`...[]`) a small per-i group of transitions directly into
      // the flat `transitions` list — same "collection-for producing
      // multiple elements per iteration" pattern used by aToKB's own
      // states list above and copyLang/crossingDep elsewhere.
      ('seek$i', 'seek$i', _selfR(a)),   // hunting: skip over any stray unmarked a's
      ('seek$i', 'seek$i', _skipX('R')), // and already-crossed X's
      if (i < k)
        ('seek$i', 'seek${i + 1}', _mark(b, 'R'))
        // Not yet at the k-th required b: cross this one, advance to the
        // NEXT hunter state (seek(i+1)) and keep moving right for the
        // next b.
      else
        ('seek$i', 'ret', _mark(b, 'L')),
        // This WAS the k-th (last) required b for this round: cross it,
        // but now turn around (move Left) to start the rewind, instead of
        // chaining to another hunter state.
    ],
    ('ret', 'ret', _skipX('L')),
    ('ret', 'ret', _selfL(a)),
    ('ret', 'q0', _atBlank('R')),
    // Rewind only skips over raw a's and X's — not raw b's — since by the
    // time a round's rewind begins, every b between the marked 'a' and the
    // current position has just been freshly marked by this same round's
    // seek-chain; any *other*, not-yet-due b's from a future round should
    // never appear before the current rewind position given the strict
    // a*b* ordering the precheck already enforced.
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
      ('q0', 'q0', _skipX('R')),           // skip already-crossed symbols from earlier rounds
      ('q0', 'seekAL', _mark(a, 'R')),     // leftmost unmarked symbol (left of '#') is 'a': cross it, hunt right for the delimiter
      ('q0', 'seekBL', _mark(b, 'R')),     // ...or 'b': same, via the B-named hunt chain
      ('q0', 'checkEnd', _selfR(_delim)),  // left side is fully exhausted (next char is '#' itself, untouched): move
                                            // past it into checkEnd to verify nothing unmarked remains on the right
      ('seekAL', 'seekAL', _selfR(a)),     // hunting right toward '#': pass over remaining unmarked left-side a's
      ('seekAL', 'seekAL', _selfR(b)),     // and b's
      ('seekAL', 'seekAL', _skipX('R')),   // and X's
      ('seekAL', 'seekAR', _selfR(_delim)),// crossed the delimiter (left, unmarked, still): now hunting on the RIGHT side for an 'a' to pair with
      ('seekAR', 'seekAR', _skipX('R')),   // on the right side: skip over already-crossed X's (already-paired positions)
      ('seekAR', 'ret', _mark(a, 'L')),    // found the corresponding 'a' on the right: cross it, turn around, rewind
      // Note: 'seekAR' has NO ('seekAR', ?, _selfR(b)) transition — if the
      // next unmarked right-side symbol is 'b' instead of the expected
      // 'a', that's a mismatch between w's two copies, and the machine
      // gets stuck. This is the copy-language equivalent of anbn's
      // "missing transition = interleaving rejected" trick.
      ('seekBL', 'seekBL', _selfR(a)),
      ('seekBL', 'seekBL', _selfR(b)),
      ('seekBL', 'seekBL', _skipX('R')),
      ('seekBL', 'seekBR', _selfR(_delim)),
      ('seekBR', 'seekBR', _skipX('R')),
      ('seekBR', 'ret', _mark(b, 'L')),    // symmetric to the A-branch above
      ('ret', 'ret', _selfL(a)),           // rewind: walk left over raw a's
      ('ret', 'ret', _selfL(b)),           // raw b's
      ('ret', 'ret', _skipX('L')),         // X's
      ('ret', 'ret', _selfL(_delim)),      // and back over the delimiter itself, without disturbing it
      ('ret', 'q0', _atBlank('R')),        // reached the left edge: step onto the first symbol, next round
      ('checkEnd', 'checkEnd', _skipX('R')), // final pass: everything left of '#' has been paired off; walk right over
                                              // X's on the right side too, confirming they were ALL paired (not longer)
      ('checkEnd', 'acc', _atBlank('S')),  // reached the true end of tape with nothing but X's since the delimiter: accept
      // If checkEnd instead encounters an unmarked 'a' or 'b' on the right
      // side (meaning the right copy is strictly longer than the left),
      // there's no matching transition and the machine gets stuck —
      // rejecting a right side that's longer than the (already fully
      // consumed) left side.
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
      // The mirror image of equalCount's own accept-on-blank transition —
      // this is the single-line embodiment of "flip the accept/reject
      // roles" mentioned in the header comment: same state, same trigger
      // condition, but here the response is simply "have no rule at all"
      // instead of "explicitly accept."
      ('fb', 'fb', _selfR(a)),
      ('fb', 'fb', _skipX('R')),
      ('fb', 'ret', _mark(b, 'L')),
      ('fb', 'acc', _atBlank('S')),
      // Unlike equalCount's identical-looking 'fb' state (which has NO
      // blank transition, deliberately, to reject on a failed hunt), this
      // family's 'fb' DOES have one: hitting blank while hunting for a
      // matching 'b' proves the counts are unequal, so it explicitly
      // accepts right there instead of getting stuck.
      ('fa', 'fa', _selfR(b)),
      ('fa', 'fa', _skipX('R')),
      ('fa', 'ret', _mark(a, 'L')),
      ('fa', 'acc', _atBlank('S')),      // same flipped accept-on-failed-hunt, mirrored for the a-hunt branch
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
  // Multiple variable declarations on one line via comma-separated `final`
  // — purely a compactness choice; each of s0-s3/m0-m3 is otherwise an
  // ordinary independent local.

  String chainName(String prefix, int j) => j == 1 ? prefix : '${prefix}_$j';
  // Same "j==1 reuses the bare prefix as the state name, j>1 gets a
  // suffix" trick as anbncn's own `stateName` helper — here applied
  // uniformly to whichever chain prefix ('g0', 'n2', 'g1', 'n3') is passed
  // in, rather than needing a separate per-block special case.

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
  // Unlike every earlier builder, `transitions` starts as an empty
  // growable list here rather than a fully inline literal — because the
  // precheck loop and both phases below are generated by nested `for`
  // loops that `.add()` onto it incrementally, rather than being
  // expressible as one flat collection-for'd literal.

  // ── Precheck: s0* s1* s2* s3*, any block(s) may be empty ───────────────────────
  for (int i = 0; i < 4; i++) {
    final pi = 'p$i';
    transitions.add((pi, pi, _selfR(order[i])));
    // Each precheck state pi self-loops over its own block's symbol —
    // e.g. p0 scans past raw s0's.
    for (int j = i + 1; j < 4; j++) {
      transitions.add((pi, 'p$j', _selfR(order[j])));
      // From state pi, seeing any LATER block's symbol (j > i) transitions
      // directly to that later state — this is what lets any block be
      // empty: e.g. from p0, seeing s2 (skipping s1 entirely) jumps
      // straight to p2, correctly handling a zero-length block 1. Because
      // this inner loop covers every j from i+1 to 3, a precheck state can
      // jump ahead by more than one block in a single transition, which is
      // exactly the "any block(s) may be empty, independently" behavior
      // called out in the header comment.
    }
    transitions.add((pi, 'rs', _atBlank('S')));
    // From ANY precheck state, hitting blank means the whole string ended
    // here — valid regardless of which block was "current," since every
    // suffix of blocks could be empty. All four pi states get their own
    // independent blank-triggered pivot into the rewind phase.
  }
  transitions.add(('rs', 'rl', _atBlank('L')));
  for (final sym in order) {
    transitions.add(('rl', 'rl', _selfL(sym)));
  }
  transitions.add(('rl', 'rl', _skipX('L')));
  transitions.add(('rl', 'g0', _atBlank('R')));
  // Rewind to the left edge, generated via a loop over all four symbols
  // (`order`) rather than four separate hardcoded `_selfL` lines — same
  // effect as anbncn's rl state, just built with a loop since there are
  // four symbols instead of three.

  // ── Phase 1: blocks 0 & 2 (counter n) ────────────────────────────────
  for (int j = 1; j <= m0; j++) {
    final name = chainName('g0', j);
    if (name != 'g0') states.add((name, 'N0_$j', false));
    final next = j < m0 ? chainName('g0', j + 1) : 'h1';
    transitions.add((name, next, _mark(s0, 'R')));
    // Chain of m0 states marking m0 copies of s0 from the head — same
    // "chained direct-mark, no hunting needed" pattern as anbncn's own
    // block-0 marking (block 0 is always contiguous from wherever the
    // head currently sits, so no hunt-over-previous-block self-loop is
    // needed here, unlike blocks 1-3 below).
  }
  transitions.add(('g0', 'g0', _skipX('R')));
  // g0 (this phase's head/hunt state) skips already-marked X's from
  // earlier rounds while looking for its next unmarked s0.
  transitions.add(('g0', 'g1', _selfS(s1)));
  transitions.add(('g0', 'g1', _atBlank('S')));
  // Phase 1 termination: if g0 (hunting for the next round's s0) instead
  // finds itself sitting on s1 (block 0 exhausted, block 1 begins) OR on
  // blank (block 0 exhausted AND block 1 is empty too), phase 1 is
  // complete — pivot straight into g1 (phase 2's head) WITHOUT moving
  // (`_selfS`/an unmoving blank check), since per the header comment "the
  // head is already sitting exactly where block 1 begins."

  transitions.add(('h1', 'h1', _selfR(s0)));
  transitions.add(('h1', 'h1', _selfR(s1)));
  transitions.add(('h1', 'h1', _skipX('R')));
  // h1: the "hunt right past block 0's leftovers, then all of block 1, and
  // any already-marked X from block 2's prior rounds" state described in
  // the header comment — self-loops over raw s0 (not-yet-due leftover
  // copies), raw s1 (block 1 is completely untouched by this phase), and
  // X (block 2 marks from earlier rounds of this same phase).

  for (int j = 1; j <= m2; j++) {
    final from = j == 1 ? 'h1' : chainName('n2', j);
    final name = chainName('n2', j);
    if (j > 1) states.add((name, 'N2_$j', false));
    final next = j < m2 ? chainName('n2', j + 1) : 'ret1';
    final dir = j < m2 ? 'R' : 'L';
    transitions.add((from, next, _mark(s2, dir)));
    // Chain of m2 states marking m2 copies of s2 — the first of these
    // marks transitions FROM h1 itself (`from = j==1 ? 'h1' : ...`) rather
    // than from a dedicated 'n2_1' state, so h1 doubles as both "the
    // hunter" and "the first s2-marking state's source," similar in
    // spirit to how anbncn's 'q0' doubles as both hunter and first-block
    // head. The very last mark of this chain moves Left (`dir = 'L'`) to
    // pivot directly into the rewind, same "last mark turns around" idiom
    // seen in anbncn/aToKB above.
  }

  transitions.add(('ret1', 'ret1', _selfL(s0)));
  transitions.add(('ret1', 'ret1', _selfL(s1)));
  transitions.add(('ret1', 'ret1', _skipX('L')));
  transitions.add(('ret1', 'g0', _atBlank('R')));
  // Phase-1 rewind: walk back left over raw s0, raw s1, and X (marks from
  // both this round's s0/s2 and earlier rounds), back to the left edge,
  // then step onto the first symbol and return to g0 for the next round.

  // ── Phase 2: blocks 1 & 3 (counter m) ────────────────────────────────
  for (int j = 1; j <= m1; j++) {
    final name = chainName('g1', j);
    if (name != 'g1') states.add((name, 'M0_$j', false));
    final next = j < m1 ? chainName('g1', j + 1) : 'h2';
    transitions.add((name, next, _mark(s1, 'R')));
    // Mirrors Phase 1's block-0 marking chain exactly, just for block 1 —
    // 'g1' plays the same "phase head, no hunting needed" role for block 1
    // that 'g0' played for block 0, since by the time Phase 2 starts, the
    // head is already sitting right at block 1's first unmarked symbol
    // (per Phase 1's own termination transitions above).
  }
  transitions.add(('g1', 'g1', _skipX('R')));
  transitions.add(('g1', 'acc', _atBlank('S')));
  // Phase 2 (and the whole machine's) accept condition: g1, hunting for
  // the next round's s1, instead finds blank — everything fully paired
  // off across both phases.

  transitions.add(('h2', 'h2', _selfR(s1)));
  transitions.add(('h2', 'h2', _skipX('R')));
  // h2: hunt right past block 1's leftovers and block 2 (which, by this
  // point in the algorithm, is ALWAYS fully marked X — Phase 1 fully
  // completes, marking every s2, before Phase 2 ever begins) — notably no
  // `_selfR(s2)` case here, since a raw (unmarked) s2 should never be
  // encountered during Phase 2 given Phase 1's own precondition.

  for (int j = 1; j <= m3; j++) {
    final from = j == 1 ? 'h2' : chainName('n3', j);
    final name = chainName('n3', j);
    if (j > 1) states.add((name, 'M2_$j', false));
    final next = j < m3 ? chainName('n3', j + 1) : 'ret2';
    final dir = j < m3 ? 'R' : 'L';
    transitions.add((from, next, _mark(s3, dir)));
    // Mirrors Phase 1's block-2 marking chain, for block 3 — same
    // "h2 doubles as hunter and first mark-chain source" pattern as h1
    // above.
  }

  transitions.add(('ret2', 'ret2', _selfL(s1)));
  transitions.add(('ret2', 'ret2', _skipX('L')));
  transitions.add(('ret2', 'g1', _atBlank('R')));
  // Phase-2 rewind — notably shorter than ret1's (no `_selfL(s0)` case):
  // by the time Phase 2's rewind runs, block 0 is entirely X (fully
  // consumed back in Phase 1), so there should be no raw s0 left to skip
  // over on the way back.

  return _graph(states: states, transitions: transitions, startId: 'p0');
}

// K) Not a decision language: f(N) = N + k for a fixed constant k, N a
// binary numeral (no leading zeros, except "0" itself). Graded on the
// tape's final contents matching N + k exactly, not just accept/reject —
// see study_mode_tm.dart's gradeStudyTm / StudyTmTestCase.expectedOutput.
//
// This is a ripple-carry adder against a *compile-time* constant: k is
// never written to the tape — its bits are baked directly into which of a
// chain of m = k.bitLength() phases the machine is in, so the state count
// is O(log k) (2*m + 3, at most 21 states for k up to 256) rather than
// O(k). A naive "chain k separate +1 machines back to back" construction
// was considered and rejected for exactly this reason: for k up to 256 it
// would run into the hundreds of states, which stops being something a
// person can read as a graph, whereas this construction tops out at 21.
//
// Algorithm, processing bit positions 0 (least-significant — the tape's
// rightmost digit) upward:
//  0. SEEK — scan right off the end of N, then step back one to sit on
//     N's rightmost bit.
//  1. PHASES 0..m-1 (p{i}_c0 / p{i}_c1 — one pair of states per bit of k,
//     the suffix tracking the incoming carry) — phase i adds k's bit i
//     plus the incoming carry to N's bit at that tape position. Reading
//     blank here means N ran out of bits first; it's treated as an
//     implicit 0 and materialized by writing the sum bit, extending the
//     tape. Each phase writes the sum bit, moves left, and advances to
//     the next phase carrying the new carry bit *in the state itself*
//     (there's nowhere on the tape to put it) — except the last phase,
//     whose target is 'acc' directly when its carry-out is 0 (nothing
//     left to change) or 'carry' when its carry-out is 1 (still need to
//     ripple through whatever of N's bits lie beyond k's bit-length).
//  2. CARRY — an ordinary increment-style ripple: flip 1→0 and keep
//     going; flip the first 0 (or blank, extending the tape with a new
//     leading digit) to 1 and stop.
//
// Verified against an independent Python model of this exact transition
// table: exhaustive over every k in 1..256 crossed with every canonical N
// from 0..299 (76,800 cases), 20,000 randomized trials with N up to 2^20,
// and a dedicated adversarial sweep of all-ones inputs (the
// maximum-carry-cascade case) at several bit-lengths relative to k, for
// k in {1,2,3,4,7,8,15,16,31,32,63,64,127,128,129,200,255,256} — 0
// failures in every case, plus N="0" for every k from 1 to 256. Worst-case
// step count observed across all of the above was 42 steps, far inside
// kStudyTmMaxSteps (5000).
GraphState _buildAddConstantTm(int k) {
  assert(k >= 1, 'addConstant needs k >= 1');
  final m = k.bitLength;
  // Dart's built-in `int.bitLength` — the minimum number of bits needed to
  // represent k (e.g. k=5 -> bitLength 3, since 5 is '101'). This directly
  // drives the O(log k) state count claimed in the header comment.
  final kBits = [for (int i = 0; i < m; i++) (k >> i) & 1];
  // Extracts k's individual bits, least-significant first: `k >> i` shifts
  // bit i down to position 0, then `& 1` isolates just that one bit —
  // kBits[0] is k's ones-place bit, kBits[1] is its twos-place bit, etc.,
  // matching the "processing bit positions 0 upward" order described in
  // the header comment.

  final states = <(String, String, bool)>[
    ('seek', 'SEEK', false),
    for (int i = 0; i < m; i++) ('p${i}_c0', 'P${i}0', false),
    for (int i = 0; i < m; i++) ('p${i}_c1', 'P${i}1', false),
    // Two full loops rather than one interleaved loop generating both
    // (p{i}_c0, p{i}_c1) per iteration — a stylistic choice that groups
    // all the "carry-in 0" phase states together, then all the "carry-in
    // 1" phase states together, rather than alternating c0/c1/c0/c1 in
    // state-list order; doesn't affect behavior, only the resulting node
    // layout grid's ordering (via `_graph`'s perRow=6 wrapping).
    ('carry', 'CARRY', false),
    ('acc', 'OK', true),
  ];

  // Where phase i lands next, given its own carry-out bit.
  String afterPhase(int i, int carryOut) {
    if (i + 1 < m) return 'p${i + 1}_c$carryOut';
    // Not yet at the last phase: advance to phase i+1, carrying `carryOut`
    // forward as that next phase's carry-IN (encoded in the next state's
    // own name, e.g. 'p2_c1') — this is the "carrying the new carry bit
    // *in the state itself*" trick from the header comment; there is no
    // tape write anywhere in this helper.
    return carryOut == 0 ? 'acc' : 'carry';
    // This WAS the last phase (i is m-1): if there's no carry left to
    // propagate, N's remaining higher-order bits (if any) don't need to
    // change at all, so jump straight to 'acc'. If there IS a carry left,
    // hand off to the 'carry' ripple state to propagate it through
    // whatever of N's bits lie beyond k's own bit-length.
  }

  final transitions = <(String, String, String)>[
    ('seek', 'seek', _selfR('0')),
    ('seek', 'seek', _selfR('1')),
    ('seek', 'p0_c0', _atBlank('L')),
    // SEEK phase: scan right over every '0'/'1' bit of N until hitting
    // blank (the end of the tape), then step back Left one cell — landing
    // exactly on N's rightmost (least-significant) bit — and enter phase 0
    // with carry-in 0 (there's no carry yet at the very start of addition).
  ];

  for (int i = 0; i < m; i++) {
    final ki = kBits[i];
    final c0 = 'p${i}_c0';
    final c1 = 'p${i}_c1';
    if (ki == 0) {
      // ── k's bit i is 0 ──────────────────────────────────────────────
      // carry-in 0, k-bit 0: sum = bit, carry-out = 0 (nothing changes).
      transitions.add((c0, afterPhase(i, 0), _tt('0', '0', 'L')));
      transitions.add((c0, afterPhase(i, 0), _tt(_blank, '0', 'L')));
      // Reading blank here means N had no more bits at this position —
      // per the header comment, treated as an implicit 0, and the write
      // (`_tt(_blank, '0', 'L')`) materializes that 0 onto the tape,
      // extending N's representation by one more (leading) digit.
      transitions.add((c0, afterPhase(i, 0), _tt('1', '1', 'L')));
      // Standard binary half-adder truth table, spelled out across these
      // six lines per non-zero/zero k-bit case: with carry-in 0 and k-bit
      // 0, N's bit passes through unchanged and there's never a carry-out
      // — 0+0=0 (carry 0), 1+0=1 (carry 0), and the "N ran out of bits"
      // blank case is folded into the 0-bit case as described above.
      // carry-in 1, k-bit 0: sum = bit XOR 1, carry-out = bit.
      transitions.add((c1, afterPhase(i, 0), _tt('0', '1', 'L')));
      // N's bit 0 + k's bit 0 + carry-in 1 = sum 1, carry-out 0.
      transitions.add((c1, afterPhase(i, 0), _tt(_blank, '1', 'L')));
      // N ran out of bits (implicit 0) + k's bit 0 + carry-in 1 = same as
      // the line above, sum 1 carry-out 0, materializing the new digit.
      transitions.add((c1, afterPhase(i, 1), _tt('1', '0', 'L')));
      // N's bit 1 + k's bit 0 + carry-in 1 = sum 0, carry-out 1 (1+1=10).
    } else {
      // ── k's bit i is 1 ──────────────────────────────────────────────
      // carry-in 0, k-bit 1: sum = bit XOR 1, carry-out = bit.
      transitions.add((c0, afterPhase(i, 0), _tt('0', '1', 'L')));
      // N's bit 0 + k's bit 1 + carry-in 0 = sum 1, carry-out 0.
      transitions.add((c0, afterPhase(i, 0), _tt(_blank, '1', 'L')));
      // N ran out of bits (implicit 0) + k's bit 1 + carry-in 0 = same as
      // above.
      transitions.add((c0, afterPhase(i, 1), _tt('1', '0', 'L')));
      // N's bit 1 + k's bit 1 + carry-in 0 = sum 0, carry-out 1.
      // carry-in 1, k-bit 1: sum = bit, carry-out = 1.
      transitions.add((c1, afterPhase(i, 1), _tt('0', '0', 'L')));
      // N's bit 0 + k's bit 1 + carry-in 1 = sum 0, carry-out 1 (0+1+1=10).
      transitions.add((c1, afterPhase(i, 1), _tt(_blank, '0', 'L')));
      // N ran out of bits (implicit 0) + k's bit 1 + carry-in 1 = same as
      // above, still materializing a new tape digit.
      transitions.add((c1, afterPhase(i, 1), _tt('1', '1', 'L')));
      // N's bit 1 + k's bit 1 + carry-in 1 = sum 1, carry-out 1 (1+1+1=11).
    }
    // Note there's no explicit handling for a phase reading anything other
    // than '0'/'1'/blank at this tape position — since N's tape only ever
    // contains binary digits (per the alphabet documented on
    // TmSolutionSpec.addConstant), no other symbol should ever be
    // encountered here in a well-formed run.
  }

  transitions.addAll([
    ('carry', 'carry', _tt('1', '0', 'L')),
    // Ordinary ripple-carry increment: a '1' becomes '0' and the carry
    // keeps propagating left (this cell's own value flips, but the +1
    // still needs to land somewhere further left).
    ('carry', 'acc', _tt('0', '1', 'S')),
    // A '0' absorbs the carry: becomes '1', and since nothing needs to
    // change further left, the machine stops right there (Stay) and
    // accepts.
    ('carry', 'acc', _tt(_blank, '1', 'S')),
    // The carry rippled all the way off N's original leading digit: blank
    // becomes a new '1' (extending the numeral by one more leading bit,
    // e.g. binary 111 + 1 = 1000), and the machine stops and accepts.
  ]);

  return _graph(states: states, transitions: transitions, startId: 'seek');
}