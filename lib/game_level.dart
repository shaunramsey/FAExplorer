import 'widgets/app_theme.dart';
import 'automaton_type_checker.dart' show RequiredAutomatonType;
import 'tutorial_screen.dart' show TutorialSlide, TutorialIllustration;

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
//
//  LAYOUT BANDS (x value → column section):
//    0.00–0.55  FA   (Finite Automata)  — columns 0–7
//    0.58–0.76  PDA  (Pushdown Automata) — columns 8–11
//    0.80–0.97  TM   (Turing Machines)  — columns 12–15
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

  /// If set, the player's submission is checked to be this automaton type
  /// BEFORE the equivalence check runs.  Null means "any type accepted".
  ///
  /// Examples:
  ///   requiredAutomatonType: RequiredAutomatonType.dfa   → player must submit a DFA
  ///   requiredAutomatonType: RequiredAutomatonType.nfa   → player must use ≥1 NFA feature
  ///   requiredAutomatonType: null                        → no type restriction
  final RequiredAutomatonType? requiredAutomatonType;

  /// Alphabet used for DFA completeness checking (missing-transition warnings).
  /// Only relevant when [requiredAutomatonType] == RequiredAutomatonType.dfa.
  /// Pass an empty set to skip the completeness check.
  final Set<String> alphabet;

  final UnlockRule unlockRule;

  /// Position on the neural-network level-select canvas (normalised 0–1).
  final double x;
  final double y;

  /// Optional tag for grouping / visual theming of the node.
  final String? tag;

  /// Whether this is a tutorial (slideshow) level rather than a puzzle.
  /// Tutorial levels show [tutorialSlides] instead of the puzzle canvas.
  final bool isTutorial;

  /// Slides shown when [isTutorial] is true.  Ignored for normal puzzle levels.
  final List<TutorialSlide> tutorialSlides;

  const GameLevel({
    required this.id,
    required this.title,
    required this.description,
    required this.svgAsset,
    this.dsl = '',
    this.automataMode = AutomataMode.ndfa,
    this.requiredAutomatonType,
    this.alphabet = const {},
    this.unlockRule = const AlwaysUnlocked(),
    this.x = 0.5,
    this.y = 0.5,
    this.tag,
    this.isTutorial = false,
    this.tutorialSlides = const [],
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  LEVEL REGISTRY
//
//  LAYOUT STRUCTURE:
//    ═══ FA SECTION (x: 0.00–0.55) ═══════════════════════════════════════════
//    Col 0  x≈0.04   FA INTRO      — single start node (AlwaysUnlocked)
//    Col 1  x≈0.12   FA BASICS     — simple DFA/NFA patterns
//    Col 2  x≈0.20   FA STRINGS    — string matching
//    Col 3  x≈0.28   FA PATTERNS   — epsilon closures & complements
//    Col 4  x≈0.36   FA ADVANCED   — boss + harder patterns
//    Col 5  x≈0.42   FA SUFFIX     — suffix/DFA conversions
//    Col 6  x≈0.49   FA LANGUAGE   — mod arithmetic, closure properties
//    Col 7  x≈0.55   FA CHALLENGE  — final FA boss levels
//
//    ═══ PDA SECTION (x: 0.60–0.76) ══════════════════════════════════════════
//    Col 8  x≈0.61   PDA INTRO     — first PDA levels
//    Col 9  x≈0.67   PDA BASICS    — stack matching
//    Col 10 x≈0.73   PDA ADVANCED  — hard stack languages + boss
//
//    ═══ TM SECTION (x: 0.79–0.97) ═══════════════════════════════════════════
//    Col 11 x≈0.80   TM INTRO      — trivial TMs
//    Col 12 x≈0.86   TM BASICS     — aⁿbⁿ, binary scan
//    Col 13 x≈0.91   TM ADVANCED   — ww, aⁿbⁿcⁿ, binary ops
//    Col 14 x≈0.96   TM BOSS       — final TM challenges
// ─────────────────────────────────────────────────────────────────────────────

const List<GameLevel> kAllLevels = [

  // ═══════════════════════════════════════════════════════════════════════════
  //  TUTORIAL 0 — WELCOME  (x ≈ 0.00)
  //  Canvas basics: add/move/delete nodes, transitions, start arrow, accept state
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_welcome',
    title: 'How to Play',
    description: 'Learn the basics of the automata canvas.',
    svgAsset: '',
    unlockRule: AlwaysUnlocked(),
    x: 0.00,
    y: 0.50,
    tag: 'tutorial',
    isTutorial: true,
    tutorialSlides: [
      TutorialSlide(
        headline: 'Welcome!',
        body: 'This app teaches you how to build **finite automata**, '
            '**pushdown automata**, and **Turing machines** — '
            'the fundamental models of computation.\n\n'
            'Each level asks you to build an automaton that matches a target language. '
            'Follow these tutorials first to learn the tools, then dive in!',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Adding States',
        body: '**Double-tap** on any empty area of the canvas to create a new state (circle).\n\n'
            'States represent positions your machine can be in while reading input. '
            'You can drag states around to arrange your diagram.',
        illustrationType: TutorialIllustration.addNode,
      ),
      TutorialSlide(
        headline: 'Drawing Transitions',
        body: 'Hold **Shift** and drag from one state to another to draw a transition arrow.\n\n'
            'After drawing, **tap the label** on the arrow to set which input symbol it reads '
            '(e.g. "a", "b", "0", "1"). '
            'A single arrow can carry multiple symbols — separate them with commas.',
        illustrationType: TutorialIllustration.addTransition,
      ),
      TutorialSlide(
        headline: 'Accept States',
        body: 'A state shown with a **double ring** is an accepting state — '
            'the machine accepts the input if it finishes in one of these.\n\n'
            'To make a state accepting: **tap it** to open its menu, then toggle **"Accept"**.',
        illustrationType: TutorialIllustration.setAccepting,
      ),
      TutorialSlide(
        headline: 'The Start Arrow',
        body: 'Every automaton needs exactly **one start state** — the state it begins in.\n\n'
            'Drag the floating start arrow onto a state to set it as the start. '
            'If no start arrow is visible, use the **toolbar** to place one.',
        illustrationType: TutorialIllustration.setStartArrow,
      ),
      TutorialSlide(
        headline: 'Deleting Things',
        body: 'Made a mistake? Use the **trash-can** button in the toolbar to enter delete mode.\n\n'
            'In delete mode, **tap** any state or transition arrow to remove it. '
            'Tap the trash-can again to exit delete mode.',
        illustrationType: TutorialIllustration.deleteMode,
      ),
      TutorialSlide(
        headline: 'Checking Your Answer',
        body: 'When you think your automaton is correct, tap **"Check"** in the top-right corner.\n\n'
            'The app will test your machine against the target language. '
            'If they match, the level is complete! If not, you\'ll see a **counterexample** — '
            'a string your machine handles differently from the target.',
        illustrationType: TutorialIllustration.checkAnswer,
      ),
    ],
  ),


  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 0 — INTRO  (x ≈ 0.04)
  //  ONE start node. Everything else chains from here.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'intro_accept_a',
    title: 'Accept "a"',
    description:
        'Build an automaton that accepts exactly the string "a" and rejects everything else.\n'
        'This is your starting point — all other levels unlock from here.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (484.0, 380.0)
      n1 = (784.0, 380.0)
      n1 is accepted
      n0 to n1 = a
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: AlwaysUnlocked(),
    x: 0.04,
    y: 0.50,
    tag: 'intro',
  ),


  // ═══════════════════════════════════════════════════════════════════════════
  //  TUTORIAL 1 — DFA vs NFA  (x ≈ 0.08)
  //  Explains determinism, nondeterminism, and when each is required
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_dfa_vs_nfa',
    title: 'DFA vs NFA',
    description: 'Understand the difference between deterministic and nondeterministic automata.',
    svgAsset: '',
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.08,
    y: 0.50,
    tag: 'tutorial',
    isTutorial: true,
    tutorialSlides: [
      TutorialSlide(
        headline: 'Two Kinds of Automaton',
        body: 'Levels in this game are tagged **DFA** or **NFA** (or neither, for bosses).\n\n'
            '• A **DFA** (Deterministic Finite Automaton) must have exactly one transition per symbol per state.\n'
            '• An **NFA** (Nondeterministic Finite Automaton) can have zero, one, or many transitions for the same symbol.',
        illustrationType: TutorialIllustration.dfaVsNfa,
      ),
      TutorialSlide(
        headline: 'DFA Rules',
        body: 'For a valid DFA over alphabet {a, b}:\n\n'
            '1. Every state must have **exactly one** outgoing transition for each symbol.\n'
            '2. No ε (epsilon / free-jump) transitions are allowed.\n'
            '3. There must be exactly **one start state**.\n\n'
            'If your submission violates any of these, the checker will tell you exactly which states are the problem.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'NFA Rules',
        body: 'An NFA is more flexible — it **may** have:\n\n'
            '• Multiple outgoing arrows for the **same** symbol from one state\n'
            '• **ε-transitions** (free jumps, drawn as arrows with no label)\n'
            '• States with **no** outgoing arrow for some symbol\n\n'
            'An NFA accepts a string if **any** path through the machine leads to an accept state.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'The "." (dot) Symbol',
        body: 'A transition labelled **"."** matches **any single symbol** from the alphabet.\n\n'
            'This is a shorthand that saves you drawing one arrow per symbol. '
            'For example, a self-loop "." on a state means "stay here for any symbol".',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Epsilon (ε) Transitions',
        body: 'An **ε-transition** (drawn without a label) is a free jump — '
            'the machine moves to the next state without consuming any input.\n\n'
            'In the canvas, draw an arrow between two states and **clear the label** to create an ε-transition. '
            'Only NFAs may use these.',
        illustrationType: TutorialIllustration.epsilonTransition,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 1 — BASICS  (x ≈ 0.12)
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.12,
    y: 0.20,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

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
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.12,
    y: 0.40,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
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
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.12,
    y: 0.60,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'.'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'level_1',
    title: 'Level 1 — Even 0s',
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
    unlockRule: RequireLevel('dsl_even_0s'),
    x: 0.12,
    y: 0.80,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 2 — STRINGS  (x ≈ 0.20)
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'dfa_ab',
    title: 'Ends with "ab"',
    description:
        'Build an automaton over {a, b} that accepts all strings ending in "ab".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n0 = (360.0, 340.0)
      n1 = (680.0, 340.0)
      n2 = (1000.0, 340.0)
      n2 is accepted
      n0 to n1 = a
      n0 to n0 = b
      n1 to n1 = a
      n1 to n2 = b
      n2 to n1 = a
      n2 to n0 = b
      l0(b) loop angle = -1.5708
      l2(a) loop angle = -1.5708
      l4(a) curve = -60.0
      l5(b) curve = -60.0
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.20,
    y: 0.15,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dfa_even_a',
    title: "Even number of a's",
    description:
        "Build an automaton that accepts strings over {a, b} with an even number of a's (zero counts as even).",
    svgAsset: '',
    dsl: '''
      n0 = even
      n1 = odd
      n0 = (504.0, 360.0)
      n1 = (904.0, 360.0)
      n0 is accepted
      n0 to n1 = a
      n1 to n0 = a
      n0 to n0 = b
      n1 to n1 = b
      l0(a) curve = -80.0
      l1(a) curve = -80.0
      l2(b) loop angle = -1.5708
      l3(b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('intro_accept_a'),
    x: 0.20,
    y: 0.35,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
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
    x: 0.20,
    y: 0.55,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'.'},
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
    x: 0.20,
    y: 0.75,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),


  // ═══════════════════════════════════════════════════════════════════════════
  //  TUTORIAL 2 — NFA PATTERNS  (x ≈ 0.24)
  //  Explains regex-like NFA patterns and how to read level descriptions
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_nfa_patterns',
    title: 'NFA Patterns',
    description: 'Learn how to think about NFA designs and read pattern descriptions.',
    svgAsset: '',
    unlockRule: RequireAny(['dfa_ab', 'dfa_even_a', 'dsl_only_empty_dfa']),
    x: 0.24,
    y: 0.50,
    tag: 'tutorial',
    isTutorial: true,
    tutorialSlides: [
      TutorialSlide(
        headline: 'Pattern Thinking',
        body: 'Many levels describe a **pattern** — for example, '
            '\'all strings ending in \"ab\"\'\n\n'
            'A reliable technique for NFA design:\n'
            '1. Draw a **"prefix sink"** state that loops on everything.\n'
            '2. Add a **chain** of states for the pattern you care about.\n'
            '3. Mark the last state as **accepting**.\n\n'
            'The NFA \'guesses\' when the pattern starts — it tries all paths.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Comma-Separated Labels',
        body: 'You can put **multiple symbols** on one arrow by separating them with commas.\n\n'
            'For example: a transition labelled **"a,b"** means the machine can take that arrow '
            'when it reads either "a" or "b". This keeps diagrams tidy.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Complement Notation',
        body: 'Some levels use notation like **".-\"Green Leaf\""** on an arrow.\n\n'
            'The dot **"."** means "any symbol". The minus means **"except"**. '
            'So **".-X"** means "any symbol except X". '
            'This is handy for caterpillar-style puzzles where one word triggers a special transition.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Self-Loops',
        body: 'A **self-loop** is an arrow from a state back to itself.\n\n'
            'It means "stay in this state while reading this symbol". '
            'Self-loops are common for "ignore everything until we see X" logic.\n\n'
            'To create one: in **line mode** (Shift held), drag from a state onto itself.',
        illustrationType: TutorialIllustration.none,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 3 — PATTERNS  (x ≈ 0.28)
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'nfa_ends_b',
    title: 'Ends with "b"',
    description:
        'Build an NFA that accepts all strings over {a, b} that end with "b".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (432.7, 360.0)
      n1 = (759.3, 360.0)
      n1 is accepted
      n0 to n0 = a,b
      n0 to n1 = b
      a,b loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAny(['dfa_ab', 'dfa_even_a']),
    x: 0.28,
    y: 0.12,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

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
    x: 0.28,
    y: 0.32,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_starts_ab',
    title: 'Starts with "ab"',
    description:
        'Build a DFA over {a, b} that accepts all strings that begin with "ab".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = dead
      n0 = (300.0, 360.0)
      n1 = (620.0, 360.0)
      n2 = (940.0, 360.0)
      n3 = (620.0, 600.0)
      n2 is accepted
      n0 to n1 = a
      n0 to n3 = b
      n1 to n2 = b
      n1 to n3 = a
      n2 to n2 = a,b
      n3 to n3 = a,b
      l4(a,b) loop angle = -1.5708
      l5(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dfa_ab'),
    x: 0.28,
    y: 0.52,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
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
    unlockRule: RequireLevel('nfa_ends_b'),
    x: 0.28,
    y: 0.72,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 4 — ADVANCED  (x ≈ 0.36)
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'nfa_complex',
    title: 'Contains "aba"',
    description:
        'Build an NFA that accepts exactly those strings over {a, b} that contain "aba" as a substring.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n0 = (280.0, 360.0)
      n1 = (580.0, 360.0)
      n2 = (880.0, 360.0)
      n3 = (1180.0, 360.0)
      n3 is accepted
      n0 to n0 = a,b
      n0 to n1 = a
      n1 to n2 = b
      n2 to n3 = a
      n3 to n3 = a,b
      l0(a,b) loop angle = -1.5708
      l4(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAll(['dfa_ab', 'dfa_even_a']),
    x: 0.36,
    y: 0.15,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'epsilon_closure',
    title: '∅-Closures',
    description:
        'Use ∅-transitions to build a compact NFA that accepts strings matching a* | b*.',
    svgAsset: '',
    dsl: '''
      n0 = S
      n1 = A
      n2 = B
      n0 = (500.0, 360.0)
      n1 = (820.0, 220.0)
      n2 = (820.0, 500.0)
      n1 is accepted
      n2 is accepted
      n0 to n1
      n0 to n2
      n1 to n1 = a
      n2 to n2 = b
      l2(a) loop angle = -1.5708
      l3(b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAll(['nfa_ends_b', 'dfa_ab']),
    x: 0.36,
    y: 0.35,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dfa_complement',
    title: 'Complement',
    description:
        "Build the complement of the \"even a's\" language — accept all strings with an ODD number of a's.",
    svgAsset: '',
    dsl: '''
      n0 = even
      n1 = odd
      n0 = (504.0, 360.0)
      n1 = (904.0, 360.0)
      n1 is accepted
      n0 to n1 = a
      n1 to n0 = a
      n0 to n0 = b
      n1 to n1 = b
      l0(a) curve = -80.0
      l1(a) curve = -80.0
      l2(b) loop angle = -1.5708
      l3(b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireExpression(
      isAnd: false,
      children: [
        RequireLevel('dfa_even_a'),
        RequireLevel('nfa_ends_b'),
      ],
    ),
    x: 0.36,
    y: 0.55,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
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
    x: 0.36,
    y: 0.75,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 5 — SUFFIX  (x ≈ 0.43)
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'boss_three_states',
    title: 'Three-state Challenge',
    description:
        'Build a 3-state DFA over {0, 1} that accepts all strings whose binary value is divisible by 3.',
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
    unlockRule: RequireAll(['nfa_complex', 'epsilon_closure', 'dfa_complement']),
    x: 0.43,
    y: 0.18,
    tag: 'boss',
  ),

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
    x: 0.43,
    y: 0.38,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

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
    x: 0.43,
    y: 0.58,
    requiredAutomatonType: RequiredAutomatonType.nfa,
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
    x: 0.43,
    y: 0.78,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 6 — LANGUAGE  (x ≈ 0.49)
  // ═══════════════════════════════════════════════════════════════════════════

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
    x: 0.49,
    y: 0.10,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b', 'c'},
    tag: 'dfa',
  ),

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
    x: 0.49,
    y: 0.28,
    requiredAutomatonType: RequiredAutomatonType.nfa,
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
    x: 0.49,
    y: 0.46,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
  ),

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
    x: 0.49,
    y: 0.65,
    requiredAutomatonType: RequiredAutomatonType.nfa,
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
    x: 0.49,
    y: 0.83,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'.'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA COLUMN 7 — CHALLENGE  (x ≈ 0.55)
  // ═══════════════════════════════════════════════════════════════════════════

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
    x: 0.55,
    y: 0.10,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_contains_aab',
    title: 'Contains "aab"',
    description:
        'Build an NFA over {a, b} that accepts all strings containing "aab" as a substring.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n0 = (300.0, 380.0)
      n1 = (620.0, 380.0)
      n2 = (940.0, 380.0)
      n3 = (1260.0, 380.0)
      n3 is accepted
      n0 to n0 = a,b
      n0 to n1 = a
      n1 to n2 = a
      n2 to n3 = b
      n3 to n3 = a,b
      l0(a,b) loop angle = -1.5708
      l4(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('nfa_complex'),
    x: 0.55,
    y: 0.28,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_len_div3',
    title: 'Length div by 3',
    description:
        'Build a DFA over {a, b} that accepts all strings whose length is divisible by 3 '
        '(including the empty string).',
    svgAsset: '',
    dsl: '''
      n0 = 0
      n1 = 1
      n2 = 2
      n0 = (500.0, 260.0)
      n1 = (880.0, 440.0)
      n2 = (500.0, 620.0)
      n0 is accepted
      n0 to n1 = a,b
      n1 to n2 = a,b
      n2 to n0 = a,b
      l0(a,b) curve = 60.0
      l1(a,b) curve = 60.0
      l2(a,b) curve = 60.0
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_b_dfa'),
    x: 0.55,
    y: 0.46,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_at_least_two_b',
    title: "At Least Two b's",
    description:
        'Build a DFA over {a, b} that accepts all strings containing at least two occurrences of "b".',
    svgAsset: '',
    dsl: '''
      n0 = zero
      n1 = one
      n2 = two
      n0 = (380.0, 380.0)
      n1 = (740.0, 380.0)
      n2 = (1100.0, 380.0)
      n2 is accepted
      n0 to n1 = b
      n1 to n2 = b
      n0 to n0 = a
      n1 to n1 = a
      n2 to n2 = a,b
      l0(a) loop angle = -1.5708
      l2(a) loop angle = -1.5708
      l4(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_b_dfa'),
    x: 0.55,
    y: 0.62,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_not_aba',
    title: 'Does NOT contain "aba"',
    description:
        'Build a DFA over {a, b} that accepts strings that do NOT contain "aba" as a substring.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = dead
      n0 = (300.0, 340.0)
      n1 = (620.0, 340.0)
      n2 = (940.0, 340.0)
      n3 = (620.0, 600.0)
      n0 is accepted
      n1 is accepted
      n2 is accepted
      n0 to n1 = a
      n0 to n0 = b
      n1 to n1 = a
      n1 to n2 = b
      n2 to n3 = a
      n2 to n0 = b
      n3 to n3 = a,b
      l0(b) loop angle = -1.5708
      l2(a) loop angle = -1.5708
      l6(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('nfa_complex'),
    x: 0.55,
    y: 0.80,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  FA BOSSES — CHALLENGE  (x ≈ 0.55, folded into col 7)
  // ═══════════════════════════════════════════════════════════════════════════
  //  These two boss levels are technically in col 7 but need boss_three_states
  //  and the higher col 6 levels as prereqs. They are placed slightly to the
  //  right-of-centre of col 7 at higher y to avoid overlap.

  GameLevel(
    id: 'boss_palindrome',
    title: 'FA Boss: Palindrome',
    description:
        'Build an automaton (any type) that accepts strings over {a, b} that are palindromes of length ≤ 5.',
    svgAsset: '',
    dsl: '''
      n0 = start
      n1 = a
      n2 = b
      n3 = aa
      n4 = ab
      n5 = ba
      n6 = bb
      n0 = (400.0, 400.0)
      n1 = (700.0, 240.0)
      n2 = (700.0, 560.0)
      n3 = (1000.0, 160.0)
      n4 = (1000.0, 320.0)
      n5 = (1000.0, 480.0)
      n6 = (1000.0, 640.0)
      n0 is accepted
      n1 is accepted
      n2 is accepted
      n3 is accepted
      n6 is accepted
      n0 to n1 = a
      n0 to n2 = b
      n1 to n3 = a
      n1 to n4 = b
      n2 to n5 = a
      n2 to n6 = b
      n3 to n3 = a
      n6 to n6 = b
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireExpression(
      isAnd: true,
      children: [
        RequireLevel('boss_three_states'),
        RequireAny(['nfa_complex', 'epsilon_closure']),
      ],
    ),
    x: 0.55,
    y: 0.90,
    tag: 'boss',
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
    x: 0.57,  // shifted right into its own sub-column to avoid clustering
    y: 0.06,
    tag: 'boss',
  ),

  GameLevel(
    id: 'dsl_no_consec_b',
    title: "No Consecutive b's",
    description:
        "Build a DFA over {a, b} that accepts all strings containing no two consecutive b's.",
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = dead
      n0 = (400.0, 340.0)
      n1 = (780.0, 340.0)
      n2 = (580.0, 580.0)
      n0 is accepted
      n1 is accepted
      n0 to n1 = b
      n0 to n0 = a
      n1 to n0 = a
      n1 to n2 = b
      n2 to n2 = a,b
      l0(a) loop angle = -1.5708
      l4(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_ends_two_same_dfa'),
    x: 0.56,  // slight x offset keeps it visually distinct from boss_palindrome
    y: 0.97,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
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
    x: 0.57,  // same sub-column as dsl_binary_mod7
    y: 0.15,
    tag: 'boss',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  PDA SECTION  (x: 0.60–0.76)
  //  Entry: RequireAny(['boss_palindrome', 'dsl_ends_b_dfa'])
  // ═══════════════════════════════════════════════════════════════════════════

  // ── PDA Col 8 — INTRO  (x ≈ 0.61) ─────────────────────────────────────────


  // ═══════════════════════════════════════════════════════════════════════════
  //  TUTORIAL 3 — PUSHDOWN AUTOMATA  (x ≈ 0.59)
  //  Explains the stack, transition format, and when PDAs are needed
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_pda',
    title: 'Pushdown Automata',
    description: 'Learn how PDAs use a stack to recognise context-free languages.',
    svgAsset: '',
    unlockRule: RequireAny(['boss_palindrome', 'dsl_ends_b_dfa']),
    x: 0.59,
    y: 0.50,
    tag: 'tutorial',
    isTutorial: true,
    tutorialSlides: [
      TutorialSlide(
        headline: 'Beyond Finite Memory',
        body: 'Some languages **cannot** be recognised by a DFA or NFA. '
            'The classic example is aⁿbⁿ — equal numbers of a\'s then b\'s.\n\n'
            'A DFA has no memory of how many a\'s it has seen. '
            'A **PDA** adds a **stack** — an infinite scratchpad — which solves this.',
        illustrationType: TutorialIllustration.pdaStack,
      ),
      TutorialSlide(
        headline: 'PDA Transition Format',
        body: 'Each PDA transition arrow has the label format:\n\n'
            '  **read, pop | push**\n\n'
            '• **read** — the input symbol consumed (∅ means consume nothing)\n'
            '• **pop**  — the stack symbol removed from the top (∅ means pop nothing)\n'
            '• **push** — the stack symbol added on top (∅ means push nothing)\n\n'
            'Example: **"a, ∅ | X"** — read "a", don\'t pop, push "X".',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'The ∅ (Empty) Symbol',
        body: 'In PDA labels, **∅** (empty set symbol) means "nothing":\n\n'
            '• **read ∅** — consume no input (ε-move on the tape)\n'
            '• **pop ∅** — don\'t remove anything from the stack\n'
            '• **push ∅** — don\'t add anything to the stack\n\n'
            'You can type it as the empty-set character or leave the field blank in the editor.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Stack Strategy for aⁿbⁿ',
        body: 'Here\'s the classic approach for equal-count problems:\n\n'
            '1. **Push** a marker (e.g. X) for each "a" you read.\n'
            '2. When you start reading "b"s, **pop** one X per "b".\n'
            '3. Accept when the stack is empty and input is exhausted.\n\n'
            'If the stack runs out before the input (or vice versa), the counts don\'t match — reject.',
        illustrationType: TutorialIllustration.none,
      ),
    ],
  ),

  GameLevel(
    id: 'pda_ab_single',
    title: 'PDA: "ab"',
    description:
        'Build a PDA that accepts exactly the string "ab".\n'
        'Use a stack push on "a" and pop it when you see "b".\n'
        'Transition format: input,stackTop|stackPush  (use ∅ for empty/no-op).',
    svgAsset: '',
    dsl: '''
      pda mode
      n0 = A
      n1 = B
      n2 = C
      n0 = (320.0, 360.0)
      n1 = (660.0, 360.0)
      n2 = (1000.0, 360.0)
      n2 is accepted
      n0 to n1 = a,∅|X
      n1 to n2 = b,X|∅
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: RequireAny(['boss_palindrome', 'dsl_ends_b_dfa']),
    x: 0.61,
    y: 0.20,
    tag: 'pda',
  ),

  GameLevel(
    id: 'pda_balanced_parens',
    title: 'Balanced Parentheses',
    description:
        'Build a PDA over {(, )} that accepts strings with balanced parentheses '
        '(e.g. "(()())" accepted, "(()" rejected).\n'
        'Push a marker on every "(" and pop it on every ")".',
    svgAsset: '',
    dsl: '''
      pda mode
      n0 = A
      n1 = B
      n0 = (480.0, 360.0)
      n1 = (820.0, 360.0)
      n0 is accepted
      n0 to n0 = (,∅|X
      n0 to n1 = ),X|∅
      n1 to n1 = ),X|∅
      n1 to n0 = ∅,∅|∅
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: RequireLevel('pda_ab_single'),
    x: 0.61,
    y: 0.40,
    tag: 'pda',
  ),

  GameLevel(
    id: 'pda_anbn',
    title: 'aⁿbⁿ',
    description:
        'Build a PDA that accepts exactly strings of the form aⁿbⁿ (n ≥ 1): '
        "the same number of a's followed by the same number of b's.\n"
        'Classic context-free language — not recognisable by any DFA!',
    svgAsset: '',
    dsl: '''
      pda mode
      n0 = A
      n1 = B
      n2 = C
      n0 = (340.0, 360.0)
      n1 = (680.0, 360.0)
      n2 = (1020.0, 360.0)
      n2 is accepted
      n0 to n0 = a,∅|X
      n0 to n1 = b,X|∅
      n1 to n1 = b,X|∅
      n1 to n2 = ∅,∅|∅
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: RequireLevel('pda_balanced_parens'),
    x: 0.61,
    y: 0.60,
    tag: 'pda',
  ),

  GameLevel(
    id: 'pda_palindrome',
    title: 'PDA Palindromes',
    description:
        'Build a PDA over {a, b} that accepts even-length palindromes '
        '(ww^R where w is any string over {a,b}).\n'
        'Hint: push the first half onto the stack, then pop-match the second half.',
    svgAsset: '',
    dsl: '''
      pda mode
      n0 = A
      n1 = B
      n2 = C
      n0 = (340.0, 360.0)
      n1 = (680.0, 360.0)
      n2 = (1020.0, 360.0)
      n2 is accepted
      n0 to n0 = a,∅|a
      n0 to n0 = b,∅|b
      n0 to n1 = ∅,∅|∅
      n1 to n1 = a,a|∅
      n1 to n1 = b,b|∅
      n1 to n2 = ∅,∅|∅
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: RequireLevel('pda_anbn'),
    x: 0.61,
    y: 0.80,
    tag: 'pda',
  ),

  // ── PDA Col 9 — STACK LANGUAGES  (x ≈ 0.68) ───────────────────────────────

  GameLevel(
    id: 'pda_more_as',
    title: "More a's Than b's",
    description:
        "Build a PDA over {a, b} that accepts strings where the number of a's "
        "is strictly greater than the number of b's (in any order).\n"
        'Push for each a, pop for each b; accept if the stack is non-empty at the end.',
    svgAsset: '',
    dsl: '''
      pda mode
      n0 = A
      n1 = B
      n2 = C
      n0 = (380.0, 360.0)
      n1 = (720.0, 360.0)
      n2 = (1060.0, 360.0)
      n0 to n0 = a,∅|X
      n0 to n0 = b,X|∅
      n0 to n1 = ∅,X|X
      n1 is accepted
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: RequireLevel('pda_anbn'),
    x: 0.68,
    y: 0.25,
    tag: 'pda',
  ),

  GameLevel(
    id: 'pda_an_b2n',
    title: 'aⁿb²ⁿ',
    description:
        'Build a PDA that accepts strings of the form aⁿb²ⁿ (n ≥ 1): '
        "for every a there must be exactly two b's.\n"
        'Hint: push two markers for each a you read.',
    svgAsset: '',
    dsl: '''
      pda mode
      n0 = A
      n1 = B
      n2 = C
      n0 = (340.0, 360.0)
      n1 = (680.0, 360.0)
      n2 = (1020.0, 360.0)
      n2 is accepted
      n0 to n0 = a,∅|X
      n0 to n0 = a,∅|X
      n0 to n1 = b,X|∅
      n1 to n1 = b,X|∅
      n1 to n2 = ∅,∅|∅
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: RequireLevel('pda_anbn'),
    x: 0.68,
    y: 0.50,
    tag: 'pda',
  ),

  // ── PDA Col 10 — BOSS  (x ≈ 0.75) ─────────────────────────────────────────

  GameLevel(
    id: 'level_2',
    title: 'Level 2 — PDA Boss',
    description:
        'Build a PDA that matches the hidden stack-based target machine. '
        'Study the transition format and think carefully about what language this could be.',
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
    unlockRule: RequireAll(['pda_palindrome', 'pda_more_as']),
    x: 0.75,
    y: 0.50,
    tag: 'pda',
  ),


  // ═══════════════════════════════════════════════════════════════════════════
  //  TUTORIAL 4 — TURING MACHINES  (x ≈ 0.79)
  //  Explains the tape, head, transitions, and TM programming mindset
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_tm',
    title: 'Turing Machines',
    description: 'Learn the read/write tape model and TM transition format.',
    svgAsset: '',
    unlockRule: RequireAny(['level_2', 'pda_an_b2n']),
    x: 0.79,
    y: 0.50,
    tag: 'tutorial',
    isTutorial: true,
    tutorialSlides: [
      TutorialSlide(
        headline: 'The Turing Machine',
        body: 'A Turing machine adds a **read/write tape** to a finite automaton. '
            'The tape is infinite in both directions and starts with your input.\n\n'
            'A **read/write head** sits on one cell at a time. '
            'On each step it reads the current symbol, writes a new symbol (or leaves it), '
            'and moves **Left** or **Right** (or stays Still).',
        illustrationType: TutorialIllustration.tmTape,
      ),
      TutorialSlide(
        headline: 'TM Transition Format',
        body: 'Each TM arrow label has the format:\n\n'
            '  **readSymbol writeSymbol Direction**\n\n'
            'Direction is **R** (right), **L** (left), or **S** (stay).\n\n'
            'Example: **"aXR"** — read "a", write "X", move Right.\n'
            'Example: **"∅∅S"** — read blank, write blank, stay (blank = empty cell).',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Accepting and Rejecting',
        body: 'A TM **accepts** by entering an accept state (double ring) and halting.\n\n'
            'A TM **rejects** either by entering a reject state (no outgoing transition for the current symbol causes a crash) '
            'or by looping forever.\n\n'
            'The equivalence checker uses a bounded simulation — '
            'it tests many input strings but can\'t always prove correctness on all inputs.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'The Crossout Technique',
        body: 'Many TM puzzles use a **crossout** strategy:\n\n'
            '1. Replace a matched symbol with **X** (or another marker) to "cross it out".\n'
            '2. Sweep the tape left/right to find the next unmatched symbol.\n'
            '3. Repeat until all symbols are matched or a mismatch is detected.\n\n'
            'You\'ll see this in aⁿbⁿ, aⁿbⁿcⁿ, palindrome, and the "ww" puzzles.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Multiple Loops on One State',
        body: 'TM states often have **many self-loops** — one for each symbol the machine should '
            'pass over without stopping.\n\n'
            'In the canvas you can drag a self-loop\'s label dot to rotate it around the state circle, '
            'so diagrams stay readable even with 4–5 loops on one state.',
        illustrationType: TutorialIllustration.none,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  TM SECTION  (x: 0.80–0.97)
  //  Entry: RequireAny(['level_2', 'pda_an_b2n'])
  // ═══════════════════════════════════════════════════════════════════════════

  // ── TM Col 11 — INTRO  (x ≈ 0.81) ─────────────────────────────────────────

  GameLevel(
    id: 'tm_identity',
    title: 'TM: Accept All (Trivial)',
    description:
        'Build the simplest possible Turing machine: one that accepts every input '
        'by halting immediately.\n'
        'A single state that is both start and accept will do it. '
        'TM transition format: readSymbol writeSymbol Direction (e.g. aBR = read a, write B, move Right).',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      A = (600.0, 360.0)
      A is accepted
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireAny(['level_2', 'pda_an_b2n']),
    x: 0.81,
    y: 0.25,
    tag: 'tm',
  ),

  GameLevel(
    id: 'tm_reject_all',
    title: 'TM: Reject All',
    description:
        'Build a TM that loops forever on any non-empty input (rejects by non-halt) '
        'and accepts only the empty tape.\n'
        'Hint: a start state with a self-loop on every symbol that moves right will spin forever.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      A = (480.0, 360.0)
      B = (820.0, 360.0)
      B is accepted
      A to B = ∅∅S
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireLevel('tm_identity'),
    x: 0.81,
    y: 0.50,
    tag: 'tm',
  ),

  GameLevel(
    id: 'tm_unary_increment',
    title: 'TM: Unary Increment',
    description:
        'Build a TM over {1} that accepts strings of the form 1ⁿ for any n ≥ 0. '
        'The machine should scan past all 1s and accept when it hits blank. '
        'This checks you can drive the head right and accept on blank.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      A = (460.0, 360.0)
      B = (820.0, 360.0)
      B is accepted
      A to A = 11R
      A to B = ∅∅S
      l0(11R) loop angle = -1.5708
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireLevel('tm_reject_all'),
    x: 0.81,
    y: 0.75,
    tag: 'tm',
  ),

  // ── TM Col 12 — BASICS  (x ≈ 0.87) ────────────────────────────────────────

  GameLevel(
    id: 'tm_anbn',
    title: 'TM: aⁿbⁿ',
    description:
        'Build a TM that accepts exactly strings of the form aⁿbⁿ (n ≥ 1). '
        'Classic TM exercise: repeatedly cross off one a and one b until both sides are exhausted.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = E
      A = (260.0, 200.0)
      B = (660.0, 200.0)
      C = (1060.0, 200.0)
      D = (660.0, 560.0)
      E = (260.0, 560.0)
      E is accepted
      A to B = aXR
      B to B = aXR
      B to C = bXL
      C to D = XXL
      D to D = aXL
      D to A = XXR
      A to E = ∅∅S
      l1(aXR) loop angle = -1.5708
      l3(XXL) loop angle = -1.5708
      l4(aXL) loop angle = 1.5708
      aXR curve = 80.0
      bXL curve = 80.0
      XXR curve = 80.0
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireLevel('tm_unary_increment'),
    x: 0.87,
    y: 0.20,
    tag: 'tm',
  ),

  GameLevel(
    id: 'tm_binary_increment',
    title: 'TM: Binary Increment',
    description:
        'Build a TM over {0,1} that accepts any binary string '
        '(treat the tape as a binary number and verify the head can scan it). '
        'The machine must scan from left to right over 0s and 1s and halt-accept on blank.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      A = (480.0, 360.0)
      B = (820.0, 360.0)
      B is accepted
      A to A = 00R
      A to A = 11R
      A to B = ∅∅S
      l0(00R) loop angle = -1.5708
      l1(11R) loop angle = -0.8000
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireLevel('tm_anbn'),
    x: 0.87,
    y: 0.45,
    tag: 'tm',
  ),

  GameLevel(
    id: 'tm_unary_addition',
    title: 'TM: Unary Addition',
    description:
        'Build a TM over {1, +} that accepts any string of the form 1ⁿ+1ᵐ '
        '(unary numbers separated by a plus sign).\n'
        'The machine should scan past all 1s and the + symbol and halt-accept on blank.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      A = (480.0, 360.0)
      B = (840.0, 360.0)
      B is accepted
      A to A = 11R
      A to A = ++R
      A to B = ∅∅S
      l0(11R) loop angle = -1.5708
      l1(++R) loop angle = -0.8000
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireLevel('tm_unary_increment'),
    x: 0.87,
    y: 0.70,
    tag: 'tm',
  ),

  // ── TM Col 13 — ADVANCED  (x ≈ 0.92) ──────────────────────────────────────

  GameLevel(
    id: 'tm_ww',
    title: 'TM: ww (Doubled Word)',
    description:
        'Build a TM that accepts strings of the form ww over {a, b}: '
        'a string that consists of some word w repeated exactly twice '
        '(e.g. "abab", "aabbaa bb"). '
        'This is a classic non-context-free language.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = E
      n5 = F
      A = (260.0, 180.0)
      B = (660.0, 180.0)
      C = (1060.0, 180.0)
      D = (1060.0, 540.0)
      E = (660.0, 540.0)
      F = (260.0, 540.0)
      F is accepted
      A to B = aXR
      A to C = bXR
      B to B = aaR
      B to B = bbR
      B to D = bXL
      C to C = aaR
      C to C = bbR
      C to E = aXL
      D to D = aaL
      D to D = bbL
      D to A = XXR
      E to E = aaL
      E to E = bbL
      E to A = XXR
      A to F = ∅∅S
      l1(aaR) loop angle = -1.5708
      l2(bbR) loop angle = -0.8000
      l5(aaR) loop angle = -1.5708
      l6(bbR) loop angle = -0.8000
      l7(aaL) loop angle = 1.5708
      l8(bbL) loop angle = 0.8000
      l10(aaL) loop angle = 1.5708
      l11(bbL) loop angle = 0.8000
      aXR curve = 60.0
      bXR curve = -60.0
      bXL curve = 60.0
      aXL curve = -60.0
      XXR_D curve = 80.0
      XXR_E curve = -80.0
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireAll(['tm_anbn', 'tm_binary_increment']),
    x: 0.92,
    y: 0.25,
    tag: 'tm',
  ),

  GameLevel(
    id: 'tm_anbncn',
    title: 'TM: aⁿbⁿcⁿ',
    description:
        'Build a TM that accepts strings of the form aⁿbⁿcⁿ (n ≥ 1).\n'
        'This language is not context-free — no PDA can recognise it — '
        'but a TM can! Cross off one a, one b, and one c per pass.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = E
      n5 = F
      A = (260.0, 200.0)
      B = (580.0, 200.0)
      C = (900.0, 200.0)
      D = (900.0, 540.0)
      E = (580.0, 540.0)
      F = (260.0, 540.0)
      F is accepted
      A to B = aXR
      B to B = aaR
      B to B = XXR
      B to C = bXR
      C to C = bbR
      C to C = XXR
      C to D = cXL
      D to D = bbL
      D to D = ccL
      D to D = XXL
      D to E = aaL
      E to E = aaL
      E to E = bbL
      E to E = ccL
      E to E = XXL
      E to A = XXR
      A to F = ∅∅S
      l1(aaR) loop angle = -1.5708
      l2(XXR) loop angle = -0.8000
      l4(bbR) loop angle = -1.5708
      l5(XXR) loop angle = -0.8000
      l7(bbL) loop angle = 1.5708
      l8(ccL) loop angle = 0.8000
      l9(XXL) loop angle = 2.3000
      l11(aaL) loop angle = 1.5708
      l12(bbL) loop angle = 0.8000
      l13(ccL) loop angle = 2.3000
      l14(XXL) loop angle = 3.1000
      aXR curve = 70.0
      bXR curve = 70.0
      cXL curve = 70.0
      aaL_E curve = 60.0
      XXR_E curve = 60.0
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireLevel('tm_anbn'),
    x: 0.92,
    y: 0.55,
    tag: 'tm',
  ),

  // ── TM Col 14 — BOSS  (x ≈ 0.97) ──────────────────────────────────────────

  GameLevel(
    id: 'tm_palindrome',
    title: 'TM: Palindrome',
    description:
        'Build a TM over {a, b} that accepts palindromes of any length.\n'
        'Strategy: repeatedly peel the first and last character and verify they match.',
    svgAsset: '',
    dsl: r'''
      tm mode
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = E
      n5 = F
      A = (260.0, 200.0)
      B = (640.0, 200.0)
      C = (1020.0, 200.0)
      D = (1020.0, 540.0)
      E = (640.0, 540.0)
      F = (260.0, 540.0)
      F is accepted
      A to B = aXR
      A to C = bXR
      B to B = aaR
      B to B = bbR
      B to E = aXL
      C to C = aaR
      C to C = bbR
      C to D = bXL
      D to D = aaL
      D to D = bbL
      D to A = XXR
      E to E = aaL
      E to E = bbL
      E to A = XXR
      A to F = ∅∅S
      l1(aaR) loop angle = -1.5708
      l2(bbR) loop angle = -0.6000
      l5(aaR) loop angle = -1.5708
      l6(bbR) loop angle = -0.6000
      l8(aaL) loop angle = 1.5708
      l9(bbL) loop angle = 0.6000
      l11(aaL) loop angle = 1.5708
      l12(bbL) loop angle = 0.6000
      aXR curve = 70.0
      bXR curve = -70.0
      aXL curve = -70.0
      bXL curve = 70.0
      to A angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.tm,
    unlockRule: RequireAll(['tm_ww', 'tm_anbncn']),
    x: 0.97,
    y: 0.30,
    tag: 'tm',
  ),

  GameLevel(
    id: 'level_3',
    title: 'Level 3 — TM Boss',
    description:
        'Build a Turing machine that matches the hidden target tape behaviour. '
        'This is the hardest TM puzzle — study the state transitions carefully.',
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
    unlockRule: RequireAll(['tm_palindrome', 'tm_unary_addition']),
    x: 0.97,
    y: 0.65,
    tag: 'tm',
  ),
];

/// Convenience map for O(1) lookup by id.
final Map<String, GameLevel> kLevelById = {
  for (final l in kAllLevels) l.id: l,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Tag colour palette used by the neural-network level map
// ─────────────────────────────────────────────────────────────────────────────

/// Default tag colors when no [AppThemeNotifier] is available.
Color levelTagColor(String? tag) => AppThemeData.defaults().tagColor(tag);