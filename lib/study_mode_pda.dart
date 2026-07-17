// PDA practice challenges and widgets for study mode.

import 'dart:math';
// ^ Random — every challenge-generation function here takes a caller-
//   supplied Random so a whole study session can be seeded deterministically
//   (or not) from one place, rather than each generator seeding its own.

import 'package:flutter/material.dart';
// ^ Widget/BuildContext/Container/Row/Text/etc — this file also defines the
//   drawing-area and test-case-strip UI, not just challenge data.

import 'package:google_fonts/google_fonts.dart';
// ^ GoogleFonts.orbitron()/courierPrime() — the two display fonts used by
//   the widgets further down (labels and monospace test-case chips).

import 'models.dart';
// ^ NodeData, LineData, StartArrowData — the graph data the drawing area
//   reads from/writes to, and that gradeStudyPda() simulates against.

import 'simulator.dart';
// ^ PdaSimulator / PdaSimResult — actually *runs* a drawn PDA against a
//   challenge's test cases so gradeStudyPda() can check correctness.

import 'pda_study_solutions.dart';
// ^ PdaSolutionSpec / buildStudyPdaSolution — every challenge below embeds a
//   PdaSolutionSpec so the "reveal answer" UI can build the canonical
//   reference machine for that language on demand.

import 'study_mode_layout.dart';
// ^ applyStudyModeLayout — run on the revealed solution graph so its nodes/
//   labels don't overlap once rendered read-only.

import 'study_mode_symbols.dart';
// ^ randomStudyAlphabet — the shared symbol pool this file draws from so
//   PDA challenges don't keep reusing the same couple of letters.

import 'widgets/app_theme.dart';
// ^ AppThemeNotifier — passed into the widgets below so they follow the
//   app's current light/dark theme colors.

import 'widgets/automata_canvas_embed.dart';
// ^ AutomataCanvasEmbed — the actual interactive/read-only graph-drawing
//   canvas widget both branches of StudyPdaDrawingArea wrap.

/// How hard a given challenge is meant to be. Purely descriptive metadata —
/// nothing in this file currently branches on it besides being stored on
/// each [StudyPdaChallenge] and set per-challenge below.
enum StudyPdaDifficulty { easy, medium, hard }

/// One input string plus whether a correct PDA for the challenge should
/// accept or reject it. [gradeStudyPda] runs every test case for a
/// challenge against the user's drawn machine.
class StudyPdaTestCase {
  final String input;    // the string to feed the simulator (empty string == ~)
  final bool expected;   // true => a correct PDA must accept this input
  const StudyPdaTestCase(this.input, this.expected);
}

/// A single study-mode PDA problem: the language description shown to the
/// user, a hint, the alphabet involved, a difficulty tag, the test cases
/// used for grading, a few accept/reject examples for the UI chips, and the
/// [PdaSolutionSpec] used to build the reference machine on "reveal answer".
class StudyPdaChallenge {
  final String description;              // full L = {...} prose shown to the user
  final String hint;                     // short strategy nudge
  final Set<String> alphabet;             // every symbol that can appear in this challenge's inputs
  final StudyPdaDifficulty difficulty;    // easy/medium/hard tag
  final List<StudyPdaTestCase> testCases; // exhaustive-ish set used to grade the user's PDA
  final List<String> acceptExamples;      // small curated subset shown as green chips
  final List<String> rejectExamples;      // small curated subset shown as red chips
  final PdaSolutionSpec solutionSpec;     // recipe for building the canonical reference PDA

  const StudyPdaChallenge({
    required this.description,
    required this.hint,
    required this.alphabet,
    required this.difficulty,
    required this.testCases,
    required this.acceptExamples,
    required this.rejectExamples,
    required this.solutionSpec,
  });
}

/// Repeats [sym] [n] times — e.g. _rep('a', 3) == 'aaa'. Just Dart's built-in
/// String*int repetition operator wrapped in a named helper for readability
/// at call sites like `_rep(a, k) + _rep(b, j)`.
String _rep(String sym, int n) => sym * n;

/// Local mirror of [PdaCompRelation] (from pda_study_solutions.dart).
///
/// Kept as a *separate* private enum here — rather than importing and using
/// PdaCompRelation directly for the challenge-generation logic below — so
/// this file's own comparison-challenge code (test case generation, the
/// description switch in [_comparisonChallenge]) doesn't need to reach into
/// the solution-builder file's enum. [_pdaComp] is the single translation
/// point between the two whenever a [PdaSolutionSpec.comp] actually needs
/// to be constructed.
enum _CompRelation { equal, leq, lt, geq, gt }

/// Translates the local [_CompRelation] into the [PdaCompRelation] that
/// [PdaSolutionSpec.comp] expects — a plain 1:1 relabeling, values in the
/// same order on both enums.
PdaCompRelation _pdaComp(_CompRelation r) => switch (r) {
      _CompRelation.equal => PdaCompRelation.equal,
      _CompRelation.leq => PdaCompRelation.leq,
      _CompRelation.lt => PdaCompRelation.lt,
      _CompRelation.geq => PdaCompRelation.geq,
      _CompRelation.gt => PdaCompRelation.gt,
    };

/// Public entry point: builds the full fixed roster of PDA challenges (see
/// [_buildAllStudyPdaChallenges]), shuffles it, and returns [count] of them
/// — wrapping around the shuffled list with modulo if [count] exceeds the
/// roster size, so callers can always ask for more than currently exist
/// without erroring (at the cost of repeats once the roster is exhausted).
List<StudyPdaChallenge> generateStudyPdaChallenges(Random rng, {int count = 20}) {
  final all = _buildAllStudyPdaChallenges(rng)..shuffle(rng);
  return [for (int i = 0; i < count; i++) all[i % all.length]];
}

/// Draws a fresh, randomly-ordered 2-symbol alphabet.
///
/// randomStudyAlphabet() returns a Set (size 2 by default, unordered), so
/// this converts it to a List and shuffles that list too — belt-and-braces
/// against relying on any incidental Set iteration order — before handing
/// back a fixed (first, second) pair via record destructuring at call sites.
(String, String) _freshPair(Random rng) {
  final syms = randomStudyAlphabet(rng).toList()..shuffle(rng);
  return (syms[0], syms[1]);
}

/// Builds the complete, fixed roster of PDA study challenges (order here is
/// irrelevant since [generateStudyPdaChallenges] shuffles the result).
/// Every language family from pda_study_solutions.dart gets at least one
/// challenge instance, each with its own freshly-drawn alphabet.
List<StudyPdaChallenge> _buildAllStudyPdaChallenges(Random rng) {
  final challenges = <StudyPdaChallenge>[];

  // Every challenge below draws its own alphabet via _freshPair() /
  // randomStudyAlphabet() rather than sharing one pair across the whole
  // batch — otherwise a single build could lock onto e.g. "x"/"y" for all
  // fifteen-odd PDA problems in a session.
  var (a, b) = _freshPair(rng); // reused/reassigned via `(a, b) = ...` for every
                                  // simple two-symbol challenge below, rather than
                                  // declaring a fresh pair of variables each time

  // ── Challenge 1: a^n b^n, n >= 0 (empty string accepted) ─────────────────
  challenges.add(StudyPdaChallenge(
    description: 'L = { $a^n $b^n | n ≥ 0 }\n\n'
        'Accept strings with an equal number of "$a"s followed by "$b"s.\n'
        'The empty string ~ (n=0) is accepted.',
    hint: 'Push a stack symbol for each "$a", pop one for each "$b". '
        'Accept when the stack is empty at the end.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.easy,
    testCases: [
      StudyPdaTestCase('', true),         // n = 0: empty string, must accept
      StudyPdaTestCase(a, false),          // a alone, no matching b: reject
      StudyPdaTestCase(b, false),          // b alone, no a to match: reject
      StudyPdaTestCase('$a$b', true),      // n = 1: exactly one of each
      StudyPdaTestCase('$a$a$b$b', true),  // n = 2: exactly two of each
      StudyPdaTestCase('$a$a$b', false),   // unequal counts (2 a's, 1 b): reject
      StudyPdaTestCase('$b$a', false),     // wrong order (b before a): reject
    ],
    acceptExamples: ['~', '$a$b', '$a$a$b$b'],
    rejectExamples: [a, b, '$a$a$b'],
    solutionSpec: PdaSolutionSpec.anbn(a, b), // acceptEmpty defaults to true
  ));

  // ── Challenge 2: a^n b^n, n >= 1 (empty string rejected) ─────────────────
  (a, b) = _freshPair(rng); // draw a brand-new pair so this challenge doesn't
                             // reuse challenge 1's symbols
  challenges.add(StudyPdaChallenge(
    description: 'L = { $a^n $b^n | n ≥ 1 }\n\n'
        'Accept non-empty strings with equal "$a" and "$b" counts.',
    hint: 'Push for each "$a", pop for each "$b". Reject ~.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.easy,
    testCases: [
      StudyPdaTestCase('', false),         // n = 0 is explicitly excluded now: reject
      StudyPdaTestCase('$a$b', true),       // n = 1: smallest accepted case
      StudyPdaTestCase('$a$a$b$b', true),   // n = 2
      StudyPdaTestCase(a, false),           // unmatched a: reject
      StudyPdaTestCase('$a$a$b', false),    // unequal counts: reject
    ],
    acceptExamples: ['$a$b', '$a$a$b$b'],
    rejectExamples: ['~', a, '$a$a$b'],
    solutionSpec: PdaSolutionSpec.anbn(a, b, acceptEmpty: false),
  ));

  // ── Challenges 3-5: fixed-ratio block languages a^(kn) b^(jn) ─────────────
  // Three (k, j) shapes, increasing in difficulty: a 2:1 ratio, a 1:2 ratio,
  // then a harder 2:3 ratio. Each iteration draws its own fresh symbol pair
  // via _freshPair (note: this uses local vars `ra`/`rb`, NOT the outer
  // `a`/`b` — the outer pair is left untouched here since the next block of
  // challenges below still expects to reassign `a`/`b` itself).
  for (final (k, j, diff) in [
    (2, 1, StudyPdaDifficulty.medium), // a's come in pairs, one b matches each pair
    (1, 2, StudyPdaDifficulty.medium), // one a matches each pair of b's
    (2, 3, StudyPdaDifficulty.hard),   // pairs of a's matched against triples of b's
  ]) {
    final (ra, rb) = _freshPair(rng);
    challenges.add(_ratioChallenge(ra, rb, k, j, diff));
  }

  // ── Challenges 6-10: the five comparison relations (=, <=, <, >=, >) ──────
  // _CompRelation.values iterates in declaration order: equal, leq, lt, geq,
  // gt — so this produces exactly one challenge per relation, each with its
  // own fresh alphabet.
  for (final rel in _CompRelation.values) {
    final (ca, cb) = _freshPair(rng);
    challenges.add(_comparisonChallenge(ca, cb, rel));
  }

  // ── Challenge 11: interleaved4 — two independently-nested symbol pairs ───
  final quad = randomStudyAlphabet(rng, size: 4).toList()..shuffle(rng);
  final s1 = quad[0], s2 = quad[1], s3 = quad[2], s4 = quad[3];
  challenges.add(StudyPdaChallenge(
    description: 'L = { $s1^n $s2^m $s3^n $s4^m | n, m ≥ 0 }',
    hint: 'Use separate stack markers for the two pairs of symbols.',
    alphabet: {s1, s2, s3, s4},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase('', true),                 // n = m = 0
      StudyPdaTestCase('$s1$s3', true),            // n = 1, m = 0
      StudyPdaTestCase('$s1$s2$s3$s4', true),      // n = 1, m = 1, correctly interleaved
      StudyPdaTestCase('$s1$s3$s2$s4', false),     // right symbol counts, wrong order
      StudyPdaTestCase('$s1$s2$s3', false),        // m mismatched between the s2 and s4 halves
    ],
    acceptExamples: ['~', '$s1$s3', '$s1$s2$s3$s4'],
    rejectExamples: ['$s1$s2$s3', '$s1$s3$s2$s4'],
    solutionSpec: PdaSolutionSpec.interleaved4(s1, s2, s3, s4),
  ));

  // ── Challenge 12: outerFrame — a's/frame's balance around a free middle ──
  final triple = randomStudyAlphabet(rng, size: 3).toList()..shuffle(rng);
  final outer = triple[0], mid = triple[1], frame = triple[2];
  challenges.add(StudyPdaChallenge(
    description: 'L = { $outer^n $mid^m $frame^n | n, m ≥ 0 }',
    hint: 'Push for each "$outer", ignore "$mid"s, pop for each "$frame".',
    alphabet: {outer, mid, frame},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase('', true),                      // n = m = 0
      StudyPdaTestCase(mid, true),                       // n = 0, m = 1: only free middle symbols
      StudyPdaTestCase('$outer$frame', true),             // n = 1, m = 0: no middle at all
      StudyPdaTestCase('$outer$mid$frame', true),         // n = 1, m = 1: full frame with middle
      StudyPdaTestCase(frame, false),                     // unmatched frame symbol: reject
      StudyPdaTestCase('$outer$mid$mid', false),          // outer never closed by a frame: reject
    ],
    acceptExamples: ['~', mid, '$outer$frame', '$outer$mid$frame'],
    rejectExamples: [frame, '$outer$mid$mid'],
    solutionSpec: PdaSolutionSpec.outerFrame(outer, mid, frame),
  ));

  // ── Challenge 13: unmarked palindromes over {a, b} ────────────────────────
  (a, b) = _freshPair(rng); // fresh pair again, back to reusing outer a/b
  challenges.add(StudyPdaChallenge(
    description: 'L = palindromes over {$a, $b}',
    hint: 'Nondeterministically guess the midpoint, push then pop.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase('', true),          // the empty string is trivially a palindrome
      StudyPdaTestCase(a, true),            // single symbol: trivially a palindrome
      StudyPdaTestCase('$a$b$a', true),     // odd-length palindrome
      StudyPdaTestCase('$a$b', false),      // not a palindrome
    ],
    acceptExamples: ['~', a, '$a$a', '$a$b$a'],
    rejectExamples: ['$a$b', '$b$a'],
    solutionSpec: PdaSolutionSpec.palindrome(a, b),
  ));

  // ── Challenge 14: marked palindrome w (b) w^R over a single symbol `a` ────
  (a, b) = _freshPair(rng); // fresh pair; here `b` plays the role of the
                             // required centre marker rather than a second
                             // "regular" alphabet symbol (see the language:
                             // w is built only out of `a`, with `b` marking
                             // the centre)
  challenges.add(StudyPdaChallenge(
    description: 'L = { w $b w^R | w ∈ {$a}* }',
    hint: 'Push "$a"s, read "$b", pop "$a"s on the way back.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase(b, true),                // w = empty, just the centre marker: accept
      StudyPdaTestCase('$a$b$a', true),          // w = "a", mirrored around the marker
      StudyPdaTestCase('', false),               // the centre marker is mandatory: reject
      StudyPdaTestCase('$a$b', false),           // left half present but no mirrored right half: reject
    ],
    acceptExamples: [b, '$a$b$a', '$a$a$b$a$a'],
    rejectExamples: ['~', '$a$b'],
    solutionSpec: PdaSolutionSpec.markedPalindrome(a, b),
  ));

  return challenges;
}

/// Builds one fixed-ratio ("a's come in groups of k, b's come in groups of
/// j") challenge for a given symbol pair, ratio, and difficulty tag.
StudyPdaChallenge _ratioChallenge(
  String a,
  String b,
  int k,
  int j,
  StudyPdaDifficulty diff,
) {
  // Render the exponent compactly: just "$a^n" when the group size is 1
  // (no need to show a redundant "^(1n)"), otherwise "$a^(kn)" so the
  // description reads e.g. "a^(2n) b^n" for a 2:1 ratio.
  final aExp = k == 1 ? '$a^n' : '$a^(${k}n)';
  final bExp = j == 1 ? '$b^n' : '$b^(${j}n)';
  return StudyPdaChallenge(
    description: 'L = { $aExp $bExp | n ≥ 0 }',
    hint: 'Balance groups of $k "$a"s against groups of $j "$b"s using the stack.',
    alphabet: {a, b},
    difficulty: diff,
    testCases: [
      StudyPdaTestCase('', true),                                    // n = 0
      StudyPdaTestCase(_rep(a, k) + _rep(b, j), true),                 // n = 1: exactly one group each side
      StudyPdaTestCase(_rep(a, k * 2) + _rep(b, j * 2), true),         // n = 2: two complete groups each side
      StudyPdaTestCase(_rep(a, k) + _rep(b, j + 1), false),            // one a-group but one extra stray b: reject
      StudyPdaTestCase(_rep(b, j) + _rep(a, k), false),                // right counts, wrong order: reject
    ],
    acceptExamples: ['~', '"${_rep(a, k)}${_rep(b, j)}"'],
    rejectExamples: ['"${_rep(a, k)}"', '"${_rep(b, j)}"'],
    solutionSpec: PdaSolutionSpec.ratio(a, b, k, j),
  );
}

/// Builds one comparison-relation (=, <=, <, >=, >) challenge for a given
/// symbol pair and relation. Test cases are generated exhaustively over a
/// small grid of (i, j) counts rather than hand-picked, so every relation
/// gets broad, systematic coverage without needing bespoke examples.
StudyPdaChallenge _comparisonChallenge(String a, String b, _CompRelation rel) {
  final testCases = <StudyPdaTestCase>[];
  // Sweep i (count of a's) and j (count of b's) each from 0 to 4, skipping
  // any combination whose *total* length exceeds 7 — keeps the generated
  // test-case list (and therefore every grading run, and every rendered
  // "accept/reject" chip) bounded to reasonably short strings.
  for (int i = 0; i <= 4; i++) {
    for (int j = 0; j <= 4; j++) {
      if (i + j > 7) continue;
      // The ground-truth answer for this (i, j) pair, under the relation
      // this specific challenge is testing.
      final ok = switch (rel) {
        _CompRelation.equal => i == j,
        _CompRelation.leq => i <= j,
        _CompRelation.lt => i < j,
        _CompRelation.geq => i >= j,
        _CompRelation.gt => i > j,
      };
      testCases.add(StudyPdaTestCase(_rep(a, i) + _rep(b, j), ok));
    }
  }
  // Always also test a single "wrong order" case (b's before a's) — none of
  // the (i, j) sweep above ever produces an out-of-order string, since it
  // always places all a's before all b's, so this is added explicitly to
  // make sure a user's PDA doesn't wrongly accept b^j a^i inputs.
  testCases.add(StudyPdaTestCase('$b$a', false));

  final desc = switch (rel) {
    _CompRelation.equal => 'L = { $a^n $b^n | n ≥ 0 }',
    _CompRelation.leq => 'L = { $a^i $b^j | 0 ≤ i ≤ j }',
    _CompRelation.lt => 'L = { $a^i $b^j | 0 ≤ i < j }',
    _CompRelation.geq => 'L = { $a^i $b^j | i ≥ j ≥ 0 }',
    _CompRelation.gt => 'L = { $a^i $b^j | i > j ≥ 0 }',
  };

  return StudyPdaChallenge(
    description: desc,
    hint: 'Use the stack to compare counts of "$a"s and "$b"s.',
    alphabet: {a, b},
    // `equal` is the simplest relation (no leftover-marker bookkeeping
    // needed beyond plain a^n b^n), so it alone is tagged easy; every other
    // relation is tagged medium.
    difficulty: rel == _CompRelation.equal
        ? StudyPdaDifficulty.easy
        : StudyPdaDifficulty.medium,
    testCases: testCases,
    acceptExamples: const ['~'], // '~' (empty string) satisfies every one of
                                   // these relations (0 == 0, 0 <= 0, etc.)
                                   // except strict '<' / '>', so it's a safe
                                   // universal accept example to show
    rejectExamples: ['"$b$a"'], // the out-of-order case is always a reject,
                                  // regardless of which relation this is
    solutionSpec: PdaSolutionSpec.comp(a, b, _pdaComp(rel)),
  );
}

/// Outcome of grading a user's drawn PDA against a challenge: either fully
/// correct, or the specific [StudyPdaTestCase] where it first diverged from
/// the expected accept/reject verdict.
class StudyPdaGradeResult {
  final bool correct;
  final StudyPdaTestCase? failedCase; // null when correct == true
  const StudyPdaGradeResult.correct() : correct = true, failedCase = null;
  const StudyPdaGradeResult.failed(this.failedCase) : correct = false;
}

/// Runs every one of [challenge]'s test cases through a [PdaSimulator] built
/// from the user's drawn graph ([nodes]/[lines]/[start]), stopping at the
/// first mismatch (or infinite-stack-growth case) and reporting it.
StudyPdaGradeResult gradeStudyPda({
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? start,
  required StudyPdaChallenge challenge,
}) {
  // No start state, or literally nothing drawn yet: fail immediately against
  // the first test case, rather than attempting to simulate an empty graph.
  if (start == null || nodes.isEmpty) {
    return StudyPdaGradeResult.failed(challenge.testCases.first);
  }
  // One simulator instance is built once and reused (via rebuild()) across
  // every test case, rather than constructing a fresh PdaSimulator per
  // input — rebuild() resets whatever per-run state the simulator carries
  // (current configurations, stack contents, etc.) for the new input.
  final sim = PdaSimulator(nodes: nodes, lines: lines);
  for (final tc in challenge.testCases) {
    sim.rebuild(tc.input, startArrow: start);
    // A PDA whose stack can grow without bound while looping on epsilon
    // moves (e.g. a bare `_eps()` self-loop that also pushes) would
    // otherwise simulate forever; the simulator instead sets this flag and
    // bails out of that branch. Treat that as equivalent to "this input
    // could never actually reach an accepting configuration through this
    // path" — i.e. effectively a reject — so a test case that expects
    // ACCEPT fails outright, while one that expects REJECT is considered
    // satisfied and grading moves on to the next test case.
    if (sim.stackGrowthLoopDetected) {
      if (tc.expected) return StudyPdaGradeResult.failed(tc);
      continue;
    }
    final accepted = sim.finalResult() == PdaSimResult.accept;
    if (accepted != tc.expected) {
      return StudyPdaGradeResult.failed(tc);
    }
  }
  // Every test case matched its expected verdict.
  return const StudyPdaGradeResult.correct();
}

/// The main drawing/answer panel for a PDA study-mode challenge.
///
/// Shows one of two things depending on [answerRevealed]:
///   - false: an empty, user-editable [AutomataCanvasEmbed] the learner
///     draws their own attempted PDA on (locked read-only once they've
///     submitted a correct answer).
///   - true: the canonical reference solution, built fresh from the
///     challenge's [PdaSolutionSpec] and laid out via
///     [applyStudyModeLayout], shown read-only with an amber "correct
///     answer" border/badge.
class StudyPdaDrawingArea extends StatefulWidget {
  final StudyPdaChallenge challenge;   // which problem is being displayed
  final bool submitted;                 // whether the user has submitted an attempt
  final bool answerRevealed;            // whether to show the reference solution instead
  final bool? lastCorrect;              // result of the most recent submission, if any
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onFaChanged; // fired whenever the user edits their drawing, so the
                    // parent can keep its own copy of nodes/lines/start in
                    // sync for grading
  final AppThemeNotifier theme; // current app theme (colors), for styling

  const StudyPdaDrawingArea({
    super.key,
    required this.challenge,
    required this.submitted,
    required this.answerRevealed,
    required this.lastCorrect,
    required this.onFaChanged,
    required this.theme,
  });

  @override
  State<StudyPdaDrawingArea> createState() => _StudyPdaDrawingAreaState();
}

class _StudyPdaDrawingAreaState extends State<StudyPdaDrawingArea> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (widget.answerRevealed) {
      // Build the canonical reference PDA for this challenge from scratch
      // every time this branch renders (cheap — these are small, static
      // graphs), then run the shared study-mode layout post-processor so
      // nodes/labels don't visually overlap on the canvas.
      final graph = buildStudyPdaSolution(widget.challenge.solutionSpec);
      applyStudyModeLayout(graph.nodes, graph.lines);
      return Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          // Amber border marks this panel as showing the "answer" state,
          // visually distinct from the plain neutral border used for the
          // user's own in-progress drawing below.
          border: Border.all(
              color: const Color(0xFFFFB300).withValues(alpha: 0.5), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias, // keeps the canvas contents within the rounded corners
        child: Stack(
          children: [
            Positioned.fill(
              child: AutomataCanvasEmbed(
                initialNodes: graph.nodes,
                initialLines: graph.lines,
                initialStart: graph.startArrow,
                onChanged: (_, _, _) {}, // read-only view: edits (if any slip through) are discarded
                readOnly: true,
              ),
            ),
            // Small "CORRECT PDA (read-only)" label pinned to the
            // top-right corner, over the canvas.
            Positioned(
              top: 10,
              right: 14,
              child: Text(
                'CORRECT PDA  (read-only)',
                style: GoogleFonts.orbitron(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.7),
                  fontSize: 8,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Not revealed yet: the learner's own editable attempt ────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The row of accept/reject example chips shown above the canvas.
        StudyPdaTestCaseStrip(challenge: widget.challenge, theme: theme),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.borderMid), // neutral border (not the amber "answer" one)
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AutomataCanvasEmbed(
                    initialNodes: const {},   // learner starts from a blank canvas...
                    initialLines: const {},
                    initialStart: null,
                    onChanged: widget.onFaChanged, // ...and every edit is streamed back to the parent
                    // Lock the canvas read-only once the user has submitted
                    // and gotten it right — nothing left to edit at that
                    // point. While still wrong (or not yet submitted), it
                    // stays editable.
                    readOnly:
                        widget.submitted && (widget.lastCorrect ?? false),
                  ),
                ),
                // "YOUR PDA" label, dimmer/neutral compared to the amber
                // "CORRECT PDA" label used in the revealed-answer branch.
                Positioned(
                  top: 10,
                  right: 14,
                  child: Text(
                    'YOUR PDA',
                    style: GoogleFonts.orbitron(
                      color: theme.textDim.withValues(alpha: 0.4),
                      fontSize: 8,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders the challenge's [acceptExamples]/[rejectExamples] as two small
/// rows of colored "chips" — green for accept, red for reject — with an
/// "accept:" / "reject:" label in front of each row.
class StudyPdaTestCaseStrip extends StatelessWidget {
  final StudyPdaChallenge challenge;
  final AppThemeNotifier theme;

  const StudyPdaTestCaseStrip({super.key, 
    required this.challenge,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Local builder closure for one chip — captures `challenge`/`theme` are
    // not needed here since chip() only needs the string+accept flag passed
    // in, but it's defined inline (rather than as a separate method) since
    // it's only ever used within this build().
    Widget chip(String s, bool accept) {
      final label = s.isEmpty ? '~' : s; // render the empty string as the ~ glyph, not blank
      final color =
          accept ? const Color(0xFF1FD99A) : const Color(0xFFFF1744); // green vs red
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),      // faint tinted background
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)), // slightly stronger tinted border
        ),
        child: Text(
          label,
          style: GoogleFonts.courierPrime( // monospace, so strings of symbols align cleanly
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Row(
      children: [
        Text('accept: ',
            style: GoogleFonts.courierPrime(fontSize: 11, color: theme.textDim)),
        // Spread one chip per accept example, in the order they were listed
        // on the challenge.
        ...challenge.acceptExamples.map((s) => chip(s, true)),
        const SizedBox(width: 10), // gap between the accept group and reject group
        Text('reject: ',
            style: GoogleFonts.courierPrime(fontSize: 11, color: theme.textDim)),
        ...challenge.rejectExamples.map((s) => chip(s, false)),
      ],
    );
  }
}

/// Builds the human-readable "you got this test case wrong" message shown
/// after a failed submission, e.g. `Input "ab": expected ACCEPT but got
/// REJECT`. Note this only reports what the *correct* answer was ("expected"
/// / "got" here describe the correct vs. the user's outcome in the abstract,
/// not a live re-run of the user's machine) — it's a fixed-format string
/// derived purely from the failing [StudyPdaTestCase] itself.
String studyPdaFailureMessage(StudyPdaTestCase tc) {
  final inputDisplay =
      tc.input.isEmpty ? '~ (empty string)' : '"${tc.input}"';
  final expected = tc.expected ? 'ACCEPT' : 'REJECT';
  final got = tc.expected ? 'REJECT' : 'ACCEPT'; // the opposite of expected —
                                                    // this function is only
                                                    // ever called on a test
                                                    // case that already failed,
                                                    // so "got" is always the
                                                    // inverse of "expected"
  return 'Input $inputDisplay: expected $expected but got $got';
}