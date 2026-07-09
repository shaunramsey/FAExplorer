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
// all strings up to length 9-11 for two different symbol alphabets each,
// before being transcribed here. See the file-level comment on each builder
// for the algorithm it implements.

import 'package:flutter/material.dart';

import 'import_export.dart';
import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

// ── Marker / blank symbols ──────────────────────────────────────────────────
//
// 'X' is the "already processed" marker used by every crossing-off
// algorithm below. Uppercase, so it can never collide with a symbol drawn
// from kStudySymbolPool (study_mode_symbols.dart), which is lowercase +
// digits only.
const String _m = 'X';

/// Blank tape symbol, as used by the TM label format (kBlank in simulator.dart).
const String _blank = '∅';

/// Which reference TM to build for a study challenge.
enum TmSolutionKind {
  anbn,
  anbncn,
  equalCount,
  palindrome,
  divisibleBy3,
  startEndSame,
}

/// Describes which reference TM to build for a study challenge.
class TmSolutionSpec {
  final TmSolutionKind kind;
  final String a;
  final String b;
  final String? c;

  const TmSolutionSpec.anbn(this.a, this.b)
      : kind = TmSolutionKind.anbn,
        c = null;

  const TmSolutionSpec.anbncn(this.a, this.b, this.c)
      : kind = TmSolutionKind.anbncn;

  const TmSolutionSpec.equalCount(this.a, this.b)
      : kind = TmSolutionKind.equalCount,
        c = null;

  const TmSolutionSpec.palindrome(this.a, this.b)
      : kind = TmSolutionKind.palindrome,
        c = null;

  const TmSolutionSpec.divisibleBy3(this.a, this.b)
      : kind = TmSolutionKind.divisibleBy3,
        c = null;

  const TmSolutionSpec.startEndSame(this.a, this.b)
      : kind = TmSolutionKind.startEndSame,
        c = null;
}

GraphState buildStudyTmSolution(TmSolutionSpec spec) {
  return switch (spec.kind) {
    TmSolutionKind.anbn => _buildAnBnTm(spec.a, spec.b),
    TmSolutionKind.anbncn => _buildAnBnCnTm(spec.a, spec.b, spec.c!),
    TmSolutionKind.equalCount => _buildEqualCountTm(spec.a, spec.b),
    TmSolutionKind.palindrome => _buildPalindromeTm(spec.a, spec.b),
    TmSolutionKind.divisibleBy3 => _buildDivisibleBy3Tm(spec.a, spec.b),
    TmSolutionKind.startEndSame => _buildStartEndSameTm(spec.a, spec.b),
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

// B) L = { a^n b^n c^n : n ≥ 0 }  — not context-free; needs a TM.
//
// Same shape as anbn above, extended to three blocks: a PRECHECK verifying
// a*b*c* order, then a crossing-off phase that removes one a, one b, and
// one c per round trip.
GraphState _buildAnBnCnTm(String a, String b, String c) {
  return _graph(
    states: [
      ('pa', 'A', false),
      ('pb', 'B', false),
      ('pc', 'C', false),
      ('rs', 'R', false),
      ('rl', 'R2', false),
      ('q0', 'Q0', false),
      ('qb', 'QB', false),
      ('qc', 'QC', false),
      ('ret', 'RET', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('pa', 'rs', _atBlank('S')),
      ('pa', 'pa', _selfR(a)),
      ('pa', 'pb', _selfR(b)),
      ('pb', 'pb', _selfR(b)),
      ('pb', 'pc', _selfR(c)),
      ('pb', 'rs', _atBlank('S')),
      ('pc', 'pc', _selfR(c)),
      ('pc', 'rs', _atBlank('S')),
      ('rs', 'rl', _atBlank('L')),
      ('rl', 'rl', _selfL(a)),
      ('rl', 'rl', _selfL(b)),
      ('rl', 'rl', _selfL(c)),
      ('rl', 'rl', _skipX('L')),
      ('rl', 'q0', _atBlank('R')),
      ('q0', 'q0', _skipX('R')),
      ('q0', 'qb', _mark(a, 'R')),
      ('q0', 'acc', _atBlank('S')),
      ('qb', 'qb', _selfR(a)),
      ('qb', 'qb', _skipX('R')),
      ('qb', 'qc', _mark(b, 'R')),
      ('qc', 'qc', _selfR(b)),
      ('qc', 'qc', _skipX('R')),
      ('qc', 'ret', _mark(c, 'L')),
      ('ret', 'ret', _skipX('L')),
      ('ret', 'ret', _selfL(a)),
      ('ret', 'ret', _selfL(b)),
      ('ret', 'q0', _atBlank('R')),
    ],
    startId: 'pa',
  );
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

// E) L = { w ∈ {a,b}* : #a(w) ≡ 0 (mod 3) }.
//
// A 3-state counter: reading 'a' advances the state mod 3 (never touching
// the tape); 'b' is a self-loop everywhere. Accept only if the machine
// reaches the end of the tape while in the "0 mod 3" state.
GraphState _buildDivisibleBy3Tm(String a, String b) {
  return _graph(
    states: [
      ('m0', 'M0', false),
      ('m1', 'M1', false),
      ('m2', 'M2', false),
      ('acc', 'OK', true),
    ],
    transitions: [
      ('m0', 'm0', _selfR(b)),
      ('m1', 'm1', _selfR(b)),
      ('m2', 'm2', _selfR(b)),
      ('m0', 'm1', _selfR(a)),
      ('m1', 'm2', _selfR(a)),
      ('m2', 'm0', _selfR(a)),
      ('m0', 'acc', _atBlank('S')),
    ],
    startId: 'm0',
  );
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