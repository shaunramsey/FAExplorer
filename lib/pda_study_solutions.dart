// Builds canonical reference PDAs for study-mode PDA challenges.
//
// Each challenge carries a [PdaSolutionSpec] describing its language family.
// [buildStudyPdaSolution] turns that spec into a [GraphState] for display after
// three wrong attempts.

import 'package:flutter/material.dart';
// ^ Only used here for the `Offset` type (state node positions in _graph()).

import 'import_export.dart';
// ^ Pulled in for its side effects on the GraphState import/export contract —
//   GraphState instances built here must round-trip through the same
//   import/export machinery used for user-drawn machines.

import 'models.dart';
// ^ NodeData, LineData, GraphState, StartArrowData — the graph data model
//   that every _build*() function ultimately assembles and returns.

import 'widgets/automata_drawer.dart' show AutomataMode;
// ^ Only AutomataMode is needed, to stamp `automataMode: AutomataMode.pda`
//   on every GraphState this file produces.

// ── Stack-marker symbol names ───────────────────────────────────────────────
// These are the literal characters pushed onto the PDA stack to "count"
// input symbols. They are uppercase specifically so they can never collide
// with a randomly-drawn lowercase/digit alphabet symbol coming from
// study_mode_symbols.dart (see that file's header comment).
const _m = 'X';   // generic single-purpose counting marker (most language families use just one)
const _mA = 'A';  // marker reserved for the "first interleaved symbol" in _buildInterleaved4
const _mB = 'B';  // marker reserved for the "second interleaved symbol" in _buildInterleaved4

/// Comparison relation for a^i b^j style languages.
enum PdaCompRelation {
  equal, // i == j  (delegates straight to the a^n b^n builder)
  leq,   // i <= j  (every a can be matched by a b, and extra b's are fine)
  lt,    // i <  j  (like leq, but at least one extra/unmatched b is required)
  geq,   // i >= j  (every b can be matched by an a, and extra a's are fine)
  gt,    // i >  j  (like geq, but at least one extra/unmatched a is required)
}

// One tag per reference-PDA "shape" this file knows how to build. Each value
// corresponds 1:1 with a private `_build*` function below, wired together by
// the switch inside buildStudyPdaSolution().
enum PdaSolutionKind {
  anbn,               // a^n b^n
  ratio,               // a^(k*m) b^(j*m) — fixed-ratio block counting
  comp,                // a^i b^j with a comparison relation between i and j
  interleaved4,        // two independently-nested pairs of symbols
  outerFrame,          // a^n (mid)* c^n — a's/c's framing an unconstrained middle
  outerFrameScaled,    // like outerFrame, but a's are consumed in fixed-size groups
  outerFrameMidDouble, // like outerFrame, but the middle section must itself balance
  palindrome,          // ww^R over a two-symbol alphabet
  markedPalindrome,    // w (mid) w^R — a palindrome with an explicit centre marker
  blockGroupLeq,       // paired a/b "blocks" where the count of a-blocks <= count of b-blocks
}

/// Describes which reference PDA to build for a study challenge.
///
/// This is a single class with several `const`/non-const *named*
/// constructors — one per [PdaSolutionKind] — rather than one constructor
/// with a giant pile of optional parameters. Each named constructor only
/// asks the caller for the fields that particular language family actually
/// needs, and fills in every other field (that this "shape" doesn't use)
/// with a fixed default via the initializer list, so [buildStudyPdaSolution]
/// can pattern-match on `kind` and always find the fields it needs already
/// populated correctly for that kind.
class PdaSolutionSpec {
  final PdaSolutionKind kind; // which _build* function ends up handling this spec
  final String a;             // primary symbol (meaning varies per kind — see each constructor)
  final String b;             // secondary symbol
  final String? c;            // tertiary symbol (only outerFrame* kinds use this)
  final String? s2;           // 2nd interleaved symbol (interleaved4 only)
  final String? s3;           // 3rd interleaved symbol (interleaved4 only)
  final String? s4;           // 4th interleaved symbol (interleaved4 only)
  final int k;                 // group size for `a` (ratio / outerFrameScaled)
  final int j;                 // group size for `b` (ratio / outerFrameMidDouble)
  final bool acceptEmpty;      // whether the empty string counts as a match (anbn / comp)
  final PdaCompRelation? relation; // which inequality to build (comp only)

  // ── a^n b^n ────────────────────────────────────────────────────────────
  const PdaSolutionSpec.anbn(this.a, this.b, {this.acceptEmpty = true})
      : kind = PdaSolutionKind.anbn,
        c = null,           // outerFrame-only field, unused by this kind
        s2 = null,          // interleaved4-only field, unused
        s3 = null,          // interleaved4-only field, unused
        s4 = null,          // interleaved4-only field, unused
        k = 1,              // ratio-only field; 1 is a harmless inert default
        j = 1,              // ratio-only field; 1 is a harmless inert default
        relation = null;    // comp-only field, unused by this kind

  // ── a^(k*m) b^(j*m) fixed block ratio ────────────────────────────────────
  const PdaSolutionSpec.ratio(this.a, this.b, this.k, this.j)
      : kind = PdaSolutionKind.ratio,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        acceptEmpty = true, // ratio machines always allow the empty string (m = 0)
        relation = null;

  // ── a^i b^j with an explicit i <?> j relation ────────────────────────────
  const PdaSolutionSpec.comp(this.a, this.b, this.relation)
      : kind = PdaSolutionKind.comp,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,              // unused for comp; comp does its own hard-coded state graphs
        j = 1,              // unused for comp
        acceptEmpty = true; // note: `relation` itself is NOT defaulted here — it's a
                             // required positional constructor arg, so it's always
                             // supplied by the caller rather than initialized here.

  // ── two independently-nested symbol pairs, interleaved ───────────────────
  // Not `const` (unlike its siblings) because `b` is derived from `s2` at
  // construction time (`b = s2 ?? ''`) rather than being a literal passed by
  // the caller — Dart doesn't allow computed initializer expressions like
  // that in a `const` constructor.
  PdaSolutionSpec.interleaved4(
    this.a,
    this.s2,
    this.s3,
    this.s4,
  )   : kind = PdaSolutionKind.interleaved4,
        b = s2 ?? '', // `b` is kept in sync with `s2` purely so any code that
                       // only knows about the generic `a`/`b` fields (rather
                       // than the interleaved-specific s2/s3/s4) still sees a
                       // sensible value; the actual build function reads s2
                       // directly and ignores this copy.
        c = null,
        k = 1,
        j = 1,
        acceptEmpty = true,
        relation = null;

  // ── a^n (mid)* c^n ────────────────────────────────────────────────────────
  const PdaSolutionSpec.outerFrame(this.a, this.b, this.c)
      : kind = PdaSolutionKind.outerFrame,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,              // outerFrame (unscaled) reads a's one-at-a-time, k=1 group size
        j = 1,
        acceptEmpty = true,
        relation = null;

  // ── outerFrame, but a's must come in fixed-size groups of k ──────────────
  const PdaSolutionSpec.outerFrameScaled(this.a, this.b, this.c, this.k)
      : kind = PdaSolutionKind.outerFrameScaled,
        s2 = null,
        s3 = null,
        s4 = null,
        j = 1,              // this variant doesn't group the middle/c side, only `a`
        acceptEmpty = true,
        relation = null;

  // ── outerFrame, but the middle section must itself contain 2 matched mids ─
  const PdaSolutionSpec.outerFrameMidDouble(this.a, this.b, this.c)
      : kind = PdaSolutionKind.outerFrameMidDouble,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 2,              // `j = 2` names the "double" in the middle (see _buildOuterFrameMidDouble)
        acceptEmpty = true,
        relation = null;

  // ── ww^R palindrome over {a, b} ───────────────────────────────────────────
  const PdaSolutionSpec.palindrome(this.a, this.b)
      : kind = PdaSolutionKind.palindrome,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 1,
        acceptEmpty = true, // the empty string is trivially its own palindrome
        relation = null;

  // ── w (mid) w^R, palindrome with an explicit centre marker ───────────────
  const PdaSolutionSpec.markedPalindrome(this.a, this.b)
      : kind = PdaSolutionKind.markedPalindrome,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 1,
        acceptEmpty = false, // the centre marker itself must always appear,
                              // so the empty string is never a match here
        relation = null;

  // ── paired a/b "blocks", #a-blocks <= #b-blocks ──────────────────────────
  const PdaSolutionSpec.blockGroupLeq(this.a, this.b)
      : kind = PdaSolutionKind.blockGroupLeq,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 2,              // each "block" here is 2 symbols wide (a a, or b b) — see builder
        j = 2,
        acceptEmpty = true,
        relation = null;
}

/// Single entry point: dispatches on [PdaSolutionSpec.kind] and calls the
/// matching private `_build*` function, forwarding exactly the fields that
/// function needs (using `!` on the fields that a given kind's constructor
/// above guarantees are non-null).
GraphState buildStudyPdaSolution(PdaSolutionSpec spec) {
  return switch (spec.kind) {
    PdaSolutionKind.anbn =>
      _buildAnBn(spec.a, spec.b, acceptEmpty: spec.acceptEmpty),
    PdaSolutionKind.ratio =>
      _buildRatio(spec.a, spec.b, spec.k, spec.j),
    PdaSolutionKind.comp =>
      // `spec.relation!` — comp's constructor takes `relation` as a required
      // positional arg, so it's always set whenever kind == comp; the `!`
      // just satisfies the analyzer since the field itself is nullable.
      _buildComp(spec.a, spec.b, spec.relation!),
    PdaSolutionKind.interleaved4 =>
      // s2/s3/s4 are all guaranteed non-null by the interleaved4 constructor
      // (they're required positional params there), so `!` is safe here too.
      _buildInterleaved4(spec.a, spec.s2!, spec.s3!, spec.s4!),
    PdaSolutionKind.outerFrame =>
      _buildOuterFrame(spec.a, spec.b, spec.c!),
    PdaSolutionKind.outerFrameScaled =>
      _buildOuterFrameScaled(spec.a, spec.b, spec.c!, spec.k),
    PdaSolutionKind.outerFrameMidDouble =>
      _buildOuterFrameMidDouble(spec.a, spec.b, spec.c!),
    PdaSolutionKind.palindrome =>
      _buildPalindrome(spec.a, spec.b),
    PdaSolutionKind.markedPalindrome =>
      _buildMarkedPalindrome(spec.a, spec.b),
    PdaSolutionKind.blockGroupLeq =>
      _buildBlockGroupLeq(spec.a, spec.b),
  };
}

// ── Graph helpers ───────────────────────────────────────────────────────────

/// Turns a flat description of states + transitions into an actual
/// [GraphState], the same data structure a user would produce by hand-
/// drawing a machine on the canvas.
///
/// Callers pass:
///   - [states]: one tuple per state — `(id, displayLabel, isAccepting)`.
///   - [transitions]: one tuple per PDA move — `(fromStateId, toStateId,
///     transitionLabel)`, where `transitionLabel` is already formatted as
///     `read,pop|push` (built by the `_push`/`_pop`/`_read`/`_eps`/`_pushSym`
///     helpers further down this file).
///   - [startId]: which state id is the start state.
GraphState _graph({
  required List<(String id, String label, bool accept)> states,
  required List<(String from, String to, String label)> transitions,
  required String startId,
}) {
  final nodes = <String, NodeData>{};
  for (int i = 0; i < states.length; i++) {
    // Destructure the i-th (id, label, accept) record.
    final (id, label, accept) = states[i];
    nodes[id] = NodeData(
      id: id,
      label: label,
      // Lay states out left-to-right in a single row, 240px apart, all at
      // the same y (320). This is a static/deterministic starting layout;
      // applyStudyModeLayout() (see study_mode_layout.dart) is run
      // separately afterwards to nudge nodes apart if lines/labels would
      // otherwise overlap them.
      position: Offset(220.0 + i * 240.0, 320.0),
      isAccept: accept,
    );
  }

  // ── Merge parallel edges (same from→to) into one LineData with \n-joined
  //    labels.  This means "read a OR b" situations render in a single textbox
  //    on the canvas instead of as two separate arrows.
  //
  //    Ordering is preserved: the first occurrence of a (from,to) pair wins
  //    the stable position in the iteration order; subsequent labels are
  //    appended with a newline separator, which the simulator already splits on.
  final edgeOrder = <(String, String)>[];          // insertion-order keys
  final edgeLabels = <(String, String), List<String>>{};

  for (final (from, to, label) in transitions) {
    final key = (from, to); // record used as a Map key — (String, String) has value equality
    if (!edgeLabels.containsKey(key)) {
      // First time we've seen this (from, to) pair: remember its position
      // in iteration order and start a fresh label bucket for it.
      edgeOrder.add(key);
      edgeLabels[key] = [];
    }
    // Append this transition's label to whichever (from, to) bucket it
    // belongs to — this is what actually merges parallel edges.
    edgeLabels[key]!.add(label);
  }

  final lines = <String, LineData>{};
  int li = 0; // running counter used both for line ids ("l0", "l1", ...) and
              // reported back to the caller as GraphState.lineCounter.
  for (final key in edgeOrder) {
    final (from, to) = key;
    // Join every label collected for this (from, to) pair with a newline —
    // this is the actual "OR" rendering: multiple transition labels stacked
    // in one textbox rather than duplicate overlapping arrows.
    final mergedLabel = edgeLabels[key]!.join('\n');
    final id = 'l$li';
    lines[id] = LineData(id: id, nodeAId: from, nodeBId: to, label: mergedLabel);
    // Register this line against both endpoint nodes so the UI knows which
    // lines are attached to which node (used for hit-testing, dragging, etc).
    nodes[from]!.connectedLineIds.add(id);
    // Self-loops (from == to) must only be added once — adding it twice to
    // the same node's connectedLineIds Set would be harmless (Set
    // dedupes) but is explicitly skipped here for clarity.
    if (to != from) nodes[to]!.connectedLineIds.add(id);
    li++;
  }

  return GraphState(
    nodes: nodes,
    lines: lines,
    startArrow: StartArrowData(nodeId: startId),
    nodeCounter: states.length, // so any later "add a new state" UI action
                                 // picks a fresh, non-colliding id/number
    lineCounter: li,            // ditto, for "add a new line"
    automataMode: AutomataMode.pda, // marks this graph as a PDA (not DFA/NFA/TM)
                                     // so the simulator interprets each
                                     // transition label as read,pop|push
  );
}

// PDA label helpers  — format: read,pop|push
//
// The simulator normalises ~ and ~ to "" (no-op) but treats ∅ as the
// literal stack-bottom sentinel kStackBottom.  Using ∅ in the push
// position would therefore *push* the sentinel instead of pushing nothing.
// We must use ~ (not ∅) wherever we want "push nothing" or "pop nothing".
//
//   _push  : read a symbol, don't pop anything, push a marker
//   _pop   : read a symbol, pop a marker,       push nothing  (~ = no push)
//   _read  : read a symbol, don't touch stack at all           (~ = no pop/push)
//   _eps   : tilda move, don't touch stack at all            (~ = no pop/push)
//   _pushSym: read a symbol, push that same symbol (used for palindromes)

// read a symbol, push `marker` (default 'X'), no pop.
// e.g. _push('a') -> "a,~|X"   (read 'a', pop nothing, push 'X')
String _push(String read, [String marker = _m]) => '$read,~|$marker';

// read a symbol, pop `marker` (default 'X'), no push.
// e.g. _pop('b') -> "b,X|~"    (read 'b', pop 'X', push nothing)
String _pop(String read, [String marker = _m]) => '$read,$marker|~';

// read a symbol, touch the stack in no way at all.
// e.g. _read('c') -> "c,~|~"
String _read(String sym) => '$sym,~|~';

// tilde/epsilon move: consume no input, touch the stack in no way at all.
// Fires unconditionally, at any point, without regard to lookahead.
String _eps() => '~,~|~';

// read a symbol, and push that *same* symbol back onto the stack verbatim
// (rather than an abstract marker like 'X') — used by the palindrome
// builders, where the popped values must be compared against the symbols
// read on the way back out, not just counted.
// e.g. _pushSym('a') -> "a,~|a"
String _pushSym(String sym) => '$sym,~|$sym';

// A plain _eps() ('~,~|~') fires unconditionally — it doesn't check the
// stack at all. That's fine for building up intermediate transitions, but
// it's wrong for the *final* move into an accept state whenever "accept"
// is supposed to mean "every pushed marker has since been popped" (e.g.
// a^n b^n, or any exact frame/ratio match). Using a bare _eps() there lets
// the machine jump to accept from a *prefix* of the real match — e.g. after
// only some of the b's/c's have been popped, or none at all — because
// leftover markers on the stack are simply never inspected.
//
// _epsWhenEmpty() closes that hole: it's still a true tilda move (fires
// at any point, doesn't consume input) but additionally requires popping
// the implicit stack-bottom sentinel ∅, which only succeeds once the stack
// is genuinely empty of real markers. Use this (instead of _eps()) for any
// transition into the accept state that is meant to certify "fully matched,
// nothing left over".
//
// e.g. _epsWhenEmpty() -> "~,∅|~"  (read nothing, pop the stack-bottom
// sentinel, push nothing back — only legal when no real marker sits above it)
String _epsWhenEmpty() => '~,∅|~';

// ── Language families ───────────────────────────────────────────────────────

/// a^n b^n  (n >= 1 always; n >= 0 too when [acceptEmpty] is true).
///
/// States:
///   n0 ("A") — reading/pushing a's.
///   n1 ("B") — reading/popping b's.
///   n2 ("C") — accepting sink, reached only once the stack is fully unwound.
GraphState _buildAnBn(String a, String b, {required bool acceptEmpty}) {
  final transitions = <(String, String, String)>[
    // Stay in n0 for every a read: push one marker per a.
    ('n0', 'n0', _push(a)),
    // First b seen switches from "reading a's" to "reading b's", popping
    // one marker for this first b in the same move.
    ('n0', 'n1', _pop(b)),
    // Every subsequent b: stay in n1, popping one marker each time.
    ('n1', 'n1', _pop(b)),
    // Accept once every b has been read AND the stack is fully unwound —
    // i.e. exactly as many b's were popped as a's were pushed.
    ('n1', 'n2', _epsWhenEmpty()),
  ];
  if (acceptEmpty) {
    // Only added when the empty string itself should match (n = 0 case):
    // from n0 (before reading anything), jump straight to accept, but only
    // if the stack is already empty of real markers (i.e. genuinely no a's
    // were read at all — not merely "we happen to currently be at n0").
    transitions.add(('n0', 'n2', _epsWhenEmpty()));
  }
  return _graph(
    states: [
      ('n0', 'A', false),
      ('n1', 'B', false),
      ('n2', 'C', true), // only accepting state
    ],
    transitions: transitions,
    startId: 'n0',
  );
}

/// a^(k*m) b^(j*m) for m >= 0 — i.e. a's and b's must appear in complete
/// groups of size k and j respectively, with the same number of groups (m)
/// on each side.
///
/// Falls back to the simple a^n b^n builder when k == j == 1, since that's
/// just this family with group size 1 on both sides.
GraphState _buildRatio(String a, String b, int k, int j) {
  if (k == 1 && j == 1) return _buildAnBn(a, b, acceptEmpty: true);

  final states = <(String, String, bool)>[];
  final trans = <(String, String, String)>[];

  // One state per position *within* an a-group: a0..a(k-1). Reaching a$i
  // means "i a's have been read since the start of the current group".
  for (int i = 0; i < k; i++) {
    states.add(('a$i', 'A$i', false));
  }
  // Same idea for b-groups: b0..b(j-1).
  for (int i = 0; i < j; i++) {
    states.add(('b$i', 'B$i', false));
  }
  states.add(('acc', 'OK', true));

  for (int i = 0; i < k; i++) {
    if (i + 1 < k) {
      // Mid-group: just advance the counter, no stack change yet — we don't
      // know how many b-markers this group will need to seed until the
      // group is actually complete.
      trans.add(('a$i', 'a${i + 1}', _read(a)));
    } else {
      // Last a in a group of k: this a completes the group, so push j
      // markers at once (one push transition whose push side lists j
      // space-separated markers) — one marker for each b that will
      // eventually need to be matched against this completed a-group —
      // then loop back to a0 to allow another group of a's to start.
      final push = List.filled(j, _m).join(' ');
      trans.add(('a$i', 'a0', '$a,~|$push'));
    }
  }

  // The switch into "consume b's" must only be reachable from a0 — the state
  // that means "zero a's into the current group" (either nothing read yet,
  // or a group of k a's has just completed and pushed its marker(s)).
  // Adding this transition from every a$i (as before) let an *incomplete*
  // group of a's (i in 1..k-1) bail straight into popping b's using markers
  // left over from an earlier completed group, so e.g. for k=3, j=1 the old
  // code wrongly accepted "aaaaab" (5 a's, 1 b — not a multiple of 3).
  if (j == 1) {
    // With only one marker pushed per completed a-group, a single b can pop
    // it directly — no need for an intermediate b-counting chain, so this
    // transition just self-loops on a0.
    trans.add(('a0', 'a0', _pop(b)));
  } else {
    // With more than one marker needed per group, the *first* b of a group
    // only starts the count (no pop yet) and moves into the b-counting
    // chain — popping only happens once a full group of j b's has been read.
    trans.add(('a0', 'b0', _read(b)));
  }

  for (int i = 0; i < j; i++) {
    if (j == 1) continue; // handled above via the direct a0-self-loop pop
    if (i + 1 < j) {
      // Mid-group: just advance the counter, stack untouched.
      trans.add(('b$i', 'b${i + 1}', _read(b)));
    } else {
      // Last b in a group of j: this b completes the group, so it's the one
      // that actually pops a marker (consuming one of the j markers seeded
      // by the matching a-group), then loops back to b0 for the next group.
      trans.add(('b$i', 'b0', _pop(b)));
    }
  }

  // Accept once positioned at the start of a fresh a-group (a0) or the
  // start of a fresh b-group (b0) — both represent "every group opened so
  // far has been completed", i.e. a valid multiple-of-k / multiple-of-j
  // split with matching group counts on each side.
  trans.add(('a0', 'acc', _eps()));
  trans.add(('b0', 'acc', _eps()));

  return _graph(states: states, transitions: trans, startId: 'a0');
}

/// a^i b^j with an explicit comparison between i and j.
GraphState _buildComp(String a, String b, PdaCompRelation rel) {
  switch (rel) {
    case PdaCompRelation.equal:
      // i == j is exactly the a^n b^n language, so just reuse that builder
      // directly rather than duplicating the same three-state machine here.
      return _buildAnBn(a, b, acceptEmpty: true);

    case PdaCompRelation.leq:
      // i <= j: every a must eventually be matched by a b, and b's are
      // additionally allowed to appear "unmatched" (in excess of the a's).
      return _graph(
        states: [
          ('n0', 'A', false), // reading a's (pushing), or the first stretch of matching b's
          ('n1', 'B', false), // reading further b's (matched or excess)
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),   // every a read: push a marker
          ('n0', 'n1', _pop(b)),    // first b: pop a marker (this b matches an a) and move to n1
          ('n0', 'n1', _read(b)),   // first b: alternatively, treat it as an excess/unmatched b
          ('n1', 'n1', _pop(b)),    // further b's: keep popping matched markers
          ('n1', 'n1', _read(b)),   // further b's: or keep treating them as excess/unmatched
          ('n0', 'n2', _eps()),     // accept directly from n0 (covers i = j = 0, or any point
                                     // where the a-reading phase has ended and no b was needed)
          ('n1', 'n2', _eps()),     // accept from n1 once b's have started being read
        ],
        startId: 'n0',
      );

    case PdaCompRelation.lt:
      // i < j: same shape as `leq`, but the machine only ever pops a
      // marker for an a itself (n0 -> n0 on pop(b)) while still in the
      // "a-reading" state, and requires at least one b read purely as an
      // excess/unmatched symbol (n0 -> n1 on read(b), with n1 only ever
      // reading further b's, never popping) before it's willing to accept —
      // i.e. strictly more b's than a's.
      return _graph(
        states: [
          ('n0', 'A', false),
          ('n1', 'B', false),
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),   // every a read: push a marker
          ('n0', 'n0', _pop(b)),    // a b read while still "in" n0 pops a marker in place
          ('n0', 'n1', _read(b)),   // the b that tips the count strictly past i: move to n1
          ('n1', 'n1', _read(b)),   // further b's beyond that: just keep reading
          ('n1', 'n2', _eps()),     // only n1 leads to accept — guarantees at least one
                                     // "extra" b was consumed via the read(b) transition
        ],
        startId: 'n0',
      );

    case PdaCompRelation.geq:
      // i >= j: mirror image of `leq` — every b must be matched by an a,
      // and a's are additionally allowed to appear unmatched/in excess.
      return _graph(
        states: [
          ('n0', 'A', false), // reading a's, some of which may end up unmatched
          ('n1', 'B', false), // reading b's, each popping a previously-pushed a marker
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),   // every a read: push a marker (may or may not later
                                     // be matched to a b — excess a's are fine for geq)
          ('n0', 'n1', _pop(b)),    // first b: pop a marker, move into "matching b's" phase
          ('n1', 'n1', _pop(b)),    // every subsequent b: pop another marker
          ('n0', 'n2', _eps()),     // accept from n0: covers i >= j with zero b's read at all
          ('n1', 'n2', _eps()),     // accept from n1: covers i >= j once some b's were matched
        ],
        startId: 'n0',
      );

    case PdaCompRelation.gt:
      // i > j: same skeleton as `geq`, but the accept move additionally
      // requires reading (not popping) the stack-bottom-adjacent marker,
      // i.e. it demands at least one leftover, unmatched a-marker still
      // sitting on the stack above the bottom sentinel — see the game-level
      // note this references for the exact reasoning.
      // Accept only when at least one stack marker remains (see game level pda_more_as).
      return _graph(
        states: [
          ('n0', 'A', false),
          ('n1', 'B', false),
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),               // every a read: push a marker
          ('n0', 'n1', _pop(b)),                 // first b: pop a matching marker
          ('n1', 'n1', _pop(b)),                 // further b's: keep popping
          // Note: these two accept moves use a hand-written label
          // ('∅,$_m|$_m' == '∅,X|X') rather than one of the _push/_pop/_eps
          // helpers — they read the stack-bottom sentinel symbol '∅' as
          // the *input* character (not the stack), pop an 'X' marker, and
          // push it straight back. Combined with the marker having to be
          // there to pop at all, this only succeeds when at least one
          // unmatched a-marker is still on the stack, i.e. i > j.
          ('n0', 'n2', '∅,$_m|$_m'),
          ('n1', 'n2', '∅,$_m|$_m'),
        ],
        startId: 'n0',
      );
  }
}

/// Two independently-nested symbol pairs, interleaved: an (s1, s3) pair
/// nested via one marker, and an (s2, s4) pair nested via a second, distinct
/// marker, both built up during the same "phase 1" stretch of input and torn
/// down (in either relative order) during "phase 2".
GraphState _buildInterleaved4(String s1, String s2, String s3, String s4) {
  return _graph(
    states: [
      ('n0', 'AB', false), // phase 1: still allowed to push either s1 or s2
      ('n1', 'CD', false), // phase 2: only popping s3/s4 now
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(s1, _mA)), // reading s1 during phase 1: push an 'A' marker
      ('n0', 'n0', _push(s2, _mB)), // reading s2 during phase 1: push a 'B' marker
                                      // (distinct marker symbols keep the two nested
                                      // pairs from being able to cross-cancel each other)
      ('n0', 'n1', _pop(s3, _mA)),  // first s3: pop an 'A' marker, switch to phase 2
      ('n1', 'n1', _pop(s4, _mB)),  // any s4 during phase 2: pop a 'B' marker
      ('n0', 'n2', _eps()),         // accept straight from phase 1 (covers the case
                                      // where both counts happen to already be zero)
      ('n1', 'n2', _eps()),         // accept from phase 2 once torn down
    ],
    startId: 'n0',
  );
}

/// a^n (mid)* c^n — a's and c's must balance in count, with an entirely
/// unconstrained run of `mid` symbols sandwiched in between.
GraphState _buildOuterFrame(String a, String mid, String c) {
  return _graph(
    states: [
      ('n0', 'AC', false), // reading a's (pushing) and/or mid's (ignored) — the "outer, still open" phase
      ('n1', 'C', false),  // reading c's (popping) — the "closing" phase
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(a)),   // every a: push a marker
      ('n0', 'n0', _read(mid)), // every mid symbol while still in n0: ignored entirely
      ('n0', 'n1', _pop(c)),    // first c: pop a marker, switch to the closing phase
      ('n1', 'n1', _pop(c)),    // every subsequent c: pop another marker
      ('n0', 'n2', _eps()),     // accept from n0: covers zero a's / zero c's
      ('n1', 'n2', _eps()),     // accept from n1: covers the general n>0 case
    ],
    startId: 'n0',
  );
}

/// Like [_buildOuterFrame], but the a's must appear in fixed-size groups of
/// [k] (each complete group of k a's seeds one c-matching marker), rather
/// than one marker per single a.
GraphState _buildOuterFrameScaled(String a, String mid, String c, int k) {
  if (k == 1) return _buildOuterFrame(a, mid, c); // no grouping needed, reuse directly

  final states = <(String, String, bool)>[];
  final trans = <(String, String, String)>[];
  // One state per position within an a-group, same pattern as _buildRatio.
  for (int i = 0; i < k; i++) {
    states.add(('a$i', 'A$i', false));
  }
  states.addAll([
    ('m0', 'M', false),  // reading (ignored) mid symbols
    ('c0', 'C', false),  // reading/popping c's
    ('acc', 'OK', true),
  ]);

  for (int i = 0; i < k; i++) {
    if (i + 1 < k) {
      // Mid-group a: just advance the counter, no stack push yet.
      trans.add(('a$i', 'a${i + 1}', _read(a)));
    } else {
      // Last a of a completed group of k: this is the one that actually
      // pushes a marker, then loops back to a0 to start counting the next
      // group.
      trans.add(('a$i', 'a0', _push(a)));
    }
    // From *any* position within an a-group (a0..a(k-1)), reading a mid
    // symbol or a c is allowed to end the "still reading a's" phase early —
    // unlike _buildRatio, an incomplete trailing a-group isn't disallowed
    // here since a's don't need to divide evenly into anything on the c
    // side; only the total *count* of complete-group markers vs c's matters.
    trans.add(('a$i', 'm0', _read(mid)));
    trans.add(('a$i', 'c0', _pop(c)));
  }
  trans.add(('m0', 'm0', _read(mid))); // further mid symbols: ignored, stay in m0
  trans.add(('m0', 'c0', _pop(c)));    // first c after the mid run: pop a marker, move to c0
  trans.add(('c0', 'c0', _pop(c)));    // further c's: keep popping
  // Accept from any of the three "settled" states: a0 (no a's read at all,
  // or a whole number of complete a-groups with nothing else yet), m0
  // (mid-reading has started/finished, no c's yet), or c0 (c's have started
  // being matched off against the pushed group-markers).
  trans.add(('a0', 'acc', _eps()));
  trans.add(('m0', 'acc', _eps()));
  trans.add(('c0', 'acc', _eps()));

  return _graph(states: states, transitions: trans, startId: 'a0');
}

/// Like [_buildOuterFrame], but the middle section is itself required to
/// contain a single matched pair of `mid` symbols (read, then later popped)
/// rather than an arbitrary unconstrained run of them.
GraphState _buildOuterFrameMidDouble(String a, String mid, String c) {
  return _graph(
    states: [
      ('n0', 'A', false),  // reading a's (pushing)
      ('b1', 'B2', false), // exactly one `mid` has been read, waiting to see it popped
      ('n2', 'C', false),  // reading/popping c's
      ('n3', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(a)),   // every a: push a marker
      ('n0', 'b1', _read(mid)), // first mid: move to the "one mid open" state (no stack change)
      ('b1', 'n0', _pop(mid)),  // the *matching* mid: pops a marker — note this reuses the
                                  // same `mid` symbol as both the "read" and "pop" trigger, so
                                  // this transition also consumes one of the a-markers, i.e. the
                                  // closing mid symbol doubles as counting toward the a/c balance
      ('n0', 'n2', _pop(c)),    // first c: pop a marker, switch to the closing/c phase
      ('n2', 'n2', _pop(c)),    // further c's: keep popping
      ('n0', 'n3', _eps()),     // accept from n0
      ('n2', 'n3', _eps()),     // accept from n2
    ],
    startId: 'n0',
  );
}

/// ww^R — even-length palindromes over the two-symbol alphabet {a, b}.
///
/// The machine nondeterministically "guesses" where the midpoint of the
/// input is: every symbol read before the guessed midpoint is pushed
/// verbatim (via [_pushSym], not an abstract counting marker), and every
/// symbol read after it must pop and match the symbol that was pushed for
/// its mirror position.
GraphState _buildPalindrome(String a, String b) {
  return _graph(
    states: [
      ('n0', 'P', false), // "first half": pushing symbols verbatim
      ('n1', 'Q', false), // "second half": popping and matching symbols verbatim
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _pushSym(a)), // first-half a: push 'a' itself onto the stack
      ('n0', 'n0', _pushSym(b)), // first-half b: push 'b' itself onto the stack
      ('n0', 'n1', _eps()),      // the nondeterministic "guess the midpoint" move:
                                  // no input consumed, just switches from pushing
                                  // to popping — every branch of this guess is
                                  // explored, so only the branch that guesses the
                                  // true midpoint will end up able to accept
      ('n1', 'n1', _pop(a)),     // second-half a: only succeeds if the top of the
                                  // stack is literally 'a' (since _pop's default
                                  // marker argument isn't used here — the read
                                  // symbol name itself, `a`, is passed as the pop
                                  // target — so this really pops the *symbol* a,
                                  // matching it against the read symbol)
      ('n1', 'n1', _pop(b)),     // second-half b: same idea, must pop a literal 'b'
      ('n1', 'n2', _eps()),      // accept once the second half has fully unwound the stack
      ('n0', 'n2', _eps()),      // accept directly from n0: covers the empty string
                                  // (zero symbols pushed, so the guessed midpoint is
                                  // trivially at position 0 with nothing to match)
    ],
    startId: 'n0',
  );
}

/// w (mid) w^R — an odd-structured palindrome with an explicit, required
/// centre marker symbol, so the machine doesn't need to nondeterministically
/// guess the midpoint the way [_buildPalindrome] does: the `mid` symbol
/// itself tells it exactly where the first half ends.
GraphState _buildMarkedPalindrome(String a, String mid) {
  return _graph(
    states: [
      ('n0', 'L', false), // reading/pushing the left half (w)
      ('n1', 'R', false), // reading/popping the right half (w^R)
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(a)),   // every symbol of the left half: push a counting marker
                                  // (note: unlike _buildPalindrome this uses the generic
                                  // _push/_m marker, not _pushSym — because [a] here is a
                                  // single symbol, not a two-letter alphabet, there's
                                  // nothing to distinguish/match on the way back out,
                                  // only a count to verify)
      ('n0', 'n1', _read(mid)), // the mandatory centre marker: consumed, no stack change,
                                  // deterministically switches from left-half to right-half
                                  // (no nondeterministic guessing needed, unlike the
                                  // unmarked palindrome builder above)
      ('n1', 'n1', _pop(a)),    // every symbol of the right half: pop a marker
      ('n1', 'n2', _eps()),     // accept once the right half has unwound every marker
                                  // pushed during the left half
    ],
    startId: 'n0',
  );
}

/// Paired a/b "blocks" — reads come in fixed pairs (a a) or (b b), and the
/// language requires the number of a-blocks to be <= the number of b-blocks.
GraphState _buildBlockGroupLeq(String a, String b) {
  return _graph(
    states: [
      ('n0', 'A', false),   // "block boundary" — waiting for the first symbol of a new block
      ('a1', 'A2', false),  // mid-way through an a-block (one `a` read, one more expected)
      ('b1', 'B2', false),  // mid-way through a b-block (one `b` read, one more expected)
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'a1', _read(a)),  // first `a` of a new block: no stack change yet, just
                                 // note that we're mid-block (a1)
      ('a1', 'n0', _push(a)),  // second `a` completes the block: *now* push a marker
                                 // for the whole completed a-block, back to a boundary state
      ('n0', 'b1', _read(b)),  // first `b` of a new block: move into b1, no stack change
      ('b1', 'n0', _pop(b)),   // second `b` completes the block *and* a marker is available
                                 // to pop: this b-block "uses up" (matches) one earlier a-block
      ('b1', 'n0', _read(b)),  // second `b` completes the block with *no* marker required:
                                 // this lets b-blocks exist in excess of a-blocks (which is
                                 // exactly what makes the relation <= rather than ==) — both
                                 // this and the _pop(b) transition above are nondeterministic
                                 // alternatives on the same (state, input) pair
      ('n0', 'n2', _eps()),     // accept only from a block boundary (n0) — never mid-block —
                                 // so a trailing half-finished block is always rejected
    ],
    startId: 'n0',
  );
}