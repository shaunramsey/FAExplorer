import 'dialogs/equivalence_dialog.dart' show RequiredAutomatonType;
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

import 'widgets/automata_drawer.dart' show AutomataMode;

// ─────────────────────────────────────────────────────────────────────────────
//  Unlock rule AST
// ─────────────────────────────────────────────────────────────────────────────

abstract class UnlockRule {
  // const constructor: every concrete subclass below is itself const, so an
  // UnlockRule literal (e.g. RequireLevel('x')) can be used directly inside
  // the const kAllLevels list without allocating at runtime.
  const UnlockRule();

  /// Returns true if [completedIds] satisfies this rule.
  // Abstract — no body. Each subclass supplies its own gating logic against
  // the caller's set of completed level ids.
  bool isSatisfied(Set<String> completedIds);

  /// A short human-readable description for the UI.
  // Abstract — used e.g. by a locked level card's tooltip to explain what
  // still needs to be done to unlock it.
  String describe();
}

/// Always unlocked — entry-point levels.
class AlwaysUnlocked extends UnlockRule {
  const AlwaysUnlocked();

  @override
  // Ignores completedIds entirely — every level using this rule is unlocked
  // regardless of player progress. Used for the very first tutorial/level.
  bool isSatisfied(Set<String> completedIds) => true;

  @override
  // Static string; no level-title interpolation needed since there's no
  // prerequisite to name.
  String describe() => 'Available from the start';
}

/// Requires a single level to be completed.
class RequireLevel extends UnlockRule {
  // The id of the one prerequisite level (matches GameLevel.id).
  final String levelId;
  const RequireLevel(this.levelId);

  @override
  // Satisfied iff the prerequisite id is present in the completed set.
  bool isSatisfied(Set<String> completedIds) => completedIds.contains(levelId);

  @override
  String describe() {
    // Look up the human-readable title for levelId; fall back to the raw id
    // string itself if the id doesn't resolve (e.g. a typo in level data,
    // or the referenced level was since removed) so describe() never throws.
    final title = kLevelById[levelId]?.title ?? levelId;
    return 'Complete "$title" first';
  }
}

/// Requires ALL listed levels to be completed (AND gate).
class RequireAll extends UnlockRule {
  // Ids of every prerequisite level; order doesn't matter for evaluation.
  final List<String> levelIds;
  const RequireAll(this.levelIds);

  @override
  // .every(...) short-circuits on the first missing id, so this is
  // satisfied only when EVERY entry in levelIds is already completed.
  bool isSatisfied(Set<String> completedIds) =>
      levelIds.every(completedIds.contains);

  @override
  String describe() {
    // Same fallback-to-raw-id behaviour as RequireLevel.describe(), applied
    // per entry, then joined into a single comma-separated list.
    final titles = levelIds.map((id) => kLevelById[id]?.title ?? id).join(', ');
    return 'Complete all of: $titles';
  }
}

/// Requires AT LEAST ONE listed level to be completed (OR gate).
class RequireAny extends UnlockRule {
  // Ids of the alternative prerequisite levels; any single one suffices.
  final List<String> levelIds;
  const RequireAny(this.levelIds);

  @override
  // .any(...) short-circuits on the first match, so this is satisfied as
  // soon as ONE entry in levelIds is completed.
  bool isSatisfied(Set<String> completedIds) =>
      levelIds.any(completedIds.contains);

  @override
  String describe() {
    // Same title-lookup-with-fallback pattern as RequireAll.describe().
    final titles = levelIds.map((id) => kLevelById[id]?.title ?? id).join(', ');
    return 'Complete any of: $titles';
  }
}

/// Arbitrary nested AND/OR expression.
class RequireExpression extends UnlockRule {
  final bool isAnd; // true = AND, false = OR
  // Child rules combined by the isAnd operator above. Children may
  // themselves be RequireExpression instances, allowing arbitrarily deep
  // AND/OR trees (e.g. (A AND B) OR (C AND D)). Not currently used by any
  // entry in kAllLevels — RequireAll/RequireAny cover every case so far —
  // but kept available for future levels with genuinely nested logic.
  final List<UnlockRule> children;

  const RequireExpression({required this.isAnd, required this.children});

  @override
  bool isSatisfied(Set<String> completedIds) {
    // Recurses into each child's own isSatisfied, so nested
    // RequireExpression trees evaluate correctly without special-casing.
    if (isAnd) return children.every((r) => r.isSatisfied(completedIds));
    return children.any((r) => r.isSatisfied(completedIds));
  }

  @override
  String describe() {
    // Parenthesize every child's description and glue them together with
    // the operator word, e.g. "(Complete "A") AND (Complete "B")".
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
  easy, // Scaffolded canvas; requires GameLevel.easyModeNodes to be set.
  hard; // Blank canvas; always available on every level.

  /// Human-readable label used in the UI toggle and page titles.
  String get displayName => switch (this) {
        LevelDifficulty.easy => 'Easy',
        LevelDifficulty.hard => 'Hard',
      };

  bool get isEasy => this == LevelDifficulty.easy; // Convenience boolean check.
  bool get isHard => this == LevelDifficulty.hard; // Convenience boolean check.
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
  buildAutomaton, // Draw-from-scratch mode; default for essentially all levels.
  regexToDfa, // Shown a regex, must build an equivalent DFA.
  dfaToRegex, // Shown a read-only DFA, must type an equivalent regex.
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
    required this.id, // must be unique within this level's easyModeNodes list
    required this.label,
    required this.x,
    required this.y,
    this.isAccept = false, // defaults to a non-accepting plain state
    this.isStart = false, // defaults to no start arrow on this node
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

/// Stores the metadata for one puzzle level, including its title, unlock rule,
/// hidden target machine, and the kind of challenge the player must solve.
class GameLevel {
  /// Unique key for this level. Used for unlockRule references, the
  /// [kLevelById] lookup map, and as the save-progress key.
  final String id;

  /// Level-card title shown in the level-select UI and puzzle-screen header.
  final String title;

  /// Task description shown at the top of the puzzle screen.
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

  /// Gate controlling when this level appears unlocked to the player.
  /// Defaults to [AlwaysUnlocked] via the constructor below.
  final UnlockRule unlockRule;

  /// Position on the neural-network level-select canvas (normalised 0–1).
  final double x; // horizontal position
  final double y; // vertical position

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
    this.dsl = '', // empty means "use svgAsset instead" (see dsl field doc above)
    this.automataMode = AutomataMode.ndfa, // most levels are plain FA levels
    this.requiredAutomatonType, // null = no type restriction
    this.alphabet = const {}, // empty = DFA-completeness check is skipped
    this.unlockRule = const AlwaysUnlocked(), // default: unlocked from the start
    this.x = 0.5, // centered by default if a level omits x/y
    this.y = 0.5,
    this.tag, // null = no special theming/grouping
    this.isTutorial = false,
    this.tutorialSlides = const [], // empty unless isTutorial is true
    this.isBoss = false,
    this.easyModeNodes, // null = easy mode behaves like hard mode
    this.easyModeBypassTypeCheck = false,
    this.puzzleVariant = PuzzleVariant.buildAutomaton, // classic draw-it-yourself mode
    this.targetRegex = '', // only meaningful for the regexToDfa/dfaToRegex variants
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
//    Col 8  x≈0.35   FA PATTERNS   — ends-b-nfa/contains-aba/tilda/complement (4 levels)
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

/// The complete catalog of puzzle levels shown by the level-selection UI.
const List<GameLevel> kAllLevels = [

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 0 — TUTORIAL: HOW TO PLAY  (x ≈ 0.00)
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tutorial_welcome',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'How to Play',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description: 'Learn the basics of the automata canvas.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Always unlocked — available to the player from the start.
    unlockRule: AlwaysUnlocked(),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.00,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tutorial',
    // True → this entry is a slideshow tutorial, not a puzzle; tutorialSlides is shown instead of the drawing canvas.
    isTutorial: true,
    // Slides shown when isTutorial is true (ignored for normal puzzle levels).
    tutorialSlides: [
      TutorialSlide(
        // Slide title.
        headline: 'Welcome!',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'This app teaches you how to build **finite automata**, '
            '**pushdown automata**, and **Turing machines** — '
            'the fundamental models of computation.\n\n'
            'Each level asks you to build an automaton that matches a target language. '
            'Follow these tutorials first to learn the tools, then dive in!',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Adding States',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: '**Double-tap** on any empty area of the canvas to create a new state (circle).\n\n'
            'States represent positions your machine can be in while reading input. '
            'You can drag states around to arrange your diagram.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.addNode,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Drawing Transitions',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Hold **Shift** and drag from one state to another to draw a transition arrow.\n\n'
            'After drawing, **tap the label** on the arrow to set which input symbol it reads '
            '(e.g. "a", "b", "0", "1"). '
            'A single arrow can carry multiple symbols — separate them with commas.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.addTransition,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Accept States',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'A state shown with a **double ring** is an accepting state — '
            'the machine accepts the input if it finishes in one of these.\n\n'
            'To make a state accepting: **tap it** to open its menu, then toggle **"Accept"**.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.setAccepting,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'The Start Arrow',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Every automaton needs exactly **one start state** — the state it begins in.\n\n'
            'Drag the floating start arrow onto a state to set it as the start. '
            'If no start arrow is visible, use the **toolbar** to place one.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.setStartArrow,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Deleting Things',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Made a mistake? Use the **trash-can** button in the toolbar to enter delete mode.\n\n'
            'In delete mode, **tap** any state or transition arrow to remove it. '
            'Tap the trash-can again to exit delete mode.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.deleteMode,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Checking Your Answer',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'When you think your automaton is correct, tap **"Check"** in the top-right corner.\n\n'
            'The app will test your machine against the target language. '
            'If they match, the level is complete! If not, you\'ll see a **counterexample** — '
            'a string your machine handles differently from the target.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.checkAnswer,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 1 — ACCEPT "a"  (x ≈ 0.04)
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'intro_accept_a',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Accept "a"',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an automaton that accepts exactly the string "a" and rejects everything else.\n'
        'This is your starting point — all other levels unlock from here.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (484.0, 380.0)          Canvas position of n0 in the level-editor layout: x=484.0, y=380.0.
    //   n1 = (784.0, 380.0)          Canvas position of n1 in the level-editor layout: x=784.0, y=380.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_welcome'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.04,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'intro',
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a'},
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 2 — TUTORIAL: DFA vs NFA  (x ≈ 0.08)
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tutorial_dfa_vs_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'DFA vs NFA',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description: 'Understand the difference between deterministic and nondeterministic automata.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('intro_accept_a'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.08,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tutorial',
    // True → this entry is a slideshow tutorial, not a puzzle; tutorialSlides is shown instead of the drawing canvas.
    isTutorial: true,
    // Slides shown when isTutorial is true (ignored for normal puzzle levels).
    tutorialSlides: [
      TutorialSlide(
        // Slide title.
        headline: 'Two Kinds of Automaton',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Levels in this game are tagged **DFA** or **NFA** (or neither, for bosses).\n\n'
            '• A **DFA** (Deterministic Finite Automaton) must have exactly one transition per symbol per state.\n'
            '• An **NFA** (Nondeterministic Finite Automaton) can have zero, one, or many transitions for the same symbol.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.dfaVsNfa,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'DFA Rules',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'For a valid DFA over alphabet {a, b}:\n\n'
            '1. Every state must have **exactly one** outgoing transition for each symbol.\n'
            '2. No ~ (tilda / free-jump) transitions are allowed.\n'
            '3. There must be exactly **one start state**.\n\n'
            'If your submission violates any of these, the checker will tell you exactly which states are the problem.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'NFA Rules',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'An NFA is more flexible — it **may** have:\n\n'
            '• Multiple outgoing arrows for the **same** symbol from one state\n'
            '• **~-transitions** (free jumps, drawn as arrows with no label)\n'
            '• States with **no** outgoing arrow for some symbol\n\n'
            'An NFA accepts a string if **any** path through the machine leads to an accept state.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'The "." (dot) Symbol',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'A transition labelled **"."** matches **any single symbol** from the alphabet.\n\n'
            'This is a shorthand that saves you drawing one arrow per symbol. '
            'For example, a self-loop "." on a state means "stay here for any symbol".',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'tilda (~) Transitions',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'An **~-transition** (drawn without a label) is a free jump — '
            'the machine moves to the next state without consuming any input.\n\n'
            'In the canvas, draw an arrow between two states and **clear the label** to create an ~-transition. '
            'Only NFAs may use these.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.epsilonTransition,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 3 — BASICS: Only ∅ / Accept Everything, DFA + NFA  (x ≈ 0.12)
  //  All four unlock from tutorial_dfa_vs_nfa.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_only_empty_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Only ∅ (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA that accepts only the empty string ∅ and rejects every non-empty input.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n0 = (607.3, 408.0)          Canvas position of n0 in the level-editor layout: x=607.3, y=408.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
    dsl: '''
      n0 = A
      n0 = (607.3, 408.0)
      n0 is accepted
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.12,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.20,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_accepts_everything_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Accept Everything (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a two-state NFA that uses a free ~-jump to accept every string. '
        'Hint: an ~-transition (no label) is a "free jump" to another state.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (734.0, 447.3)          Canvas position of n0 in the level-editor layout: x=734.0, y=447.3.
    //   n1 = (1022.0, 468.7)         Canvas position of n1 in the level-editor layout: x=1022.0, y=468.7.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1                     ε-transition (free jump, consumes no input): n0 → n1.
    //   n1 to n1 = .                 Transition n1 --.--> n1  (fires on "." (matches any single symbol in the alphabet)).
    //   . loop angle = -1.5708       Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "." (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.12,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.40,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_only_empty_dfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Only ∅ (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA that accepts only the empty string ∅. '
        'Hint: use "." (dot) to mean "every symbol in the alphabet".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (765.3, 365.3)          Canvas position of n0 in the level-editor layout: x=765.3, y=365.3.
    //   n1 = (1080.7, 360.7)         Canvas position of n1 in the level-editor layout: x=1080.7, y=360.7.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n1 = .                 Transition n0 --.--> n1  (fires on "." (matches any single symbol in the alphabet)).
    //   n1 to n1 = .                 Transition n1 --.--> n1  (fires on "." (matches any single symbol in the alphabet)).
    //   l1(.) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled ".").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.12,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.60,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'.'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_accepts_everything',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Accept Everything (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA that accepts every string (including ∅). '
        'Use "." to represent the entire alphabet.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n0 = (734.0, 447.3)          Canvas position of n0 in the level-editor layout: x=734.0, y=447.3.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n0 = .                 Transition n0 --.--> n0  (fires on "." (matches any single symbol in the alphabet)).
    //   . loop angle = -1.5708       Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "." (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
    dsl: '''
      n0 = A
      n0 = (734.0, 447.3)
      n0 is accepted
      n0 to n0 = .
      . loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_dfa_vs_nfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.12,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.80,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'.'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 4 — STARTS WITH "a" / ENDS WITH "b", DFA + NFA  (x ≈ 0.18)
  //  NFA pair requires Only ∅ NFA AND Accept Everything NFA.
  //  DFA pair requires Only ∅ DFA AND Accept Everything DFA.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'nfa_starts_a',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Starts with "a" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {a, b} that accepts all strings that start with "a".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (400.0, 360.0)          Canvas position of n0 in the level-editor layout: x=400.0, y=360.0.
    //   n1 = (760.0, 360.0)          Canvas position of n1 in the level-editor layout: x=760.0, y=360.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n1 = a,b               Transition n1 --a,b--> n1  (fires on symbols a,b).
    //   a,b loop angle = -1.5708     Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked only after the player has completed ALL of the listed levels (AND gate).
    unlockRule: RequireAll(['dsl_only_empty_nfa', 'dsl_accepts_everything_nfa']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.18,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.15,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
    // True → in easy mode, skip the requiredAutomatonType check entirely (any FA type is accepted); hard mode still enforces it.
    easyModeBypassTypeCheck: true,
    // Pre-placed state nodes for easy-mode scaffolding — the player only needs to draw transitions between them; null/absent means easy mode behaves like hard mode.
    easyModeNodes: [
      // Pre-placed easy-mode node "n0" labeled "A" (start state); GamePuzzleScreen seeds it onto the canvas before the player's first move.
      EasyModeNode(id: 'n0', label: 'A', x: 400.0, y: 360.0, isStart: true),
      // Pre-placed easy-mode node "n1" labeled "B" (accepting state); GamePuzzleScreen seeds it onto the canvas before the player's first move.
      EasyModeNode(id: 'n1', label: 'B', x: 760.0, y: 360.0, isAccept: true),
    ],
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'nfa_ends_b',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends with "b" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {a, b} that accepts all strings that end with "b".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (432.7, 360.0)          Canvas position of n0 in the level-editor layout: x=432.7, y=360.0.
    //   n1 = (759.3, 360.0)          Canvas position of n1 in the level-editor layout: x=759.3, y=360.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n0 = a,b               Transition n0 --a,b--> n0  (fires on symbols a,b).
    //   n0 to n1 = b                 Transition n0 --b--> n1  (fires on symbol "b").
    //   a,b loop angle = -1.5708     Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked only after the player has completed ALL of the listed levels (AND gate).
    unlockRule: RequireAll(['dsl_only_empty_nfa', 'dsl_accepts_everything_nfa']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.18,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.35,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_starts_a',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Starts with "a" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} that accepts all strings that start with "a". '
        'Every state must handle both symbols.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = dead                    Declares node n2 with display label "dead".
    //   n0 = (320.0, 360.0)          Canvas position of n0 in the level-editor layout: x=320.0, y=360.0.
    //   n1 = (660.0, 360.0)          Canvas position of n1 in the level-editor layout: x=660.0, y=360.0.
    //   n2 = (660.0, 600.0)          Canvas position of n2 in the level-editor layout: x=660.0, y=600.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n2 = b                 Transition n0 --b--> n2  (fires on symbol "b").
    //   n1 to n1 = a,b               Transition n1 --a,b--> n1  (fires on symbols a,b).
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   l2(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "a,b").
    //   l3(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked only after the player has completed ALL of the listed levels (AND gate).
    unlockRule: RequireAll(['dsl_only_empty_dfa', 'dsl_accepts_everything']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.18,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.65,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_ends_b_dfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends with "b" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} that accepts all strings ending in "b". '
        'This is the deterministic version — every state needs transitions for both a and b.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (513.3, 335.3)          Canvas position of n0 in the level-editor layout: x=513.3, y=335.3.
    //   n1 = (862.7, 218.7)          Canvas position of n1 in the level-editor layout: x=862.7, y=218.7.
    //   n2 = (845.3, 522.0)          Canvas position of n2 in the level-editor layout: x=845.3, y=522.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n2 = b                 Transition n0 --b--> n2  (fires on symbol "b").
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n1 = a                 Transition n1 --a--> n1  (fires on symbol "a").
    //   n2 to n2 = b                 Transition n2 --b--> n2  (fires on symbol "b").
    //   n2 to n1 = a                 Transition n2 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   l0(b) curve = -22.0          Rendering hint: curvature/bow (-22.0px) for transition line l0 (labeled "b"), which connects two distinct states.
    //   l1(a) curve = 24.4           Rendering hint: curvature/bow (24.4px) for transition line l1 (labeled "a"), which connects two distinct states.
    //   l4(a) curve = -38.6          Rendering hint: curvature/bow (-38.6px) for transition line l4 (labeled "a"), which connects two distinct states.
    //   l5(b) curve = -72.2          Rendering hint: curvature/bow (-72.2px) for transition line l5 (labeled "b"), which connects two distinct states.
    //   l2(a) loop angle = -0.5312   Rendering hint: self-loop arc angle (-0.5312 rad) for transition line l2 (labeled "a").
    //   l3(b) loop angle = -0.3351   Rendering hint: self-loop arc angle (-0.3351 rad) for transition line l3 (labeled "b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked only after the player has completed ALL of the listed levels (AND gate).
    unlockRule: RequireAll(['dsl_only_empty_dfa', 'dsl_accepts_everything']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.18,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.85,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
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
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_starts_ab',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Starts with "ab" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} that accepts all strings that begin with "ab".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = dead                    Declares node n3 with display label "dead".
    //   n0 = (300.0, 360.0)          Canvas position of n0 in the level-editor layout: x=300.0, y=360.0.
    //   n1 = (620.0, 360.0)          Canvas position of n1 in the level-editor layout: x=620.0, y=360.0.
    //   n2 = (940.0, 360.0)          Canvas position of n2 in the level-editor layout: x=940.0, y=360.0.
    //   n3 = (620.0, 600.0)          Canvas position of n3 in the level-editor layout: x=620.0, y=600.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n3 = b                 Transition n0 --b--> n3  (fires on symbol "b").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n1 to n3 = a                 Transition n1 --a--> n3  (fires on symbol "a").
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   l4(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a,b").
    //   l5(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dfa_starts_a'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.24,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.10,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'nfa_starts_ab',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Starts with "ab" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {a, b} that accepts all strings that begin with "ab".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (300.0, 360.0)          Canvas position of n0 in the level-editor layout: x=300.0, y=360.0.
    //   n1 = (620.0, 360.0)          Canvas position of n1 in the level-editor layout: x=620.0, y=360.0.
    //   n2 = (940.0, 360.0)          Canvas position of n2 in the level-editor layout: x=940.0, y=360.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   a,b loop angle = -1.5708     Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('nfa_starts_a'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.24,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.30,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_ends_ab',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends with "ab" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} that accepts all strings ending in "ab".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (360.0, 340.0)          Canvas position of n0 in the level-editor layout: x=360.0, y=340.0.
    //   n1 = (680.0, 340.0)          Canvas position of n1 in the level-editor layout: x=680.0, y=340.0.
    //   n2 = (1000.0, 340.0)         Canvas position of n2 in the level-editor layout: x=1000.0, y=340.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n0 = b                 Transition n0 --b--> n0  (fires on symbol "b").
    //   n1 to n1 = a                 Transition n1 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n1 = a                 Transition n2 --a--> n1  (fires on symbol "a").
    //   n2 to n0 = b                 Transition n2 --b--> n0  (fires on symbol "b").
    //   l0(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "b").
    //   l2(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "a").
    //   l4(a) curve = -60.0          Rendering hint: curvature/bow (-60.0px) for transition line l4 (labeled "a"), which connects two distinct states.
    //   l5(b) curve = -60.0          Rendering hint: curvature/bow (-60.0px) for transition line l5 (labeled "b"), which connects two distinct states.
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_ends_b_dfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.24,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.55,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'nfa_ends_ab',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends with "ab" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {a, b} that accepts all strings ending in "ab".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (360.0, 340.0)          Canvas position of n0 in the level-editor layout: x=360.0, y=340.0.
    //   n1 = (680.0, 340.0)          Canvas position of n1 in the level-editor layout: x=680.0, y=340.0.
    //   n2 = (1000.0, 340.0)         Canvas position of n2 in the level-editor layout: x=1000.0, y=340.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n0 = a,b               Transition n0 --a,b--> n0  (fires on symbols a,b).
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   a,b loop angle = -1.5708     Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('nfa_ends_b'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.24,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.75,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
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
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_starts_abc',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Starts with "abc" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b, c} that accepts all strings that begin with "abc".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = dead                    Declares node n4 with display label "dead".
    //   n0 = (220.0, 360.0)          Canvas position of n0 in the level-editor layout: x=220.0, y=360.0.
    //   n1 = (480.0, 360.0)          Canvas position of n1 in the level-editor layout: x=480.0, y=360.0.
    //   n2 = (740.0, 360.0)          Canvas position of n2 in the level-editor layout: x=740.0, y=360.0.
    //   n3 = (1000.0, 360.0)         Canvas position of n3 in the level-editor layout: x=1000.0, y=360.0.
    //   n4 = (600.0, 580.0)          Canvas position of n4 in the level-editor layout: x=600.0, y=580.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n4 = b,c               Transition n0 --b,c--> n4  (fires on symbols b,c).
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n1 to n4 = a,c               Transition n1 --a,c--> n4  (fires on symbols a,c).
    //   n2 to n3 = c                 Transition n2 --c--> n3  (fires on symbol "c").
    //   n2 to n4 = a,b               Transition n2 --a,b--> n4  (fires on symbols a,b).
    //   n3 to n3 = a,b,c             Transition n3 --a,b,c--> n3  (fires on symbols a,b,c).
    //   n4 to n4 = a,b,c             Transition n4 --a,b,c--> n4  (fires on symbols a,b,c).
    //   l6(a,b,c) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l6 (labeled "a,b,c").
    //   l7(a,b,c) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l7 (labeled "a,b,c").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dfa_starts_ab'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.30,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.10,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b', 'c'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'nfa_starts_abc',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Starts with "abc" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {a, b, c} that accepts all strings that begin with "abc".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n0 = (220.0, 360.0)          Canvas position of n0 in the level-editor layout: x=220.0, y=360.0.
    //   n1 = (480.0, 360.0)          Canvas position of n1 in the level-editor layout: x=480.0, y=360.0.
    //   n2 = (740.0, 360.0)          Canvas position of n2 in the level-editor layout: x=740.0, y=360.0.
    //   n3 = (1000.0, 360.0)         Canvas position of n3 in the level-editor layout: x=1000.0, y=360.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n3 = c                 Transition n2 --c--> n3  (fires on symbol "c").
    //   n3 to n3 = a,b,c             Transition n3 --a,b,c--> n3  (fires on symbols a,b,c).
    //   a,b,c loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b,c" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('nfa_starts_ab'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.30,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.30,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b', 'c'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_ends_abc_dfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends with "abc" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b, c} that accepts all strings ending in "abc". '
        'Every state must handle all three symbols.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n0 = (447.3, 392.0)          Canvas position of n0 in the level-editor layout: x=447.3, y=392.0.
    //   n1 = (694.0, 400.0)          Canvas position of n1 in the level-editor layout: x=694.0, y=400.0.
    //   n2 = (951.3, 404.7)          Canvas position of n2 in the level-editor layout: x=951.3, y=404.7.
    //   n3 = (1161.3, 406.7)         Canvas position of n3 in the level-editor layout: x=1161.3, y=406.7.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n0 = b,c               Transition n0 --b,c--> n0  (fires on symbols b,c).
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n3 = c                 Transition n2 --c--> n3  (fires on symbol "c").
    //   n3 to n1 = a                 Transition n3 --a--> n1  (fires on symbol "a").
    //   n2 to n1 = a                 Transition n2 --a--> n1  (fires on symbol "a").
    //   n3 to n0 = b,c               Transition n3 --b,c--> n0  (fires on symbols b,c).
    //   n2 to n0 = b,c               Transition n2 --b,c--> n0  (fires on symbols b,c).
    //   b curve = 1.7                Rendering hint: curvature/bow (1.7px) for the transition labeled "b".
    //   l4(a) curve = 359.1          Rendering hint: curvature/bow (359.1px) for transition line l4 (labeled "a"), which connects two distinct states.
    //   l5(a) curve = 130.8          Rendering hint: curvature/bow (130.8px) for transition line l5 (labeled "a"), which connects two distinct states.
    //   l6(b,c) curve = -344.8       Rendering hint: curvature/bow (-344.8px) for transition line l6 (labeled "b,c"), which connects two distinct states.
    //   l7(b,c) curve = -236.0       Rendering hint: curvature/bow (-236.0px) for transition line l7 (labeled "b,c"), which connects two distinct states.
    //   l0(b,c) loop angle = 1.7357  Rendering hint: self-loop arc angle (1.7357 rad) for transition line l0 (labeled "b,c").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dfa_ends_ab'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.30,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.55,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b', 'c'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_ends_abc_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends with "abc" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {a, b, c} that accepts all strings ending in "abc".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n0 = (497.3, 348.7)          Canvas position of n0 in the level-editor layout: x=497.3, y=348.7.
    //   n1 = (818.0, 358.7)          Canvas position of n1 in the level-editor layout: x=818.0, y=358.7.
    //   n2 = (1138.7, 361.3)         Canvas position of n2 in the level-editor layout: x=1138.7, y=361.3.
    //   n3 = (1412.0, 370.7)         Canvas position of n3 in the level-editor layout: x=1412.0, y=370.7.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n0 to n0 = a,b,c             Transition n0 --a,b,c--> n0  (fires on symbols a,b,c).
    //   n2 to n3 = c                 Transition n2 --c--> n3  (fires on symbol "c").
    //   a,b,c loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b,c" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('nfa_ends_ab'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.30,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.75,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b', 'c'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
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
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_ends_two_same_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends in 00 or 11 (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {0,1} that accepts strings ending in "00" or "11".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = E                       Declares node n4 with display label "E".
    //   n0 = (604.7, 275.3)          Canvas position of n0 in the level-editor layout: x=604.7, y=275.3.
    //   n1 = (934.7, 190.0)          Canvas position of n1 in the level-editor layout: x=934.7, y=190.0.
    //   n2 = (1212.0, 198.7)         Canvas position of n2 in the level-editor layout: x=1212.0, y=198.7.
    //   n3 = (910.0, 474.7)          Canvas position of n3 in the level-editor layout: x=910.0, y=474.7.
    //   n4 = (1160.7, 511.3)         Canvas position of n4 in the level-editor layout: x=1160.7, y=511.3.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n4 is accepted               n4 is an accepting (double-ring) state.
    //   n0 to n3 = 0                 Transition n0 --0--> n3  (fires on symbol "0").
    //   n3 to n4 = 0                 Transition n3 --0--> n4  (fires on symbol "0").
    //   n0 to n1 = 1                 Transition n0 --1--> n1  (fires on symbol "1").
    //   n1 to n2 = 1                 Transition n1 --1--> n2  (fires on symbol "1").
    //   n2 to n2 = 1                 Transition n2 --1--> n2  (fires on symbol "1").
    //   n4 to n4 = 0                 Transition n4 --0--> n4  (fires on symbol "0").
    //   n0 to n0 = 1,0               Transition n0 --1,0--> n0  (fires on symbols 1,0).
    //   l4(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "1").
    //   l5(0) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "0").
    //   1,0 loop angle = -1.5708     Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "1,0" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_ends_abc_nfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.36,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.10,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_ends_two_same_dfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Ends in 00 or 11 (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {0,1} that accepts strings ending in "00" or "11".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = E                       Declares node n4 with display label "E".
    //   n0 = (403.3, 416.7)          Canvas position of n0 in the level-editor layout: x=403.3, y=416.7.
    //   n1 = (738.7, 293.3)          Canvas position of n1 in the level-editor layout: x=738.7, y=293.3.
    //   n2 = (743.3, 592.7)          Canvas position of n2 in the level-editor layout: x=743.3, y=592.7.
    //   n3 = (1046.7, 426.7)         Canvas position of n3 in the level-editor layout: x=1046.7, y=426.7.
    //   n4 = (1169.3, 650.7)         Canvas position of n4 in the level-editor layout: x=1169.3, y=650.7.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n4 is accepted               n4 is an accepting (double-ring) state.
    //   n4 to n4 = 1                 Transition n4 --1--> n4  (fires on symbol "1").
    //   n4 to n1 = 1                 Transition n4 --1--> n1  (fires on symbol "1").
    //   n2 to n4 = 1                 Transition n2 --1--> n4  (fires on symbol "1").
    //   n0 to n2 = 1                 Transition n0 --1--> n2  (fires on symbol "1").
    //   n0 to n1 = 0                 Transition n0 --0--> n1  (fires on symbol "0").
    //   n1 to n2 = 1                 Transition n1 --1--> n2  (fires on symbol "1").
    //   n2 to n1 = 0                 Transition n2 --0--> n1  (fires on symbol "0").
    //   n1 to n3 = 0                 Transition n1 --0--> n3  (fires on symbol "0").
    //   n3 to n3 = 0                 Transition n3 --0--> n3  (fires on symbol "0").
    //   n3 to n2 = 1                 Transition n3 --1--> n2  (fires on symbol "1").
    //   l1(1) curve = -326.2         Rendering hint: curvature/bow (-326.2px) for transition line l1 (labeled "1"), which connects two distinct states.
    //   l2(1) curve = -71.8          Rendering hint: curvature/bow (-71.8px) for transition line l2 (labeled "1"), which connects two distinct states.
    //   l3(1) curve = -86.5          Rendering hint: curvature/bow (-86.5px) for transition line l3 (labeled "1"), which connects two distinct states.
    //   l4(0) curve = 40.9           Rendering hint: curvature/bow (40.9px) for transition line l4 (labeled "0"), which connects two distinct states.
    //   l5(1) curve = 57.3           Rendering hint: curvature/bow (57.3px) for transition line l5 (labeled "1"), which connects two distinct states.
    //   l6(0) curve = 53.5           Rendering hint: curvature/bow (53.5px) for transition line l6 (labeled "0"), which connects two distinct states.
    //   l0(1) loop angle = 0.4065    Rendering hint: self-loop arc angle (0.4065 rad) for transition line l0 (labeled "1").
    //   l8(0) loop angle = 0.0537    Rendering hint: self-loop arc angle (0.0537 rad) for transition line l8 (labeled "0").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 length = 184.8         Rendering hint: pixel length 184.8 for the start arrow into n0.
    //   to n0 angle = -0.9911, -0.1335 Rendering hint: direction vector (-0.9911, -0.1335) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_ends_abc_dfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.36,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.30,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_contains_aba',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Contains "aba" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} that accepts exactly those strings containing "aba" as a substring.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n0 = (280.0, 360.0)          Canvas position of n0 in the level-editor layout: x=280.0, y=360.0.
    //   n1 = (580.0, 360.0)          Canvas position of n1 in the level-editor layout: x=580.0, y=360.0.
    //   n2 = (880.0, 360.0)          Canvas position of n2 in the level-editor layout: x=880.0, y=360.0.
    //   n3 = (1180.0, 360.0)         Canvas position of n3 in the level-editor layout: x=1180.0, y=360.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n0 = b                 Transition n0 --b--> n0  (fires on symbol "b").
    //   n1 to n1 = a                 Transition n1 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n3 = a                 Transition n2 --a--> n3  (fires on symbol "a").
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   n2 to n0 = b                 Transition n2 --b--> n0  (fires on symbol "b").
    //   l0(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "b").
    //   l2(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "a").
    //   l5(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['dsl_ends_abc_dfa', 'dfa_starts_abc']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.36,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.55,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'nfa_complex',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Contains "aba" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA that accepts exactly those strings over {a, b} that contain "aba" as a substring.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n0 = (280.0, 360.0)          Canvas position of n0 in the level-editor layout: x=280.0, y=360.0.
    //   n1 = (580.0, 360.0)          Canvas position of n1 in the level-editor layout: x=580.0, y=360.0.
    //   n2 = (880.0, 360.0)          Canvas position of n2 in the level-editor layout: x=880.0, y=360.0.
    //   n3 = (1180.0, 360.0)         Canvas position of n3 in the level-editor layout: x=1180.0, y=360.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n0 = a,b               Transition n0 --a,b--> n0  (fires on symbols a,b).
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n3 = a                 Transition n2 --a--> n3  (fires on symbol "a").
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   l0(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a,b").
    //   l4(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['dsl_ends_abc_nfa', 'nfa_starts_abc']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.36,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.75,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 8 — CONTAINS "aab", DFA + NFA  (x ≈ 0.41)
  //  contains aab DFA ← contains aba DFA
  //  contains aab NFA ← contains aba NFA
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_contains_aab',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Contains "aab" (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} that accepts all strings containing "aab" as a substring.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n0 = (300.0, 380.0)          Canvas position of n0 in the level-editor layout: x=300.0, y=380.0.
    //   n1 = (620.0, 380.0)          Canvas position of n1 in the level-editor layout: x=620.0, y=380.0.
    //   n2 = (940.0, 380.0)          Canvas position of n2 in the level-editor layout: x=940.0, y=380.0.
    //   n3 = (1260.0, 380.0)         Canvas position of n3 in the level-editor layout: x=1260.0, y=380.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n0 = b                 Transition n0 --b--> n0  (fires on symbol "b").
    //   n1 to n2 = a                 Transition n1 --a--> n2  (fires on symbol "a").
    //   n1 to n0 = b                 Transition n1 --b--> n0  (fires on symbol "b").
    //   n2 to n3 = b                 Transition n2 --b--> n3  (fires on symbol "b").
    //   n2 to n2 = a                 Transition n2 --a--> n2  (fires on symbol "a").
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   l0(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "b").
    //   l4(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a").
    //   l6(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l6 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dfa_contains_aba'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.41,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.30,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_contains_aab',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Contains "aab" (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an NFA over {a, b} that accepts all strings containing "aab" as a substring.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n0 = (300.0, 380.0)          Canvas position of n0 in the level-editor layout: x=300.0, y=380.0.
    //   n1 = (620.0, 380.0)          Canvas position of n1 in the level-editor layout: x=620.0, y=380.0.
    //   n2 = (940.0, 380.0)          Canvas position of n2 in the level-editor layout: x=940.0, y=380.0.
    //   n3 = (1260.0, 380.0)         Canvas position of n3 in the level-editor layout: x=1260.0, y=380.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n0 = a,b               Transition n0 --a,b--> n0  (fires on symbols a,b).
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = a                 Transition n1 --a--> n2  (fires on symbol "a").
    //   n2 to n3 = b                 Transition n2 --b--> n3  (fires on symbol "b").
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   l0(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a,b").
    //   l4(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('nfa_complex'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.41,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.70,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 9 — AT LEAST 2 Bs AND NOT "aba", DFA + NFA  (x ≈ 0.46)
  //  Both require contains aab (DFA or NFA respectively).
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_at_least_two_b_not_aba_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: "At Least 2 b's & Not \"aba\" (NFA)",
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        "Build an NFA over {a, b} that accepts strings with at least two b's "
        'AND that do NOT contain "aba" as a substring.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = dead                    Declares node n3 with display label "dead".
    //   n0 = (260.0, 360.0)          Canvas position of n0 in the level-editor layout: x=260.0, y=360.0.
    //   n1 = (580.0, 360.0)          Canvas position of n1 in the level-editor layout: x=580.0, y=360.0.
    //   n2 = (900.0, 360.0)          Canvas position of n2 in the level-editor layout: x=900.0, y=360.0.
    //   n3 = (580.0, 580.0)          Canvas position of n3 in the level-editor layout: x=580.0, y=580.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n1 = b                 Transition n0 --b--> n1  (fires on symbol "b").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n0 to n0 = a                 Transition n0 --a--> n0  (fires on symbol "a").
    //   n1 to n1 = a                 Transition n1 --a--> n1  (fires on symbol "a").
    //   n2 to n3 = a                 Transition n2 --a--> n3  (fires on symbol "a").
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   l0(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a").
    //   l2(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "a").
    //   l5(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_contains_aab'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.46,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.65,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_at_least_two_b_not_aba_dfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: "At Least 2 b's & Not \"aba\" (DFA)",
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        "Build a DFA over {a, b} that accepts strings with at least two b's "
        'AND that do NOT contain "aba" as a substring.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = dead                    Declares node n4 with display label "dead".
    //   n0 = (220.0, 360.0)          Canvas position of n0 in the level-editor layout: x=220.0, y=360.0.
    //   n1 = (500.0, 260.0)          Canvas position of n1 in the level-editor layout: x=500.0, y=260.0.
    //   n2 = (500.0, 460.0)          Canvas position of n2 in the level-editor layout: x=500.0, y=460.0.
    //   n3 = (820.0, 360.0)          Canvas position of n3 in the level-editor layout: x=820.0, y=360.0.
    //   n4 = (820.0, 580.0)          Canvas position of n4 in the level-editor layout: x=820.0, y=580.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n2 = b                 Transition n0 --b--> n2  (fires on symbol "b").
    //   n1 to n3 = b                 Transition n1 --b--> n3  (fires on symbol "b").
    //   n1 to n1 = a                 Transition n1 --a--> n1  (fires on symbol "a").
    //   n2 to n3 = b                 Transition n2 --b--> n3  (fires on symbol "b").
    //   n2 to n1 = a                 Transition n2 --a--> n1  (fires on symbol "a").
    //   n3 to n4 = a                 Transition n3 --a--> n4  (fires on symbol "a").
    //   n3 to n3 = b                 Transition n3 --b--> n3  (fires on symbol "b").
    //   n4 to n4 = a,b               Transition n4 --a,b--> n4  (fires on symbols a,b).
    //   l1(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled "a").
    //   l5(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "b").
    //   l8(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l8 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dfa_contains_aab'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.46,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.35,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 10 — EXACTLY ONE 0, DFA + NFA  (x ≈ 0.51)
  //  exactly one 0 NFA ← at-least-2-bs NFA
  //  exactly one 0 DFA ← at-least-2-bs DFA
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_exactly_one_0_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Exactly One 0 (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a compact NFA over {0,1} that accepts strings containing exactly one 0. '
        'Can you do it in just two states?',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (667.3, 421.3)          Canvas position of n0 in the level-editor layout: x=667.3, y=421.3.
    //   n1 = (907.3, 421.3)          Canvas position of n1 in the level-editor layout: x=907.3, y=421.3.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = 1                 Transition n0 --1--> n1  (fires on symbol "1").
    //   n1 to n1 = 0                 Transition n1 --0--> n1  (fires on symbol "0").
    //   n0 to n0 = 0                 Transition n0 --0--> n0  (fires on symbol "0").
    //   l1(0) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled "0").
    //   l2(0) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "0").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_at_least_two_b_not_aba_nfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.51,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.65,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_exactly_one_0_dfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Exactly One 0 (DFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {0,1} that accepts strings containing exactly one 0.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (566.7, 381.3)          Canvas position of n0 in the level-editor layout: x=566.7, y=381.3.
    //   n1 = (866.0, 386.0)          Canvas position of n1 in the level-editor layout: x=866.0, y=386.0.
    //   n2 = (1175.3, 390.0)         Canvas position of n2 in the level-editor layout: x=1175.3, y=390.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = 0                 Transition n0 --0--> n1  (fires on symbol "0").
    //   n1 to n2 = 0                 Transition n1 --0--> n2  (fires on symbol "0").
    //   n2 to n2 = 1,0               Transition n2 --1,0--> n2  (fires on symbols 1,0).
    //   n1 to n1 = 1                 Transition n1 --1--> n1  (fires on symbol "1").
    //   n0 to n0 = 1                 Transition n0 --1--> n0  (fires on symbol "1").
    //   1,0 loop angle = -1.5708     Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "1,0" (resolved by label since it's the only line with that text).
    //   l3(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "1").
    //   l4(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "1").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 length = 186.9         Rendering hint: pixel length 186.9 for the start arrow into n0.
    //   to n0 angle = -0.8246, -0.5657 Rendering hint: direction vector (-0.8246, -0.5657) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_at_least_two_b_not_aba_dfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.51,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.35,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 11 — NO CONSECUTIVE Bs, DFA + NFA  (x ≈ 0.56)
  //  no consec bs NFA ← exactly one 0 NFA
  //  no consec bs DFA ← exactly one 0 DFA
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_no_consec_b_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: "No Consecutive b's (NFA)",
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        "Build an NFA over {a, b} that accepts all strings containing no two consecutive b's.",
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (420.0, 360.0)          Canvas position of n0 in the level-editor layout: x=420.0, y=360.0.
    //   n1 = (780.0, 360.0)          Canvas position of n1 in the level-editor layout: x=780.0, y=360.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = b                 Transition n0 --b--> n1  (fires on symbol "b").
    //   n0 to n0 = a                 Transition n0 --a--> n0  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   l0(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_exactly_one_0_nfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.56,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.65,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_no_consec_b',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: "No Consecutive b's (DFA)",
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        "Build a DFA over {a, b} that accepts all strings containing no two consecutive b's.",
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = dead                    Declares node n2 with display label "dead".
    //   n0 = (400.0, 340.0)          Canvas position of n0 in the level-editor layout: x=400.0, y=340.0.
    //   n1 = (780.0, 340.0)          Canvas position of n1 in the level-editor layout: x=780.0, y=340.0.
    //   n2 = (580.0, 580.0)          Canvas position of n2 in the level-editor layout: x=580.0, y=580.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = b                 Transition n0 --b--> n1  (fires on symbol "b").
    //   n0 to n0 = a                 Transition n0 --a--> n0  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   l0(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a").
    //   l4(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_exactly_one_0_dfa'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.56,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.35,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 12 — PALINDROME BOSS  (x ≈ 0.61)
  //  Requires no consec bs DFA OR no consec bs NFA.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'boss_palindrome',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'FA Boss: Palindrome',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an automaton (any type) that accepts strings over {a, b} that are palindromes of length ≤ 5.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = start                   Declares node n0 with display label "start".
    //   n1 = a                       Declares node n1 with display label "a".
    //   n2 = b                       Declares node n2 with display label "b".
    //   n3 = aa                      Declares node n3 with display label "aa".
    //   n4 = ab                      Declares node n4 with display label "ab".
    //   n5 = ba                      Declares node n5 with display label "ba".
    //   n6 = bb                      Declares node n6 with display label "bb".
    //   n0 = (400.0, 400.0)          Canvas position of n0 in the level-editor layout: x=400.0, y=400.0.
    //   n1 = (700.0, 240.0)          Canvas position of n1 in the level-editor layout: x=700.0, y=240.0.
    //   n2 = (700.0, 560.0)          Canvas position of n2 in the level-editor layout: x=700.0, y=560.0.
    //   n3 = (1000.0, 160.0)         Canvas position of n3 in the level-editor layout: x=1000.0, y=160.0.
    //   n4 = (1000.0, 320.0)         Canvas position of n4 in the level-editor layout: x=1000.0, y=320.0.
    //   n5 = (1000.0, 480.0)         Canvas position of n5 in the level-editor layout: x=1000.0, y=480.0.
    //   n6 = (1000.0, 640.0)         Canvas position of n6 in the level-editor layout: x=1000.0, y=640.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n6 is accepted               n6 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n2 = b                 Transition n0 --b--> n2  (fires on symbol "b").
    //   n1 to n3 = a                 Transition n1 --a--> n3  (fires on symbol "a").
    //   n1 to n4 = b                 Transition n1 --b--> n4  (fires on symbol "b").
    //   n2 to n5 = a                 Transition n2 --a--> n5  (fires on symbol "a").
    //   n2 to n6 = b                 Transition n2 --b--> n6  (fires on symbol "b").
    //   n3 to n3 = a                 Transition n3 --a--> n3  (fires on symbol "a").
    //   n6 to n6 = b                 Transition n6 --b--> n6  (fires on symbol "b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['dsl_no_consec_b', 'dsl_no_consec_b_nfa']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.61,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'boss',
    // True → this is a boss level; LayerConstraintValidator caps boss layers at 2 bosses and forbids mixing bosses with non-boss levels in the same layer.
    isBoss: true,
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 13 — EVEN 0s AND COMPLEMENT  (x ≈ 0.65)
  //  Both require palindrome boss.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_even_0s',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Even 0s',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {0,1} that accepts strings with an even number of 0s. '
        '(Equivalently, binary mod 2 = 0.)',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (504.7, 310.0)          Canvas position of n0 in the level-editor layout: x=504.7, y=310.0.
    //   n1 = (1030.0, 314.0)         Canvas position of n1 in the level-editor layout: x=1030.0, y=314.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n1 = 0                 Transition n0 --0--> n1  (fires on symbol "0").
    //   n1 to n0 = 0                 Transition n1 --0--> n0  (fires on symbol "0").
    //   n0 to n0 = 1                 Transition n0 --1--> n0  (fires on symbol "1").
    //   n1 to n1 = 1                 Transition n1 --1--> n1  (fires on symbol "1").
    //   l0(0) curve = -74.1          Rendering hint: curvature/bow (-74.1px) for transition line l0 (labeled "0"), which connects two distinct states.
    //   l1(0) curve = -72.7          Rendering hint: curvature/bow (-72.7px) for transition line l1 (labeled "0"), which connects two distinct states.
    //   l2(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "1").
    //   l3(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "1").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('boss_palindrome'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.65,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.30,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_complement',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Complement',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        "Build the complement of the \"even a's\" language — accept all strings with an ODD number of a's.",
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = even                    Declares node n0 with display label "even".
    //   n1 = odd                     Declares node n1 with display label "odd".
    //   n0 = (504.0, 360.0)          Canvas position of n0 in the level-editor layout: x=504.0, y=360.0.
    //   n1 = (904.0, 360.0)          Canvas position of n1 in the level-editor layout: x=904.0, y=360.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   n0 to n0 = b                 Transition n0 --b--> n0  (fires on symbol "b").
    //   n1 to n1 = b                 Transition n1 --b--> n1  (fires on symbol "b").
    //   l0(a) curve = -80.0          Rendering hint: curvature/bow (-80.0px) for transition line l0 (labeled "a"), which connects two distinct states.
    //   l1(a) curve = -80.0          Rendering hint: curvature/bow (-80.0px) for transition line l1 (labeled "a"), which connects two distinct states.
    //   l2(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "b").
    //   l3(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('boss_palindrome'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.65,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.70,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 14 — BINARY MOD 3  (x ≈ 0.69)
  //  Requires complement OR even 0s.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_binary_mod3',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Binary Mod 3',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {0,1} that accepts binary strings whose value is '
        'divisible by 3 (i.e. binary mod 3 = 0). '
        'Reading a 0 doubles the current remainder; reading a 1 doubles it and adds 1.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = 0                       Declares node n0 with display label "0".
    //   n1 = 1                       Declares node n1 with display label "1".
    //   n2 = 2                       Declares node n2 with display label "2".
    //   n0 = (538.7, 187.3)          Canvas position of n0 in the level-editor layout: x=538.7, y=187.3.
    //   n1 = (1036.7, 342.0)         Canvas position of n1 in the level-editor layout: x=1036.7, y=342.0.
    //   n2 = (670.0, 578.7)          Canvas position of n2 in the level-editor layout: x=670.0, y=578.7.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n1 = 1                 Transition n0 --1--> n1  (fires on symbol "1").
    //   n1 to n0 = 1                 Transition n1 --1--> n0  (fires on symbol "1").
    //   n0 to n0 = 0                 Transition n0 --0--> n0  (fires on symbol "0").
    //   n1 to n2 = 0                 Transition n1 --0--> n2  (fires on symbol "0").
    //   n2 to n1 = 0                 Transition n2 --0--> n1  (fires on symbol "0").
    //   n2 to n2 = 1                 Transition n2 --1--> n2  (fires on symbol "1").
    //   l0(1) curve = 75.9           Rendering hint: curvature/bow (75.9px) for transition line l0 (labeled "1"), which connects two distinct states.
    //   l1(1) curve = 79.5           Rendering hint: curvature/bow (79.5px) for transition line l1 (labeled "1"), which connects two distinct states.
    //   l3(0) curve = 91.1           Rendering hint: curvature/bow (91.1px) for transition line l3 (labeled "0"), which connects two distinct states.
    //   l4(0) curve = 25.3           Rendering hint: curvature/bow (25.3px) for transition line l4 (labeled "0"), which connects two distinct states.
    //   l2(0) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "0").
    //   l5(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "1").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['dfa_complement', 'dsl_even_0s']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.69,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'dfa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 15 — BINARY MOD 7 AND MOD 8  (x ≈ 0.73)
  //  Both require mod 3.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_binary_mod7',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Binary Mod 7',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {0,1} that accepts binary strings whose value is '
        'divisible by 7 (binary mod 7 = 0). '
        'States 0–6 represent the current remainder.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = 0                       Declares node n0 with display label "0".
    //   n1 = 1                       Declares node n1 with display label "1".
    //   n2 = 2                       Declares node n2 with display label "2".
    //   n3 = 3                       Declares node n3 with display label "3".
    //   n4 = 4                       Declares node n4 with display label "4".
    //   n5 = 5                       Declares node n5 with display label "5".
    //   n6 = 6                       Declares node n6 with display label "6".
    //   n0 = (640.0, 92.6)           Canvas position of n0 in the level-editor layout: x=640.0, y=92.6.
    //   n1 = (1112.0, 196.0)         Canvas position of n1 in the level-editor layout: x=1112.0, y=196.0.
    //   n2 = (1560.0, 282.7)         Canvas position of n2 in the level-editor layout: x=1560.0, y=282.7.
    //   n3 = (250.0, 223.3)          Canvas position of n3 in the level-editor layout: x=250.0, y=223.3.
    //   n4 = (929.3, 422.7)          Canvas position of n4 in the level-editor layout: x=929.3, y=422.7.
    //   n5 = (645.3, 592.7)          Canvas position of n5 in the level-editor layout: x=645.3, y=592.7.
    //   n6 = (303.3, 518.7)          Canvas position of n6 in the level-editor layout: x=303.3, y=518.7.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n1 = 1                 Transition n0 --1--> n1  (fires on symbol "1").
    //   n0 to n0 = 0                 Transition n0 --0--> n0  (fires on symbol "0").
    //   n1 to n2 = 0                 Transition n1 --0--> n2  (fires on symbol "0").
    //   n1 to n3 = 1                 Transition n1 --1--> n3  (fires on symbol "1").
    //   n3 to n6 = 0                 Transition n3 --0--> n6  (fires on symbol "0").
    //   n3 to n0 = 1                 Transition n3 --1--> n0  (fires on symbol "1").
    //   n2 to n5 = 1                 Transition n2 --1--> n5  (fires on symbol "1").
    //   n2 to n4 = 0                 Transition n2 --0--> n4  (fires on symbol "0").
    //   n4 to n1 = 0                 Transition n4 --0--> n1  (fires on symbol "0").
    //   n4 to n2 = 1                 Transition n4 --1--> n2  (fires on symbol "1").
    //   n5 to n3 = 1                 Transition n5 --1--> n3  (fires on symbol "1").
    //   n5 to n4 = 1                 Transition n5 --1--> n4  (fires on symbol "1").
    //   n6 to n5 = 0                 Transition n6 --0--> n5  (fires on symbol "0").
    //   n6 to n6 = 1                 Transition n6 --1--> n6  (fires on symbol "1").
    //   l3(1) curve = 21.0           Rendering hint: curvature/bow (21.0px) for transition line l3 (labeled "1"), which connects two distinct states.
    //   l4(0) curve = -194.4         Rendering hint: curvature/bow (-194.4px) for transition line l4 (labeled "0"), which connects two distinct states.
    //   l5(1) curve = 34.0           Rendering hint: curvature/bow (34.0px) for transition line l5 (labeled "1"), which connects two distinct states.
    //   l6(1) curve = 316.5          Rendering hint: curvature/bow (316.5px) for transition line l6 (labeled "1"), which connects two distinct states.
    //   l7(0) curve = 152.5          Rendering hint: curvature/bow (152.5px) for transition line l7 (labeled "0"), which connects two distinct states.
    //   l8(0) curve = 17.9           Rendering hint: curvature/bow (17.9px) for transition line l8 (labeled "0"), which connects two distinct states.
    //   l9(1) curve = -15.5          Rendering hint: curvature/bow (-15.5px) for transition line l9 (labeled "1"), which connects two distinct states.
    //   l10(1) curve = 15.0          Rendering hint: curvature/bow (15.0px) for transition line l10 (labeled "1"), which connects two distinct states.
    //   l11(1) curve = -59.2         Rendering hint: curvature/bow (-59.2px) for transition line l11 (labeled "1"), which connects two distinct states.
    //   l1(0) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled "0").
    //   l13(1) loop angle = -1.5708  Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l13 (labeled "1").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 length = 150.3         Rendering hint: pixel length 150.3 for the start arrow into n0.
    //   to n0 angle = -0.8423, -0.5390 Rendering hint: direction vector (-0.8423, -0.5390) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_binary_mod3'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.73,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.25,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'boss',
    // True → this is a boss level; LayerConstraintValidator caps boss layers at 2 bosses and forbids mixing bosses with non-boss levels in the same layer.
    isBoss: true,
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_binary_mod8',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Binary Mod 8',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {0,1} that accepts binary strings whose value is '
        'divisible by 8 (binary mod 8 = 0). '
        'States 0–7 represent the current remainder.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = 0                       Declares node n0 with display label "0".
    //   n1 = 1                       Declares node n1 with display label "1".
    //   n2 = 2                       Declares node n2 with display label "2".
    //   n3 = 3                       Declares node n3 with display label "3".
    //   n4 = 4                       Declares node n4 with display label "4".
    //   n5 = 5                       Declares node n5 with display label "5".
    //   n6 = 6                       Declares node n6 with display label "6".
    //   n7 = 7                       Declares node n7 with display label "7".
    //   n0 = (338.0, 209.3)          Canvas position of n0 in the level-editor layout: x=338.0, y=209.3.
    //   n1 = (715.3, 212.0)          Canvas position of n1 in the level-editor layout: x=715.3, y=212.0.
    //   n2 = (432.0, 446.7)          Canvas position of n2 in the level-editor layout: x=432.0, y=446.7.
    //   n3 = (1418.7, 219.3)         Canvas position of n3 in the level-editor layout: x=1418.7, y=219.3.
    //   n4 = (167.3, 640.7)          Canvas position of n4 in the level-editor layout: x=167.3, y=640.7.
    //   n5 = (585.3, 610.0)          Canvas position of n5 in the level-editor layout: x=585.3, y=610.0.
    //   n6 = (870.0, 627.3)          Canvas position of n6 in the level-editor layout: x=870.0, y=627.3.
    //   n7 = (1173.3, 622.0)         Canvas position of n7 in the level-editor layout: x=1173.3, y=622.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n0 = 0                 Transition n0 --0--> n0  (fires on symbol "0").
    //   n0 to n1 = 1                 Transition n0 --1--> n1  (fires on symbol "1").
    //   n1 to n3 = 1                 Transition n1 --1--> n3  (fires on symbol "1").
    //   n1 to n2 = 0                 Transition n1 --0--> n2  (fires on symbol "0").
    //   n2 to n4 = 0                 Transition n2 --0--> n4  (fires on symbol "0").
    //   n4 to n0 = 0                 Transition n4 --0--> n0  (fires on symbol "0").
    //   n4 to n1 = 1                 Transition n4 --1--> n1  (fires on symbol "1").
    //   n2 to n5 = 1                 Transition n2 --1--> n5  (fires on symbol "1").
    //   n5 to n2 = 0                 Transition n5 --0--> n2  (fires on symbol "0").
    //   n5 to n3 = 1                 Transition n5 --1--> n3  (fires on symbol "1").
    //   n3 to n6 = 0                 Transition n3 --0--> n6  (fires on symbol "0").
    //   n3 to n7 = 1                 Transition n3 --1--> n7  (fires on symbol "1").
    //   n7 to n6 = 0                 Transition n7 --0--> n6  (fires on symbol "0").
    //   n7 to n7 = 1                 Transition n7 --1--> n7  (fires on symbol "1").
    //   n6 to n4 = 0                 Transition n6 --0--> n4  (fires on symbol "0").
    //   n6 to n5 = 1                 Transition n6 --1--> n5  (fires on symbol "1").
    //   l6(1) curve = 439.5          Rendering hint: curvature/bow (439.5px) for transition line l6 (labeled "1"), which connects two distinct states.
    //   l7(1) curve = 30.8           Rendering hint: curvature/bow (30.8px) for transition line l7 (labeled "1"), which connects two distinct states.
    //   l8(0) curve = 16.7           Rendering hint: curvature/bow (16.7px) for transition line l8 (labeled "0"), which connects two distinct states.
    //   l14(0) curve = 126.4         Rendering hint: curvature/bow (126.4px) for transition line l14 (labeled "0"), which connects two distinct states.
    //   l0(0) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "0").
    //   l13(1) loop angle = 0.4628   Rendering hint: self-loop arc angle (0.4628 rad) for transition line l13 (labeled "1").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 length = 114.5         Rendering hint: pixel length 114.5 for the start arrow into n0.
    //   to n0 angle = -0.9767, -0.2148 Rendering hint: direction vector (-0.9767, -0.2148) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('dsl_binary_mod3'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.73,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.75,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'boss',
    // True → this is a boss level; LayerConstraintValidator caps boss layers at 2 bosses and forbids mixing bosses with non-boss levels in the same layer.
    isBoss: true,
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 16 — TUTORIAL: PUSHDOWN AUTOMATA  (x ≈ 0.77)
  //  Requires mod 7 AND mod 8.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tutorial_pda',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Pushdown Automata',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description: 'Learn how PDAs use a stack to recognise context-free languages.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Unlocked only after the player has completed ALL of the listed levels (AND gate).
    unlockRule: RequireAll(['dsl_binary_mod7', 'dsl_binary_mod8']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.77,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tutorial',
    // True → this entry is a slideshow tutorial, not a puzzle; tutorialSlides is shown instead of the drawing canvas.
    isTutorial: true,
    // Slides shown when isTutorial is true (ignored for normal puzzle levels).
    tutorialSlides: [
      TutorialSlide(
        // Slide title.
        headline: 'Beyond Finite Memory',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Some languages **cannot** be recognised by a DFA or NFA. '
            'The classic example is aⁿbⁿ — equal numbers of a\'s then b\'s.\n\n'
            'A DFA has no memory of how many a\'s it has seen. '
            'A **PDA** adds a **stack** — an infinite scratchpad — which solves this.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.pdaStack,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'PDA Transition Format',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Each PDA transition arrow has the label format:\n\n'
            '  **read, pop | push**\n\n'
            '• **read** — the input symbol consumed (**~** means consume nothing)\n'
            '• **pop**  — the stack symbol removed from the top (**~** means pop nothing)\n'
            '• **push** — the stack symbol added on top (**~** means push nothing)\n\n'
            'Example: **"a, ~ | X"** — read "a", don\'t pop, push "X".',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Stack Strategy for aⁿbⁿ',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Here\'s the classic approach for equal-count problems:\n\n'
            '1. **Push** a marker (e.g. X) for each "a" you read.\n'
            '2. When you start reading "b"s, **pop** one X per "b".\n'
            '3. Accept when the stack is empty and input is exhausted.\n\n'
            'If the stack runs out before the input (or vice versa), the counts don\'t match — reject.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 18 — HUNGRY CATERPILLAR (NFA + DFA) AND HALT ON Y  (x ≈ 0.81)
  //  Both require PDA tutorial.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_caterpillar_nfa',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Hungry Caterpillar (NFA)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'The Very Hungry Caterpillar ends by eating EXACTLY one "Green Leaf".\n'
        'Build an NFA over story words where .-"Green Leaf" means '
        '"every word except Green Leaf". Accept strings whose last food item is exactly one Green Leaf.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (689.3, 458.7)          Canvas position of n0 in the level-editor layout: x=689.3, y=458.7.
    //   n1 = (1080.7, 454.7)         Canvas position of n1 in the level-editor layout: x=1080.7, y=454.7.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = "Green Leaf"      Transition n0 --"Green Leaf"--> n1  (fires on symbol ""Green Leaf"").
    //   n0 to n0 = .-"Green Leaf"    Transition n0 --.-"Green Leaf"--> n0  (fires on symbol ".-"Green Leaf"").
    //   .-"Green Leaf" loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled ".-"Green Leaf"" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_pda'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.81,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.20,
    // Player's submission must use at least one genuine NFA feature (nondeterminism or a ~-transition) — a plain DFA is rejected here.
    requiredAutomatonType: RequiredAutomatonType.nfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'"Green Leaf"', '(others)'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'nfa',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dsl_halt_accept_y',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Halt on y',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build an FA over the lowercase English alphabet that stops computing '
        'and accepts the moment it sees the letter "y".\n'
        'Use <<Ha>> to mark a halt-and-accept state, and .-y to mean '
        '"every letter except y".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = <<Ha>>                  Declares node n1 as a halt-ACCEPT state (label "Ha") — the <<...>> marker means the machine halts and accepts the moment it enters this state, bypassing the normal isAccept flag.
    //   n0 = (484.0, 492.0)          Canvas position of n0 in the level-editor layout: x=484.0, y=492.0.
    //   Ha = (834.0, 492.0)          Canvas position of Ha in the level-editor layout: x=834.0, y=492.0.
    //   n0 to Ha = y                 Transition n0 --y--> Ha  (fires on symbol "y").
    //   n0 to n0 = a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,z Transition n0 --a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,z--> n0  (fires on symbols a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,z).
    //   a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,z loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,z" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_pda'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.81,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.80,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b', 'c', '…', 'z'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'fa',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 19 — BALANCED PARENTHESES  (x ≈ 0.84)
  //  Requires hungry caterpillar AND halt on y.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'pda_balanced_parens',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Balanced Parentheses',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a PDA over {(, )} that accepts strings with balanced parentheses '
        '(e.g. "(()())" accepted, "(()" rejected).\n'
        'Push a marker on every "(" and pop it on every ")".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   pda mode                     Switches this DSL block into PDA mode — transition labels below are read,pop|push triples (∅ / ~ = "nothing").
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (480.0, 360.0)          Canvas position of n0 in the level-editor layout: x=480.0, y=360.0.
    //   n1 = (820.0, 360.0)          Canvas position of n1 in the level-editor layout: x=820.0, y=360.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n0 = (,∅|X             Transition n0 → n0: read "(", pop nothing (no pop) off the stack, push "X" on top.
    //   n0 to n1 = ),X|∅             Transition n0 → n1: read ")", pop "X" off the stack, push nothing (no push) on top.
    //   n1 to n1 = ),X|∅             Transition n1 → n1: read ")", pop "X" off the stack, push nothing (no push) on top.
    //   n1 to n0 = ∅,∅|∅             Transition n1 → n0: read ε (no input consumed), pop nothing (no pop) off the stack, push nothing (no push) on top.
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in pushdown-automaton (stack-based) mode.
    automataMode: AutomataMode.pda,
    // Unlocked only after the player has completed ALL of the listed levels (AND gate).
    unlockRule: RequireAll(['dsl_caterpillar_nfa', 'dsl_halt_accept_y']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.84,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'(', ')'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 20 — aⁿbⁿ  (x ≈ 0.87)
  //  Requires balanced parentheses.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'pda_anbn',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'aⁿbⁿ',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a PDA that accepts exactly strings of the form aⁿbⁿ (n ≥ 1): '
        "the same number of a's followed by the same number of b's.\n"
        'Classic context-free language — not recognisable by any DFA!',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   pda mode                     Switches this DSL block into PDA mode — transition labels below are read,pop|push triples (∅ / ~ = "nothing").
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (340.0, 360.0)          Canvas position of n0 in the level-editor layout: x=340.0, y=360.0.
    //   n1 = (680.0, 360.0)          Canvas position of n1 in the level-editor layout: x=680.0, y=360.0.
    //   n2 = (1020.0, 360.0)         Canvas position of n2 in the level-editor layout: x=1020.0, y=360.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n0 = a,∅|X             Transition n0 → n0: read "a", pop nothing (no pop) off the stack, push "X" on top.
    //   n0 to n1 = b,X|∅             Transition n0 → n1: read "b", pop "X" off the stack, push nothing (no push) on top.
    //   n1 to n1 = b,X|∅             Transition n1 → n1: read "b", pop "X" off the stack, push nothing (no push) on top.
    //   n1 to n2 = ∅,∅|∅             Transition n1 → n2: read ε (no input consumed), pop nothing (no pop) off the stack, push nothing (no push) on top.
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in pushdown-automaton (stack-based) mode.
    automataMode: AutomataMode.pda,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('pda_balanced_parens'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.87,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 21 — MORE As THAN Bs  (x ≈ 0.89)
  //  Requires aⁿbⁿ.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'pda_more_as',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: "More a's Than b's",
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        "Build a PDA over {a, b} that accepts strings where the number of a's "
        "is strictly greater than the number of b's (in any order).\n"
        'Push for each a, pop for each b; accept if the stack is non-empty at the end.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   pda mode                     Switches this DSL block into PDA mode — transition labels below are read,pop|push triples (∅ / ~ = "nothing").
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n0 = (380.0, 360.0)          Canvas position of n0 in the level-editor layout: x=380.0, y=360.0.
    //   n1 = (720.0, 360.0)          Canvas position of n1 in the level-editor layout: x=720.0, y=360.0.
    //   n0 to n0 = a,∅|X             Transition n0 → n0: read "a", pop nothing (no pop) off the stack, push "X" on top.
    //   n0 to n0 = b,X|∅             Transition n0 → n0: read "b", pop "X" off the stack, push nothing (no push) on top.
    //   n0 to n1 = ∅,X|X             Transition n0 → n1: read ε (no input consumed), pop "X" off the stack, push "X" on top.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in pushdown-automaton (stack-based) mode.
    automataMode: AutomataMode.pda,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('pda_anbn'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.89,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 22 — aⁿb²ⁿ  (x ≈ 0.91)
  //  Requires more As than Bs.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'pda_an_b2n',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'aⁿb²ⁿ',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a PDA that accepts strings of the form aⁿb²ⁿ (n ≥ 1): '
        "for every a there must be exactly two b's.\n"
        'Hint: push two markers for each a you read.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   pda mode                     Switches this DSL block into PDA mode — transition labels below are read,pop|push triples (∅ / ~ = "nothing").
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (340.0, 360.0)          Canvas position of n0 in the level-editor layout: x=340.0, y=360.0.
    //   n1 = (680.0, 360.0)          Canvas position of n1 in the level-editor layout: x=680.0, y=360.0.
    //   n2 = (1020.0, 360.0)         Canvas position of n2 in the level-editor layout: x=1020.0, y=360.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n0 = a,∅|X             Transition n0 → n0: read "a", pop nothing (no pop) off the stack, push "X" on top.
    //   n0 to n0 = a,∅|X             Transition n0 → n0: read "a", pop nothing (no pop) off the stack, push "X" on top.
    //   n0 to n1 = b,X|∅             Transition n0 → n1: read "b", pop "X" off the stack, push nothing (no push) on top.
    //   n1 to n1 = b,X|∅             Transition n1 → n1: read "b", pop "X" off the stack, push nothing (no push) on top.
    //   n1 to n2 = ∅,∅|∅             Transition n1 → n2: read ε (no input consumed), pop nothing (no pop) off the stack, push nothing (no push) on top.
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in pushdown-automaton (stack-based) mode.
    automataMode: AutomataMode.pda,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('pda_more_as'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.91,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'pda',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 23 — PDA BOSS AND PDA PALINDROME  (x ≈ 0.93)
  //  Both require aⁿb²ⁿ.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'level_2',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Level 2 — PDA Boss',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a PDA that matches the hidden stack-based target machine. '
        'Study the transition format and think carefully about what language this could be.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   pda mode                     Switches this DSL block into PDA mode — transition labels below are read,pop|push triples (∅ / ~ = "nothing").
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = <<ha>>                  Declares node n3 as a halt-ACCEPT state (label "ha") — the <<...>> marker means the machine halts and accepts the moment it enters this state, bypassing the normal isAccept flag.
    //   n4 = E                       Declares node n4 with display label "E".
    //   n5 = F                       Declares node n5 with display label "F".
    //   n0 = (723.3, 204.7)          Canvas position of n0 in the level-editor layout: x=723.3, y=204.7.
    //   n1 = (1139.3, 259.3)         Canvas position of n1 in the level-editor layout: x=1139.3, y=259.3.
    //   n2 = (1196.0, 527.3)         Canvas position of n2 in the level-editor layout: x=1196.0, y=527.3.
    //   n3 = (739.3, 705.3)          Canvas position of n3 in the level-editor layout: x=739.3, y=705.3.
    //   n4 = (345.3, 504.7)          Canvas position of n4 in the level-editor layout: x=345.3, y=504.7.
    //   n5 = (345.3, 277.3)          Canvas position of n5 in the level-editor layout: x=345.3, y=277.3.
    //   n0 to n5 = 0,~|X             Transition n0 → n5: read "0", pop nothing (no pop) off the stack, push "X" on top.
    //   n0 to n1 = 1,~|Y             Transition n0 → n1: read "1", pop nothing (no pop) off the stack, push "Y" on top.
    //   n1 to n1 = 1,~|Y             Transition n1 → n1: read "1", pop nothing (no pop) off the stack, push "Y" on top.
    //   n1 to n2 = 0,Y|~             Transition n1 → n2: read "0", pop "Y" off the stack, push nothing (no push) on top.
    //   n2 to n1 = 1,∅|Y             Transition n2 → n1: read "1", pop nothing (no pop) off the stack, push "Y" on top.
    //   n2 to n5 = 0,∅|X             Transition n2 → n5: read "0", pop nothing (no pop) off the stack, push "X" on top.
    //   n4 to n1 = 1,∅|Y             Transition n4 → n1: read "1", pop nothing (no pop) off the stack, push "Y" on top.
    //   n4 to n5 = 0,∅|X             Transition n4 → n5: read "0", pop nothing (no pop) off the stack, push "X" on top.
    //   n5 to n4 = 1,X|~             Transition n5 → n4: read "1", pop "X" off the stack, push nothing (no push) on top.
    //   n5 to n5 = 0,~|X             Transition n5 → n5: read "0", pop nothing (no pop) off the stack, push "X" on top.
    //   n4 to n4 = 1,X|~             Transition n4 → n4: read "1", pop "X" off the stack, push nothing (no push) on top.
    //   n4 to n3 = ∅,∅|~             Transition n4 → n3: read ε (no input consumed), pop nothing (no pop) off the stack, push nothing (no push) on top.
    //   n2 to n3 = ∅,∅|~             Transition n2 → n3: read ε (no input consumed), pop nothing (no pop) off the stack, push nothing (no push) on top.
    //   n2 to n2 = 0,Y|~             Transition n2 → n2: read "0", pop "Y" off the stack, push nothing (no push) on top.
    //   l0(0,~|X) curve = -2.9       Rendering hint: curvature/bow (-2.9px) for transition line l0 (labeled "0,~|X"), which connects two distinct states.
    //   l3(0,Y|~) curve = 62.2       Rendering hint: curvature/bow (62.2px) for transition line l3 (labeled "0,Y|~"), which connects two distinct states.
    //   l4(1,∅|Y) curve = 55.1       Rendering hint: curvature/bow (55.1px) for transition line l4 (labeled "1,∅|Y"), which connects two distinct states.
    //   l5(0,∅|X) curve = 39.9       Rendering hint: curvature/bow (39.9px) for transition line l5 (labeled "0,∅|X"), which connects two distinct states.
    //   l6(1,∅|Y) curve = 16.9       Rendering hint: curvature/bow (16.9px) for transition line l6 (labeled "1,∅|Y"), which connects two distinct states.
    //   l7(0,∅|X) curve = -8.2       Rendering hint: curvature/bow (-8.2px) for transition line l7 (labeled "0,∅|X"), which connects two distinct states.
    //   l8(1,X|~) curve = -105.4     Rendering hint: curvature/bow (-105.4px) for transition line l8 (labeled "1,X|~"), which connects two distinct states.
    //   l2(1,~|Y) loop angle = -0.7988 Rendering hint: self-loop arc angle (-0.7988 rad) for transition line l2 (labeled "1,~|Y").
    //   l9(0,~|X) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l9 (labeled "0,~|X").
    //   l10(1,X|~) loop angle = 1.7686 Rendering hint: self-loop arc angle (1.7686 rad) for transition line l10 (labeled "1,X|~").
    //   l13(0,Y|~) loop angle = -0.0754 Rendering hint: self-loop arc angle (-0.0754 rad) for transition line l13 (labeled "0,Y|~").
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in pushdown-automaton (stack-based) mode.
    automataMode: AutomataMode.pda,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('pda_an_b2n'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.93,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.25,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'pda',
    // True → this is a boss level; LayerConstraintValidator caps boss layers at 2 bosses and forbids mixing bosses with non-boss levels in the same layer.
    isBoss: true,
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'pda_palindrome',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'PDA Palindromes',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a PDA over {a, b} that accepts even-length palindromes '
        '(ww^R where w is any string over {a,b}).\n'
        'Hint: push the first half onto the stack, then pop-match the second half.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   pda mode                     Switches this DSL block into PDA mode — transition labels below are read,pop|push triples (∅ / ~ = "nothing").
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n0 = (340.0, 360.0)          Canvas position of n0 in the level-editor layout: x=340.0, y=360.0.
    //   n1 = (680.0, 360.0)          Canvas position of n1 in the level-editor layout: x=680.0, y=360.0.
    //   n2 = (1020.0, 360.0)         Canvas position of n2 in the level-editor layout: x=1020.0, y=360.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n0 = a,∅|a             Transition n0 → n0: read "a", pop nothing (no pop) off the stack, push "a" on top.
    //   n0 to n0 = b,∅|b             Transition n0 → n0: read "b", pop nothing (no pop) off the stack, push "b" on top.
    //   n0 to n1 = ∅,∅|∅             Transition n0 → n1: read ε (no input consumed), pop nothing (no pop) off the stack, push nothing (no push) on top.
    //   n1 to n1 = a,a|∅             Transition n1 → n1: read "a", pop "a" off the stack, push nothing (no push) on top.
    //   n1 to n1 = b,b|∅             Transition n1 → n1: read "b", pop "b" off the stack, push nothing (no push) on top.
    //   n1 to n2 = ∅,∅|∅             Transition n1 → n2: read ε (no input consumed), pop nothing (no pop) off the stack, push nothing (no push) on top.
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in pushdown-automaton (stack-based) mode.
    automataMode: AutomataMode.pda,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('pda_an_b2n'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.93,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.75,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'pda',
    // Paired with level_2 in the same unlock layer (both require
    // pda_an_b2n) — flagged as a boss too so the pair satisfies the
    // "boss layer may only contain boss levels" rule (up to 2 allowed)
    // instead of violating "boss can't mix with a regular level".
    // True → this is a boss level; LayerConstraintValidator caps boss layers at 2 bosses and forbids mixing bosses with non-boss levels in the same layer.
    isBoss: true,
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 24 — TUTORIAL: TURING MACHINES  (x ≈ 0.95)
  //  Requires PDA Boss OR PDA Palindrome.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tutorial_tm',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Turing Machines',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description: 'Learn the read/write tape model and TM transition format.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['level_2', 'pda_palindrome']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.95,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tutorial',
    // True → this entry is a slideshow tutorial, not a puzzle; tutorialSlides is shown instead of the drawing canvas.
    isTutorial: true,
    // Slides shown when isTutorial is true (ignored for normal puzzle levels).
    tutorialSlides: [
      TutorialSlide(
        // Slide title.
        headline: 'The Turing Machine',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'A Turing machine adds a **read/write tape** to a finite automaton. '
            'The tape is infinite in both directions and starts with your input.\n\n'
            'A **read/write head** sits on one cell at a time. '
            'On each step it reads the current symbol, writes a new symbol (or leaves it), '
            'and moves **Left** or **Right** (or stays Still).',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.tmTape,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'TM Transition Format',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Each TM arrow label has the format:\n\n'
            '  **readSymbol writeSymbol Direction**\n\n'
            'Direction is **R** (right), **L** (left), or **S** (stay).\n\n'
            'Example: **"aXR"** — read "a", write "X", move Right.\n'
            'Example: **"∅∅S"** — read blank, write blank, stay (blank = empty cell).',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Accepting and Rejecting',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'A TM **accepts** by entering an accept state (double ring) and halting.\n\n'
            'A TM **rejects** either by entering a reject state (no outgoing transition for the current symbol causes a crash) '
            'or by looping forever.\n\n'
            'The equivalence checker uses a bounded simulation — '
            'it tests many input strings but can\'t always prove correctness on all inputs.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'The Crossout Technique',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Many TM puzzles use a **crossout** strategy:\n\n'
            '1. Replace a matched symbol with **X** (or another marker) to "cross it out".\n'
            '2. Sweep the tape left/right to find the next unmatched symbol.\n'
            '3. Repeat until all symbols are matched or a mismatch is detected.\n\n'
            'You\'ll see this in aⁿbⁿ, aⁿbⁿcⁿ, palindrome, and the "ww" puzzles.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Multiple Loops on One State',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'TM states often have **many self-loops** — one for each symbol the machine should '
            'pass over without stopping.\n\n'
            'In the canvas you can drag a self-loop\'s label dot to rotate it around the state circle, '
            'so diagrams stay readable even with 4–5 loops on one state.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 25 — ACCEPT ALL TM AND REJECT ALL TM  (x ≈ 0.96)
  //  Both require TM tutorial.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tm_identity',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'TM: Accept All (Trivial)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build the simplest possible Turing machine: one that accepts every input '
        'by halting immediately.\n'
        'A single state that is both start and accept will do it. '
        'TM transition format: readSymbol writeSymbol Direction (e.g. aBR = read a, write B, move Right).',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   tm mode                      Switches this DSL block into TM mode — transition labels below are 3-character readSymbol/writeSymbol/Direction shorthand (∅ = blank cell).
    //   n0 = A                       Declares node n0 with display label "A".
    //   A = (600.0, 360.0)           Canvas position of A in the level-editor layout: x=600.0, y=360.0.
    //   A is accepted                A is an accepting (double-ring) state.
    //   to A angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into A.
    dsl: r'''
      tm mode
      n0 = A
      A = (600.0, 360.0)
      A is accepted
      to A angle = -1.0000, 0.0000
    ''',
    // Hidden target is checked for equivalence in Turing-machine (tape-based) mode.
    automataMode: AutomataMode.tm,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_tm'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.96,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.25,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tm',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tm_reject_all',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'TM: Reject All',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a TM that loops forever on any non-empty input (rejects by non-halt) '
        'and accepts only the empty tape.\n'
        'Hint: a start state with a self-loop on every symbol that moves right will spin forever.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   tm mode                      Switches this DSL block into TM mode — transition labels below are 3-character readSymbol/writeSymbol/Direction shorthand (∅ = blank cell).
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   A = (480.0, 360.0)           Canvas position of A in the level-editor layout: x=480.0, y=360.0.
    //   B = (820.0, 360.0)           Canvas position of B in the level-editor layout: x=820.0, y=360.0.
    //   B is accepted                B is an accepting (double-ring) state.
    //   A to B = ∅∅S                 Transition A → B: read blank (∅), write blank (∅), move Stay (does not move).
    //   to A angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into A.
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
    // Hidden target is checked for equivalence in Turing-machine (tape-based) mode.
    automataMode: AutomataMode.tm,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_tm'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.96,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.75,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 26 — aⁿbⁿ TM  (x ≈ 0.97)
  //  Requires accept all TM AND reject all TM.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tm_anbn',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'TM: aⁿbⁿ',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a TM that accepts exactly strings of the form aⁿbⁿ (n ≥ 1). '
        'Classic TM exercise: repeatedly cross off one a and one b until both sides are exhausted.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   tm mode                      Switches this DSL block into TM mode — transition labels below are 3-character readSymbol/writeSymbol/Direction shorthand (∅ = blank cell).
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = E                       Declares node n4 with display label "E".
    //   A = (260.0, 200.0)           Canvas position of A in the level-editor layout: x=260.0, y=200.0.
    //   B = (660.0, 200.0)           Canvas position of B in the level-editor layout: x=660.0, y=200.0.
    //   C = (1060.0, 200.0)          Canvas position of C in the level-editor layout: x=1060.0, y=200.0.
    //   D = (660.0, 560.0)           Canvas position of D in the level-editor layout: x=660.0, y=560.0.
    //   E = (260.0, 560.0)           Canvas position of E in the level-editor layout: x=260.0, y=560.0.
    //   E is accepted                E is an accepting (double-ring) state.
    //   A to B = aXR                 Transition A → B: read "a", write "X", move Right.
    //   B to B = aXR                 Transition B → B: read "a", write "X", move Right.
    //   B to C = bXL                 Transition B → C: read "b", write "X", move Left.
    //   C to D = XXL                 Transition C → D: read "X", write "X", move Left.
    //   D to D = aXL                 Transition D → D: read "a", write "X", move Left.
    //   D to A = XXR                 Transition D → A: read "X", write "X", move Right.
    //   A to E = ∅∅S                 Transition A → E: read blank (∅), write blank (∅), move Stay (does not move).
    //   l1(aXR) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled "aXR").
    //   l3(XXL) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "XXL").
    //   l4(aXL) loop angle = 1.5708  Rendering hint: self-loop arc angle (1.5708 rad) for transition line l4 (labeled "aXL").
    //   aXR curve = 80.0             Rendering hint: curvature/bow (80.0px) for the transition labeled "aXR".
    //   bXL curve = 80.0             Rendering hint: curvature/bow (80.0px) for the transition labeled "bXL".
    //   XXR curve = 80.0             Rendering hint: curvature/bow (80.0px) for the transition labeled "XXR".
    //   to A angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into A.
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
    // Hidden target is checked for equivalence in Turing-machine (tape-based) mode.
    automataMode: AutomataMode.tm,
    // Unlocked only after the player has completed ALL of the listed levels (AND gate).
    unlockRule: RequireAll(['tm_identity', 'tm_reject_all']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.97,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 27 — aⁿbⁿcⁿ  (x ≈ 0.975)
  //  Requires aⁿbⁿ TM.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tm_anbncn',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'TM: aⁿbⁿcⁿ',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a TM that accepts strings of the form aⁿbⁿcⁿ (n ≥ 1).\n'
        'This language is not context-free — no PDA can recognise it — '
        'but a TM can! Cross off one a, one b, and one c per pass.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   tm mode                      Switches this DSL block into TM mode — transition labels below are 3-character readSymbol/writeSymbol/Direction shorthand (∅ = blank cell).
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = E                       Declares node n4 with display label "E".
    //   n5 = F                       Declares node n5 with display label "F".
    //   A = (260.0, 200.0)           Canvas position of A in the level-editor layout: x=260.0, y=200.0.
    //   B = (580.0, 200.0)           Canvas position of B in the level-editor layout: x=580.0, y=200.0.
    //   C = (900.0, 200.0)           Canvas position of C in the level-editor layout: x=900.0, y=200.0.
    //   D = (900.0, 540.0)           Canvas position of D in the level-editor layout: x=900.0, y=540.0.
    //   E = (580.0, 540.0)           Canvas position of E in the level-editor layout: x=580.0, y=540.0.
    //   F = (260.0, 540.0)           Canvas position of F in the level-editor layout: x=260.0, y=540.0.
    //   F is accepted                F is an accepting (double-ring) state.
    //   A to B = aXR                 Transition A → B: read "a", write "X", move Right.
    //   B to B = aaR                 Transition B → B: read "a", write "a", move Right.
    //   B to B = XXR                 Transition B → B: read "X", write "X", move Right.
    //   B to C = bXR                 Transition B → C: read "b", write "X", move Right.
    //   C to C = bbR                 Transition C → C: read "b", write "b", move Right.
    //   C to C = XXR                 Transition C → C: read "X", write "X", move Right.
    //   C to D = cXL                 Transition C → D: read "c", write "X", move Left.
    //   D to D = bbL                 Transition D → D: read "b", write "b", move Left.
    //   D to D = ccL                 Transition D → D: read "c", write "c", move Left.
    //   D to D = XXL                 Transition D → D: read "X", write "X", move Left.
    //   D to E = aaL                 Transition D → E: read "a", write "a", move Left.
    //   E to E = aaL                 Transition E → E: read "a", write "a", move Left.
    //   E to E = bbL                 Transition E → E: read "b", write "b", move Left.
    //   E to E = ccL                 Transition E → E: read "c", write "c", move Left.
    //   E to E = XXL                 Transition E → E: read "X", write "X", move Left.
    //   E to A = XXR                 Transition E → A: read "X", write "X", move Right.
    //   A to F = ∅∅S                 Transition A → F: read blank (∅), write blank (∅), move Stay (does not move).
    //   l1(aaR) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled "aaR").
    //   l2(XXR) loop angle = -0.8000 Rendering hint: self-loop arc angle (-0.8000 rad) for transition line l2 (labeled "XXR").
    //   l4(bbR) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "bbR").
    //   l5(XXR) loop angle = -0.8000 Rendering hint: self-loop arc angle (-0.8000 rad) for transition line l5 (labeled "XXR").
    //   l7(bbL) loop angle = 1.5708  Rendering hint: self-loop arc angle (1.5708 rad) for transition line l7 (labeled "bbL").
    //   l8(ccL) loop angle = 0.8000  Rendering hint: self-loop arc angle (0.8000 rad) for transition line l8 (labeled "ccL").
    //   l9(XXL) loop angle = 2.3000  Rendering hint: self-loop arc angle (2.3000 rad) for transition line l9 (labeled "XXL").
    //   l11(aaL) loop angle = 1.5708 Rendering hint: self-loop arc angle (1.5708 rad) for transition line l11 (labeled "aaL").
    //   l12(bbL) loop angle = 0.8000 Rendering hint: self-loop arc angle (0.8000 rad) for transition line l12 (labeled "bbL").
    //   l13(ccL) loop angle = 2.3000 Rendering hint: self-loop arc angle (2.3000 rad) for transition line l13 (labeled "ccL").
    //   l14(XXL) loop angle = 3.1000 Rendering hint: self-loop arc angle (3.1000 rad) for transition line l14 (labeled "XXL").
    //   aXR curve = 70.0             Rendering hint: curvature/bow (70.0px) for the transition labeled "aXR".
    //   bXR curve = 70.0             Rendering hint: curvature/bow (70.0px) for the transition labeled "bXR".
    //   cXL curve = 70.0             Rendering hint: curvature/bow (70.0px) for the transition labeled "cXL".
    //   aaL_E curve = 60.0           Rendering hint: curvature/bow (60.0px) for the transition labeled "aaL_E".  NOTE: this key is resolved by exact label-text lookup, and no transition in this block carries this literal label (transitions here use the plain code "aaL", not "aaL_E") — per _resolveLineRef in import_export.dart this hint silently fails to resolve and has no visible effect.
    //   XXR_E curve = 60.0           Rendering hint: curvature/bow (60.0px) for the transition labeled "XXR_E".  NOTE: this key is resolved by exact label-text lookup, and no transition in this block carries this literal label (transitions here use the plain code "XXR", not "XXR_E") — per _resolveLineRef in import_export.dart this hint silently fails to resolve and has no visible effect.
    //   to A angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into A.
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
    // Hidden target is checked for equivalence in Turing-machine (tape-based) mode.
    automataMode: AutomataMode.tm,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tm_anbn'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.975,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 28 — DOUBLED WORD (ww)  (x ≈ 0.982)
  //  Requires aⁿbⁿcⁿ.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tm_ww',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'TM: ww (Doubled Word)',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a TM that accepts strings of the form ww over {a, b}: '
        'a string that consists of some word w repeated exactly twice '
        '(e.g. "abab", "aabb aabb"). '
        'This is a classic non-context-free language.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   tm mode                      Switches this DSL block into TM mode — transition labels below are 3-character readSymbol/writeSymbol/Direction shorthand (∅ = blank cell).
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = E                       Declares node n4 with display label "E".
    //   n5 = F                       Declares node n5 with display label "F".
    //   A = (260.0, 180.0)           Canvas position of A in the level-editor layout: x=260.0, y=180.0.
    //   B = (660.0, 180.0)           Canvas position of B in the level-editor layout: x=660.0, y=180.0.
    //   C = (1060.0, 180.0)          Canvas position of C in the level-editor layout: x=1060.0, y=180.0.
    //   D = (1060.0, 540.0)          Canvas position of D in the level-editor layout: x=1060.0, y=540.0.
    //   E = (660.0, 540.0)           Canvas position of E in the level-editor layout: x=660.0, y=540.0.
    //   F = (260.0, 540.0)           Canvas position of F in the level-editor layout: x=260.0, y=540.0.
    //   F is accepted                F is an accepting (double-ring) state.
    //   A to B = aXR                 Transition A → B: read "a", write "X", move Right.
    //   A to C = bXR                 Transition A → C: read "b", write "X", move Right.
    //   B to B = aaR                 Transition B → B: read "a", write "a", move Right.
    //   B to B = bbR                 Transition B → B: read "b", write "b", move Right.
    //   B to D = bXL                 Transition B → D: read "b", write "X", move Left.
    //   C to C = aaR                 Transition C → C: read "a", write "a", move Right.
    //   C to C = bbR                 Transition C → C: read "b", write "b", move Right.
    //   C to E = aXL                 Transition C → E: read "a", write "X", move Left.
    //   D to D = aaL                 Transition D → D: read "a", write "a", move Left.
    //   D to D = bbL                 Transition D → D: read "b", write "b", move Left.
    //   D to A = XXR                 Transition D → A: read "X", write "X", move Right.
    //   E to E = aaL                 Transition E → E: read "a", write "a", move Left.
    //   E to E = bbL                 Transition E → E: read "b", write "b", move Left.
    //   E to A = XXR                 Transition E → A: read "X", write "X", move Right.
    //   A to F = ∅∅S                 Transition A → F: read blank (∅), write blank (∅), move Stay (does not move).
    //   l1(aaR) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled "aaR").
    //   l2(bbR) loop angle = -0.8000 Rendering hint: self-loop arc angle (-0.8000 rad) for transition line l2 (labeled "bbR").
    //   l5(aaR) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "aaR").
    //   l6(bbR) loop angle = -0.8000 Rendering hint: self-loop arc angle (-0.8000 rad) for transition line l6 (labeled "bbR").
    //   l7(aaL) loop angle = 1.5708  Rendering hint: self-loop arc angle (1.5708 rad) for transition line l7 (labeled "aaL").
    //   l8(bbL) loop angle = 0.8000  Rendering hint: self-loop arc angle (0.8000 rad) for transition line l8 (labeled "bbL").
    //   l10(aaL) loop angle = 1.5708 Rendering hint: self-loop arc angle (1.5708 rad) for transition line l10 (labeled "aaL").
    //   l11(bbL) loop angle = 0.8000 Rendering hint: self-loop arc angle (0.8000 rad) for transition line l11 (labeled "bbL").
    //   aXR curve = 60.0             Rendering hint: curvature/bow (60.0px) for the transition labeled "aXR".
    //   bXR curve = -60.0            Rendering hint: curvature/bow (-60.0px) for the transition labeled "bXR".
    //   bXL curve = 60.0             Rendering hint: curvature/bow (60.0px) for the transition labeled "bXL".
    //   aXL curve = -60.0            Rendering hint: curvature/bow (-60.0px) for the transition labeled "aXL".
    //   XXR_D curve = 80.0           Rendering hint: curvature/bow (80.0px) for the transition labeled "XXR_D".  NOTE: this key is resolved by exact label-text lookup, and no transition in this block carries this literal label (transitions here use the plain code "XXR", not "XXR_D") — per _resolveLineRef in import_export.dart this hint silently fails to resolve and has no visible effect.
    //   XXR_E curve = -80.0          Rendering hint: curvature/bow (-80.0px) for the transition labeled "XXR_E".  NOTE: this key is resolved by exact label-text lookup, and no transition in this block carries this literal label (transitions here use the plain code "XXR", not "XXR_E") — per _resolveLineRef in import_export.dart this hint silently fails to resolve and has no visible effect.
    //   to A angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into A.
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
    // Hidden target is checked for equivalence in Turing-machine (tape-based) mode.
    automataMode: AutomataMode.tm,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tm_anbncn'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.982,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 29 — TM PALINDROME  (x ≈ 0.990)
  //  Requires doubled word.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tm_palindrome',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'TM: Palindrome',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a TM over {a, b} that accepts palindromes of any length.\n'
        'Strategy: repeatedly peel the first and last character and verify they match.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   tm mode                      Switches this DSL block into TM mode — transition labels below are 3-character readSymbol/writeSymbol/Direction shorthand (∅ = blank cell).
    //   n0 = A                       Declares node n0 with display label "A".
    //   n1 = B                       Declares node n1 with display label "B".
    //   n2 = C                       Declares node n2 with display label "C".
    //   n3 = D                       Declares node n3 with display label "D".
    //   n4 = E                       Declares node n4 with display label "E".
    //   n5 = F                       Declares node n5 with display label "F".
    //   A = (260.0, 200.0)           Canvas position of A in the level-editor layout: x=260.0, y=200.0.
    //   B = (640.0, 200.0)           Canvas position of B in the level-editor layout: x=640.0, y=200.0.
    //   C = (1020.0, 200.0)          Canvas position of C in the level-editor layout: x=1020.0, y=200.0.
    //   D = (1020.0, 540.0)          Canvas position of D in the level-editor layout: x=1020.0, y=540.0.
    //   E = (640.0, 540.0)           Canvas position of E in the level-editor layout: x=640.0, y=540.0.
    //   F = (260.0, 540.0)           Canvas position of F in the level-editor layout: x=260.0, y=540.0.
    //   F is accepted                F is an accepting (double-ring) state.
    //   A to B = aXR                 Transition A → B: read "a", write "X", move Right.
    //   A to C = bXR                 Transition A → C: read "b", write "X", move Right.
    //   B to B = aaR                 Transition B → B: read "a", write "a", move Right.
    //   B to B = bbR                 Transition B → B: read "b", write "b", move Right.
    //   B to E = aXL                 Transition B → E: read "a", write "X", move Left.
    //   C to C = aaR                 Transition C → C: read "a", write "a", move Right.
    //   C to C = bbR                 Transition C → C: read "b", write "b", move Right.
    //   C to D = bXL                 Transition C → D: read "b", write "X", move Left.
    //   D to D = aaL                 Transition D → D: read "a", write "a", move Left.
    //   D to D = bbL                 Transition D → D: read "b", write "b", move Left.
    //   D to A = XXR                 Transition D → A: read "X", write "X", move Right.
    //   E to E = aaL                 Transition E → E: read "a", write "a", move Left.
    //   E to E = bbL                 Transition E → E: read "b", write "b", move Left.
    //   E to A = XXR                 Transition E → A: read "X", write "X", move Right.
    //   A to F = ∅∅S                 Transition A → F: read blank (∅), write blank (∅), move Stay (does not move).
    //   l1(aaR) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l1 (labeled "aaR").
    //   l2(bbR) loop angle = -0.6000 Rendering hint: self-loop arc angle (-0.6000 rad) for transition line l2 (labeled "bbR").
    //   l5(aaR) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "aaR").
    //   l6(bbR) loop angle = -0.6000 Rendering hint: self-loop arc angle (-0.6000 rad) for transition line l6 (labeled "bbR").
    //   l8(aaL) loop angle = 1.5708  Rendering hint: self-loop arc angle (1.5708 rad) for transition line l8 (labeled "aaL").
    //   l9(bbL) loop angle = 0.6000  Rendering hint: self-loop arc angle (0.6000 rad) for transition line l9 (labeled "bbL").
    //   l11(aaL) loop angle = 1.5708 Rendering hint: self-loop arc angle (1.5708 rad) for transition line l11 (labeled "aaL").
    //   l12(bbL) loop angle = 0.6000 Rendering hint: self-loop arc angle (0.6000 rad) for transition line l12 (labeled "bbL").
    //   aXR curve = 70.0             Rendering hint: curvature/bow (70.0px) for the transition labeled "aXR".
    //   bXR curve = -70.0            Rendering hint: curvature/bow (-70.0px) for the transition labeled "bXR".
    //   aXL curve = -70.0            Rendering hint: curvature/bow (-70.0px) for the transition labeled "aXL".
    //   bXL curve = 70.0             Rendering hint: curvature/bow (70.0px) for the transition labeled "bXL".
    //   to A angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into A.
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
    // Hidden target is checked for equivalence in Turing-machine (tape-based) mode.
    automataMode: AutomataMode.tm,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tm_ww'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 0.990,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tm',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 26 — TUTORIAL: REGULAR EXPRESSIONS  (x ≈ 1.00)
  //  Requires TM palindrome (last TM level).
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'tutorial_regex',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Regular Expressions',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description: 'Learn the connection between regular expressions and finite automata.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tm_palindrome'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.00,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'tutorial',
    // True → this entry is a slideshow tutorial, not a puzzle; tutorialSlides is shown instead of the drawing canvas.
    isTutorial: true,
    // Slides shown when isTutorial is true (ignored for normal puzzle levels).
    tutorialSlides: [
      TutorialSlide(
        // Slide title.
        headline: 'What is a Regular Expression?',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'A **regular expression** (regex) is a compact notation for describing a '
            'regular language — the same class of languages recognised by DFAs and NFAs.\n\n'
            'Operators used in these puzzles:\n'
            '• **a** — literal symbol "a"\n'
            '• **ab** — concatenation (a then b)\n'
            '• **a+b** — alternation / union (a OR b)\n'
            '• **a*** — Kleene star (zero or more a)\n'
            '• **(…)** — grouping',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Regex ↔ Automaton',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Every regular expression describes exactly the same set of strings '
            'as some DFA (and vice versa). This is why they are called *regular* languages.\n\n'
            'This section has two challenge types:\n\n'
            '**Regex → DFA** — You are given a regex and must build a DFA whose language '
            'matches it exactly.\n\n'
            '**DFA → Regex** — You are shown a read-only DFA diagram and must type a '
            'regex that describes the same language.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Notation Reference',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'The checker uses the following notation:\n\n'
            '• **~** — empty string ~  (e.g. a+~ means "a or nothing")\n'
            '• **∅** — empty language (matches nothing)\n'
            '• **+** — alternation  (a+b means a OR b)\n'
            '• ***** — Kleene star, postfix  (a* = zero or more a)\n'
            '• Concatenation is implicit: **ab** means a then b\n\n'
            'Precedence (high→low): star → concat → union.\n'
            'Use parentheses to override: (a+b)* = any string over {a,b}.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'Tips: Regex → DFA',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'When you see a regex, ask: "what pattern must a string satisfy?"\n\n'
            '• **ab*** — any number of b\'s after exactly one a\n'
            '• **(a+b)*abb** — anything, ending in "abb"\n'
            '• **(ab)*** — alternating pairs: ~, ab, abab, …\n\n'
            'Think about what the machine must *remember*. '
            'Each memory unit (e.g. "last symbol seen") usually becomes a state.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.none,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'DFA → Regex: Add Super States',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'To turn a DFA into a regex, first convert it into a **GNFA** '
            '(generalised NFA) by adding two new states:\n\n'
            '• A **super-start** S, with a single ~-edge into the original '
            'start state.\n'
            '• A **super-accept** F, with an ~-edge in from every original '
            'accept state (if there\'s more than one, they all point to the '
            'same F).\n\n'
            'From this point on, only S and F count as start/accept — that '
            'frees every other state, including the old accept state(s), to '
            'be eliminated in the next step.',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.addSuperStates,
      ),
      TutorialSlide(
        // Slide title.
        headline: 'DFA → Regex: Eliminate States',
        // Slide body text (supports **bold** markdown-style emphasis and \n line breaks).
        body: 'Now eliminate the remaining states one at a time until only '
            'S and F are left. To remove a state B sitting between '
            'neighbours A and C:\n\n'
            '1. **Star** its self-loop, if it has one — label b becomes b*.\n'
            '2. **Sandwich** that between the edge going in and the edge '
            'going out: a · b* · c.\n'
            '3. **Union** (+) that with whatever edge, if any, already ran '
            'directly from A to C.\n\n'
            'Example: A -a→ B (self-loop b) -c→ C collapses to one edge '
            'A → C labelled **ab*c**.\n\n'
            'Repeat for every remaining state. Whatever label ends up on '
            'the final S → F edge is your answer.\n\n'
            'Shortcut: pattern recognition is often faster than working it '
            'out by hand — spot self-loops (→ *), linear paths (→ concat), '
            'branches (→ +).',
        // Which built-in illustration graphic tutorial_screen.dart renders alongside this slide's text.
        illustrationType: TutorialIllustration.stateElimination,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 27 — REGEX → DFA  (BASIC)  (x ≈ 1.03)
  //  All three require the regex tutorial.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'regex_to_dfa_ab_star',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Regex → DFA: ab*',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    ab*\n\n'
        'Matches "a" followed by any number of b\'s: "a", "ab", "abb", "abbb", …',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n2 = dead                    Declares node n2 with display label "dead".
    //   n0 = (320.0, 360.0)          Canvas position of n0 in the level-editor layout: x=320.0, y=360.0.
    //   n1 = (660.0, 360.0)          Canvas position of n1 in the level-editor layout: x=660.0, y=360.0.
    //   n2 = (660.0, 580.0)          Canvas position of n2 in the level-editor layout: x=660.0, y=580.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n2 = b                 Transition n0 --b--> n2  (fires on symbol "b").
    //   n1 to n1 = b                 Transition n1 --b--> n1  (fires on symbol "b").
    //   n1 to n2 = a                 Transition n1 --a--> n2  (fires on symbol "a").
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   l2(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "b").
    //   l4(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_regex'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.03,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.20,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a regex in the goal banner and must build an equivalent DFA on the canvas.
    puzzleVariant: PuzzleVariant.regexToDfa,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: 'ab*',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'regex_to_dfa_starts_a',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Regex → DFA: a(a+b)*',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    a(a+b)*\n\n'
        'Matches all strings that start with "a": "a", "aa", "ab", "aba", …',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n2 = dead                    Declares node n2 with display label "dead".
    //   n0 = (320.0, 360.0)          Canvas position of n0 in the level-editor layout: x=320.0, y=360.0.
    //   n1 = (660.0, 360.0)          Canvas position of n1 in the level-editor layout: x=660.0, y=360.0.
    //   n2 = (660.0, 580.0)          Canvas position of n2 in the level-editor layout: x=660.0, y=580.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n2 = b                 Transition n0 --b--> n2  (fires on symbol "b").
    //   n1 to n1 = a,b               Transition n1 --a,b--> n1  (fires on symbols a,b).
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   l2(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "a,b").
    //   l3(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_regex'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.03,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a regex in the goal banner and must build an equivalent DFA on the canvas.
    puzzleVariant: PuzzleVariant.regexToDfa,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: 'a(a+b)*',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'regex_to_dfa_ends_b',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Regex → DFA: (a+b)*b',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    (a+b)*b\n\n'
        'Matches all strings that end with "b": "b", "ab", "bb", "aab", …',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n0 = (400.0, 360.0)          Canvas position of n0 in the level-editor layout: x=400.0, y=360.0.
    //   n1 = (780.0, 360.0)          Canvas position of n1 in the level-editor layout: x=780.0, y=360.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = b                 Transition n0 --b--> n1  (fires on symbol "b").
    //   n0 to n0 = a                 Transition n0 --a--> n0  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   n1 to n1 = b                 Transition n1 --b--> n1  (fires on symbol "b").
    //   l0(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a").
    //   l3(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked once the player has completed the single listed level.
    unlockRule: RequireLevel('tutorial_regex'),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.03,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.80,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a regex in the goal banner and must build an equivalent DFA on the canvas.
    puzzleVariant: PuzzleVariant.regexToDfa,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: '(a+b)*b',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 28 — REGEX → DFA  (INTERMEDIATE)  (x ≈ 1.06)
  //  Unlock from any level in layer 27.
  // ═══════════════════════════════════════════════════════════════════════════

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'regex_to_dfa_a_or_b_star',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Regex → DFA: (a+b)*',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    (a+b)*\n\n'
        'Matches every string over {a, b} — including the empty string ~.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n0 = (600.0, 360.0)          Canvas position of n0 in the level-editor layout: x=600.0, y=360.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n0 = a,b               Transition n0 --a,b--> n0  (fires on symbols a,b).
    //   a,b loop angle = -1.5708     Rendering hint: self-loop arc angle (-1.5708 rad) for the transition labeled "a,b" (resolved by label since it's the only line with that text).
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
    dsl: '''
      n0 = q0
      n0 = (600.0, 360.0)
      n0 is accepted
      n0 to n0 = a,b
      a,b loop angle = -1.5708
      to n0
      to n0 angle = -1.0000, 0.0000
    ''',
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['regex_to_dfa_ab_star', 'regex_to_dfa_starts_a', 'regex_to_dfa_ends_b']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.06,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.20,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a regex in the goal banner and must build an equivalent DFA on the canvas.
    puzzleVariant: PuzzleVariant.regexToDfa,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: '(a+b)*',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'regex_to_dfa_aba',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Regex → DFA: (a+b)*aba(a+b)*',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    (a+b)*aba(a+b)*\n\n'
        'Matches all strings containing "aba" as a substring.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n2 = q2                      Declares node n2 with display label "q2".
    //   n3 = q3                      Declares node n3 with display label "q3".
    //   n0 = (280.0, 360.0)          Canvas position of n0 in the level-editor layout: x=280.0, y=360.0.
    //   n1 = (580.0, 360.0)          Canvas position of n1 in the level-editor layout: x=580.0, y=360.0.
    //   n2 = (880.0, 360.0)          Canvas position of n2 in the level-editor layout: x=880.0, y=360.0.
    //   n3 = (1180.0, 360.0)         Canvas position of n3 in the level-editor layout: x=1180.0, y=360.0.
    //   n3 is accepted               n3 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n0 = b                 Transition n0 --b--> n0  (fires on symbol "b").
    //   n1 to n1 = a                 Transition n1 --a--> n1  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n3 = a                 Transition n2 --a--> n3  (fires on symbol "a").
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   n2 to n0 = b                 Transition n2 --b--> n0  (fires on symbol "b").
    //   l0(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "b").
    //   l2(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "a").
    //   l5(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['regex_to_dfa_ab_star', 'regex_to_dfa_starts_a', 'regex_to_dfa_ends_b']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.06,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a regex in the goal banner and must build an equivalent DFA on the canvas.
    puzzleVariant: PuzzleVariant.regexToDfa,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: '(a+b)*aba(a+b)*',
  ),

  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'regex_to_dfa_even_as',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'Regex → DFA: b*(ab*ab*)*',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'Build a DFA over {a, b} equivalent to the regular expression:\n\n'
        '    b*(ab*ab*)*\n\n'
        "Matches all strings with an even number of a's (including zero a's).",
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = even                    Declares node n0 with display label "even".
    //   n1 = odd                     Declares node n1 with display label "odd".
    //   n0 = (500.0, 360.0)          Canvas position of n0 in the level-editor layout: x=500.0, y=360.0.
    //   n1 = (900.0, 360.0)          Canvas position of n1 in the level-editor layout: x=900.0, y=360.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   n0 to n0 = b                 Transition n0 --b--> n0  (fires on symbol "b").
    //   n1 to n1 = b                 Transition n1 --b--> n1  (fires on symbol "b").
    //   l0(a) curve = -80.0          Rendering hint: curvature/bow (-80.0px) for transition line l0 (labeled "a"), which connects two distinct states.
    //   l1(a) curve = -80.0          Rendering hint: curvature/bow (-80.0px) for transition line l1 (labeled "a"), which connects two distinct states.
    //   l2(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "b").
    //   l3(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['regex_to_dfa_ab_star', 'regex_to_dfa_starts_a', 'regex_to_dfa_ends_b']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.06,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.80,
    // Player's submission must be a valid DFA (one transition per symbol per state, no ~-jumps) before the equivalence check runs.
    requiredAutomatonType: RequiredAutomatonType.dfa,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a regex in the goal banner and must build an equivalent DFA on the canvas.
    puzzleVariant: PuzzleVariant.regexToDfa,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: 'b*(ab*ab*)*',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 29 — DFA → REGEX  (BASIC)  (x ≈ 1.09)
  //  Unlock from any level in layer 28.
  // ═══════════════════════════════════════════════════════════════════════════

  /// DFA accepts exactly "a".  Canonical answer: a
  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_to_regex_single_a',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'DFA → Regex: Accept "a"',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts only the single-character string "a".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n2 = dead                    Declares node n2 with display label "dead".
    //   n0 = (320.0, 360.0)          Canvas position of n0 in the level-editor layout: x=320.0, y=360.0.
    //   n1 = (660.0, 360.0)          Canvas position of n1 in the level-editor layout: x=660.0, y=360.0.
    //   n2 = (660.0, 580.0)          Canvas position of n2 in the level-editor layout: x=660.0, y=580.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n2 = b                 Transition n0 --b--> n2  (fires on symbol "b").
    //   n1 to n2 = a,b               Transition n1 --a,b--> n2  (fires on symbols a,b).
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   l3(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "a,b").
    //   l2(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['regex_to_dfa_a_or_b_star', 'regex_to_dfa_aba', 'regex_to_dfa_even_as']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.09,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.20,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a read-only DFA and must type an equivalent regex into the input box.
    puzzleVariant: PuzzleVariant.dfaToRegex,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: 'a',
  ),

  /// DFA accepts strings ending in "b".  Canonical answer: (a+b)*b
  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_to_regex_ends_b',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'DFA → Regex: Ends with b',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts all strings over {a, b} that end with "b".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n0 = (400.0, 360.0)          Canvas position of n0 in the level-editor layout: x=400.0, y=360.0.
    //   n1 = (780.0, 360.0)          Canvas position of n1 in the level-editor layout: x=780.0, y=360.0.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = b                 Transition n0 --b--> n1  (fires on symbol "b").
    //   n0 to n0 = a                 Transition n0 --a--> n0  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   n1 to n1 = b                 Transition n1 --b--> n1  (fires on symbol "b").
    //   l0(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a").
    //   l3(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['regex_to_dfa_a_or_b_star', 'regex_to_dfa_aba', 'regex_to_dfa_even_as']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.09,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a read-only DFA and must type an equivalent regex into the input box.
    puzzleVariant: PuzzleVariant.dfaToRegex,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: '(a+b)*b',
  ),

  /// DFA accepts strings with even number of a's.  Canonical answer: b*(ab*ab*)*
  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_to_regex_even_as',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: "DFA → Regex: Even a's",
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        "This DFA accepts all strings over {a, b} with an even number of a's.",
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = even                    Declares node n0 with display label "even".
    //   n1 = odd                     Declares node n1 with display label "odd".
    //   n0 = (500.0, 360.0)          Canvas position of n0 in the level-editor layout: x=500.0, y=360.0.
    //   n1 = (900.0, 360.0)          Canvas position of n1 in the level-editor layout: x=900.0, y=360.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   n0 to n0 = b                 Transition n0 --b--> n0  (fires on symbol "b").
    //   n1 to n1 = b                 Transition n1 --b--> n1  (fires on symbol "b").
    //   l0(a) curve = -80.0          Rendering hint: curvature/bow (-80.0px) for transition line l0 (labeled "a"), which connects two distinct states.
    //   l1(a) curve = -80.0          Rendering hint: curvature/bow (-80.0px) for transition line l1 (labeled "a"), which connects two distinct states.
    //   l2(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "b").
    //   l3(b) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['regex_to_dfa_a_or_b_star', 'regex_to_dfa_aba', 'regex_to_dfa_even_as']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.09,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.80,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a read-only DFA and must type an equivalent regex into the input box.
    puzzleVariant: PuzzleVariant.dfaToRegex,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: 'b*(ab*ab*)*',
  ),

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 30 — DFA → REGEX  (INTERMEDIATE)  (x ≈ 1.12)
  //  Unlock from any level in layer 29.
  // ═══════════════════════════════════════════════════════════════════════════

  /// DFA accepts strings starting with "ab".  Canonical answer: ab(a+b)*
  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_to_regex_starts_ab',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'DFA → Regex: Starts with ab',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts all strings over {a, b} that start with "ab".',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n2 = q2                      Declares node n2 with display label "q2".
    //   n3 = dead                    Declares node n3 with display label "dead".
    //   n0 = (240.0, 360.0)          Canvas position of n0 in the level-editor layout: x=240.0, y=360.0.
    //   n1 = (560.0, 360.0)          Canvas position of n1 in the level-editor layout: x=560.0, y=360.0.
    //   n2 = (880.0, 360.0)          Canvas position of n2 in the level-editor layout: x=880.0, y=360.0.
    //   n3 = (560.0, 600.0)          Canvas position of n3 in the level-editor layout: x=560.0, y=600.0.
    //   n2 is accepted               n2 is an accepting (double-ring) state.
    //   n0 to n1 = a                 Transition n0 --a--> n1  (fires on symbol "a").
    //   n0 to n3 = b                 Transition n0 --b--> n3  (fires on symbol "b").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n1 to n3 = a                 Transition n1 --a--> n3  (fires on symbol "a").
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   n3 to n3 = a,b               Transition n3 --a,b--> n3  (fires on symbols a,b).
    //   l4(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a,b").
    //   l5(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l5 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['dfa_to_regex_single_a', 'dfa_to_regex_ends_b', 'dfa_to_regex_even_as']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.12,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.20,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a read-only DFA and must type an equivalent regex into the input box.
    puzzleVariant: PuzzleVariant.dfaToRegex,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: 'ab(a+b)*',
  ),

  /// DFA accepts strings with no consecutive b's.  Canonical answer: a*(ba+)*b?
  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_to_regex_no_consec_b',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: "DFA → Regex: No Consecutive b's",
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        "This DFA accepts all strings over {a, b} containing no two consecutive b's.",
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = q0                      Declares node n0 with display label "q0".
    //   n1 = q1                      Declares node n1 with display label "q1".
    //   n2 = dead                    Declares node n2 with display label "dead".
    //   n0 = (400.0, 340.0)          Canvas position of n0 in the level-editor layout: x=400.0, y=340.0.
    //   n1 = (780.0, 340.0)          Canvas position of n1 in the level-editor layout: x=780.0, y=340.0.
    //   n2 = (580.0, 580.0)          Canvas position of n2 in the level-editor layout: x=580.0, y=580.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n1 is accepted               n1 is an accepting (double-ring) state.
    //   n0 to n1 = b                 Transition n0 --b--> n1  (fires on symbol "b").
    //   n0 to n0 = a                 Transition n0 --a--> n0  (fires on symbol "a").
    //   n1 to n0 = a                 Transition n1 --a--> n0  (fires on symbol "a").
    //   n1 to n2 = b                 Transition n1 --b--> n2  (fires on symbol "b").
    //   n2 to n2 = a,b               Transition n2 --a,b--> n2  (fires on symbols a,b).
    //   l0(a) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l0 (labeled "a").
    //   l4(a,b) loop angle = -1.5708 Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l4 (labeled "a,b").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['dfa_to_regex_single_a', 'dfa_to_regex_ends_b', 'dfa_to_regex_even_as']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.12,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.50,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'a', 'b'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a read-only DFA and must type an equivalent regex into the input box.
    puzzleVariant: PuzzleVariant.dfaToRegex,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
    targetRegex: 'a*(ba+)*b?',
  ),

  /// DFA accepts binary strings with even number of 0s.  Canonical answer: 1*(01*01*)*
  GameLevel(
    // Unique key for this level — used for unlock-rule references, kLevelById lookup, and save-progress persistence.
    id: 'dfa_to_regex_binary_mod2',
    // Level-card title shown in the level-select UI and atop the puzzle screen.
    title: 'DFA → Regex: Even 0s',
    // Task description shown at the top of the puzzle screen (may continue across the adjacent string-literal lines below).
    description:
        'A read-only DFA is shown on the canvas. Type a regular expression '
        'in the input box whose language is exactly what this DFA accepts.\n\n'
        'This DFA accepts binary strings over {0, 1} with an even number of 0s.',
    // Flutter asset path for a pre-drawn target SVG; left empty here because the target machine is defined inline via 'dsl' below instead.
    svgAsset: '',
    // Embedded DSL for the hidden target automaton (parsed by DslCodec.importFromDsl —
    // see import_export.dart for the full grammar). Line-by-line breakdown of the
    // content below:
    //   n0 = even                    Declares node n0 with display label "even".
    //   n1 = odd                     Declares node n1 with display label "odd".
    //   n0 = (504.7, 310.0)          Canvas position of n0 in the level-editor layout: x=504.7, y=310.0.
    //   n1 = (1030.0, 314.0)         Canvas position of n1 in the level-editor layout: x=1030.0, y=314.0.
    //   n0 is accepted               n0 is an accepting (double-ring) state.
    //   n0 to n1 = 0                 Transition n0 --0--> n1  (fires on symbol "0").
    //   n1 to n0 = 0                 Transition n1 --0--> n0  (fires on symbol "0").
    //   n0 to n0 = 1                 Transition n0 --1--> n0  (fires on symbol "1").
    //   n1 to n1 = 1                 Transition n1 --1--> n1  (fires on symbol "1").
    //   l0(0) curve = -74.1          Rendering hint: curvature/bow (-74.1px) for transition line l0 (labeled "0"), which connects two distinct states.
    //   l1(0) curve = -72.7          Rendering hint: curvature/bow (-72.7px) for transition line l1 (labeled "0"), which connects two distinct states.
    //   l2(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l2 (labeled "1").
    //   l3(1) loop angle = -1.5708   Rendering hint: self-loop arc angle (-1.5708 rad) for transition line l3 (labeled "1").
    //   to n0                        Marks n0 as the start state — the start arrow points here.
    //   to n0 angle = -1.0000, 0.0000 Rendering hint: direction vector (-1.0000, 0.0000) the start arrow points along into n0.
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
    // Hidden target is checked for equivalence in finite-automaton (DFA/NFA) mode.
    automataMode: AutomataMode.ndfa,
    // Unlocked after the player has completed ANY ONE of the listed levels (OR gate).
    unlockRule: RequireAny(['dfa_to_regex_single_a', 'dfa_to_regex_ends_b', 'dfa_to_regex_even_as']),
    // Normalized horizontal position (0-1) of this level's node on the neural-network level-select map.
    x: 1.12,
    // Normalized vertical position (0-1) of this level's node on the neural-network level-select map.
    y: 0.80,
    // Alphabet used for DFA-completeness checking (flags missing transitions in the player submission); only consulted when requiredAutomatonType is dfa.
    alphabet: {'0', '1'},
    // UI grouping/theming tag — drives the node color/icon on the level-select map.
    tag: 'regex',
    // Player is shown a read-only DFA and must type an equivalent regex into the input box.
    puzzleVariant: PuzzleVariant.dfaToRegex,
    // Regex string shown to the player (goal banner for regexToDfa, hint alongside the canvas for dfaToRegex) — display only; the equivalence check always uses 'dsl' as ground truth.
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
//  [kLayerConstraintErrors] shortcut) at app startup — e.g. in main():
//
//    final errors = kLayerConstraintErrors;
//    if (errors.isNotEmpty) {
//      throw StateError('Layer constraint violations:\n${errors.join('\n')}');
//    }
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
//  "Layer" is determined by [computeLevelLayers] below — the single,
//  shared topological-sort implementation. level_select_screen.dart calls
//  this same function for its on-screen layout, so the startup validator
//  and the rendered map can never disagree about what a "layer" is.
// ─────────────────────────────────────────────────────────────────────────────

/// Assigns each level a layer index via a topological sort (Kahn's
/// algorithm) over the unlock-dependency graph: a level's layer is the
/// longest path (in steps of 2) from any root (always-unlocked) level.
/// Levels involved in an unlock cycle — which should never happen in a
/// well-formed level list — are pushed past the max assigned layer rather
/// than left unassigned, so a malformed graph still produces a usable
/// (if flagged-elsewhere) layout instead of crashing.
///
/// Shared by [LayerConstraintValidator] (startup validation) and
/// level_select_screen.dart (actual rendered layout) so the two can never
/// silently diverge.
Map<String, int> computeLevelLayers(List<GameLevel> levels) {
  // Extracts the prerequisite level ids from an UnlockRule, regardless of
  // its concrete subtype, so the graph-building loop below can stay
  // subtype-agnostic. Returns [] for AlwaysUnlocked (no prerequisites) and
  // for any rule type not recognized here.
  List<String> depsOf(UnlockRule rule) {
    if (rule is AlwaysUnlocked) return [];
    if (rule is RequireLevel) return [rule.levelId];
    if (rule is RequireAll) return rule.levelIds;
    if (rule is RequireAny) return rule.levelIds;
    // Recurses through nested RequireExpression trees, flattening every
    // leaf-level dependency into a single flat list via expand+toList.
    if (rule is RequireExpression) return rule.children.expand(depsOf).toList();
    return [];
  }

  // adj: forward adjacency list, prerequisite id -> list of level ids that
  // depend on it (i.e. edges point from "unlocks earlier" to "unlocks later").
  final Map<String, List<String>> adj = {for (final l in levels) l.id: []};
  // indeg: in-degree (number of not-yet-processed prerequisites) per level id;
  // this is Kahn's-algorithm bookkeeping for the topological sort below.
  final Map<String, int> indeg = {for (final l in levels) l.id: 0};

  // Build the graph: for every level, walk its unlock-rule dependencies and
  // record a forward edge dep -> level, bumping level's in-degree by one per
  // dependency. Dependencies on unknown/removed ids are silently skipped
  // (adj.containsKey check) rather than crashing.
  for (final l in levels) {
    for (final d in depsOf(l.unlockRule)) {
      if (!adj.containsKey(d)) continue;
      adj[d] = [...adj[d]!, l.id];
      indeg[l.id] = indeg[l.id]! + 1;
    }
  }

  // q: the Kahn's-algorithm work queue of ids whose remaining in-degree has
  // hit zero (i.e. every prerequisite has already been processed).
  final List<String> q = [];
  // layer: the result map being built — each id's longest-path distance (in
  // steps of 2) from a root. Initialized to 0 for every level (roots keep
  // this value; everything else gets overwritten as edges relax below).
  final Map<String, int> layer = {for (final l in levels) l.id: 0};
  // Seed the queue with every root: a level with zero prerequisites (i.e.
  // AlwaysUnlocked, or an unlock rule whose every dependency id was
  // filtered out above) starts the sort at layer 0.
  for (final id in indeg.keys) {
    if (indeg[id] == 0) q.add(id);
  }

  // Standard Kahn's-algorithm BFS: repeatedly pop a "ready" id, relax the
  // layer of everything it unlocks (longest-path relaxation: only raise a
  // neighbor's layer, never lower it), decrement the neighbor's in-degree,
  // and enqueue the neighbor once ALL of its prerequisites have been
  // processed (in-degree reaches 0).
  while (q.isNotEmpty) {
    final cur = q.removeAt(0);
    for (final next in adj[cur]!) {
      // +2 (not +1) reserves an odd layer between consecutive levels for
      // visual spacing on the level-select map — see the x/y layout
      // comments above kAllLevels.
      final candidate = layer[cur]! + 2;
      if (candidate > layer[next]!) layer[next] = candidate;
      indeg[next] = indeg[next]! - 1;
      if (indeg[next] == 0) q.add(next);
    }
  }

  // Anything still left with indeg > 0 here is part of an unlock cycle (a
  // malformed level list — should never happen, but this keeps the
  // function total instead of looping forever or leaving ids unassigned).
  // Each such id is pushed one layer past the current maximum, in
  // Map-iteration order, so the graph still yields *a* usable layout.
  int maxAssigned = layer.values.fold(0, (a, b) => a > b ? a : b);
  for (final id in indeg.keys) {
    if (indeg[id]! > 0) {
      maxAssigned += 1;
      layer[id] = maxAssigned;
    }
  }
  return layer;
}

abstract final class LayerConstraintValidator {
  /// Returns a list of human-readable error strings.  Empty means all good.
  static List<String> validate(List<GameLevel> levels) {
    // Reuse the same topological layering used for the on-screen map, so
    // "layer" means exactly the same thing here as it does when rendered.
    final layerById = computeLevelLayers(levels);
    // Group levels by their assigned layer index so each layer's rules can
    // be checked against the full set of levels sharing that layer.
    final Map<int, List<GameLevel>> byLayer = {};
    for (final l in levels) {
      byLayer.putIfAbsent(layerById[l.id]!, () => []).add(l);
    }

    final errors = <String>[];

    for (final entry in byLayer.entries) {
      final layerIdx = entry.key;
      final members = entry.value;

      // Partition this layer's members into the three mutually-exclusive
      // categories the rules below reason about.
      final tutorials = members.where((l) => l.isTutorial).toList();
      final bosses    = members.where((l) => l.isBoss).toList();
      final regular   = members.where((l) => !l.isTutorial && !l.isBoss).toList();
      // Pre-formatted, quoted, comma-joined id list reused by multiple error messages below.
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
}

/// Shortcut: returns validation error strings for [kAllLevels].
/// Use in an assert at startup — empty list means all constraints pass.
List<String> get kLayerConstraintErrors =>
    LayerConstraintValidator.validate(kAllLevels);