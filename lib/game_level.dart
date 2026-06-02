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
  String describe() => 'Complete "$levelId" first';
}

/// Requires ALL listed levels to be completed (AND gate).
class RequireAll extends UnlockRule {
  final List<String> levelIds;
  const RequireAll(this.levelIds);

  @override
  bool isSatisfied(Set<String> completedIds) =>
      levelIds.every(completedIds.contains);

  @override
  String describe() => 'Complete all of: ${levelIds.join(", ")}';
}

/// Requires AT LEAST ONE listed level to be completed (OR gate).
class RequireAny extends UnlockRule {
  final List<String> levelIds;
  const RequireAny(this.levelIds);

  @override
  bool isSatisfied(Set<String> completedIds) =>
      levelIds.any(completedIds.contains);

  @override
  String describe() => 'Complete any of: ${levelIds.join(", ")}';
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
    y: 0.15,
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
    x: 0.5,
    y: 0.15,
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
    x: 0.82,
    y: 0.15,
    tag: 'custom',
  ),

  GameLevel(
    id: 'intro_accept_a',
    title: 'Accept "a"',
    description:
        'Build an automaton that accepts exactly the string "a" and rejects everything else.',
    svgAsset: 'assets/levels/intro_accept_a.svg',
    unlockRule: AlwaysUnlocked(),
    x: 0.5,
    y: 0.05,
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
    x: 0.25,
    y: 0.22,
    tag: 'dfa',
  ),
  GameLevel(
    id: 'dfa_even_a',
    title: 'Even number of a\'s',
    description:
        'Build an automaton that accepts strings over {a, b} with an even number of a\'s (zero counts as even).',
    svgAsset: 'assets/levels/dfa_even_a.svg',
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.75,
    y: 0.22,
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
    x: 0.5,
    y: 0.4,
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
    x: 0.15,
    y: 0.57,
    tag: 'nfa',
  ),
  GameLevel(
    id: 'epsilon_closure',
    title: 'ε-Closures',
    description:
        'Use ε-transitions to build a compact NFA that accepts strings matching a* | b*.',
    svgAsset: 'assets/levels/epsilon_closure.svg',
    unlockRule: RequireAll(['nfa_ends_b', 'dfa_ab']),
    x: 0.5,
    y: 0.57,
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
    x: 0.85,
    y: 0.57,
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
    x: 0.5,
    y: 0.78,
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
    x: 0.5,
    y: 0.93,
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
