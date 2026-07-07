// Builds canonical reference PDAs for study-mode PDA challenges.
//
// Each challenge carries a [PdaSolutionSpec] describing its language family.
// [buildStudyPdaSolution] turns that spec into a [GraphState] for display after
// three wrong attempts.

import 'package:flutter/material.dart';

import 'import_export.dart';
import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

const _m = 'X';
const _mA = 'A';
const _mB = 'B';

/// Comparison relation for a^i b^j style languages.
enum PdaCompRelation { equal, leq, lt, geq, gt }

enum PdaSolutionKind {
  anbn,
  ratio,
  comp,
  interleaved4,
  outerFrame,
  outerFrameScaled,
  outerFrameMidDouble,
  palindrome,
  markedPalindrome,
  blockGroupLeq,
}

/// Describes which reference PDA to build for a study challenge.
class PdaSolutionSpec {
  final PdaSolutionKind kind;
  final String a;
  final String b;
  final String? c;
  final String? s2;
  final String? s3;
  final String? s4;
  final int k;
  final int j;
  final bool acceptEmpty;
  final PdaCompRelation? relation;

  const PdaSolutionSpec.anbn(this.a, this.b, {this.acceptEmpty = true})
      : kind = PdaSolutionKind.anbn,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 1,
        relation = null;

  const PdaSolutionSpec.ratio(this.a, this.b, this.k, this.j)
      : kind = PdaSolutionKind.ratio,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        acceptEmpty = true,
        relation = null;

  const PdaSolutionSpec.comp(this.a, this.b, this.relation)
      : kind = PdaSolutionKind.comp,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 1,
        acceptEmpty = true;

  PdaSolutionSpec.interleaved4(
    this.a,
    this.s2,
    this.s3,
    this.s4,
  )   : kind = PdaSolutionKind.interleaved4,
        b = s2 ?? '',
        c = null,
        k = 1,
        j = 1,
        acceptEmpty = true,
        relation = null;

  const PdaSolutionSpec.outerFrame(this.a, this.b, this.c)
      : kind = PdaSolutionKind.outerFrame,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 1,
        acceptEmpty = true,
        relation = null;

  const PdaSolutionSpec.outerFrameScaled(this.a, this.b, this.c, this.k)
      : kind = PdaSolutionKind.outerFrameScaled,
        s2 = null,
        s3 = null,
        s4 = null,
        j = 1,
        acceptEmpty = true,
        relation = null;

  const PdaSolutionSpec.outerFrameMidDouble(this.a, this.b, this.c)
      : kind = PdaSolutionKind.outerFrameMidDouble,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 2,
        acceptEmpty = true,
        relation = null;

  const PdaSolutionSpec.palindrome(this.a, this.b)
      : kind = PdaSolutionKind.palindrome,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 1,
        acceptEmpty = true,
        relation = null;

  const PdaSolutionSpec.markedPalindrome(this.a, this.b)
      : kind = PdaSolutionKind.markedPalindrome,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 1,
        j = 1,
        acceptEmpty = false,
        relation = null;

  const PdaSolutionSpec.blockGroupLeq(this.a, this.b)
      : kind = PdaSolutionKind.blockGroupLeq,
        c = null,
        s2 = null,
        s3 = null,
        s4 = null,
        k = 2,
        j = 2,
        acceptEmpty = true,
        relation = null;
}

GraphState buildStudyPdaSolution(PdaSolutionSpec spec) {
  return switch (spec.kind) {
    PdaSolutionKind.anbn => _buildAnBn(spec.a, spec.b, acceptEmpty: spec.acceptEmpty),
    PdaSolutionKind.ratio => _buildRatio(spec.a, spec.b, spec.k, spec.j),
    PdaSolutionKind.comp => _buildComp(spec.a, spec.b, spec.relation!),
    PdaSolutionKind.interleaved4 =>
      _buildInterleaved4(spec.a, spec.s2!, spec.s3!, spec.s4!),
    PdaSolutionKind.outerFrame => _buildOuterFrame(spec.a, spec.b, spec.c!),
    PdaSolutionKind.outerFrameScaled =>
      _buildOuterFrameScaled(spec.a, spec.b, spec.c!, spec.k),
    PdaSolutionKind.outerFrameMidDouble =>
      _buildOuterFrameMidDouble(spec.a, spec.b, spec.c!),
    PdaSolutionKind.palindrome => _buildPalindrome(spec.a, spec.b),
    PdaSolutionKind.markedPalindrome => _buildMarkedPalindrome(spec.a, spec.b),
    PdaSolutionKind.blockGroupLeq => _buildBlockGroupLeq(spec.a, spec.b),
  };
}

// ── Graph helpers ───────────────────────────────────────────────────────────

GraphState _graph({
  required List<(String id, String label, bool accept)> states,
  required List<(String from, String to, String label)> transitions,
  required String startId,
}) {
  final nodes = <String, NodeData>{};
  for (int i = 0; i < states.length; i++) {
    final (id, label, accept) = states[i];
    nodes[id] = NodeData(
      id: id,
      label: label,
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
    automataMode: AutomataMode.pda,
  );
}

// PDA label helpers  — format: read,pop|push
//
// The simulator normalises ~ and ε to "" (no-op) but treats ∅ as the
// literal stack-bottom sentinel kStackBottom.  Using ∅ in the push
// position would therefore *push* the sentinel instead of pushing nothing.
// We must use ~ (not ∅) wherever we want "push nothing" or "pop nothing".
//
//   _push  : read a symbol, don't pop anything, push a marker
//   _pop   : read a symbol, pop a marker,       push nothing  (~ = no push)
//   _read  : read a symbol, don't touch stack at all           (~ = no pop/push)
//   _eps   : epsilon move, don't touch stack at all            (~ = no pop/push)
//   _pushSym: read a symbol, push that same symbol (used for palindromes)
String _push(String read, [String marker = _m]) => '$read,~|$marker';
String _pop(String read, [String marker = _m]) => '$read,$marker|~';
String _read(String sym) => '$sym,~|~';
String _eps() => '~,~|~';
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
// _epsWhenEmpty() closes that hole: it's still a true epsilon move (fires
// at any point, doesn't consume input) but additionally requires popping
// the implicit stack-bottom sentinel ∅, which only succeeds once the stack
// is genuinely empty of real markers. Use this (instead of _eps()) for any
// transition into the accept state that is meant to certify "fully matched,
// nothing left over".
String _epsWhenEmpty() => '~,∅|~';

// ── Language families ───────────────────────────────────────────────────────

GraphState _buildAnBn(String a, String b, {required bool acceptEmpty}) {
  final transitions = <(String, String, String)>[
    ('n0', 'n0', _push(a)),
    ('n0', 'n1', _pop(b)),
    ('n1', 'n1', _pop(b)),
    ('n1', 'n2', _epsWhenEmpty()),
  ];
  if (acceptEmpty) {
    transitions.add(('n0', 'n2', _epsWhenEmpty()));
  }
  return _graph(
    states: [
      ('n0', 'A', false),
      ('n1', 'B', false),
      ('n2', 'C', true),
    ],
    transitions: transitions,
    startId: 'n0',
  );
}

GraphState _buildRatio(String a, String b, int k, int j) {
  if (k == 1 && j == 1) return _buildAnBn(a, b, acceptEmpty: true);

  final states = <(String, String, bool)>[];
  final trans = <(String, String, String)>[];

  for (int i = 0; i < k; i++) {
    states.add(('a$i', 'A$i', false));
  }
  for (int i = 0; i < j; i++) {
    states.add(('b$i', 'B$i', false));
  }
  states.add(('acc', 'OK', true));

  for (int i = 0; i < k; i++) {
    if (i + 1 < k) {
      trans.add(('a$i', 'a${i + 1}', _read(a)));
    } else {
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
    trans.add(('a0', 'a0', _pop(b)));
  } else {
    trans.add(('a0', 'b0', _read(b)));
  }

  for (int i = 0; i < j; i++) {
    if (j == 1) continue;
    if (i + 1 < j) {
      trans.add(('b$i', 'b${i + 1}', _read(b)));
    } else {
      trans.add(('b$i', 'b0', _pop(b)));
    }
  }

  trans.add(('a0', 'acc', _eps()));
  trans.add(('b0', 'acc', _eps()));

  return _graph(states: states, transitions: trans, startId: 'a0');
}

GraphState _buildComp(String a, String b, PdaCompRelation rel) {
  switch (rel) {
    case PdaCompRelation.equal:
      return _buildAnBn(a, b, acceptEmpty: true);
    case PdaCompRelation.leq:
      return _graph(
        states: [
          ('n0', 'A', false),
          ('n1', 'B', false),
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),
          ('n0', 'n1', _pop(b)),
          ('n0', 'n1', _read(b)),
          ('n1', 'n1', _pop(b)),
          ('n1', 'n1', _read(b)),
          ('n0', 'n2', _eps()),
          ('n1', 'n2', _eps()),
        ],
        startId: 'n0',
      );
    case PdaCompRelation.lt:
      return _graph(
        states: [
          ('n0', 'A', false),
          ('n1', 'B', false),
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),
          ('n0', 'n0', _pop(b)),
          ('n0', 'n1', _read(b)),
          ('n1', 'n1', _read(b)),
          ('n1', 'n2', _eps()),
        ],
        startId: 'n0',
      );
    case PdaCompRelation.geq:
      return _graph(
        states: [
          ('n0', 'A', false),
          ('n1', 'B', false),
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),
          ('n0', 'n1', _pop(b)),
          ('n1', 'n1', _pop(b)),
          ('n0', 'n2', _eps()),
          ('n1', 'n2', _eps()),
        ],
        startId: 'n0',
      );
    case PdaCompRelation.gt:
      // Accept only when at least one stack marker remains (see game level pda_more_as).
      return _graph(
        states: [
          ('n0', 'A', false),
          ('n1', 'B', false),
          ('n2', 'OK', true),
        ],
        transitions: [
          ('n0', 'n0', _push(a)),
          ('n0', 'n1', _pop(b)),
          ('n1', 'n1', _pop(b)),
          ('n0', 'n2', '∅,$_m|$_m'),
          ('n1', 'n2', '∅,$_m|$_m'),
        ],
        startId: 'n0',
      );
  }
}

GraphState _buildInterleaved4(String s1, String s2, String s3, String s4) {
  return _graph(
    states: [
      ('n0', 'AB', false),
      ('n1', 'CD', false),
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(s1, _mA)),
      ('n0', 'n0', _push(s2, _mB)),
      ('n0', 'n1', _pop(s3, _mA)),
      ('n1', 'n1', _pop(s4, _mB)),
      ('n0', 'n2', _eps()),
      ('n1', 'n2', _eps()),
    ],
    startId: 'n0',
  );
}

GraphState _buildOuterFrame(String a, String mid, String c) {
  return _graph(
    states: [
      ('n0', 'AC', false),
      ('n1', 'C', false),
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(a)),
      ('n0', 'n0', _read(mid)),
      ('n0', 'n1', _pop(c)),
      ('n1', 'n1', _pop(c)),
      ('n0', 'n2', _eps()),
      ('n1', 'n2', _eps()),
    ],
    startId: 'n0',
  );
}

GraphState _buildOuterFrameScaled(String a, String mid, String c, int k) {
  if (k == 1) return _buildOuterFrame(a, mid, c);

  final states = <(String, String, bool)>[];
  final trans = <(String, String, String)>[];
  for (int i = 0; i < k; i++) {
    states.add(('a$i', 'A$i', false));
  }
  states.addAll([
    ('m0', 'M', false),
    ('c0', 'C', false),
    ('acc', 'OK', true),
  ]);

  for (int i = 0; i < k; i++) {
    if (i + 1 < k) {
      trans.add(('a$i', 'a${i + 1}', _read(a)));
    } else {
      trans.add(('a$i', 'a0', _push(a)));
    }
    trans.add(('a$i', 'm0', _read(mid)));
    trans.add(('a$i', 'c0', _pop(c)));
  }
  trans.add(('m0', 'm0', _read(mid)));
  trans.add(('m0', 'c0', _pop(c)));
  trans.add(('c0', 'c0', _pop(c)));
  trans.add(('a0', 'acc', _eps()));
  trans.add(('m0', 'acc', _eps()));
  trans.add(('c0', 'acc', _eps()));

  return _graph(states: states, transitions: trans, startId: 'a0');
}

GraphState _buildOuterFrameMidDouble(String a, String mid, String c) {
  return _graph(
    states: [
      ('n0', 'A', false),
      ('b1', 'B2', false),
      ('n2', 'C', false),
      ('n3', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(a)),
      ('n0', 'b1', _read(mid)),
      ('b1', 'n0', _pop(mid)),
      ('n0', 'n2', _pop(c)),
      ('n2', 'n2', _pop(c)),
      ('n0', 'n3', _eps()),
      ('n2', 'n3', _eps()),
    ],
    startId: 'n0',
  );
}

GraphState _buildPalindrome(String a, String b) {
  return _graph(
    states: [
      ('n0', 'P', false),
      ('n1', 'Q', false),
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _pushSym(a)),
      ('n0', 'n0', _pushSym(b)),
      ('n0', 'n1', _eps()),
      ('n1', 'n1', _pop(a)),
      ('n1', 'n1', _pop(b)),
      ('n1', 'n2', _eps()),
      ('n0', 'n2', _eps()),
    ],
    startId: 'n0',
  );
}

GraphState _buildMarkedPalindrome(String a, String mid) {
  return _graph(
    states: [
      ('n0', 'L', false),
      ('n1', 'R', false),
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'n0', _push(a)),
      ('n0', 'n1', _read(mid)),
      ('n1', 'n1', _pop(a)),
      ('n1', 'n2', _eps()),
    ],
    startId: 'n0',
  );
}

GraphState _buildBlockGroupLeq(String a, String b) {
  return _graph(
    states: [
      ('n0', 'A', false),
      ('a1', 'A2', false),
      ('b1', 'B2', false),
      ('n2', 'OK', true),
    ],
    transitions: [
      ('n0', 'a1', _read(a)),
      ('a1', 'n0', _push(a)),
      ('n0', 'b1', _read(b)),
      ('b1', 'n0', _pop(b)),
      ('b1', 'n0', _read(b)),
      ('n0', 'n2', _eps()),
    ],
    startId: 'n0',
  );
}