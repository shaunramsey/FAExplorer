// ─────────────────────────────────────────────────────────────────────────────
//  Game Mode — Level definitions and registry
//
//  HOW TO ADD LEVELS (backend/designer workflow):
//  ───────────────────────────────────────────────
//  1. Add the SVG asset under  assets/levels/<id>.svg
//     The SVG must contain the embedded  <script id="automata-data">  block
//     that the DslCodec.importFromSvg() parser understands.
//
//  2. Add a GameLevel entry to kAllLevels below.
//     • id          — unique string key, also maps to the SVG filename
//     • title       — shown on the level card
//     • description — task description shown at the top of the puzzle screen
//     • svgAsset    — path under assets/  (e.g. 'assets/levels/level1.svg')
//     • unlockRule  — one of:
//         AlwaysUnlocked()          → starter level, always available
//         RequireLevel('id')        → must beat exactly one level first
//         RequireAll(['a','b'])     → must beat ALL listed levels (AND)
//         RequireAny(['a','b'])     → must beat AT LEAST ONE listed level (OR)
//         RequireExpression(...)    → nested AND/OR tree for complex logic
//
//  3. Wire the node position in the neural-network level-select map by
//     setting  x / y  on the level entry.  The map auto-scales.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

// ─────────────────────────────────────────────────────────────────────────────
//  Unlock rule AST
// ─────────────────────────────────────────────────────────────────────────────

abstract class UnlockRule {
  const UnlockRule();

  /// Returns true if [completedIds] satisfies this rule.
  bool isSatisfied(Set<String> completedIds);

  /// A short human-readable description for the UI.
  String describe();
}

/// Always unlocked — entry-point levels.
class AlwaysUnlocked extends UnlockRule {
  const AlwaysUnlocked();

  @override
  bool isSatisfied(Set<String> completedIds) => true;

  @override
  String describe() => 'Available from the start';
}

/// Requires a single level to be completed.
class RequireLevel extends UnlockRule {
  final String levelId;
  const RequireLevel(this.levelId);

  @override
  bool isSatisfied(Set<String> completedIds) => completedIds.contains(levelId);

  @override
  String describe() {
    final title = kLevelById[levelId]?.title ?? levelId;
    return 'Complete "$title" first';
  }
}

/// Requires ALL listed levels to be completed (AND gate).
class RequireAll extends UnlockRule {
  final List<String> levelIds;
  const RequireAll(this.levelIds);

  @override
  bool isSatisfied(Set<String> completedIds) =>
      levelIds.every(completedIds.contains);

  @override
  String describe() {
    final titles = levelIds.map((id) => kLevelById[id]?.title ?? id).join(', ');
    return 'Complete all of: $titles';
  }
}

/// Requires AT LEAST ONE listed level to be completed (OR gate).
class RequireAny extends UnlockRule {
  final List<String> levelIds;
  const RequireAny(this.levelIds);

  @override
  bool isSatisfied(Set<String> completedIds) =>
      levelIds.any(completedIds.contains);

  @override
  String describe() {
    final titles = levelIds.map((id) => kLevelById[id]?.title ?? id).join(', ');
    return 'Complete any of: $titles';
  }
}

/// Arbitrary nested AND/OR expression.
class RequireExpression extends UnlockRule {
  final bool isAnd; // true = AND, false = OR
  final List<UnlockRule> children;

  const RequireExpression({required this.isAnd, required this.children});

  @override
  bool isSatisfied(Set<String> completedIds) {
    if (isAnd) return children.every((r) => r.isSatisfied(completedIds));
    return children.any((r) => r.isSatisfied(completedIds));
  }

  @override
  String describe() {
    final op = isAnd ? ' AND ' : ' OR ';
    return children.map((c) => '(${c.describe()})').join(op);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GameLevel
// ─────────────────────────────────────────────────────────────────────────────

class GameLevel {
  final String id;
  final String title;
  final String description;

  /// Flutter asset path for the target SVG, e.g. 'assets/levels/level1.svg'
  final String svgAsset;

  /// Embedded DSL form of the target level. If present, it is used instead of
  /// loading an SVG asset, which keeps the target machine hidden from the user.
  final String dsl;

  /// Which automata mode the hidden target should use for equivalence checking.
  final AutomataMode automataMode;

  final UnlockRule unlockRule;

  /// Position on the neural-network level-select canvas (normalised 0–1).
  final double x;
  final double y;

  /// Optional tag for grouping / visual theming of the node.
  final String? tag;

  const GameLevel({
    required this.id,
    required this.title,
    required this.description,
    required this.svgAsset,
    this.dsl = '',
    this.automataMode = AutomataMode.ndfa,
    this.unlockRule = const AlwaysUnlocked(),
    this.x = 0.5,
    this.y = 0.5,
    this.tag,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  LEVEL REGISTRY
//  ──────────────────────────────────────────────────────────────────────────
//  Add your levels here.  The SVG files live in  assets/levels/<id>.svg
//  (make sure each is listed in pubspec.yaml under flutter > assets).
//
//  The x/y coordinates place the node on the neural-network map.
//  Use values in [0, 1] — the map renderer scales them to the screen.
// ─────────────────────────────────────────────────────────────────────────────

const List<GameLevel> kAllLevels = [
  // ── Layer 0 — Introduction ──────────────────────────────────────────────
  GameLevel(
    id: 'level_1',
    title: 'Level 1',
    description:
        'Build a DFA that accepts exactly those strings over {0,1} with an even number of 0s.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (556.7, 321.3)
      n1 = (1062.0, 328.7)
      n0 is accepted
      n0 to n1 = 0
      n1 to n0 = 0
      n0 to n0 = 1
      n1 to n1 = 1
      l0(0) curve = -159.5
      l1(0) curve = -83.0
      l2(1) loop angle = -1.5708
      l3(1) loop angle = -0.3442
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: AlwaysUnlocked(),
    x: 0.18,
    y: 0.72,
    tag: 'custom',
  ),
  GameLevel(
    id: 'level_2',
    title: 'Level 2',
    description:
        'Build a PDA that matches the hidden stack-based target machine.',
    svgAsset: '',
    dsl: '''
      pda mode
      n0 = A
      n1 = B
      n2 = C
      n3 = <<ha>>
      n4 = E
      n5 = F
      n0 = (723.3, 204.7)
      n1 = (1139.3, 259.3)
      n2 = (1196.0, 527.3)
      n3 = (739.3, 705.3)
      n4 = (345.3, 504.7)
      n5 = (345.3, 277.3)
      n0 to n5 = 0,~|X
      n0 to n1 = 1,~|Y
      n1 to n1 = 1,~|Y
      n1 to n2 = 0,Y|~
      n2 to n1 = 1,∅|Y
      n2 to n5 = 0,∅|X
      n4 to n1 = 1,∅|Y
      n4 to n5 = 0,∅|X
      n5 to n4 = 1,X|~
      n5 to n5 = 0,~|X
      n4 to n4 = 1,X|~
      n4 to n3 = ∅,∅|~
      n2 to n3 = ∅,∅|~
      n2 to n2 = 0,Y|~
      l0(0,~|X) curve = -2.9
      l3(0,Y|~) curve = 62.2
      l4(1,∅|Y) curve = 55.1
      l5(0,∅|X) curve = 39.9
      l6(1,∅|Y) curve = 16.9
      l7(0,∅|X) curve = -8.2
      l8(1,X|~) curve = -105.4
      l2(1,~|Y) loop angle = -0.7988
      l9(0,~|X) loop angle = -1.5708
      l10(1,X|~) loop angle = 1.7686
      l13(0,Y|~) loop angle = -0.0754
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: AlwaysUnlocked(),
    x: 0.18,
    y: 0.83,
    tag: 'custom',
  ),
  GameLevel(
    id: 'level_3',
    title: 'Level 3',
    description:
        'Build a Turing machine that matches the hidden target tape behaviour.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = E
      n5 = F
      A = (260.1, 194.6)
      B = (1233.4, 154.6)
      C = (772.1, 630.0)
      D = (460.1, 504.0)
      E = (765.4, 454.0)
      F = (758.1, 255.9)
      B is accepted
      F is accepted
      E to F = ∅∅S
      A to F = ∅∅S
      C to E = \0\0R
      C to C = XXL
      D to D = aaL
      B to B = aaR
      B to B = XXR
      B to C = bXL
      C to D = aaL
      D to A = XXR
      A to B = aXR
      E to E = XXR
      l0(∅∅S) curve = 4.2
      l1(∅∅S) curve = -75.2
      bXL curve = 103.8
      l7(aaL) curve = 40.7
      l8(XXR) curve = 53.9
      aXR curve = 61.8
      XXL loop angle = 1.5107
      l4(aaL) loop angle = 2.2185
      aaR loop angle = -1.5708
      l10(XXR) loop angle = 3.3847
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: AlwaysUnlocked(),
    x: 0.18,
    y: 0.93,
    tag: 'custom',
  ),

  GameLevel(
    id: 'intro_accept_a',
    title: 'Accept "a"',
    description:
        'Build an automaton that accepts exactly the string "a" and rejects everything else.',
    svgAsset: 'assets/levels/intro_accept_a.svg',
    unlockRule: AlwaysUnlocked(),
    x: 0.05,
    y: 0.15,
    tag: 'intro',
  ),

  // ── Layer 1 — Basic DFA ─────────────────────────────────────────────────
  GameLevel(
    id: 'dfa_ab',
    title: 'Ends with "ab"',
    description:
        'Build an automaton over {a, b} that accepts all strings ending in "ab".',
    svgAsset: 'assets/levels/dfa_ab.svg',
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.18,
    y: 0.10,
    tag: 'dfa',
  ),
  GameLevel(
    id: 'dfa_even_a',
    title: 'Even number of a\'s',
    description:
        'Build an automaton that accepts strings over {a, b} with an even number of a\'s (zero counts as even).',
    svgAsset: 'assets/levels/dfa_even_a.svg',
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.18,
    y: 0.25,
    tag: 'dfa',
  ),

  // ── Layer 2 — NFA ───────────────────────────────────────────────────────
  GameLevel(
    id: 'nfa_ends_b',
    title: 'Ends with "b"',
    description:
        'Build an NFA that accepts all strings over {a, b} that end with "b".',
    svgAsset: 'assets/levels/nfa_ends_b.svg',
    unlockRule: RequireAny(['dfa_ab', 'dfa_even_a']),
    x: 0.31,
    y: 0.15,
    tag: 'nfa',
  ),

  // ── Layer 3 — Mixed requirement ─────────────────────────────────────────
  GameLevel(
    id: 'nfa_complex',
    title: 'Contains "aba"',
    description:
        'Build an NFA that accepts exactly those strings over {a, b} that contain "aba" as a substring.',
    svgAsset: 'assets/levels/nfa_complex.svg',
    unlockRule: RequireAll(['dfa_ab', 'dfa_even_a']),
    x: 0.44,
    y: 0.10,
    tag: 'nfa',
  ),
  GameLevel(
    id: 'epsilon_closure',
    title: '∅-Closures',
    description:
        'Use ∅-transitions to build a compact NFA that accepts strings matching a* | b*.',
    svgAsset: 'assets/levels/epsilon_closure.svg',
    unlockRule: RequireAll(['nfa_ends_b', 'dfa_ab']),
    x: 0.44,
    y: 0.28,
    tag: 'nfa',
  ),
  GameLevel(
    id: 'dfa_complement',
    title: 'Complement',
    description:
        'Build the complement of the "even a\'s" language — accept all strings with an ODD number of a\'s.',
    svgAsset: 'assets/levels/dfa_complement.svg',
    unlockRule: RequireExpression(
      isAnd: false, // OR
      children: [
        RequireLevel('dfa_even_a'),
        RequireLevel('nfa_ends_b'),
      ],
    ),
    x: 0.44,
    y: 0.46,
    tag: 'dfa',
  ),

  // ── Layer 4 — Boss levels ───────────────────────────────────────────────
  GameLevel(
    id: 'boss_three_states',
    title: 'Three-state Challenge',
    description:
        'Build a 3-state DFA over {0, 1} that accepts all strings whose binary value is divisible by 3.',
    svgAsset: 'assets/levels/boss_three_states.svg',
    unlockRule: RequireAll(['nfa_complex', 'epsilon_closure', 'dfa_complement']),
    x: 0.80,
    y: 0.20,
    tag: 'boss',
  ),
  GameLevel(
    id: 'boss_palindrome',
    title: 'Palindrome Detector',
    description:
        'Build an automaton (any type) that accepts strings over {a, b} that are palindromes of length ≤ 5.',
    svgAsset: 'assets/levels/boss_palindrome.svg',
    unlockRule: RequireExpression(
      isAnd: true,
      children: [
        RequireLevel('boss_three_states'),
        RequireAny(['nfa_complex', 'epsilon_closure']),
      ],
    ),
    x: 0.90,
    y: 0.30,
    tag: 'boss',
  ),

  // ── DSL Levels — from designer chat ────────────────────────────────────

  // ── Beginner: Simple string/parity puzzles ──────────────────────────────
  GameLevel(
    id: 'dsl_even_0s',
    title: 'Even 0s',
    description:
        'Build a DFA over {0,1} that accepts strings with an even number of 0s. '
        '(Equivalently, binary mod 2 = 0.)',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (504.7, 310.0)
      n1 = (1030.0, 314.0)
      n0 is accepted
      n0 to n1 = 0
      n1 to n0 = 0
      n0 to n0 = 1
      n1 to n1 = 1
      l0(0) curve = -74.1
      l1(0) curve = -72.7
      l2(1) loop angle = -1.5708
      l3(1) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: AlwaysUnlocked(),
    x: 0.05,
    y: 0.35,
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_only_empty_nfa',
    title: 'Only ∅ (NFA)',
    description:
        'Build an NFA that accepts only the empty string ∅ and rejects every non-empty input.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n0 = (607.3, 408.0)
      n0 is accepted
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: AlwaysUnlocked(),
    x: 0.05,
    y: 0.55,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_only_empty_dfa',
    title: 'Only ∅ (DFA)',
    description:
        'Build a DFA that accepts only the empty string ∅. '
        'Hint: use "." (dot) to mean "every symbol in the alphabet".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (765.3, 365.3)
      n1 = (1080.7, 360.7)
      n0 is accepted
      n0 to n1 = .
      n1 to n1 = .
      l1(.) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_only_empty_nfa'),
    x: 0.18,
    y: 0.42,
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_accepts_everything',
    title: 'Accept Everything',
    description:
        'Build a DFA that accepts every string (including ∅). '
        'Use "." to represent the entire alphabet.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n0 = (734.0, 447.3)
      n0 is accepted
      n0 to n0 = .
      . loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: AlwaysUnlocked(),
    x: 0.05,
    y: 0.75,
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_accepts_everything_nfa',
    title: 'Accept Everything (NFA + ~-jump)',
    description:
        'Build a two-state NFA that uses a free ~-jump to accept every string. '
        'Hint: an ~-transition (no label) is a "free jump" to another state.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (734.0, 447.3)
      n1 = (1022.0, 468.7)
      n1 is accepted
      n0 to n1
      n1 to n1 = .
      . loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_accepts_everything'),
    x: 0.18,
    y: 0.58,
    tag: 'nfa',
  ),

  // ── Intermediate: single-zero / ends-with puzzles ───────────────────────
  GameLevel(
    id: 'dsl_exactly_one_0_dfa',
    title: 'Exactly One 0 (DFA)',
    description:
        'Build a DFA over {0,1} that accepts strings containing exactly one 0.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n0 = (566.7, 381.3)
      n1 = (866.0, 386.0)
      n2 = (1175.3, 390.0)
      n1 is accepted
      n0 to n1 = 0
      n1 to n2 = 0
      n2 to n2 = 1,0
      n1 to n1 = 1
      n0 to n0 = 1
      1,0 loop angle = -1.5708
      l3(1) loop angle = -1.5708
      l4(1) loop angle = -1.5708
      to n0
      to n0 length = 186.9
      to n0 angle = -0.8246, -0.5657
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_even_0s'),
    x: 0.31,
    y: 0.42,
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_exactly_one_0_nfa',
    title: 'Exactly One 0 (NFA)',
    description:
        'Build a compact NFA over {0,1} that accepts strings containing exactly one 0. '
        'Can you do it in just two states?',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (667.3, 421.3)
      n1 = (907.3, 421.3)
      n1 is accepted
      n0 to n1 = 1
      n1 to n1 = 0
      n0 to n0 = 0
      l1(0) loop angle = -1.5708
      l2(0) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_exactly_one_0_dfa'),
    x: 0.44,
    y: 0.63,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_ends_b_nfa',
    title: 'Ends with b (NFA)',
    description:
        'Build an NFA over {a, b} that accepts all strings ending in "b".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (432.7, 324.7)
      n1 = (759.3, 327.3)
      n1 is accepted
      n0 to n0 = a,b
      n0 to n1 = b
      a,b loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: AlwaysUnlocked(),
    x: 0.31,
    y: 0.62,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_ends_b_dfa',
    title: 'Ends with b (DFA)',
    description:
        'Build a DFA over {a, b} that accepts all strings ending in "b". '
        'This is the deterministic version — every state needs transitions for both a and b.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n0 = (513.3, 335.3)
      n1 = (862.7, 218.7)
      n2 = (845.3, 522.0)
      n2 is accepted
      n0 to n2 = b
      n0 to n1 = a
      n1 to n1 = a
      n2 to n2 = b
      n2 to n1 = a
      n1 to n2 = b
      l0(b) curve = -22.0
      l1(a) curve = 24.4
      l4(a) curve = -38.6
      l5(b) curve = -72.2
      l2(a) loop angle = -0.5312
      l3(b) loop angle = -0.3351
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_b_nfa'),
    x: 0.44,
    y: 0.80,
    tag: 'dfa',
  ),

  // ── Intermediate: substring / suffix patterns ───────────────────────────
  GameLevel(
    id: 'dsl_ends_abc_nfa',
    title: 'Ends with abc (NFA)',
    description:
        'Build an NFA over {a, b, c} that accepts all strings ending in "abc".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n0 = (497.3, 348.7)
      n1 = (818.0, 358.7)
      n2 = (1138.7, 361.3)
      n3 = (1412.0, 370.7)
      n3 is accepted
      n0 to n1 = a
      n1 to n2 = b
      n0 to n0 = a,b,c
      n2 to n3 = c
      a,b,c loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_b_nfa'),
    x: 0.57,
    y: 0.22,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_ends_abc_dfa',
    title: 'Ends with abc (DFA)',
    description:
        'Build a DFA over {a, b, c} that accepts all strings ending in "abc". '
        'Every state must handle all three symbols.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n0 = (447.3, 392.0)
      n1 = (694.0, 400.0)
      n2 = (951.3, 404.7)
      n3 = (1161.3, 406.7)
      n3 is accepted
      n0 to n0 = b,c
      n0 to n1 = a
      n1 to n2 = b
      n2 to n3 = c
      n3 to n1 = a
      n2 to n1 = a
      n3 to n0 = b,c
      n2 to n0 = b,c
      b curve = 1.7
      l4(a) curve = 359.1
      l5(a) curve = 130.8
      l6(b,c) curve = -344.8
      l7(b,c) curve = -236.0
      l0(b,c) loop angle = 1.7357
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_abc_nfa'),
    x: 0.70,
    y: 0.35,
    tag: 'dfa',
  ),

  // ── Intermediate: ends in double / two-symbol suffix ───────────────────
  GameLevel(
    id: 'dsl_ends_two_same_nfa',
    title: 'Ends in 00 or 11 (NFA)',
    description:
        'Build an NFA over {0,1} that accepts strings ending in "00" or "11".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = E
      n0 = (604.7, 275.3)
      n1 = (934.7, 190.0)
      n2 = (1212.0, 198.7)
      n3 = (910.0, 474.7)
      n4 = (1160.7, 511.3)
      n2 is accepted
      n4 is accepted
      n0 to n3 = 0
      n3 to n4 = 0
      n0 to n1 = 1
      n1 to n2 = 1
      n2 to n2 = 1
      n4 to n4 = 0
      n0 to n0 = 1,0
      l4(1) loop angle = -1.5708
      l5(0) loop angle = -1.5708
      1,0 loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_b_nfa'),
    x: 0.57,
    y: 0.65,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_ends_two_same_dfa',
    title: 'Ends in 00 or 11 (DFA)',
    description:
        'Build a DFA over {0,1} that accepts strings ending in "00" or "11".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = E
      n0 = (403.3, 416.7)
      n1 = (738.7, 293.3)
      n2 = (743.3, 592.7)
      n3 = (1046.7, 426.7)
      n4 = (1169.3, 650.7)
      n3 is accepted
      n4 is accepted
      n4 to n4 = 1
      n4 to n1 = 1
      n2 to n4 = 1
      n0 to n2 = 1
      n0 to n1 = 0
      n1 to n2 = 1
      n2 to n1 = 0
      n1 to n3 = 0
      n3 to n3 = 0
      n3 to n2 = 1
      l1(1) curve = -326.2
      l2(1) curve = -71.8
      l3(1) curve = -86.5
      l4(0) curve = 40.9
      l5(1) curve = 57.3
      l6(0) curve = 53.5
      l0(1) loop angle = 0.4065
      l8(0) loop angle = 0.0537
      to n0
      to n0 length = 184.8
      to n0 angle = -0.9911, -0.1335
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_two_same_nfa'),
    x: 0.70,
    y: 0.55,
    tag: 'dfa',
  ),

  // ── Advanced: word-level / natural-language patterns ────────────────────
  GameLevel(
    id: 'dsl_caterpillar_nfa',
    title: 'Hungry Caterpillar (NFA)',
    description:
        'The Very Hungry Caterpillar ends by eating EXACTLY one "Green Leaf".\n'
        'Build an NFA over story words where .-"Green Leaf" means '
        '"every word except Green Leaf". Accept strings whose last food item is exactly one Green Leaf.',
    svgAsset: '',
    dsl: r'''
      n0 = A
      n1 = B
      n0 = (689.3, 458.7)
      n1 = (1080.7, 454.7)
      n1 is accepted
      n0 to n1 = "Green Leaf"
      n0 to n0 = .-"Green Leaf"
      .-"Green Leaf" loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_abc_nfa'),
    x: 0.70,
    y: 0.15,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_caterpillar_dfa',
    title: 'Hungry Caterpillar (DFA)',
    description:
        'The Very Hungry Caterpillar ends by eating EXACTLY one "Green Leaf".\n'
        'Build the deterministic version. Use "." for "all words" and '
        '.-"Green Leaf" for "all words except Green Leaf". '
        'After seeing a Green Leaf, any further input must go to a dead state.',
    svgAsset: '',
    dsl: r'''
      n0 = A
      n1 = B
      n2 = C
      n0 = (484.0, 492.0)
      n1 = (834.0, 492.0)
      n2 = (1120.0, 486.7)
      n1 is accepted
      n2 to n2 = .
      n1 to n2 = .
      n0 to n1 = "Green Leaf"
      n0 to n0 = .-"Green Leaf"
      l0(.) loop angle = -1.5708
      .-"Green Leaf" loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_caterpillar_nfa'),
    x: 0.80,
    y: 0.45,
    tag: 'dfa',
  ),

  // ── Advanced: halt-and-accept ───────────────────────────────────────────
  GameLevel(
    id: 'dsl_halt_accept_y',
    title: 'Halt on y',
    description:
        'Build an FA over the lowercase English alphabet that stops computing '
        'and accepts the moment it sees the letter "y".\n'
        'Use <<Ha>> to mark a halt-and-accept state, and .-y to mean '
        '"every letter except y".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = <<Ha>>
      n0 = (484.0, 492.0)
      Ha = (834.0, 492.0)
      n0 to Ha = y
      n0 to n0 = a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,z
      a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,z loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_accepts_everything_nfa'),
    x: 0.70,
    y: 0.75,
    tag: 'nfa',
  ),

  // ── Advanced: binary modular arithmetic ────────────────────────────────
  GameLevel(
    id: 'dsl_binary_mod3',
    title: 'Binary Mod 3',
    description:
        'Build a DFA over {0,1} that accepts binary strings whose value is '
        'divisible by 3 (i.e. binary mod 3 = 0). '
        'Reading a 0 doubles the current remainder; reading a 1 doubles it and adds 1.',
    svgAsset: '',
    dsl: '''
      n0 = 0
      n1 = 1
      n2 = 2
      n0 = (538.7, 187.3)
      n1 = (1036.7, 342.0)
      n2 = (670.0, 578.7)
      n0 is accepted
      n0 to n1 = 1
      n1 to n0 = 1
      n0 to n0 = 0
      n1 to n2 = 0
      n2 to n1 = 0
      n2 to n2 = 1
      l0(1) curve = 75.9
      l1(1) curve = 79.5
      l3(0) curve = 91.1
      l4(0) curve = 25.3
      l2(0) loop angle = -1.5708
      l5(1) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_even_0s'),
    x: 0.80,
    y: 0.68,
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_binary_mod7',
    title: 'Binary Mod 7',
    description:
        'Build a DFA over {0,1} that accepts binary strings whose value is '
        'divisible by 7 (binary mod 7 = 0). '
        'States 0–6 represent the current remainder.',
    svgAsset: '',
    dsl: '''
      n0 = 0
      n1 = 1
      n2 = 2
      n3 = 3
      n4 = 4
      n5 = 5
      n6 = 6
      n0 = (640.0, 92.6)
      n1 = (1112.0, 196.0)
      n2 = (1560.0, 282.7)
      n3 = (250.0, 223.3)
      n4 = (929.3, 422.7)
      n5 = (645.3, 592.7)
      n6 = (303.3, 518.7)
      n0 is accepted
      n0 to n1 = 1
      n0 to n0 = 0
      n1 to n2 = 0
      n1 to n3 = 1
      n3 to n6 = 0
      n3 to n0 = 1
      n2 to n5 = 1
      n2 to n4 = 0
      n4 to n1 = 0
      n4 to n2 = 1
      n5 to n3 = 1
      n5 to n4 = 1
      n6 to n5 = 0
      n6 to n6 = 1
      l3(1) curve = 21.0
      l4(0) curve = -194.4
      l5(1) curve = 34.0
      l6(1) curve = 316.5
      l7(0) curve = 152.5
      l8(0) curve = 17.9
      l9(1) curve = -15.5
      l10(1) curve = 15.0
      l11(1) curve = -59.2
      l1(0) loop angle = -1.5708
      l13(1) loop angle = -1.5708
      to n0
      to n0 length = 150.3
      to n0 angle = -0.8423, -0.5390
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_binary_mod3'),
    x: 0.90,
    y: 0.62,
    tag: 'boss',
  ),

  GameLevel(
    id: 'dsl_binary_mod8',
    title: 'Binary Mod 8',
    description:
        'Build a DFA over {0,1} that accepts binary strings whose value is '
        'divisible by 8 (binary mod 8 = 0). '
        'States 0–7 represent the current remainder.',
    svgAsset: '',
    dsl: '''
      n0 = 0
      n1 = 1
      n2 = 2
      n3 = 3
      n4 = 4
      n5 = 5
      n6 = 6
      n7 = 7
      n0 = (338.0, 209.3)
      n1 = (715.3, 212.0)
      n2 = (432.0, 446.7)
      n3 = (1418.7, 219.3)
      n4 = (167.3, 640.7)
      n5 = (585.3, 610.0)
      n6 = (870.0, 627.3)
      n7 = (1173.3, 622.0)
      n0 is accepted
      n0 to n0 = 0
      n0 to n1 = 1
      n1 to n3 = 1
      n1 to n2 = 0
      n2 to n4 = 0
      n4 to n0 = 0
      n4 to n1 = 1
      n2 to n5 = 1
      n5 to n2 = 0
      n5 to n3 = 1
      n3 to n6 = 0
      n3 to n7 = 1
      n7 to n6 = 0
      n7 to n7 = 1
      n6 to n4 = 0
      n6 to n5 = 1
      l6(1) curve = 439.5
      l7(1) curve = 30.8
      l8(0) curve = 16.7
      l14(0) curve = 126.4
      l0(0) loop angle = -1.5708
      l13(1) loop angle = 0.4628
      to n0
      to n0 length = 114.5
      to n0 angle = -0.9767, -0.2148
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_binary_mod7'),
    x: 0.97,
    y: 0.46,
    tag: 'boss',
  ),
];

/// Convenience map for O(1) lookup by id.
final Map<String, GameLevel> kLevelById = {
  for (final l in kAllLevels) l.id: l,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Tag colour palette used by the neural-network level map
// ─────────────────────────────────────────────────────────────────────────────

Color levelTagColor(String? tag) {
  switch (tag) {
    case 'intro':
      return const Color(0xFF00E5FF); // cyan
    case 'dfa':
      return const Color(0xFF69FF47); // green
    case 'nfa':
      return const Color(0xFFFFD740); // amber
    case 'boss':
      return const Color(0xFFFF1744); // red
    case 'custom':
      return const Color(0xFF7C4DFF); // purple
    default:
      return const Color(0xFF9E9E9E); // grey
  }
}