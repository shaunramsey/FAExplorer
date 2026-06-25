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
//    0.00–0.64  FA   (Finite Automata)  — columns 0–15
//    0.68–0.80  PDA  (Pushdown Automata) — columns 16–19
//    0.84–0.97  TM   (Turing Machines)  — columns 20–25
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
//  LevelDifficulty
// ─────────────────────────────────────────────────────────────────────────────

/// The two play modes available for every puzzle level.
///
/// [easy]  — scaffold nodes are pre-placed on the canvas (connections still
///           need to be drawn by the player).  Only available when the level
///           defines [GameLevel.easyModeNodes].
///
/// [hard]  — blank canvas; the player builds everything from scratch.
///           This is the original behaviour and is always available.
enum LevelDifficulty {
  easy,
  hard;

  /// Human-readable label used in the UI toggle and page titles.
  String get displayName => switch (this) {
        LevelDifficulty.easy => 'Easy',
        LevelDifficulty.hard => 'Hard',
      };

  bool get isEasy => this == LevelDifficulty.easy;
  bool get isHard => this == LevelDifficulty.hard;
}

// ─────────────────────────────────────────────────────────────────────────────
//  PuzzleVariant
// ─────────────────────────────────────────────────────────────────────────────

/// Governs what kind of challenge the player faces and how the puzzle screen
/// presents it.
///
/// [buildAutomaton]  — Classic mode: blank (or scaffolded) canvas; player draws
///                     states and transitions; submission is checked for FA/PDA/TM
///                     equivalence against the embedded target DSL.  This is the
///                     original behaviour and the default for all existing levels.
///
/// [regexToDfa]      — The player is shown a regular expression in the goal banner
///                     and must build a DFA whose language is equivalent to that
///                     regex.  Submission is checked for FA equivalence against a
///                     pre-computed DFA stored in [GameLevel.dsl].  The level must
///                     also set [GameLevel.requiredAutomatonType] to
///                     [RequiredAutomatonType.dfa] so the type-check fires first.
///
/// [dfaToRegex]      — The player is shown a DFA diagram (rendered read-only on the
///                     canvas) and must type a regular expression into a text field.
///                     Their regex is compiled to an NFA/DFA and then checked for
///                     FA equivalence against the target stored in [GameLevel.dsl].
///                     The canvas is non-interactive; only the regex input matters.
enum PuzzleVariant {
  buildAutomaton,
  regexToDfa,
  dfaToRegex,
}

// ─────────────────────────────────────────────────────────────────────────────
//  EasyModeNode
// ─────────────────────────────────────────────────────────────────────────────

/// A single pre-placed state node for easy-mode puzzles.
///
/// [GamePuzzleScreen] converts these into [NodeData] instances at the correct
/// canvas positions before the player interacts with the level.
/// Transitions are intentionally absent — the player draws those themselves.
///
/// Example (a two-state DFA over {a, b}):
/// ```dart
/// easyModeNodes: [
///   EasyModeNode(id: 'n0', label: 'q0', x: 160, y: 300, isStart: true),
///   EasyModeNode(id: 'n1', label: 'q1', x: 480, y: 300, isAccept: true),
/// ]
/// ```
class EasyModeNode {
  const EasyModeNode({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    this.isAccept = false,
    this.isStart = false,
  });

  /// Stable node identifier matching the `nN` prefix convention (e.g. `'n0'`).
  final String id;

  /// State label shown inside the node circle.
  final String label;

  /// Horizontal canvas position in logical pixels.
  final double x;

  /// Vertical canvas position in logical pixels.
  final double y;

  /// True → double-ring accept state.
  final bool isAccept;

  /// True → the start arrow points at this node.
  /// At most one node per level should have this set.
  final bool isStart;
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

  /// Whether this is a boss level.
  ///
  /// Layer placement rules enforced by [LayerConstraintValidator]:
  ///   • A layer containing a boss may contain AT MOST 2 bosses and NO non-boss,
  ///     non-tutorial levels.
  ///   • A layer containing a tutorial must contain ONLY that tutorial
  ///     (isTutorial is already exclusive by design, but this makes it explicit).
  ///   • All other layers may contain AT MOST 4 levels.
  final bool isBoss;

  /// Pre-placed node layout for easy mode.
  ///
  /// When non-null, [GamePuzzleScreen] seeds the canvas with these nodes
  /// (positions, labels, accept/start flags) before the player's first move.
  /// The player only needs to draw the transitions.
  ///
  /// When null, easy mode behaves identically to hard mode (blank canvas).
  final List<EasyModeNode>? easyModeNodes;

  /// Whether this level supports [LevelDifficulty.easy] mode with scaffolding.
  bool get hasEasyMode => easyModeNodes != null && easyModeNodes!.isNotEmpty;

  /// Controls which kind of challenge the puzzle screen presents.
  ///
  /// Defaults to [PuzzleVariant.buildAutomaton] for all existing levels.
  /// Set to [PuzzleVariant.regexToDfa] or [PuzzleVariant.dfaToRegex] for the
  /// new regex section.
  final PuzzleVariant puzzleVariant;

  /// The regular expression string shown to the player in [PuzzleVariant.regexToDfa]
  /// and [PuzzleVariant.dfaToRegex] levels.
  ///
  /// For [regexToDfa]: displayed prominently in the goal banner so the player
  /// knows which language they must capture.
  ///
  /// For [dfaToRegex]: also displayed as a hint / reference alongside the
  /// read-only DFA canvas.  The equivalence check ignores this field; only
  /// [dsl] is used as the ground truth.
  final String targetRegex;

  /// When true, the [requiredAutomatonType] constraint is relaxed in easy mode:
  /// the player may submit any finite automaton (DFA or NFA) and the type check
  /// is skipped entirely.  The language-equivalence check still runs as normal.
  ///
  /// This is useful for levels that require a DFA on hard mode (teaching the
  /// deterministic construction) but want to give easy-mode players the freedom
  /// to solve the puzzle with whichever FA style they prefer.
  ///
  /// Has no effect when [requiredAutomatonType] is null (the level already
  /// accepts any FA type) or when the player is playing on hard mode.
  final bool easyModeBypassTypeCheck;

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
    this.isBoss = false,
    this.easyModeNodes,
    this.easyModeBypassTypeCheck = false,
    this.puzzleVariant = PuzzleVariant.buildAutomaton,
    this.targetRegex = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  LEVEL REGISTRY
//
//  LAYOUT STRUCTURE:  (max 4 levels/layer; tutorials alone; boss layers ≤2 bosses, no non-bosses)
//
//    ═══ FA SECTION (x: 0.00–0.64) ═══════════════════════════════════════════
//    Col 0  x≈0.00   TUTORIAL      — welcome / canvas basics (alone)
//    Col 1  x≈0.05   FA INTRO      — single start node (AlwaysUnlocked)
//    Col 2  x≈0.09   TUTORIAL      — DFA vs NFA (alone)
//    Col 3  x≈0.13   FA BASICS A   — empty/even-0s/accept-all  (3 levels)
//    Col 4  x≈0.17   FA BASICS B   — ab/even-a/level_1          (3 levels)
//    Col 5  x≈0.22   FA STRINGS A  — empty-dfa/accept-all-nfa   (2 levels)
//    Col 6  x≈0.26   TUTORIAL      — NFA Patterns (alone)
//    Col 7  x≈0.31   FA STRINGS B  — ends-b/one-0-dfa/starts-ab (3 levels)
//    Col 8  x≈0.35   FA PATTERNS   — ends-b-nfa/contains-aba/epsilon/complement (4 levels)
//    Col 9  x≈0.40   FA ADVANCED A — one-0-nfa/ends-abc-nfa/ends-same-nfa/ends-b-dfa (4 levels)
//    Col 10 x≈0.44   BOSS          — three-state challenge (boss, alone)
//    Col 11 x≈0.48   FA ADVANCED B — ends-abc-dfa/caterpillar-nfa/ends-same-dfa/halt-y (4 levels)
//    Col 12 x≈0.52   FA LANGUAGE A — caterpillar-dfa/binary-mod3/contains-aab/len-div3 (4 levels)
//    Col 13 x≈0.56   FA LANGUAGE B — at-least-two-b/not-aba/no-consec-b (3 levels)
//    Col 14 x≈0.60   BOSS          — palindrome-boss + binary-mod7 (2 bosses, alone)
//    Col 15 x≈0.64   BOSS          — binary-mod8 (boss, alone)
//
//    ═══ PDA SECTION (x: 0.68–0.80) ══════════════════════════════════════════
//    Col 16 x≈0.68   TUTORIAL      — Pushdown Automata (alone)
//    Col 17 x≈0.72   PDA INTRO     — ab/parens/anbn/palindrome (4 levels)
//    Col 18 x≈0.76   PDA BASICS    — more-as/an-b2n (2 levels)
//    Col 19 x≈0.80   BOSS          — level_2 PDA boss (boss, alone)
//
//    ═══ TM SECTION (x: 0.84–0.97) ═══════════════════════════════════════════
//    Col 20 x≈0.84   TUTORIAL      — Turing Machines (alone)
//    Col 21 x≈0.87   TM INTRO      — identity/reject/unary-inc (3 levels)
//    Col 22 x≈0.91   TM BASICS     — anbn/binary-inc/unary-add (3 levels)
//    Col 23 x≈0.94   TM ADVANCED   — ww/anbncn (2 levels)
//    Col 24 x≈0.96   TM CHALLENGE  — tm_palindrome (1 level)
//    Col 25 x≈0.98   BOSS          — level_3 TM boss (boss, alone)
//
//    ═══ REGEX SECTION (x: 1.00–1.12) ════════════════════════════════════════
//    Col 26 x≈1.00   TUTORIAL      — Regular Expressions (alone)
//    Col 27 x≈1.03   REGEX→DFA A   — regex_to_dfa_ab_star / regex_to_dfa_starts_a / regex_to_dfa_ends_b (3 levels)
//    Col 28 x≈1.06   REGEX→DFA B   — regex_to_dfa_a_or_b_star / regex_to_dfa_aba / regex_to_dfa_no_aa (3 levels)
//    Col 29 x≈1.09   DFA→REGEX A   — dfa_to_regex_single_a / dfa_to_regex_ends_b / dfa_to_regex_even_as (3 levels)
//    Col 30 x≈1.12   DFA→REGEX B   — dfa_to_regex_starts_ab / dfa_to_regex_no_consec_b / dfa_to_regex_binary_mod2 (3 levels)
// ─────────────────────────────────────────────────────────────────────────────

const List<GameLevel> kAllLevels = [

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 0 — TUTORIAL: HOW TO PLAY  (x ≈ 0.00)
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
  //  LAYER 1 — ACCEPT "a"  (x ≈ 0.04)
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
    unlockRule: RequireLevel('tutorial_welcome'),
    x: 0.04,
    y: 0.50,
    tag: 'intro',
    alphabet: {'a'},
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 2 — TUTORIAL: DFA vs NFA  (x ≈ 0.08)
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
  //  LAYER 3 — BASICS: Only ∅ / Accept Everything, DFA + NFA  (x ≈ 0.12)
  //  All four unlock from tutorial_dfa_vs_nfa.
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
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    x: 0.12,
    y: 0.20,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_accepts_everything_nfa',
    title: 'Accept Everything (NFA)',
    description:
        'Build a two-state NFA that uses a free ε-jump to accept every string. '
        'Hint: an ε-transition (no label) is a "free jump" to another state.',
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
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    x: 0.12,
    y: 0.40,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
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
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    x: 0.12,
    y: 0.60,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'.'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_accepts_everything',
    title: 'Accept Everything (DFA)',
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
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    x: 0.12,
    y: 0.80,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'.'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 4 — STARTS WITH "a" / ENDS WITH "b", DFA + NFA  (x ≈ 0.18)
  //  NFA pair requires Only ∅ NFA AND Accept Everything NFA.
  //  DFA pair requires Only ∅ DFA AND Accept Everything DFA.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'nfa_starts_a',
    title: 'Starts with "a" (NFA)',
    description:
        'Build an NFA over {a, b} that accepts all strings that start with "a".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (400.0, 360.0)
      n1 = (760.0, 360.0)
      n1 is accepted
      n0 to n1 = a
      n1 to n1 = a,b
      a,b loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAll(['dsl_only_empty_nfa', 'dsl_accepts_everything_nfa']),
    x: 0.18,
    y: 0.15,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
    easyModeBypassTypeCheck: true,
    easyModeNodes: [
      EasyModeNode(id: 'n0', label: 'A', x: 400.0, y: 360.0, isStart: true),
      EasyModeNode(id: 'n1', label: 'B', x: 760.0, y: 360.0, isAccept: true),
    ],
  ),

  GameLevel(
    id: 'nfa_ends_b',
    title: 'Ends with "b" (NFA)',
    description:
        'Build an NFA over {a, b} that accepts all strings that end with "b".',
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
    unlockRule: RequireAll(['dsl_only_empty_nfa', 'dsl_accepts_everything_nfa']),
    x: 0.18,
    y: 0.35,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dfa_starts_a',
    title: 'Starts with "a" (DFA)',
    description:
        'Build a DFA over {a, b} that accepts all strings that start with "a". '
        'Every state must handle both symbols.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = dead
      n0 = (320.0, 360.0)
      n1 = (660.0, 360.0)
      n2 = (660.0, 600.0)
      n1 is accepted
      n0 to n1 = a
      n0 to n2 = b
      n1 to n1 = a,b
      n2 to n2 = a,b
      l2(a,b) loop angle = -1.5708
      l3(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAll(['dsl_only_empty_dfa', 'dsl_accepts_everything']),
    x: 0.18,
    y: 0.65,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_ends_b_dfa',
    title: 'Ends with "b" (DFA)',
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
    unlockRule: RequireAll(['dsl_only_empty_dfa', 'dsl_accepts_everything']),
    x: 0.18,
    y: 0.85,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 5 — STARTS/ENDS WITH "ab", DFA + NFA  (x ≈ 0.24)
  //  starts ab DFA  ← starts a DFA
  //  starts ab NFA  ← starts a NFA
  //  ends ab DFA    ← ends b DFA
  //  ends ab NFA    ← ends b NFA
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'dfa_starts_ab',
    title: 'Starts with "ab" (DFA)',
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
    unlockRule: RequireLevel('dfa_starts_a'),
    x: 0.24,
    y: 0.10,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'nfa_starts_ab',
    title: 'Starts with "ab" (NFA)',
    description:
        'Build an NFA over {a, b} that accepts all strings that begin with "ab".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n0 = (300.0, 360.0)
      n1 = (620.0, 360.0)
      n2 = (940.0, 360.0)
      n2 is accepted
      n0 to n1 = a
      n1 to n2 = b
      n2 to n2 = a,b
      a,b loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('nfa_starts_a'),
    x: 0.24,
    y: 0.30,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dfa_ends_ab',
    title: 'Ends with "ab" (DFA)',
    description:
        'Build a DFA over {a, b} that accepts all strings ending in "ab".',
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
    unlockRule: RequireLevel('dsl_ends_b_dfa'),
    x: 0.24,
    y: 0.55,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'nfa_ends_ab',
    title: 'Ends with "ab" (NFA)',
    description:
        'Build an NFA over {a, b} that accepts all strings ending in "ab".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n0 = (360.0, 340.0)
      n1 = (680.0, 340.0)
      n2 = (1000.0, 340.0)
      n2 is accepted
      n0 to n0 = a,b
      n0 to n1 = a
      n1 to n2 = b
      a,b loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('nfa_ends_b'),
    x: 0.24,
    y: 0.75,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 6 — STARTS/ENDS WITH "abc", DFA + NFA  (x ≈ 0.30)
  //  starts abc DFA ← starts ab DFA
  //  starts abc NFA ← starts ab NFA
  //  ends abc DFA   ← ends ab DFA
  //  ends abc NFA   ← ends ab NFA
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'dfa_starts_abc',
    title: 'Starts with "abc" (DFA)',
    description:
        'Build a DFA over {a, b, c} that accepts all strings that begin with "abc".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = dead
      n0 = (220.0, 360.0)
      n1 = (480.0, 360.0)
      n2 = (740.0, 360.0)
      n3 = (1000.0, 360.0)
      n4 = (600.0, 580.0)
      n3 is accepted
      n0 to n1 = a
      n0 to n4 = b,c
      n1 to n2 = b
      n1 to n4 = a,c
      n2 to n3 = c
      n2 to n4 = a,b
      n3 to n3 = a,b,c
      n4 to n4 = a,b,c
      l6(a,b,c) loop angle = -1.5708
      l7(a,b,c) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dfa_starts_ab'),
    x: 0.30,
    y: 0.10,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b', 'c'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'nfa_starts_abc',
    title: 'Starts with "abc" (NFA)',
    description:
        'Build an NFA over {a, b, c} that accepts all strings that begin with "abc".',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n0 = (220.0, 360.0)
      n1 = (480.0, 360.0)
      n2 = (740.0, 360.0)
      n3 = (1000.0, 360.0)
      n3 is accepted
      n0 to n1 = a
      n1 to n2 = b
      n2 to n3 = c
      n3 to n3 = a,b,c
      a,b,c loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('nfa_starts_ab'),
    x: 0.30,
    y: 0.30,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b', 'c'},
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_ends_abc_dfa',
    title: 'Ends with "abc" (DFA)',
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
    unlockRule: RequireLevel('dfa_ends_ab'),
    x: 0.30,
    y: 0.55,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b', 'c'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_ends_abc_nfa',
    title: 'Ends with "abc" (NFA)',
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
    unlockRule: RequireLevel('nfa_ends_ab'),
    x: 0.30,
    y: 0.75,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b', 'c'},
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 7 — ENDS 00/11, CONTAINS "aba", DFA + NFA  (x ≈ 0.36)
  //  ends 00/11 NFA   ← ends abc NFA
  //  ends 00/11 DFA   ← ends abc DFA
  //  contains aba DFA ← ends abc DFA OR starts abc DFA
  //  contains aba NFA ← ends abc NFA OR starts abc NFA
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('dsl_ends_abc_nfa'),
    x: 0.36,
    y: 0.10,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'0', '1'},
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
    unlockRule: RequireLevel('dsl_ends_abc_dfa'),
    x: 0.36,
    y: 0.30,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dfa_contains_aba',
    title: 'Contains "aba" (DFA)',
    description:
        'Build a DFA over {a, b} that accepts exactly those strings containing "aba" as a substring.',
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
      n0 to n1 = a
      n0 to n0 = b
      n1 to n1 = a
      n1 to n2 = b
      n2 to n3 = a
      n3 to n3 = a,b
      n2 to n0 = b
      l0(b) loop angle = -1.5708
      l2(a) loop angle = -1.5708
      l5(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAny(['dsl_ends_abc_dfa', 'dfa_starts_abc']),
    x: 0.36,
    y: 0.55,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'nfa_complex',
    title: 'Contains "aba" (NFA)',
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
    unlockRule: RequireAny(['dsl_ends_abc_nfa', 'nfa_starts_abc']),
    x: 0.36,
    y: 0.75,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 8 — CONTAINS "aab", DFA + NFA  (x ≈ 0.41)
  //  contains aab DFA ← contains aba DFA
  //  contains aab NFA ← contains aba NFA
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'dfa_contains_aab',
    title: 'Contains "aab" (DFA)',
    description:
        'Build a DFA over {a, b} that accepts all strings containing "aab" as a substring.',
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
      n0 to n1 = a
      n0 to n0 = b
      n1 to n2 = a
      n1 to n0 = b
      n2 to n3 = b
      n2 to n2 = a
      n3 to n3 = a,b
      l0(b) loop angle = -1.5708
      l4(a) loop angle = -1.5708
      l6(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dfa_contains_aba'),
    x: 0.41,
    y: 0.30,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  GameLevel(
    id: 'dsl_contains_aab',
    title: 'Contains "aab" (NFA)',
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
    x: 0.41,
    y: 0.70,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 9 — AT LEAST 2 Bs AND NOT "aba", DFA + NFA  (x ≈ 0.46)
  //  Both require contains aab (DFA or NFA respectively).
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'dsl_at_least_two_b_not_aba_nfa',
    title: "At Least 2 b's & Not \"aba\" (NFA)",
    description:
        "Build an NFA over {a, b} that accepts strings with at least two b's "
        'AND that do NOT contain "aba" as a substring.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = dead
      n0 = (260.0, 360.0)
      n1 = (580.0, 360.0)
      n2 = (900.0, 360.0)
      n3 = (580.0, 580.0)
      n2 is accepted
      n0 to n1 = b
      n1 to n2 = b
      n0 to n0 = a
      n1 to n1 = a
      n2 to n3 = a
      n3 to n3 = a,b
      l0(a) loop angle = -1.5708
      l2(a) loop angle = -1.5708
      l5(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_contains_aab'),
    x: 0.46,
    y: 0.65,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_at_least_two_b_not_aba_dfa',
    title: "At Least 2 b's & Not \"aba\" (DFA)",
    description:
        "Build a DFA over {a, b} that accepts strings with at least two b's "
        'AND that do NOT contain "aba" as a substring.',
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n2 = C
      n3 = D
      n4 = dead
      n0 = (220.0, 360.0)
      n1 = (500.0, 260.0)
      n2 = (500.0, 460.0)
      n3 = (820.0, 360.0)
      n4 = (820.0, 580.0)
      n3 is accepted
      n0 to n1 = a
      n0 to n2 = b
      n1 to n3 = b
      n1 to n1 = a
      n2 to n3 = b
      n2 to n1 = a
      n3 to n4 = a
      n3 to n3 = b
      n4 to n4 = a,b
      l1(a) loop angle = -1.5708
      l5(b) loop angle = -1.5708
      l8(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dfa_contains_aab'),
    x: 0.46,
    y: 0.35,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 10 — EXACTLY ONE 0, DFA + NFA  (x ≈ 0.51)
  //  exactly one 0 NFA ← at-least-2-bs NFA
  //  exactly one 0 DFA ← at-least-2-bs DFA
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('dsl_at_least_two_b_not_aba_nfa'),
    x: 0.51,
    y: 0.65,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'0', '1'},
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
    unlockRule: RequireLevel('dsl_at_least_two_b_not_aba_dfa'),
    x: 0.51,
    y: 0.35,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 11 — NO CONSECUTIVE Bs, DFA + NFA  (x ≈ 0.56)
  //  no consec bs NFA ← exactly one 0 NFA
  //  no consec bs DFA ← exactly one 0 DFA
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'dsl_no_consec_b_nfa',
    title: "No Consecutive b's (NFA)",
    description:
        "Build an NFA over {a, b} that accepts all strings containing no two consecutive b's.",
    svgAsset: '',
    dsl: '''
      n0 = A
      n1 = B
      n0 = (420.0, 360.0)
      n1 = (780.0, 360.0)
      n0 is accepted
      n1 is accepted
      n0 to n1 = b
      n0 to n0 = a
      n1 to n0 = a
      l0(a) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('dsl_exactly_one_0_nfa'),
    x: 0.56,
    y: 0.65,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'a', 'b'},
    tag: 'nfa',
  ),

  GameLevel(
    id: 'dsl_no_consec_b',
    title: "No Consecutive b's (DFA)",
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
    unlockRule: RequireLevel('dsl_exactly_one_0_dfa'),
    x: 0.56,
    y: 0.35,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 12 — PALINDROME BOSS  (x ≈ 0.61)
  //  Requires no consec bs DFA OR no consec bs NFA.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireAny(['dsl_no_consec_b', 'dsl_no_consec_b_nfa']),
    x: 0.61,
    y: 0.50,
    alphabet: {'a', 'b'},
    tag: 'boss',
    isBoss: true,
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 13 — EVEN 0s AND COMPLEMENT  (x ≈ 0.65)
  //  Both require palindrome boss.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('boss_palindrome'),
    x: 0.65,
    y: 0.30,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
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
    unlockRule: RequireLevel('boss_palindrome'),
    x: 0.65,
    y: 0.70,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 14 — BINARY MOD 3  (x ≈ 0.69)
  //  Requires complement OR even 0s.
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
    unlockRule: RequireAny(['dfa_complement', 'dsl_even_0s']),
    x: 0.69,
    y: 0.50,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'0', '1'},
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 15 — BINARY MOD 7 AND MOD 8  (x ≈ 0.73)
  //  Both require mod 3.
  // ═══════════════════════════════════════════════════════════════════════════

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
    x: 0.73,
    y: 0.25,
    alphabet: {'0', '1'},
    tag: 'boss',
    isBoss: true,
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
    unlockRule: RequireLevel('dsl_binary_mod3'),
    x: 0.73,
    y: 0.75,
    alphabet: {'0', '1'},
    tag: 'boss',
    isBoss: true,
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 16 — TUTORIAL: PUSHDOWN AUTOMATA  (x ≈ 0.77)
  //  Requires mod 7 AND mod 8.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_pda',
    title: 'Pushdown Automata',
    description: 'Learn how PDAs use a stack to recognise context-free languages.',
    svgAsset: '',
    unlockRule: RequireAll(['dsl_binary_mod7', 'dsl_binary_mod8']),
    x: 0.77,
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
            '• **read** — the input symbol consumed (**~** means consume nothing)\n'
            '• **pop**  — the stack symbol removed from the top (**~** means pop nothing)\n'
            '• **push** — the stack symbol added on top (**~** means push nothing)\n\n'
            'Example: **"a, ~ | X"** — read "a", don\'t pop, push "X".',
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 18 — HUNGRY CATERPILLAR (NFA + DFA) AND HALT ON Y  (x ≈ 0.81)
  //  Both require PDA tutorial.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('tutorial_pda'),
    x: 0.81,
    y: 0.20,
    requiredAutomatonType: RequiredAutomatonType.nfa,
    alphabet: {'"Green Leaf"', '(others)'},
    tag: 'nfa',
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
    unlockRule: RequireLevel('tutorial_pda'),
    x: 0.81,
    y: 0.80,
    alphabet: {'a', 'b', 'c', '…', 'z'},
    tag: 'fa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 19 — BALANCED PARENTHESES  (x ≈ 0.84)
  //  Requires hungry caterpillar AND halt on y.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireAll(['dsl_caterpillar_nfa', 'dsl_halt_accept_y']),
    x: 0.84,
    y: 0.50,
    alphabet: {'(', ')'},
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 20 — aⁿbⁿ  (x ≈ 0.87)
  //  Requires balanced parentheses.
  // ═══════════════════════════════════════════════════════════════════════════

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
    x: 0.87,
    y: 0.50,
    alphabet: {'a', 'b'},
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 21 — MORE As THAN Bs  (x ≈ 0.89)
  //  Requires aⁿbⁿ.
  // ═══════════════════════════════════════════════════════════════════════════

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
      n0 = (380.0, 360.0)
      n1 = (720.0, 360.0)
      n0 to n0 = a,∅|X
      n0 to n0 = b,X|∅
      n0 to n1 = ∅,X|X
      n1 is accepted
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.pda,
    unlockRule: RequireLevel('pda_anbn'),
    x: 0.89,
    y: 0.50,
    alphabet: {'a', 'b'},
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 22 — aⁿb²ⁿ  (x ≈ 0.91)
  //  Requires more As than Bs.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('pda_more_as'),
    x: 0.91,
    y: 0.50,
    alphabet: {'a', 'b'},
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 23 — PDA BOSS AND PDA PALINDROME  (x ≈ 0.93)
  //  Both require aⁿb²ⁿ.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('pda_an_b2n'),
    x: 0.93,
    y: 0.25,
    tag: 'pda',
    isBoss: true,
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
    unlockRule: RequireLevel('pda_an_b2n'),
    x: 0.93,
    y: 0.75,
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 24 — TUTORIAL: TURING MACHINES  (x ≈ 0.95)
  //  Requires PDA Boss OR PDA Palindrome.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_tm',
    title: 'Turing Machines',
    description: 'Learn the read/write tape model and TM transition format.',
    svgAsset: '',
    unlockRule: RequireAny(['level_2', 'pda_palindrome']),
    x: 0.95,
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
  //  LAYER 25 — ACCEPT ALL TM AND REJECT ALL TM  (x ≈ 0.96)
  //  Both require TM tutorial.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('tutorial_tm'),
    x: 0.96,
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
    unlockRule: RequireLevel('tutorial_tm'),
    x: 0.96,
    y: 0.75,
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 26 — aⁿbⁿ TM  (x ≈ 0.97)
  //  Requires accept all TM AND reject all TM.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireAll(['tm_identity', 'tm_reject_all']),
    x: 0.97,
    y: 0.50,
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 27 — aⁿbⁿcⁿ  (x ≈ 0.975)
  //  Requires aⁿbⁿ TM.
  // ═══════════════════════════════════════════════════════════════════════════

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
    x: 0.975,
    y: 0.50,
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 28 — DOUBLED WORD (ww)  (x ≈ 0.982)
  //  Requires aⁿbⁿcⁿ.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tm_ww',
    title: 'TM: ww (Doubled Word)',
    description:
        'Build a TM that accepts strings of the form ww over {a, b}: '
        'a string that consists of some word w repeated exactly twice '
        '(e.g. "abab", "aabb aabb"). '
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
    unlockRule: RequireLevel('tm_anbncn'),
    x: 0.982,
    y: 0.50,
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 29 — TM PALINDROME  (x ≈ 0.990)
  //  Requires doubled word.
  // ═══════════════════════════════════════════════════════════════════════════

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
    unlockRule: RequireLevel('tm_ww'),
    x: 0.990,
    y: 0.50,
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 26 — TUTORIAL: REGULAR EXPRESSIONS  (x ≈ 1.00)
  //  Requires TM palindrome (last TM level).
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'tutorial_regex',
    title: 'Regular Expressions',
    description: 'Learn the connection between regular expressions and finite automata.',
    svgAsset: '',
    unlockRule: RequireLevel('tm_palindrome'),
    x: 1.00,
    y: 0.50,
    tag: 'tutorial',
    isTutorial: true,
    tutorialSlides: [
      TutorialSlide(
        headline: 'What is a Regular Expression?',
        body: 'A **regular expression** (regex) is a compact notation for describing a '
            'regular language — the same class of languages recognised by DFAs and NFAs.\n\n'
            'Operators used in these puzzles:\n'
            '• **a** — literal symbol "a"\n'
            '• **ab** — concatenation (a then b)\n'
            '• **a+b** — alternation / union (a OR b)\n'
            '• **a*** — Kleene star (zero or more a)\n'
            '• **(…)** — grouping',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Regex ↔ Automaton',
        body: 'Every regular expression describes exactly the same set of strings '
            'as some DFA (and vice versa). This is why they are called *regular* languages.\n\n'
            'This section has two challenge types:\n\n'
            '**Regex → DFA** — You are given a regex and must build a DFA whose language '
            'matches it exactly.\n\n'
            '**DFA → Regex** — You are shown a read-only DFA diagram and must type a '
            'regex that describes the same language.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Notation Reference',
        body: 'The checker uses the following notation:\n\n'
            '• **~** — empty string ε  (e.g. a+~ means "a or nothing")\n'
            '• **∅** — empty language (matches nothing)\n'
            '• **+** — alternation  (a+b means a OR b)\n'
            '• ***** — Kleene star, postfix  (a* = zero or more a)\n'
            '• Concatenation is implicit: **ab** means a then b\n\n'
            'Precedence (high→low): star → concat → union.\n'
            'Use parentheses to override: (a+b)* = any string over {a,b}.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Tips: Regex → DFA',
        body: 'When you see a regex, ask: "what pattern must a string satisfy?"\n\n'
            '• **ab*** — any number of b\'s after exactly one a\n'
            '• **(a+b)*abb** — anything, ending in "abb"\n'
            '• **(ab)*** — alternating pairs: ε, ab, abab, …\n\n'
            'Think about what the machine must *remember*. '
            'Each memory unit (e.g. "last symbol seen") usually becomes a state.',
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        headline: 'Tips: DFA → Regex',
        body: 'To derive a regex from a DFA, try **state elimination**:\n\n'
            '1. Add a super-start → original start and all accept states → super-accept '
            'with ε-transitions.\n'
            '2. Remove inner states one by one, merging their transitions into '
            'regex labels on the remaining edges.\n'
            '3. The final label on the super-start → super-accept edge is your regex.\n\n'
            'In practice, pattern recognition is often faster: '
            'spot self-loops (→ *), linear paths (→ concat), branches (→ +).',
        illustrationType: TutorialIllustration.none,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 27 — REGEX → DFA  (BASIC)  (x ≈ 1.03)
  //  All three require the regex tutorial.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'regex_to_dfa_ab_star',
    title: 'Regex → DFA: ab*',
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    ab*\n\n'
        'Matches "a" followed by any number of b\'s: "a", "ab", "abb", "abbb", …',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
      n2 = dead
      n0 = (320.0, 360.0)
      n1 = (660.0, 360.0)
      n2 = (660.0, 580.0)
      n1 is accepted
      n0 to n1 = a
      n0 to n2 = b
      n1 to n1 = b
      n1 to n2 = a
      n2 to n2 = a,b
      l2(b) loop angle = -1.5708
      l4(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('tutorial_regex'),
    x: 1.03,
    y: 0.20,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.regexToDfa,
    targetRegex: 'ab*',
  ),

  GameLevel(
    id: 'regex_to_dfa_starts_a',
    title: 'Regex → DFA: a(a+b)*',
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    a(a+b)*\n\n'
        'Matches all strings that start with "a": "a", "aa", "ab", "aba", …',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
      n2 = dead
      n0 = (320.0, 360.0)
      n1 = (660.0, 360.0)
      n2 = (660.0, 580.0)
      n1 is accepted
      n0 to n1 = a
      n0 to n2 = b
      n1 to n1 = a,b
      n2 to n2 = a,b
      l2(a,b) loop angle = -1.5708
      l3(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('tutorial_regex'),
    x: 1.03,
    y: 0.50,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.regexToDfa,
    targetRegex: 'a(a+b)*',
  ),

  GameLevel(
    id: 'regex_to_dfa_ends_b',
    title: 'Regex → DFA: (a+b)*b',
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    (a+b)*b\n\n'
        'Matches all strings that end with "b": "b", "ab", "bb", "aab", …',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
      n0 = (400.0, 360.0)
      n1 = (780.0, 360.0)
      n1 is accepted
      n0 to n1 = b
      n0 to n0 = a
      n1 to n0 = a
      n1 to n1 = b
      l0(a) loop angle = -1.5708
      l3(b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireLevel('tutorial_regex'),
    x: 1.03,
    y: 0.80,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.regexToDfa,
    targetRegex: '(a+b)*b',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 28 — REGEX → DFA  (INTERMEDIATE)  (x ≈ 1.06)
  //  Unlock from any level in layer 27.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    id: 'regex_to_dfa_a_or_b_star',
    title: 'Regex → DFA: (a+b)*',
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    (a+b)*\n\n'
        'Matches every string over {a, b} — including the empty string ε.',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n0 = (600.0, 360.0)
      n0 is accepted
      n0 to n0 = a,b
      a,b loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAny(['regex_to_dfa_ab_star', 'regex_to_dfa_starts_a', 'regex_to_dfa_ends_b']),
    x: 1.06,
    y: 0.20,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.regexToDfa,
    targetRegex: '(a+b)*',
  ),

  GameLevel(
    id: 'regex_to_dfa_aba',
    title: 'Regex → DFA: (a+b)*aba(a+b)*',
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    (a+b)*aba(a+b)*\n\n'
        'Matches all strings containing "aba" as a substring.',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
      n2 = q2
      n3 = q3
      n0 = (280.0, 360.0)
      n1 = (580.0, 360.0)
      n2 = (880.0, 360.0)
      n3 = (1180.0, 360.0)
      n3 is accepted
      n0 to n1 = a
      n0 to n0 = b
      n1 to n1 = a
      n1 to n2 = b
      n2 to n3 = a
      n3 to n3 = a,b
      n2 to n0 = b
      l0(b) loop angle = -1.5708
      l2(a) loop angle = -1.5708
      l5(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAny(['regex_to_dfa_ab_star', 'regex_to_dfa_starts_a', 'regex_to_dfa_ends_b']),
    x: 1.06,
    y: 0.50,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.regexToDfa,
    targetRegex: '(a+b)*aba(a+b)*',
  ),

  GameLevel(
    id: 'regex_to_dfa_even_as',
    title: 'Regex → DFA: b*(ab*ab*)*',
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    b*(ab*ab*)*\n\n'
        "Matches all strings with an even number of a's (including zero a's).",
    svgAsset: '',
    dsl: '''
      n0 = even
      n1 = odd
      n0 = (500.0, 360.0)
      n1 = (900.0, 360.0)
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
    unlockRule: RequireAny(['regex_to_dfa_ab_star', 'regex_to_dfa_starts_a', 'regex_to_dfa_ends_b']),
    x: 1.06,
    y: 0.80,
    requiredAutomatonType: RequiredAutomatonType.dfa,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.regexToDfa,
    targetRegex: 'b*(ab*ab*)*',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 29 — DFA → REGEX  (BASIC)  (x ≈ 1.09)
  //  Unlock from any level in layer 28.
  // ═══════════════════════════════════════════════════════════════════════════

  /// DFA accepts exactly "a".  Canonical answer: a
  GameLevel(
    id: 'dfa_to_regex_single_a',
    title: 'DFA → Regex: Accept "a"',
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts only the single-character string "a".',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
      n2 = dead
      n0 = (320.0, 360.0)
      n1 = (660.0, 360.0)
      n2 = (660.0, 580.0)
      n1 is accepted
      n0 to n1 = a
      n0 to n2 = b
      n1 to n2 = a,b
      n2 to n2 = a,b
      l3(a,b) loop angle = -1.5708
      l2(a,b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAny(['regex_to_dfa_a_or_b_star', 'regex_to_dfa_aba', 'regex_to_dfa_even_as']),
    x: 1.09,
    y: 0.20,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.dfaToRegex,
    targetRegex: 'a',
  ),

  /// DFA accepts strings ending in "b".  Canonical answer: (a+b)*b
  GameLevel(
    id: 'dfa_to_regex_ends_b',
    title: 'DFA → Regex: Ends with b',
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts all strings over {a, b} that end with "b".',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
      n0 = (400.0, 360.0)
      n1 = (780.0, 360.0)
      n1 is accepted
      n0 to n1 = b
      n0 to n0 = a
      n1 to n0 = a
      n1 to n1 = b
      l0(a) loop angle = -1.5708
      l3(b) loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    automataMode: AutomataMode.ndfa,
    unlockRule: RequireAny(['regex_to_dfa_a_or_b_star', 'regex_to_dfa_aba', 'regex_to_dfa_even_as']),
    x: 1.09,
    y: 0.50,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.dfaToRegex,
    targetRegex: '(a+b)*b',
  ),

  /// DFA accepts strings with even number of a's.  Canonical answer: b*(ab*ab*)*
  GameLevel(
    id: 'dfa_to_regex_even_as',
    title: "DFA → Regex: Even a's",
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        "This DFA accepts all strings over {a, b} with an even number of a's.",
    svgAsset: '',
    dsl: '''
      n0 = even
      n1 = odd
      n0 = (500.0, 360.0)
      n1 = (900.0, 360.0)
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
    unlockRule: RequireAny(['regex_to_dfa_a_or_b_star', 'regex_to_dfa_aba', 'regex_to_dfa_even_as']),
    x: 1.09,
    y: 0.80,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.dfaToRegex,
    targetRegex: 'b*(ab*ab*)*',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 30 — DFA → REGEX  (INTERMEDIATE)  (x ≈ 1.12)
  //  Unlock from any level in layer 29.
  // ═══════════════════════════════════════════════════════════════════════════

  /// DFA accepts strings starting with "ab".  Canonical answer: ab(a+b)*
  GameLevel(
    id: 'dfa_to_regex_starts_ab',
    title: 'DFA → Regex: Starts with ab',
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts all strings over {a, b} that start with "ab".',
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
      n2 = q2
      n3 = dead
      n0 = (240.0, 360.0)
      n1 = (560.0, 360.0)
      n2 = (880.0, 360.0)
      n3 = (560.0, 600.0)
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
    unlockRule: RequireAny(['dfa_to_regex_single_a', 'dfa_to_regex_ends_b', 'dfa_to_regex_even_as']),
    x: 1.12,
    y: 0.20,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.dfaToRegex,
    targetRegex: 'ab(a+b)*',
  ),

  /// DFA accepts strings with no consecutive b's.  Canonical answer: a*(ba+)*b?
  GameLevel(
    id: 'dfa_to_regex_no_consec_b',
    title: "DFA → Regex: No Consecutive b's",
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        "This DFA accepts all strings over {a, b} containing no two consecutive b's.",
    svgAsset: '',
    dsl: '''
      n0 = q0
      n1 = q1
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
    unlockRule: RequireAny(['dfa_to_regex_single_a', 'dfa_to_regex_ends_b', 'dfa_to_regex_even_as']),
    x: 1.12,
    y: 0.50,
    alphabet: {'a', 'b'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.dfaToRegex,
    targetRegex: 'a*(ba+)*b?',
  ),

  /// DFA accepts binary strings with even number of 0s.  Canonical answer: 1*(01*01*)*
  GameLevel(
    id: 'dfa_to_regex_binary_mod2',
    title: 'DFA → Regex: Even 0s',
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts binary strings over {0, 1} with an even number of 0s.',
    svgAsset: '',
    dsl: '''
      n0 = even
      n1 = odd
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
    unlockRule: RequireAny(['dfa_to_regex_single_a', 'dfa_to_regex_ends_b', 'dfa_to_regex_even_as']),
    x: 1.12,
    y: 0.80,
    alphabet: {'0', '1'},
    tag: 'regex',
    puzzleVariant: PuzzleVariant.dfaToRegex,
    targetRegex: '1*(01*01*)*',
  ),

];

/// Convenience map for O(1) lookup by id.
final Map<String, GameLevel> kLevelById = {
  for (final l in kAllLevels) l.id: l,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Layer Constraint Validator
//
//  Enforces three layout rules for kAllLevels.  Call [validate] (or use the
//  [kLayerConstraintErrors] shortcut) in an assert at app startup — e.g. in
//  main():
//
//    assert(() {
//      final errors = LayerConstraintValidator.validate(kAllLevels);
//      if (errors.isNotEmpty) {
//        throw StateError('Layer constraint violations:\n${errors.join('\n')}');
//      }
//      return true;
//    }());
//
//  RULES
//  ─────
//  1. TUTORIAL EXCLUSIVITY — a layer that contains a tutorial must contain
//     ONLY that tutorial (no other level of any kind).
//
//  2. BOSS EXCLUSIVITY — a layer that contains at least one boss may contain
//     ONLY boss levels (no regular levels and no tutorials mixed in).
//
//  3. BOSS CAP — a boss-only layer may contain AT MOST 2 boss levels.
//
//  4. NORMAL CAP — a regular (non-tutorial, non-boss) layer may contain
//     AT MOST 4 levels.
//
//  "Layer" is determined by the same topological-sort logic used by
//  [_computeLayersFromDeps] in level_select_screen.dart.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class LayerConstraintValidator {
  /// Returns a list of human-readable error strings.  Empty means all good.
  static List<String> validate(List<GameLevel> levels) {
    final layerById = _computeLayers(levels);
    final Map<int, List<GameLevel>> byLayer = {};
    for (final l in levels) {
      byLayer.putIfAbsent(layerById[l.id]!, () => []).add(l);
    }

    final errors = <String>[];

    for (final entry in byLayer.entries) {
      final layerIdx = entry.key;
      final members = entry.value;

      final tutorials = members.where((l) => l.isTutorial).toList();
      final bosses    = members.where((l) => l.isBoss).toList();
      final regular   = members.where((l) => !l.isTutorial && !l.isBoss).toList();
      final ids       = members.map((l) => '"${l.id}"').join(', ');

      // Rule 1 — tutorial exclusivity
      if (tutorials.isNotEmpty && members.length > 1) {
        errors.add(
          'Layer $layerIdx: tutorial "${tutorials.first.id}" must be alone, '
          'but shares the layer with ${members.length - 1} other level(s): $ids',
        );
      }

      // Rule 2 — boss exclusivity (bosses and regular levels cannot mix)
      if (bosses.isNotEmpty && regular.isNotEmpty) {
        errors.add(
          'Layer $layerIdx: boss level(s) ${bosses.map((l) => '"${l.id}"').join(', ')} '
          'share a layer with non-boss level(s) ${regular.map((l) => '"${l.id}"').join(', ')}. '
          'A boss layer may only contain boss levels.',
        );
      }

      // Rule 3 — boss cap
      if (bosses.length > 2) {
        errors.add(
          'Layer $layerIdx: contains ${bosses.length} boss levels '
          '(${bosses.map((l) => '"${l.id}"').join(', ')}), '
          'but the maximum is 2.',
        );
      }

      // Rule 4 — normal layer cap
      if (tutorials.isEmpty && bosses.isEmpty && members.length > 4) {
        errors.add(
          'Layer $layerIdx: contains ${members.length} regular levels '
          '($ids), but the maximum is 4.',
        );
      }
    }

    return errors;
  }

  // ── Internal: same topological-sort as level_select_screen.dart ─────────────

  static Map<String, int> _computeLayers(List<GameLevel> levels) {
    List<String> _depsOf(UnlockRule rule) {
      if (rule is AlwaysUnlocked) return [];
      if (rule is RequireLevel) return [rule.levelId];
      if (rule is RequireAll) return rule.levelIds;
      if (rule is RequireAny) return rule.levelIds;
      if (rule is RequireExpression) return rule.children.expand(_depsOf).toList();
      return [];
    }

    final Map<String, List<String>> adj = {for (final l in levels) l.id: []};
    final Map<String, int> indeg = {for (final l in levels) l.id: 0};

    for (final l in levels) {
      for (final d in _depsOf(l.unlockRule)) {
        if (!adj.containsKey(d)) continue;
        adj[d] = [...adj[d]!, l.id];
        indeg[l.id] = indeg[l.id]! + 1;
      }
    }

    final List<String> q = [];
    final Map<String, int> layer = {for (final l in levels) l.id: 0};
    for (final id in indeg.keys) {
      if (indeg[id] == 0) q.add(id);
    }

    while (q.isNotEmpty) {
      final cur = q.removeAt(0);
      for (final next in adj[cur]!) {
        final candidate = layer[cur]! + 2;
        if (candidate > layer[next]!) layer[next] = candidate;
        indeg[next] = indeg[next]! - 1;
        if (indeg[next] == 0) q.add(next);
      }
    }

    int maxAssigned = layer.values.fold(0, (a, b) => a > b ? a : b);
    for (final id in indeg.keys) {
      if (indeg[id]! > 0) {
        maxAssigned += 1;
        layer[id] = maxAssigned;
      }
    }
    return layer;
  }
}

/// Shortcut: returns validation error strings for [kAllLevels].
/// Use in an assert at startup — empty list means all constraints pass.
List<String> get kLayerConstraintErrors =>
    LayerConstraintValidator.validate(kAllLevels);

// ─────────────────────────────────────────────────────────────────────────────
//  Tag colour palette used by the neural-network level map
// ─────────────────────────────────────────────────────────────────────────────

/// Default tag colors when no [AppThemeNotifier] is available.
Color levelTagColor(String? tag) => AppThemeData.defaults().tagColor(tag);