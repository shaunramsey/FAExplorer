// TM practice challenges and widgets for study mode.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';
import 'simulator.dart';
import 'tm_study_solutions.dart';
import 'study_mode_layout.dart';
import 'study_mode_symbols.dart';
import 'widgets/app_theme.dart';
import 'widgets/automata_canvas_embed.dart';

enum StudyTmDifficulty { easy, medium, hard }

class StudyTmTestCase {
  final String input;
  final bool expected;
  const StudyTmTestCase(this.input, this.expected);
}

class StudyTmChallenge {
  final String description;
  final String hint;
  final Set<String> alphabet;
  final StudyTmDifficulty difficulty;
  final List<StudyTmTestCase> testCases;
  final List<String> acceptExamples;
  final List<String> rejectExamples;
  final TmSolutionSpec solutionSpec;

  const StudyTmChallenge({
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

/// One entry per TM language family. Each is a *function*, called fresh for
/// every challenge instance — see the note on [generateStudyTmChallenges]
/// for why that matters.
typedef _TmTemplate = StudyTmChallenge Function(Random rng);

final List<_TmTemplate> _kTmTemplates = [
  _tmAnBn,
  _tmEqualCount,
  _tmPalindrome,
  _tmDivisibleByK,
  _tmStartEndSame,
  _tmAnBnCn,
  _tmAToKB,
  _tmCopyLang,
  _tmUnequalCount,
  _tmCrossingDep,
];

/// Repeats [s] [n] times. Dart strings don't overload `*`, and several
/// families below need to build test-case strings out of a randomly-chosen
/// count (k, i, j, …) rather than a small fixed literal.
String _rep(String s, int n) => List.filled(n, s).join();

/// Builds [count] TM challenges.
///
/// There are 10 language families below, so hitting the default count of 20
/// still means revisiting families multiple times — that part's
/// unavoidable. What matters is that every visit is a *fresh* call into the
/// template, drawing its own alphabet via [_freshPair] /
/// [randomStudyAlphabet] (and, for divisibleByK/aToKB, its own random k),
/// so two challenges from the same family never come out as literally the
/// same question. (Previously the 6 challenges were each built exactly once
/// and then just re-indexed with `all[i % all.length]` to pad out to 20 —
/// meaning entries 20 apart were, byte for byte, the exact same object.
/// That's the bug this fixes.)
///
/// On top of that, [_spreadOutSameFamily] nudges the shuffled result so the
/// same family doesn't land back-to-back either — even with different
/// symbols, two "a^n b^n"-shaped questions in a row read as repetitive.
/// Generates a shuffled pool of TM practice challenges and makes sure the same
/// language family does not appear back-to-back too often.
List<StudyTmChallenge> generateStudyTmChallenges(Random rng, {int count = 20}) {
  final templates = List<_TmTemplate>.of(_kTmTemplates)..shuffle(rng);
  final result = <StudyTmChallenge>[
    for (int i = 0; i < count; i++) templates[i % templates.length](rng),
  ];
  result.shuffle(rng);
  _spreadOutSameFamily(result);
  return result;
}

/// Reorders [challenges] in place so no two adjacent entries come from the
/// same language family (compared via [TmSolutionSpec.kind]). A plain
/// shuffle can still land two same-family challenges next to each other;
/// this does a best-effort local swap to break that up. If a run of
/// same-family entries can't be fully untangled (only possible when one
/// family dominates a short queue), it leaves the remainder as-is rather
/// than looping forever.
void _spreadOutSameFamily(List<StudyTmChallenge> challenges) {
  for (int i = 1; i < challenges.length; i++) {
    if (challenges[i].solutionSpec.kind != challenges[i - 1].solutionSpec.kind) {
      continue;
    }
    for (int j = i + 1; j < challenges.length; j++) {
      if (challenges[j].solutionSpec.kind != challenges[i - 1].solutionSpec.kind) {
        final tmp = challenges[i];
        challenges[i] = challenges[j];
        challenges[j] = tmp;
        break;
      }
    }
  }
}

/// Draws a fresh, randomly-ordered 2-symbol alphabet.
(String, String) _freshPair(Random rng) {
  final syms = randomStudyAlphabet(rng).toList()..shuffle(rng);
  return (syms[0], syms[1]);
}

StudyTmChallenge _tmAnBn(Random rng) {
  final (a, b) = _freshPair(rng);
  return StudyTmChallenge(
    description: 'L = { $a^n $b^n | n ≥ 0 }\n\n'
        'Accept strings with an equal number of "$a"s followed by "$b"s. '
        'The empty string ~ (n=0) is accepted.',
    hint: 'Repeatedly cross off the leftmost "$a" and the next "$b" to its '
        'right, bouncing back to the start each round. Reject if a "$a" '
        'shows up after a "$b", or if the counts don\'t line up.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.easy,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase(a, false),
      StudyTmTestCase(b, false),
      StudyTmTestCase('$a$b', true),
      StudyTmTestCase('$a$a$b$b', true),
      StudyTmTestCase('$a$a$b', false),
      StudyTmTestCase('$b$a', false),
      StudyTmTestCase('$a$b$a$b', false),
    ],
    acceptExamples: ['~', '$a$b', '$a$a$b$b'],
    rejectExamples: [a, b, '$a$a$b'],
    solutionSpec: TmSolutionSpec.anbn(a, b),
  );
}

StudyTmChallenge _tmEqualCount(Random rng) {
  final (a, b) = _freshPair(rng);
  return StudyTmChallenge(
    description: 'L = { w ∈ {$a,$b}* : #$a(w) = #$b(w) }\n\n'
        'Accept strings with equal numbers of "$a" and "$b", in any order.',
    hint: 'Cross off the leftmost unmarked symbol, then scan right for the '
        'nearest unmarked symbol of the other kind and cross that off too. '
        'Restart from the beginning each round; accept once nothing '
        'unmarked is left.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.medium,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase('$a$b', true),
      StudyTmTestCase('$b$a', true),
      StudyTmTestCase('$a$a$b$b', true),
      StudyTmTestCase('$a$b$a$b', true),
      StudyTmTestCase(a, false),
      StudyTmTestCase(b, false),
      StudyTmTestCase('$a$a$b', false),
    ],
    acceptExamples: ['~', '$a$b', '$b$a$a$b'],
    rejectExamples: [a, '$a$a$b'],
    solutionSpec: TmSolutionSpec.equalCount(a, b),
  );
}

StudyTmChallenge _tmPalindrome(Random rng) {
  final (a, b) = _freshPair(rng);
  return StudyTmChallenge(
    description: 'L = palindromes over {$a, $b}',
    hint: 'Cross off the leftmost unmarked symbol, sweep to the far end, '
        'and check the last unmarked symbol matches. Repeat inward.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.hard,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase(a, true),
      StudyTmTestCase('$a$a', true),
      StudyTmTestCase('$a$b$a', true),
      StudyTmTestCase('$a$b$b$a', true),
      StudyTmTestCase('$a$b', false),
      StudyTmTestCase('$b$a', false),
      StudyTmTestCase('$a$a$b', false),
    ],
    acceptExamples: ['~', a, '$a$b$a'],
    rejectExamples: ['$a$b', '$a$a$b'],
    solutionSpec: TmSolutionSpec.palindrome(a, b),
  );
}

StudyTmChallenge _tmDivisibleByK(Random rng) {
  final (a, b) = _freshPair(rng);
  final k = [2, 3, 4, 5][rng.nextInt(4)];
  return StudyTmChallenge(
    description: 'L = { w ∈ {$a,$b}* : #$a(w) ≡ 0 (mod $k) }\n\n'
        'Accept iff the number of "$a"s is a multiple of $k (0, $k, '
        '${2 * k}, …). "$b"s can appear anywhere and don\'t count.',
    hint: 'Cycle through $k states as you scan right over "$a"s (ignore '
        '"$b"s entirely). Accept if you hit the end of the tape on the '
        '"0 mod $k" state.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.easy,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase(b, true),
      StudyTmTestCase(_rep(a, k), true),
      StudyTmTestCase('$b${_rep(a, k)}$b', true),
      StudyTmTestCase(a, false),
      StudyTmTestCase(_rep(a, k + 1), false),
      StudyTmTestCase(_rep(a, 2 * k - 1), false),
    ],
    acceptExamples: ['~', _rep(a, k), '$b${_rep(a, k)}$b'],
    rejectExamples: [a, _rep(a, k + 1)],
    solutionSpec: TmSolutionSpec.divisibleByK(a, b, k),
  );
}

StudyTmChallenge _tmAToKB(Random rng) {
  final (a, b) = _freshPair(rng);
  final k = [2, 3][rng.nextInt(2)];
  return StudyTmChallenge(
    description: 'L = { $a^n $b^(${k}n) | n ≥ 0 }\n\n'
        'Accept strings with exactly $k "$b"s for every "$a" — $k times as '
        'many "$b"s as "$a"s, in that block order. The empty string (n=0) '
        'is accepted.',
    hint: 'Same crossing-off idea as $a^n$b^n, but chain $k "$b"-hunters '
        'per "$a": mark one "$a", then cross off $k "$b"s in a row before '
        'bouncing back to the start for the next "$a".',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.medium,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase(a, false),
      StudyTmTestCase(b, false),
      StudyTmTestCase('$a${_rep(b, k)}', true),
      StudyTmTestCase('${_rep(a, 2)}${_rep(b, 2 * k)}', true),
      StudyTmTestCase('$a${_rep(b, k - 1)}', false),
      StudyTmTestCase('$a${_rep(b, k + 1)}', false),
      StudyTmTestCase('$b$a', false),
    ],
    acceptExamples: ['~', '$a${_rep(b, k)}', '${_rep(a, 2)}${_rep(b, 2 * k)}'],
    rejectExamples: [a, '$a${_rep(b, k + 1)}'],
    solutionSpec: TmSolutionSpec.aToKB(a, b, k),
  );
}

StudyTmChallenge _tmCopyLang(Random rng) {
  final (a, b) = _freshPair(rng);
  return StudyTmChallenge(
    description: 'L = { w#w : w ∈ {$a,$b}* }\n\n'
        'Accept strings made of some pattern "w", a "#" delimiter, then '
        'that exact same pattern "w" again. This is genuinely not '
        'context-free — unlike w#w^R (reversed), which a PDA can check '
        'with a stack, a PDA cannot verify an in-order copy, but a TM can.',
    hint: 'Cross off the leftmost unmarked symbol before the "#", hop the '
        'delimiter, and cross off the matching leftmost unmarked symbol '
        'after it — reject on any mismatch. Repeat, then confirm nothing '
        'unmarked is left dangling on either side.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.hard,
    testCases: [
      StudyTmTestCase('#', true),
      StudyTmTestCase('$a#$a', true),
      StudyTmTestCase('$a$b#$a$b', true),
      StudyTmTestCase('$a$a$b#$a$a$b', true),
      StudyTmTestCase('', false),
      StudyTmTestCase(a, false),
      StudyTmTestCase('$a#', false),
      StudyTmTestCase('#$a', false),
      StudyTmTestCase('$a$b#$b$a', false),
      StudyTmTestCase('$a#$a$a', false),
    ],
    acceptExamples: ['#', '$a#$a', '$a$b#$a$b'],
    rejectExamples: ['~', '$a#', '$a$b#$b$a'],
    solutionSpec: TmSolutionSpec.copyLang(a, b),
  );
}

StudyTmChallenge _tmUnequalCount(Random rng) {
  final (a, b) = _freshPair(rng);
  return StudyTmChallenge(
    description: 'L = { w ∈ {$a,$b}* : #$a(w) ≠ #$b(w) }\n\n'
        'Accept strings where the count of "$a" and the count of "$b" are '
        '*not* equal, in any order — the complement of the equal-count '
        'language.',
    hint: 'Same crossing-off idea as the equal-count language — cross off '
        'the leftmost unmarked symbol, then scan right for the nearest '
        'unmarked symbol of the other kind and cross that off too — but '
        'flip the outcome: accept the moment a hunt runs off the end of '
        'the tape without finding a match (that proves the counts differ), '
        'and reject if everything ever gets fully paired off.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.medium,
    testCases: [
      StudyTmTestCase('', false),
      StudyTmTestCase(a, true),
      StudyTmTestCase(b, true),
      StudyTmTestCase('$a$b', false),
      StudyTmTestCase('$b$a', false),
      StudyTmTestCase('$a$a$b', true),
      StudyTmTestCase('$a$b$b', true),
      StudyTmTestCase('$a$a$b$b', false),
    ],
    acceptExamples: [a, '$a$a$b'],
    rejectExamples: ['~', '$a$b'],
    solutionSpec: TmSolutionSpec.unequalCount(a, b),
  );
}

StudyTmChallenge _tmStartEndSame(Random rng) {
  final (a, b) = _freshPair(rng);
  return StudyTmChallenge(
    description: 'L = { w ∈ {$a,$b}* : w is empty, or its first and last '
        'symbols match }',
    hint: 'Remember the first symbol (which state you\'re in), sweep to '
        'the end, then check the last symbol matches.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.easy,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase(a, true),
      StudyTmTestCase(b, true),
      StudyTmTestCase('$a$b$a', true),
      StudyTmTestCase('$b$a$b', true),
      StudyTmTestCase('$a$b', false),
      StudyTmTestCase('$b$a', false),
      StudyTmTestCase('$a$a$b', false),
    ],
    acceptExamples: ['~', a, '$a$b$a'],
    rejectExamples: ['$a$b', '$b$a'],
    solutionSpec: TmSolutionSpec.startEndSame(a, b),
  );
}

// L = { a^(m0*n) b^(m1*n) c^(m2*n) : n ≥ 0 }, difficulty-tiered:
//   easy   — plain a^n b^n c^n. Block order is a-then-b-then-c (whichever
//            three symbols got drawn), all multipliers 1.
//   medium — same fixed block order, but one randomly-chosen block gets a
//            multiplier of 2-4 (e.g. a^n b^(3n) c^n).
//   hard   — two of the three blocks get a multiplier of 2-4 each, AND the
//            block order itself is shuffled to a random one of the 6
//            permutations, so it's no longer necessarily "a-block then
//            b-block then c-block".
//
// Difficulty is picked per-instance (not fixed per-family) so a study
// session can surface any of the three tiers from this one template.
StudyTmChallenge _tmAnBnCn(Random rng) {
  final triple = randomStudyAlphabet(rng, size: 3).toList();
  final difficulty = StudyTmDifficulty.values[rng.nextInt(3)];

  final mults = [1, 1, 1];
  switch (difficulty) {
    case StudyTmDifficulty.easy:
      break;
    case StudyTmDifficulty.medium:
      mults[rng.nextInt(3)] = 2 + rng.nextInt(3); // 2..4
      break;
    case StudyTmDifficulty.hard:
      final boosted = [0, 1, 2]..shuffle(rng);
      mults[boosted[0]] = 2 + rng.nextInt(3);
      mults[boosted[1]] = 2 + rng.nextInt(3);
      triple.shuffle(rng); // randomize block presentation order too
      break;
  }

  final ta = triple[0], tb = triple[1], tc = triple[2];
  final ma = mults[0], mb = mults[1], mc = mults[2];

  String blockTerm(String sym, int m) => m == 1 ? '$sym^n' : '$sym^(${m}n)';
  String countPhrase(int m) => m == 1 ? 'n' : '$m·n';

  String build(int n) => _rep(ta, ma * n) + _rep(tb, mb * n) + _rep(tc, mc * n);
  final n1 = build(1);
  final n2 = build(2);
  final missingLastBlock = _rep(ta, ma) + _rep(tb, mb); // drop the c block
  final extraInFirstBlock = _rep(ta, ma + 1) + _rep(tb, mb) + _rep(tc, mc);
  final reversedOrder = _rep(tc, mc) + _rep(tb, mb) + _rep(ta, ma);
  final trailingExtra = '$n1$tc';

  final formula = '${blockTerm(ta, ma)} ${blockTerm(tb, mb)} ${blockTerm(tc, mc)}';

  return StudyTmChallenge(
    description: 'L = { $formula | n ≥ 0 }\n\n'
        'Not context-free — a PDA cannot recognize this language, but a TM '
        'can. Accept strings made of "$ta" repeated ${countPhrase(ma)} '
        'times, then "$tb" repeated ${countPhrase(mb)} times, then "$tc" '
        'repeated ${countPhrase(mc)} times, in that exact block order, all '
        'sharing the same n ≥ 0.',
    hint: 'Same crossing-off idea as $ta^n$tb^n, extended to three blocks '
        'with their own per-block counts: each round, cross $ma "$ta"(s), '
        'then $mb "$tb"(s), then $mc "$tc"(s), bouncing back to the start '
        'every round. Reject if a block runs short, has leftovers, or the '
        'block order gets broken.',
    alphabet: {ta, tb, tc},
    difficulty: difficulty,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase(n1, true),
      StudyTmTestCase(n2, true),
      StudyTmTestCase(ta, false),
      StudyTmTestCase(missingLastBlock, false),
      StudyTmTestCase(extraInFirstBlock, false),
      StudyTmTestCase(reversedOrder, false),
      StudyTmTestCase(trailingExtra, false),
    ],
    acceptExamples: ['~', n1, n2],
    rejectExamples: [ta, missingLastBlock],
    solutionSpec: TmSolutionSpec.anbncn(ta, tb, tc, mults: mults),
  );
}

// L = { s0^(m0*n) s1^(m1*m) s2^(m2*n) s3^(m3*m) : n, m ≥ 0 } — "crossing
// dependencies", the classic non-context-free example built from two
// *independent* counters (n and m) whose blocks interleave rather than
// nest or sit adjacent. Distinct from _tmAnBnCn: that family is three
// blocks sharing *one* counter (nested, in a sense — a PDA gets tripped up
// only by the third simultaneous block); this is two counters that open
// and close in an interleaved order a single stack fundamentally can't
// track (see the comment on TmSolutionSpec.crossingDep's builder for why).
//
// Two tiers:
//   easy — block order fixed exactly as the four symbols were drawn, no
//          multipliers (so s0 s1 s2 s3, all multiplier 1).
//   hard — block order shuffled to a random permutation of the same four
//          symbols (still always a genuine crossing dependency — position
//          0/2 share one counter and 1/3 share the other no matter which
//          literal symbols land there, so *any* permutation keeps the
//          language non-context-free), AND two of the four blocks get a
//          random multiplier of 2-4.
StudyTmChallenge _tmCrossingDep(Random rng) {
  final four = randomStudyAlphabet(rng, size: 4).toList()..shuffle(rng);
  final difficulty =
      rng.nextBool() ? StudyTmDifficulty.hard : StudyTmDifficulty.easy;

  final order = List<String>.of(four);
  final mults = [1, 1, 1, 1];
  if (difficulty == StudyTmDifficulty.hard) {
    order.shuffle(rng);
    final boosted = [0, 1, 2, 3]..shuffle(rng);
    mults[boosted[0]] = 2 + rng.nextInt(3);
    mults[boosted[1]] = 2 + rng.nextInt(3);
  }

  final s0 = order[0], s1 = order[1], s2 = order[2], s3 = order[3];
  final m0 = mults[0], m1 = mults[1], m2 = mults[2], m3 = mults[3];

  String blockTerm(String sym, int m, String counter) =>
      m == 1 ? '$sym^$counter' : '$sym^($m$counter)';
  String countPhrase(int m, String counter) =>
      m == 1 ? counter : '$m·$counter';

  String build(int n, int m) =>
      _rep(s0, m0 * n) + _rep(s1, m1 * m) + _rep(s2, m2 * n) + _rep(s3, m3 * m);

  final empty = build(0, 0);
  final n1m1 = build(1, 1);
  final n1m0 = build(1, 0);
  final n0m1 = build(0, 1);
  final n2m1 = build(2, 1);
  final missingSecondNBlock = _rep(s0, m0) + _rep(s1, m1); // drop blocks 2 & 3
  final mismatchedN =
      _rep(s0, m0 * 2) + _rep(s1, m1) + _rep(s2, m2) + _rep(s3, m3); // n:2 vs 1
  final wrongOrder =
      _rep(s2, m2) + _rep(s1, m1) + _rep(s0, m0) + _rep(s3, m3); // scrambled

  final formula =
      '${blockTerm(s0, m0, 'n')} ${blockTerm(s1, m1, 'm')} '
      '${blockTerm(s2, m2, 'n')} ${blockTerm(s3, m3, 'm')}';

  return StudyTmChallenge(
    description: 'L = { $formula | n,m ≥ 0 }\n\n'
        'Not context-free — a PDA cannot recognize this "crossing '
        'dependency" pattern, but a TM can. Accept strings made of "$s0" '
        'repeated ${countPhrase(m0, 'n')} times, then "$s1" repeated '
        '${countPhrase(m1, 'm')} times, then "$s2" repeated '
        '${countPhrase(m2, 'n')} times, then "$s3" repeated '
        '${countPhrase(m3, 'm')} times, in that exact block order — where '
        'the "$s0"/"$s2" counts must match each other (count n) and the '
        '"$s1"/"$s3" counts must match each other (count m), independently.',
    hint: 'Two independent crossing-off passes. First pair off "$s0" with '
        '"$s2" (hunting past "$s1" without touching it) to confirm they '
        'share the same count — that\'s the crossing part, since they '
        'aren\'t adjacent. Once that\'s fully matched, do the same for '
        '"$s1" with "$s3". Reject if either pass runs short, has '
        'leftovers, or the block order breaks.',
    alphabet: {s0, s1, s2, s3},
    difficulty: difficulty,
    testCases: [
      StudyTmTestCase(empty, true),
      StudyTmTestCase(n1m1, true),
      StudyTmTestCase(n1m0, true),
      StudyTmTestCase(n0m1, true),
      StudyTmTestCase(n2m1, true),
      StudyTmTestCase(s0, false),
      StudyTmTestCase(missingSecondNBlock, false),
      StudyTmTestCase(mismatchedN, false),
      StudyTmTestCase(wrongOrder, false),
    ],
    acceptExamples: ['~', n1m1, n2m1],
    rejectExamples: [s0, mismatchedN],
    solutionSpec: TmSolutionSpec.crossingDep(s0, s1, s2, s3, mults: mults),
  );
}

// ── Grading ──────────────────────────────────────────────────────────────────

/// Safety cap on simulation steps per test case. Every construction the
/// reference solutions use halts (by getting stuck) within steps roughly
/// proportional to input length, so this is a generous backstop against a
/// genuinely buggy player machine looping forever — not something the
/// reference solutions are expected to come close to.
const int kStudyTmMaxSteps = 5000;

class StudyTmGradeResult {
  final bool correct;
  final StudyTmTestCase? failedCase;
  const StudyTmGradeResult.correct() : correct = true, failedCase = null;
  const StudyTmGradeResult.failed(this.failedCase) : correct = false;
}

/// Grades a player's TM solution by running the submitted machine against the
/// challenge's oracle test cases and comparing the outcomes to the expected ones.
StudyTmGradeResult gradeStudyTm({
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? start,
  required StudyTmChallenge challenge,
}) {
  if (start == null || nodes.isEmpty) {
    return StudyTmGradeResult.failed(challenge.testCases.first);
  }
  final sim = TmSimulator(nodes: nodes, lines: lines);
  for (final tc in challenge.testCases) {
    sim.rebuild(tc.input, startArrow: start);
    for (int i = 0; i < kStudyTmMaxSteps && sim.result == TmResult.running; i++) {
      if (!sim.computeNext()) break;
    }
    if (sim.result == TmResult.running) {
      // Never halted within the step cap. Treat like a machine that loops
      // forever on this input: that's indistinguishable from "reject" for
      // grading purposes, so only fail if this input was supposed to accept.
      if (tc.expected) return StudyTmGradeResult.failed(tc);
      continue;
    }
    final accepted = sim.result == TmResult.accept;
    if (accepted != tc.expected) {
      return StudyTmGradeResult.failed(tc);
    }
  }
  return const StudyTmGradeResult.correct();
}

// ── Widgets ──────────────────────────────────────────────────────────────────

/// Draw area for TM practice rounds, rendering either the player's current
/// machine or the read-only solution once the answer is revealed.
class StudyTmDrawingArea extends StatefulWidget {
  final StudyTmChallenge challenge;
  final bool submitted;
  final bool answerRevealed;
  final bool? lastCorrect;
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onFaChanged;
  final AppThemeNotifier theme;

  const StudyTmDrawingArea({
    super.key,
    required this.challenge,
    required this.submitted,
    required this.answerRevealed,
    required this.lastCorrect,
    required this.onFaChanged,
    required this.theme,
  });

  @override
  State<StudyTmDrawingArea> createState() => _StudyTmDrawingAreaState();
}

class _StudyTmDrawingAreaState extends State<StudyTmDrawingArea> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (widget.answerRevealed) {
      final graph = buildStudyTmSolution(widget.challenge.solutionSpec);
      applyStudyModeLayout(graph.nodes, graph.lines);
      return Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFFFB300).withValues(alpha: 0.5), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: AutomataCanvasEmbed(
                initialNodes: graph.nodes,
                initialLines: graph.lines,
                initialStart: graph.startArrow,
                onChanged: (_, _, _) {},
                readOnly: true,
              ),
            ),
            Positioned(
              top: 10,
              right: 14,
              child: Text(
                'CORRECT TM  (read-only)',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudyTmTestCaseStrip(challenge: widget.challenge, theme: theme),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.borderMid),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AutomataCanvasEmbed(
                    initialNodes: const {},
                    initialLines: const {},
                    initialStart: null,
                    onChanged: widget.onFaChanged,
                    readOnly:
                        widget.submitted && (widget.lastCorrect ?? false),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 14,
                  child: Text(
                    'YOUR TM',
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

/// Compact strip showing accepting and rejecting example strings for the TM challenge.
class StudyTmTestCaseStrip extends StatelessWidget {
  final StudyTmChallenge challenge;
  final AppThemeNotifier theme;

  const StudyTmTestCaseStrip({super.key,
    required this.challenge,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String s, bool accept) {
      final label = s.isEmpty ? '~' : s;
      final color =
          accept ? const Color(0xFF1FD99A) : const Color(0xFFFF1744);
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: GoogleFonts.courierPrime(
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
        ...challenge.acceptExamples.map((s) => chip(s, true)),
        const SizedBox(width: 10),
        Text('reject: ',
            style: GoogleFonts.courierPrime(fontSize: 11, color: theme.textDim)),
        ...challenge.rejectExamples.map((s) => chip(s, false)),
      ],
    );
  }
}

String studyTmFailureMessage(StudyTmTestCase tc) {
  final inputDisplay =
      tc.input.isEmpty ? '~ (empty string)' : '"${tc.input}"';
  final expected = tc.expected ? 'ACCEPT' : 'REJECT';
  final got = tc.expected ? 'REJECT' : 'ACCEPT';
  return 'Input $inputDisplay: expected $expected but got $got';
}