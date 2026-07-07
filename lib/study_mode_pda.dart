// PDA practice challenges and widgets for study mode.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';
import 'simulator.dart';
import 'pda_study_solutions.dart';
import 'study_mode_symbols.dart';
import 'widgets/app_theme.dart';
import 'widgets/automata_canvas_embed.dart';

enum StudyPdaDifficulty { easy, medium, hard }

class StudyPdaTestCase {
  final String input;
  final bool expected;
  const StudyPdaTestCase(this.input, this.expected);
}

class StudyPdaChallenge {
  final String description;
  final String hint;
  final Set<String> alphabet;
  final StudyPdaDifficulty difficulty;
  final List<StudyPdaTestCase> testCases;
  final List<String> acceptExamples;
  final List<String> rejectExamples;
  final PdaSolutionSpec solutionSpec;

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

String _rep(String sym, int n) => sym * n;

enum _CompRelation { equal, leq, lt, geq, gt }

PdaCompRelation _pdaComp(_CompRelation r) => switch (r) {
      _CompRelation.equal => PdaCompRelation.equal,
      _CompRelation.leq => PdaCompRelation.leq,
      _CompRelation.lt => PdaCompRelation.lt,
      _CompRelation.geq => PdaCompRelation.geq,
      _CompRelation.gt => PdaCompRelation.gt,
    };

List<StudyPdaChallenge> generateStudyPdaChallenges(Random rng, {int count = 20}) {
  final all = _buildAllStudyPdaChallenges(rng)..shuffle(rng);
  return [for (int i = 0; i < count; i++) all[i % all.length]];
}

/// Draws a fresh, randomly-ordered 2-symbol alphabet.
(String, String) _freshPair(Random rng) {
  final syms = randomStudyAlphabet(rng).toList()..shuffle(rng);
  return (syms[0], syms[1]);
}

List<StudyPdaChallenge> _buildAllStudyPdaChallenges(Random rng) {
  final challenges = <StudyPdaChallenge>[];

  // Every challenge below draws its own alphabet via _freshPair() /
  // randomStudyAlphabet() rather than sharing one pair across the whole
  // batch — otherwise a single build could lock onto e.g. "x"/"y" for all
  // fifteen-odd PDA problems in a session.
  var (a, b) = _freshPair(rng);

  challenges.add(StudyPdaChallenge(
    description: 'L = { $a^n $b^n | n ≥ 0 }\n\n'
        'Accept strings with an equal number of "$a"s followed by "$b"s.\n'
        'The empty string ~ (n=0) is accepted.',
    hint: 'Push a stack symbol for each "$a", pop one for each "$b". '
        'Accept when the stack is empty at the end.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.easy,
    testCases: [
      StudyPdaTestCase('', true),
      StudyPdaTestCase(a, false),
      StudyPdaTestCase(b, false),
      StudyPdaTestCase('$a$b', true),
      StudyPdaTestCase('$a$a$b$b', true),
      StudyPdaTestCase('$a$a$b', false),
      StudyPdaTestCase('$b$a', false),
    ],
    acceptExamples: ['~', '$a$b', '$a$a$b$b'],
    rejectExamples: [a, b, '$a$a$b'],
    solutionSpec: PdaSolutionSpec.anbn(a, b),
  ));

  (a, b) = _freshPair(rng);
  challenges.add(StudyPdaChallenge(
    description: 'L = { $a^n $b^n | n ≥ 1 }\n\n'
        'Accept non-empty strings with equal "$a" and "$b" counts.',
    hint: 'Push for each "$a", pop for each "$b". Reject ~.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.easy,
    testCases: [
      StudyPdaTestCase('', false),
      StudyPdaTestCase('$a$b', true),
      StudyPdaTestCase('$a$a$b$b', true),
      StudyPdaTestCase(a, false),
      StudyPdaTestCase('$a$a$b', false),
    ],
    acceptExamples: ['$a$b', '$a$a$b$b'],
    rejectExamples: ['~', a, '$a$a$b'],
    solutionSpec: PdaSolutionSpec.anbn(a, b, acceptEmpty: false),
  ));

  for (final (k, j, diff) in [
    (2, 1, StudyPdaDifficulty.medium),
    (1, 2, StudyPdaDifficulty.medium),
    (2, 3, StudyPdaDifficulty.hard),
  ]) {
    final (ra, rb) = _freshPair(rng);
    challenges.add(_ratioChallenge(ra, rb, k, j, diff));
  }

  for (final rel in _CompRelation.values) {
    final (ca, cb) = _freshPair(rng);
    challenges.add(_comparisonChallenge(ca, cb, rel));
  }

  final quad = randomStudyAlphabet(rng, size: 4).toList()..shuffle(rng);
  final s1 = quad[0], s2 = quad[1], s3 = quad[2], s4 = quad[3];
  challenges.add(StudyPdaChallenge(
    description: 'L = { $s1^n $s2^m $s3^n $s4^m | n, m ≥ 0 }',
    hint: 'Use separate stack markers for the two pairs of symbols.',
    alphabet: {s1, s2, s3, s4},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase('', true),
      StudyPdaTestCase('$s1$s3', true),
      StudyPdaTestCase('$s1$s2$s3$s4', true),
      StudyPdaTestCase('$s1$s3$s2$s4', false),
      StudyPdaTestCase('$s1$s2$s3', false),
    ],
    acceptExamples: ['~', '$s1$s3', '$s1$s2$s3$s4'],
    rejectExamples: ['$s1$s2$s3', '$s1$s3$s2$s4'],
    solutionSpec: PdaSolutionSpec.interleaved4(s1, s2, s3, s4),
  ));

  final triple = randomStudyAlphabet(rng, size: 3).toList()..shuffle(rng);
  final outer = triple[0], mid = triple[1], frame = triple[2];
  challenges.add(StudyPdaChallenge(
    description: 'L = { $outer^n $mid^m $frame^n | n, m ≥ 0 }',
    hint: 'Push for each "$outer", ignore "$mid"s, pop for each "$frame".',
    alphabet: {outer, mid, frame},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase('', true),
      StudyPdaTestCase(mid, true),
      StudyPdaTestCase('$outer$frame', true),
      StudyPdaTestCase('$outer$mid$frame', true),
      StudyPdaTestCase(frame, false),
      StudyPdaTestCase('$outer$mid$mid', false),
    ],
    acceptExamples: ['~', mid, '$outer$frame', '$outer$mid$frame'],
    rejectExamples: [frame, '$outer$mid$mid'],
    solutionSpec: PdaSolutionSpec.outerFrame(outer, mid, frame),
  ));

  (a, b) = _freshPair(rng);
  challenges.add(StudyPdaChallenge(
    description: 'L = palindromes over {$a, $b}',
    hint: 'Nondeterministically guess the midpoint, push then pop.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase('', true),
      StudyPdaTestCase(a, true),
      StudyPdaTestCase('$a$b$a', true),
      StudyPdaTestCase('$a$b', false),
    ],
    acceptExamples: ['~', a, '$a$a', '$a$b$a'],
    rejectExamples: ['$a$b', '$b$a'],
    solutionSpec: PdaSolutionSpec.palindrome(a, b),
  ));

  (a, b) = _freshPair(rng);
  challenges.add(StudyPdaChallenge(
    description: 'L = { w $b w^R | w ∈ {$a}* }',
    hint: 'Push "$a"s, read "$b", pop "$a"s on the way back.',
    alphabet: {a, b},
    difficulty: StudyPdaDifficulty.hard,
    testCases: [
      StudyPdaTestCase(b, true),
      StudyPdaTestCase('$a$b$a', true),
      StudyPdaTestCase('', false),
      StudyPdaTestCase('$a$b', false),
    ],
    acceptExamples: [b, '$a$b$a', '$a$a$b$a$a'],
    rejectExamples: ['~', '$a$b'],
    solutionSpec: PdaSolutionSpec.markedPalindrome(a, b),
  ));

  return challenges;
}

StudyPdaChallenge _ratioChallenge(
  String a,
  String b,
  int k,
  int j,
  StudyPdaDifficulty diff,
) {
  final aExp = k == 1 ? '$a^n' : '$a^(${k}n)';
  final bExp = j == 1 ? '$b^n' : '$b^(${j}n)';
  return StudyPdaChallenge(
    description: 'L = { $aExp $bExp | n ≥ 0 }',
    hint: 'Balance groups of $k "$a"s against groups of $j "$b"s using the stack.',
    alphabet: {a, b},
    difficulty: diff,
    testCases: [
      StudyPdaTestCase('', true),
      StudyPdaTestCase(_rep(a, k) + _rep(b, j), true),
      StudyPdaTestCase(_rep(a, k * 2) + _rep(b, j * 2), true),
      StudyPdaTestCase(_rep(a, k) + _rep(b, j + 1), false),
      StudyPdaTestCase(_rep(b, j) + _rep(a, k), false),
    ],
    acceptExamples: ['~', '"${_rep(a, k)}${_rep(b, j)}"'],
    rejectExamples: ['"${_rep(a, k)}"', '"${_rep(b, j)}"'],
    solutionSpec: PdaSolutionSpec.ratio(a, b, k, j),
  );
}

StudyPdaChallenge _comparisonChallenge(String a, String b, _CompRelation rel) {
  final testCases = <StudyPdaTestCase>[];
  for (int i = 0; i <= 4; i++) {
    for (int j = 0; j <= 4; j++) {
      if (i + j > 7) continue;
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
    difficulty: rel == _CompRelation.equal
        ? StudyPdaDifficulty.easy
        : StudyPdaDifficulty.medium,
    testCases: testCases,
    acceptExamples: const ['~'],
    rejectExamples: ['"$b$a"'],
    solutionSpec: PdaSolutionSpec.comp(a, b, _pdaComp(rel)),
  );
}

class StudyPdaGradeResult {
  final bool correct;
  final StudyPdaTestCase? failedCase;
  const StudyPdaGradeResult.correct() : correct = true, failedCase = null;
  const StudyPdaGradeResult.failed(this.failedCase) : correct = false;
}

StudyPdaGradeResult gradeStudyPda({
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? start,
  required StudyPdaChallenge challenge,
}) {
  if (start == null || nodes.isEmpty) {
    return StudyPdaGradeResult.failed(challenge.testCases.first);
  }
  final sim = PdaSimulator(nodes: nodes, lines: lines);
  for (final tc in challenge.testCases) {
    sim.rebuild(tc.input, startArrow: start);
    if (sim.stackGrowthLoopDetected) {
      if (tc.expected) return StudyPdaGradeResult.failed(tc);
      continue;
    }
    final accepted = sim.finalResult() == PdaSimResult.accept;
    if (accepted != tc.expected) {
      return StudyPdaGradeResult.failed(tc);
    }
  }
  return const StudyPdaGradeResult.correct();
}

class StudyPdaDrawingArea extends StatefulWidget {
  final StudyPdaChallenge challenge;
  final bool submitted;
  final bool answerRevealed;
  final bool? lastCorrect;
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onFaChanged;
  final AppThemeNotifier theme;

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
      final graph = buildStudyPdaSolution(widget.challenge.solutionSpec);
      _applyStudyModeLayout(graph.nodes, graph.lines);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudyPdaTestCaseStrip(challenge: widget.challenge, theme: theme),
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

class StudyPdaTestCaseStrip extends StatelessWidget {
  final StudyPdaChallenge challenge;
  final AppThemeNotifier theme;

  const StudyPdaTestCaseStrip({super.key, 
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

String studyPdaFailureMessage(StudyPdaTestCase tc) {
  final inputDisplay =
      tc.input.isEmpty ? '~ (empty string)' : '"${tc.input}"';
  final expected = tc.expected ? 'ACCEPT' : 'REJECT';
  final got = tc.expected ? 'REJECT' : 'ACCEPT';
  return 'Input $inputDisplay: expected $expected but got $got';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Study-mode layout post-processor
//
//  Applied to the solution graph after it is built from a PDA spec, before
//  rendering it read-only.  Three passes:
//
//  1. Set a default perpendicularPart of 30 on every non-self-loop line.
//
//  2+3. For every node N and every line L that does not touch N, run two
//     sub-checks inside a single convergence loop so both can react to each
//     other rather than fighting across two separate loops:
//
//     2. CHORD CLEARANCE — closest point on the straight chord through the two
//        endpoint centres.  If within clearance, push N perpendicularly away.
//
//     3. TEXTBOX CLEARANCE — axis-aligned bounding rect of the line's label
//        (computed by LineData.getTextBoxLocation).  If the node circle
//        overlaps the rect, push N away from the nearest edge.
//
//     Repeat until stable (max iterations).
// ─────────────────────────────────────────────────────────────────────────────

void _applyStudyModeLayout(
  Map<String, NodeData> nodes,
  Map<String, LineData> lines,
) {
  // ── Pass 1: default perpendicularPart on all non-self-loop lines ───────────
  for (final line in lines.values) {
    if (line.nodeAId != line.nodeBId) {
      line.perpendicularPart = 30.0;
    }
  }

  // ── Shared constants ───────────────────────────────────────────────────────
  const double nodeRadius     = 50.0;               // visual radius of a state circle
  const double nodeDiameter   = nodeRadius * 2;
  const double minNodeGap     = nodeDiameter + 40.0; // minimum centre-to-centre distance
  const double clearance      = nodeRadius + 30.0;   // min dist: node centre ↔ chord
  const double textBuffer     = 14.0;                // extra padding around textbox rect
  const double boxWidth       = kLabelBoxWidth;       // must match LineWidget — see models.dart
  const double lineHeight     = kLabelLineHeight;      // single-line height in LineWidget — see models.dart
  const double selfLoopRadius = kSelfLoopRadius;       // loop circle radius — see models.dart
  const double selfLoopCenterDist = kSelfLoopCenterDistance; // centre offset for loop — see models.dart
  const int    iterations     = 30;                  // convergence passes

  // Helper: push node away from an axis-aligned rect.
  // Returns true if a push was applied.
  bool pushNodeFromRect(
    NodeData node,
    double rLeft,
    double rTop,
    double rRight,
    double rBottom,
  ) {
    final nc = node.center;
    final closestX = nc.dx.clamp(rLeft, rRight);
    final closestY = nc.dy.clamp(rTop, rBottom);
    final dxFromBox = nc.dx - closestX;
    final dyFromBox = nc.dy - closestY;
    final distFromBox = sqrt(dxFromBox * dxFromBox + dyFromBox * dyFromBox);

    if (distFromBox < nodeRadius) {
      final push = nodeRadius - distFromBox + 2.0; // +2 px safety margin

      final Offset pushDir;
      if (distFromBox < 0.5) {
        final rcx = (rLeft + rRight) / 2;
        final rcy = (rTop + rBottom) / 2;
        final awayDx = nc.dx - rcx;
        final awayDy = nc.dy - rcy;
        final awayLen = sqrt(awayDx * awayDx + awayDy * awayDy);
        pushDir = awayLen < 0.5
            ? const Offset(0, 1)
            : Offset(awayDx / awayLen, awayDy / awayLen);
      } else {
        pushDir = Offset(dxFromBox / distFromBox, dyFromBox / distFromBox);
      }

      node.position = Offset(
        node.position.dx + pushDir.dx * push,
        node.position.dy + pushDir.dy * push,
      );
      return true;
    }
    return false;
  }

  // ── Convergence loop ───────────────────────────────────────────────────────
  for (int iter = 0; iter < iterations; iter++) {
    bool anyMoved = false;
    final nodeList = nodes.values.toList();

    // ── Check A: node-node minimum distance ─────────────────────────────────
    for (int i = 0; i < nodeList.length; i++) {
      final na = nodeList[i];
      if (na.isBlackBox) continue;
      for (int j = i + 1; j < nodeList.length; j++) {
        final nb = nodeList[j];
        if (nb.isBlackBox) continue;

        final cA = na.center;
        final cB = nb.center;
        final dx = cB.dx - cA.dx;
        final dy = cB.dy - cA.dy;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < minNodeGap && dist > 0.1) {
          final overlap = (minNodeGap - dist) / 2.0 + 2.0;
          final ux = dx / dist;
          final uy = dy / dist;
          // Push both nodes apart equally.
          na.position = Offset(na.position.dx - ux * overlap, na.position.dy - uy * overlap);
          nb.position = Offset(nb.position.dx + ux * overlap, nb.position.dy + uy * overlap);
          anyMoved = true;
        }
      }
    }

    // ── Checks B+C+D: per-line clearance for every node ─────────────────────
    for (final node in nodeList) {
      if (node.isBlackBox) continue;

      for (final line in lines.values) {
        final isSelfLoop = line.nodeAId == line.nodeBId;

        if (isSelfLoop) {
          // ── Check D: self-loop textbox must not overlap OTHER nodes ─────
          // The loop belongs to its own node; we only care if it overlaps a
          // *different* node's circle.
          if (line.nodeAId == node.id) continue;

          final ownerNode = nodes[line.nodeAId];
          if (ownerNode == null) continue;

          // Compute self-loop textbox centre (mirrors LineData.getTextBoxLocation).
          final oc = ownerNode.center;
          final angle = line.selfLoopAngle; // default: -π/2 (straight up)
          final outward = Offset(cos(angle), sin(angle));
          final loopCenter = Offset(
            oc.dx + outward.dx * selfLoopCenterDist,
            oc.dy + outward.dy * selfLoopCenterDist,
          );
          const textDistance = kSelfLoopTextDistance;
          final textCenter = Offset(
            loopCenter.dx + outward.dx * (selfLoopRadius + textDistance),
            loopCenter.dy + outward.dy * (selfLoopRadius + textDistance),
          );

          if (line.label.isNotEmpty) {
            final lineCount = '\n'.allMatches(line.label).length + 1;
            final boxHeight = lineHeight * lineCount;
            final tLeft   = textCenter.dx - boxWidth / 2 - textBuffer;
            final tTop    = textCenter.dy - boxHeight / 2 - textBuffer;
            final tRight  = textCenter.dx + boxWidth / 2 + textBuffer;
            final tBottom = textCenter.dy + boxHeight / 2 + textBuffer;

            if (pushNodeFromRect(node, tLeft, tTop, tRight, tBottom)) {
              anyMoved = true;
            }
          }

          // Also keep OTHER nodes away from the loop circle itself.
          final nc = node.center;
          final dxLoop = nc.dx - loopCenter.dx;
          final dyLoop = nc.dy - loopCenter.dy;
          final distLoop = sqrt(dxLoop * dxLoop + dyLoop * dyLoop);
          final minDist = nodeRadius + selfLoopRadius + 10.0;
          if (distLoop < minDist && distLoop > 0.1) {
            final push = minDist - distLoop + 2.0;
            final ux = dxLoop / distLoop;
            final uy = dyLoop / distLoop;
            node.position = Offset(
              node.position.dx + ux * push,
              node.position.dy + uy * push,
            );
            anyMoved = true;
          }
          continue;
        }

        // Non-self-loop: skip if this line directly touches the node.
        if (line.nodeAId == node.id || line.nodeBId == node.id) continue;

        final nodeA = nodes[line.nodeAId];
        final nodeB = nodes[line.nodeBId];
        if (nodeA == null || nodeB == null) continue;

        final cA = nodeA.center;
        final cB = nodeB.center;

        // ── Check B: chord clearance ────────────────────────────────────
        {
          final nc = node.center;
          final abx = cB.dx - cA.dx;
          final aby = cB.dy - cA.dy;
          final abLen = sqrt(abx * abx + aby * aby);

          if (abLen >= 1) {
            final t = ((nc.dx - cA.dx) * abx + (nc.dy - cA.dy) * aby) /
                (abLen * abLen);
            if (t >= -0.05 && t <= 1.05) {
              final closestX = cA.dx + t * abx;
              final closestY = cA.dy + t * aby;
              final dxFromChord = nc.dx - closestX;
              final dyFromChord = nc.dy - closestY;
              final distFromChord =
                  sqrt(dxFromChord * dxFromChord + dyFromChord * dyFromChord);

              if (distFromChord < clearance) {
                final push = clearance - distFromChord + 2.0;
                final Offset perp;
                if (distFromChord < 0.5) {
                  perp = Offset(aby / abLen, -abx / abLen);
                } else {
                  perp = Offset(
                      dxFromChord / distFromChord, dyFromChord / distFromChord);
                }
                node.position = Offset(
                  node.position.dx + perp.dx * push,
                  node.position.dy + perp.dy * push,
                );
                anyMoved = true;
              }
            }
          }
        }

        // ── Check C: non-self-loop textbox clearance ────────────────────
        if (line.label.isNotEmpty) {
// re-read after chord push
          final lineCount = '\n'.allMatches(line.label).length + 1;
          final double boxHeight = lineHeight * lineCount;

          final Offset topLeft = line.getTextBoxLocation(
              cA, cB, boxWidth, boxHeight, line.label);

          final rLeft   = topLeft.dx - textBuffer;
          final rTop    = topLeft.dy - textBuffer;
          final rRight  = topLeft.dx + boxWidth  + textBuffer;
          final rBottom = topLeft.dy + boxHeight + textBuffer;

          if (pushNodeFromRect(node, rLeft, rTop, rRight, rBottom)) {
            anyMoved = true;
          }
        }
      }
    }

    // ── Check E: self-loop textbox spacing between nodes on same node ────────
    // When a node has multiple self-loops (shouldn't happen after merge, but
    // guard anyway) or its own self-loop label would overlap itself, adjust
    // selfLoopAngle to spread them out.
    final selfLoopsByNode = <String, List<LineData>>{};
    for (final line in lines.values) {
      if (line.nodeAId == line.nodeBId) {
        selfLoopsByNode.putIfAbsent(line.nodeAId, () => []).add(line);
      }
    }
    for (final entry in selfLoopsByNode.entries) {
      final loopsOnNode = entry.value;
      if (loopsOnNode.length <= 1) continue;
      // Spread multiple self-loops evenly around the node.
      final angleStep = (2 * pi) / loopsOnNode.length;
      for (int i = 0; i < loopsOnNode.length; i++) {
        loopsOnNode[i].selfLoopAngle = -pi / 2 + angleStep * i;
      }
    }

    if (!anyMoved) break;
  }
}
