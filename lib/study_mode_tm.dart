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

List<StudyTmChallenge> generateStudyTmChallenges(Random rng, {int count = 20}) {
  final all = _buildAllStudyTmChallenges(rng)..shuffle(rng);
  return [for (int i = 0; i < count; i++) all[i % all.length]];
}

/// Draws a fresh, randomly-ordered 2-symbol alphabet.
(String, String) _freshPair(Random rng) {
  final syms = randomStudyAlphabet(rng).toList()..shuffle(rng);
  return (syms[0], syms[1]);
}

List<StudyTmChallenge> _buildAllStudyTmChallenges(Random rng) {
  final challenges = <StudyTmChallenge>[];

  // Every challenge below draws its own alphabet via _freshPair() /
  // randomStudyAlphabet() rather than sharing one pair across the whole
  // batch — see study_mode_pda.dart for why.
  var (a, b) = _freshPair(rng);

  challenges.add(StudyTmChallenge(
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
  ));

  (a, b) = _freshPair(rng);
  challenges.add(StudyTmChallenge(
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
  ));

  (a, b) = _freshPair(rng);
  challenges.add(StudyTmChallenge(
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
  ));

  (a, b) = _freshPair(rng);
  challenges.add(StudyTmChallenge(
    description: 'L = { w ∈ {$a,$b}* : #$a(w) ≡ 0 (mod 3) }\n\n'
        'Accept iff the number of "$a"s is a multiple of 3 (0, 3, 6, …). '
        '"$b"s can appear anywhere and don\'t count.',
    hint: 'Cycle through 3 states as you scan right over "$a"s (ignore '
        '"$b"s entirely). Accept if you hit the end of the tape on the '
        '"0 mod 3" state.',
    alphabet: {a, b},
    difficulty: StudyTmDifficulty.easy,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase(b, true),
      StudyTmTestCase('$a$a$a', true),
      StudyTmTestCase('$b$a$a$a$b', true),
      StudyTmTestCase(a, false),
      StudyTmTestCase('$a$a', false),
      StudyTmTestCase('$a$a$a$a', false),
    ],
    acceptExamples: ['~', '$a$a$a', '$b$a$a$a$b'],
    rejectExamples: [a, '$a$a'],
    solutionSpec: TmSolutionSpec.divisibleBy3(a, b),
  ));

  (a, b) = _freshPair(rng);
  challenges.add(StudyTmChallenge(
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
  ));

  final triple = randomStudyAlphabet(rng, size: 3).toList()..shuffle(rng);
  final ta = triple[0], tb = triple[1], tc = triple[2];
  challenges.add(StudyTmChallenge(
    description: 'L = { $ta^n $tb^n $tc^n | n ≥ 0 }\n\n'
        'Not context-free — a PDA cannot recognize this language, but a TM '
        'can. Accept strings with equal counts of "$ta", then "$tb", then '
        '"$tc", in that block order.',
    hint: 'Same crossing-off idea as $ta^n$tb^n, extended to three blocks: '
        'cross one "$ta", one "$tb", and one "$tc" per round trip.',
    alphabet: {ta, tb, tc},
    difficulty: StudyTmDifficulty.hard,
    testCases: [
      StudyTmTestCase('', true),
      StudyTmTestCase('$ta$tb$tc', true),
      StudyTmTestCase('$ta$ta$tb$tb$tc$tc', true),
      StudyTmTestCase('$ta$tb', false),
      StudyTmTestCase('$ta$ta$tb$tc', false),
      StudyTmTestCase('$tc$tb$ta', false),
      StudyTmTestCase('$ta$tb$tc$tc', false),
    ],
    acceptExamples: ['~', '$ta$tb$tc', '$ta$ta$tb$tb$tc$tc'],
    rejectExamples: ['$ta$tb', '$ta$ta$tb$tc'],
    solutionSpec: TmSolutionSpec.anbncn(ta, tb, tc),
  ));

  return challenges;
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