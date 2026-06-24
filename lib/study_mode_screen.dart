// ─────────────────────────────────────────────────────────────────────────────
//  study_mode_screen.dart
//
//  Interactive practice mode — generates unlimited regex↔DFA challenges
//  that are separate from the main game.  Two modes, selectable from the
//  top bar:
//
//    REGEX → DFA   Show a regular expression; player draws the equivalent DFA.
//                  Checked with FA equivalence (same as game mode).
//
//    DFA → REGEX   Show a read-only DFA; player types an equivalent regex.
//                  Checked with FA equivalence.
//
//  Challenges are drawn from a curated pool of (regex, alphabet) pairs that
//  span easy → hard.  Each round the pool is shuffled; when exhausted it
//  reshuffles so practice never ends.  No flashcards, no self-grading —
//  every round has a real machine-checked answer.
//
//  The puzzle UX reuses the same widget structure the game puzzle screen uses
//  so the interaction is identical: the automata_screen canvas for drawing,
//  the FA-equivalence checker for grading.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'fa_equivalence.dart';
import 'fa_to_regex.dart';
import 'game_level.dart';
import 'models.dart';
import 'regex_engine.dart';
import 'widgets/app_theme.dart';
import 'widgets/app_theme_settings.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;
import 'widgets/automata_canvas_embed.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Challenge pool
// ─────────────────────────────────────────────────────────────────────────────

class _Challenge {
  final String regex;
  final Set<String> alphabet;
  final _Difficulty difficulty;

  const _Challenge({
    required this.regex,
    required this.alphabet,
    required this.difficulty,
  });
}

enum _Difficulty { easy, medium, hard }

// ─────────────────────────────────────────────────────────────────────────────
//  Procedural challenge generator
//
//  Builds a fresh shuffled list of _Challenge objects on demand.
//  Regexes are assembled from parameterised templates so each call produces
//  a different ordering and, for templates that accept substitutable symbols,
//  different concrete expressions.
// ─────────────────────────────────────────────────────────────────────────────

/// All alphabets the generator may pick from.
const _kAlphabets = [
  {'a', 'b'},
  {'0', '1'},
  {'x', 'y'},
  {'p', 'q'},
];

/// Generates a fresh list of [count] randomised challenges.
List<_Challenge> _generateChallenges(Random rng, {int count = 30}) {
  final results = <_Challenge>[];

  // Each entry is a factory that takes (rng, alphabet) and returns a regex.
  // Factories that don't need both symbols only use the first/second element.
  final alphabets = List.of(_kAlphabets)..shuffle(rng);

  // We'll cycle through alphabets and difficulty buckets.
  final easyTemplates   = _kEasyTemplates;
  final mediumTemplates = _kMediumTemplates;
  final hardTemplates   = _kHardTemplates;

  // Shuffle each bucket independently.
  final easy   = List.of(easyTemplates)..shuffle(rng);
  final medium = List.of(mediumTemplates)..shuffle(rng);
  final hard   = List.of(hardTemplates)..shuffle(rng);

  // Interleave difficulties ~30/40/30 over [count] items.
  final targets = [
    (_Difficulty.easy,   (count * 0.30).round()),
    (_Difficulty.medium, (count * 0.40).round()),
    (_Difficulty.hard,   count - (count * 0.30).round() - (count * 0.40).round()),
  ];

  for (final (diff, n) in targets) {
    final pool = switch (diff) {
      _Difficulty.easy   => easy,
      _Difficulty.medium => medium,
      _Difficulty.hard   => hard,
    };
    for (int i = 0; i < n; i++) {
      final template = pool[i % pool.length];
      final alphabet = alphabets[rng.nextInt(alphabets.length)];
      final symbols  = alphabet.toList()..sort();
      final a = symbols[0];
      final b = symbols.length > 1 ? symbols[1] : symbols[0];
      results.add(_Challenge(
        regex:      template(a, b, rng),
        alphabet:   alphabet,
        difficulty: diff,
      ));
    }
  }

  results.shuffle(rng);
  return results;
}

// Template signature: (firstSymbol, secondSymbol, rng) → regex string.
typedef _RegexTemplate = String Function(String a, String b, Random rng);

// ── Easy templates ────────────────────────────────────────────────────────────
const List<_RegexTemplate> _kEasyTemplates = [
  // Single symbol
  _tSingle,
  // Exact two-symbol string
  _tExactTwo,
  // Union of two symbols
  _tUnionTwo,
  // Star of first symbol
  _tStarA,
  // Star of union
  _tStarUnion,
  // First symbol then star of second
  _tABStar,
  // Star of first then second
  _tStarAB,
  // Optional single symbol
  _tOptional,
  // Exact three-symbol string
  _tExactThree,
  // Two-symbol string or empty
  _tTwoOrEps,
];

String _tSingle(String a, String b, Random rng)      => rng.nextBool() ? a : b;
String _tExactTwo(String a, String b, Random rng)    => '$a$b';
String _tUnionTwo(String a, String b, Random rng)    => '$a+$b';
String _tStarA(String a, String b, Random rng)       => '$a*';
String _tStarUnion(String a, String b, Random rng)   => '($a+$b)*';
String _tABStar(String a, String b, Random rng)      => '$a$b*';
String _tStarAB(String a, String b, Random rng)      => '$a*$b';
String _tOptional(String a, String b, Random rng)    => rng.nextBool() ? '$a?' : '$b?';
String _tExactThree(String a, String b, Random rng)  {
  final s = [a, b, a];
  if (rng.nextBool()) s[1] = a;
  return s.join();
}
String _tTwoOrEps(String a, String b, Random rng)    => '($a$b)?';

// ── Medium templates ──────────────────────────────────────────────────────────
const List<_RegexTemplate> _kMediumTemplates = [
  _tEndsWith,
  _tStartsWith,
  _tContainsSub,
  _tExactlyOneB,
  _tRepeatPair,
  _tEvenCountA,
  _tStarAStar,
  _tEvenLength,
  _tNotEmpty,
  _tAtLeastTwo,
];

String _tEndsWith(String a, String b, Random rng)    => '($a+$b)*$b';
String _tStartsWith(String a, String b, Random rng)  => '$a($a+$b)*';
String _tContainsSub(String a, String b, Random rng) => '($a+$b)*$a$b($a+$b)*';
String _tExactlyOneB(String a, String b, Random rng) => '$a*$b$a*';
String _tRepeatPair(String a, String b, Random rng)  => '($a$b)*';
String _tEvenCountA(String a, String b, Random rng)  => '$b*($a$b*$a$b*)*';
String _tStarAStar(String a, String b, Random rng)   => '$a*$b*';
String _tEvenLength(String a, String b, Random rng)  => '(($a+$b)($a+$b))*';
String _tNotEmpty(String a, String b, Random rng)    => '($a+$b)($a+$b)*';
String _tAtLeastTwo(String a, String b, Random rng)  =>
    '($a+$b)*$a($a+$b)*$a($a+$b)*';

// ── Hard templates ────────────────────────────────────────────────────────────
const List<_RegexTemplate> _kHardTemplates = [
  _tContainsLength3Sub,
  _tStartsWith2,
  _tThirdFromEnd,
  _tEvenBothCounts,
  _tComplexSuffix,
  _tRepeatTriple,
  _tOddLength,
  _tContainsDouble,
  _tAtLeastThree,
  _tMixedSuffix,
];

String _tContainsLength3Sub(String a, String b, Random rng) {
  final sub = rng.nextBool() ? '$a$b$a' : '$b$a$b';
  return '($a+$b)*$sub($a+$b)*';
}
String _tStartsWith2(String a, String b, Random rng)   => '$a$b($a+$b)*';
String _tThirdFromEnd(String a, String b, Random rng)  =>
    '($a+$b)*$a($a+$b)($a+$b)';
String _tEvenBothCounts(String a, String b, Random rng) =>
    '($a$a+$b$b+($a$b+$b$a)($a$a+$b$b)*($a$b+$b$a))*';
String _tComplexSuffix(String a, String b, Random rng)  =>
    '$a*($b$a+)*$b?';
String _tRepeatTriple(String a, String b, Random rng)   => '($a$b$a)*';
String _tOddLength(String a, String b, Random rng)      =>
    '($a+$b)(($a+$b)($a+$b))*';
String _tContainsDouble(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return '($a+$b)*$sym$sym($a+$b)*';
}
String _tAtLeastThree(String a, String b, Random rng)   =>
    '($a+$b)*$a($a+$b)*$a($a+$b)*$a($a+$b)*';
String _tMixedSuffix(String a, String b, Random rng)    =>
    '($a+$b)*($a$b+$b$a)($a+$b)*';


// ─────────────────────────────────────────────────────────────────────────────
//  Practice mode enum
// ─────────────────────────────────────────────────────────────────────────────

enum _PracticeMode {
  regexToDfa('REGEX → DFA', Icons.functions),
  dfaToRegex('DFA → REGEX', Icons.account_tree_outlined);

  const _PracticeMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Result of grading a player's attempt
// ─────────────────────────────────────────────────────────────────────────────

class _GradeResult {
  final bool correct;
  final String? counterexample; // null when correct
  final String? error;          // parse / build error

  const _GradeResult.correct()
      : correct = true,
        counterexample = null,
        error = null;

  const _GradeResult.wrong(this.counterexample)
      : correct = false,
        error = null;

  const _GradeResult.parseError(this.error)
      : correct = false,
        counterexample = null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  StudyModeScreen
// ─────────────────────────────────────────────────────────────────────────────

class StudyModeScreen extends StatefulWidget {
  /// Called when the user taps "SANDBOX" — navigate to the free-canvas screen.
  final VoidCallback onGoToSandbox;

  // Kept for API compat with old callers.
  final VoidCallback? onGoToStudy;
  final dynamic progressStore; // GameProgressStore? — not used here

  const StudyModeScreen({
    super.key,
    VoidCallback? onGoToSandbox,
    this.onGoToStudy,
    this.progressStore,
  }) : onGoToSandbox = onGoToSandbox ?? _noop;

  @override
  State<StudyModeScreen> createState() => _StudyModeScreenState();
}

void _noop() {}

// ─────────────────────────────────────────────────────────────────────────────

class _StudyModeScreenState extends State<StudyModeScreen>
    with TickerProviderStateMixin {
  final _rng = Random();

  _PracticeMode _mode = _PracticeMode.regexToDfa;

  // The working queue — a shuffled copy of _kPool.
  late List<_Challenge> _queue;
  int _queueIndex = 0;

  // Session counters
  int _attempted = 0;
  int _correct = 0;

  // Per-round state
  _GradeResult? _gradeResult;
  bool _submitted = false;

  // For DFA → REGEX: player types a regex into this controller.
  final TextEditingController _regexInputCtrl = TextEditingController();
  final FocusNode _regexInputFocus = FocusNode();

  // For REGEX → DFA: player draws on an embedded mini-canvas.
  // We represent their drawn FA here; the embedded canvas writes into these.
  Map<String, NodeData> _playerNodes = {};
  Map<String, LineData> _playerLines = {};
  StartArrowData? _playerStart;

  // Entry animation
  late final AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _buildQueue();
  }

  @override
  void dispose() {
    _regexInputCtrl.dispose();
    _regexInputFocus.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  // ── Queue management ──────────────────────────────────────────────────────

  void _buildQueue() {
    _queue = _generateChallenges(_rng);
    _queueIndex = 0;
  }

  _Challenge get _current => _queue[_queueIndex];

  void _nextChallenge() {
    _queueIndex++;
    if (_queueIndex >= _queue.length) _buildQueue();

    setState(() {
      _gradeResult = null;
      _submitted = false;
      _playerNodes = {};
      _playerLines = {};
      _playerStart = null;
      _regexInputCtrl.clear();
    });

    _entryCtrl
      ..reset()
      ..forward();
  }

  void _switchMode(_PracticeMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _gradeResult = null;
      _submitted = false;
      _playerNodes = {};
      _playerLines = {};
      _playerStart = null;
      _regexInputCtrl.clear();
    });
    _buildQueue();
    _entryCtrl
      ..reset()
      ..forward();
  }

  // ── Grading ───────────────────────────────────────────────────────────────

  /// Grade the player's DFA against the target regex (REGEX → DFA mode).
  _GradeResult _gradePlayerDfa() {
    if (_playerStart == null || _playerNodes.isEmpty) {
      return const _GradeResult.parseError('Draw some states first, then hit Check.');
    }

    // Build target DFA from the challenge regex.
    final targetResult = regexToDfa(_current.regex.replaceAll(' ', ''));
    if (targetResult.isError) {
      return _GradeResult.parseError('Internal error: ${targetResult.error}');
    }

    // Compare player FA to target FA.
    final eq = checkEquivalence(
      nodes1: _playerNodes,
      lines1: _playerLines,
      startArrow1: _playerStart,
      nodes2: targetResult.nodes,
      lines2: targetResult.lines,
      startArrow2: targetResult.startArrow,
    );

    if (eq.status == EquivalenceStatus.equivalent) return const _GradeResult.correct();
    return _GradeResult.wrong(eq.witness);
  }

  /// Grade the player's regex string against the target DFA (DFA → REGEX mode).
  _GradeResult _gradePlayerRegex() {
    final raw = _regexInputCtrl.text.trim();
    if (raw.isEmpty) {
      return const _GradeResult.parseError('Type a regular expression first.');
    }

    // Build player NFA from their typed regex.
    final playerResult = regexToNfa(raw);
    if (playerResult.isError) {
      return _GradeResult.parseError('Parse error: ${playerResult.error}');
    }

    // Build target DFA from the challenge's canonical regex.
    final targetResult = regexToDfa(_current.regex.replaceAll(' ', ''));
    if (targetResult.isError) {
      return _GradeResult.parseError('Internal error building target.');
    }

    final eq = checkEquivalence(
      nodes1: playerResult.nodes,
      lines1: playerResult.lines,
      startArrow1: playerResult.startArrow,
      nodes2: targetResult.nodes,
      lines2: targetResult.lines,
      startArrow2: targetResult.startArrow,
    );

    if (eq.status == EquivalenceStatus.equivalent) return const _GradeResult.correct();
    return _GradeResult.wrong(eq.witness);
  }

  void _submit() {
    final result = _mode == _PracticeMode.regexToDfa
        ? _gradePlayerDfa()
        : _gradePlayerRegex();

    setState(() {
      _gradeResult = result;
      _submitted = true;
      if (result.error == null) _attempted++;
      if (result.correct) _correct++;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final challenge = _current;

    return Scaffold(
      backgroundColor: theme.bg,
      body: Column(
        children: [
          _TopBar(
            mode: _mode,
            onModeChanged: _switchMode,
            correct: _correct,
            total: _attempted,
            onGoToSandbox: widget.onGoToSandbox,
          ),
          Expanded(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _entryCtrl,
                curve: Curves.easeOut,
              ),
              child: _ChallengeBody(
                key: ValueKey('${_mode.name}:${_queueIndex}'),
                mode: _mode,
                challenge: challenge,
                queueIndex: _queueIndex,
                queueTotal: _queue.length,
                gradeResult: _gradeResult,
                submitted: _submitted,
                regexInputCtrl: _regexInputCtrl,
                regexInputFocus: _regexInputFocus,
                onPlayerFaChanged: (nodes, lines, start) {
                  _playerNodes = nodes;
                  _playerLines = lines;
                  _playerStart = start;
                },
                onSubmit: _submitted && _gradeResult?.error != null
                    ? _submit        // allow re-try on parse errors
                    : _submitted
                        ? _nextChallenge
                        : _submit,
                onSkip: _nextChallenge,
                theme: theme,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final _PracticeMode mode;
  final ValueChanged<_PracticeMode> onModeChanged;
  final int correct;
  final int total;
  final VoidCallback onGoToSandbox;

  const _TopBar({
    required this.mode,
    required this.onModeChanged,
    required this.correct,
    required this.total,
    required this.onGoToSandbox,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Title
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PRACTICE',
                  style: GoogleFonts.orbitron(
                    color: theme.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  'MODE',
                  style: GoogleFonts.orbitron(
                    color: theme.textDim,
                    fontSize: 9,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 16),

            // Mode selector chips
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _PracticeMode.values.map((m) {
                    final sel = m == mode;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => onModeChanged(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel
                                ? theme.accent.withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: sel
                                  ? theme.accent.withOpacity(0.8)
                                  : theme.borderMid,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(m.icon,
                                  size: 12,
                                  color: sel ? theme.accent : theme.textDim),
                              const SizedBox(width: 5),
                              Text(
                                m.label,
                                style: GoogleFonts.orbitron(
                                  color: sel ? theme.accent : theme.textDim,
                                  fontSize: 8,
                                  letterSpacing: 1.5,
                                  fontWeight: sel
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Score
            if (total > 0)
              Text(
                '$correct / $total',
                style: GoogleFonts.orbitron(
                  color: theme.textMid,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),

            const SizedBox(width: 8),

            // Theme settings
            IconButton(
              tooltip: 'Appearance',
              icon:
                  Icon(Icons.palette_outlined, color: theme.textMid, size: 20),
              onPressed: () => showAppThemeSettings(context),
            ),

            // Sandbox shortcut
            TextButton(
              onPressed: onGoToSandbox,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(color: theme.borderMid),
                ),
              ),
              child: Text(
                'SANDBOX',
                style: GoogleFonts.orbitron(
                    color: theme.textDim, fontSize: 8, letterSpacing: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Challenge body  (keyed so it fully rebuilds on new challenge)
// ─────────────────────────────────────────────────────────────────────────────

class _ChallengeBody extends StatelessWidget {
  final _PracticeMode mode;
  final _Challenge challenge;
  final int queueIndex;
  final int queueTotal;
  final _GradeResult? gradeResult;
  final bool submitted;
  final TextEditingController regexInputCtrl;
  final FocusNode regexInputFocus;
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onPlayerFaChanged;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  final AppThemeNotifier theme;

  const _ChallengeBody({
    super.key,
    required this.mode,
    required this.challenge,
    required this.queueIndex,
    required this.queueTotal,
    required this.gradeResult,
    required this.submitted,
    required this.regexInputCtrl,
    required this.regexInputFocus,
    required this.onPlayerFaChanged,
    required this.onSubmit,
    required this.onSkip,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress bar
          _ProgressRow(
            index: queueIndex,
            total: queueTotal,
            theme: theme,
          ),

          const SizedBox(height: 16),

          // Challenge card
          _ChallengeCard(
            mode: mode,
            challenge: challenge,
            theme: theme,
          ),

          const SizedBox(height: 16),

          // Input area (drawing canvas for REGEX→DFA, text field for DFA→REGEX)
          Expanded(
            child: mode == _PracticeMode.regexToDfa
                ? _DfaDrawingArea(
                    challenge: challenge,
                    submitted: submitted,
                    gradeResult: gradeResult,
                    onFaChanged: onPlayerFaChanged,
                    theme: theme,
                  )
                : _RegexInputArea(
                    challenge: challenge,
                    controller: regexInputCtrl,
                    focusNode: regexInputFocus,
                    submitted: submitted,
                    gradeResult: gradeResult,
                    theme: theme,
                  ),
          ),

          const SizedBox(height: 14),

          // Feedback banner (shown after submission)
          if (gradeResult != null)
            _FeedbackBanner(
              result: gradeResult!,
              challenge: challenge,
              mode: mode,
              theme: theme,
            ),

          if (gradeResult != null) const SizedBox(height: 12),

          // Action row
          _ActionRow(
            submitted: submitted,
            gradeResult: gradeResult,
            onSubmit: onSubmit,
            onSkip: onSkip,
            theme: theme,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Progress row
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  final int index;
  final int total;
  final AppThemeNotifier theme;

  const _ProgressRow(
      {required this.index, required this.total, required this.theme});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (index + 1) / total : 0.0;
    return Row(
      children: [
        Text(
          '${index + 1} / $total',
          style: GoogleFonts.sourceCodePro(
              color: theme.textDim, fontSize: 11, letterSpacing: 1),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 3,
              backgroundColor: theme.gridLine,
              valueColor:
                  AlwaysStoppedAnimation(theme.accent.withOpacity(0.6)),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Challenge card  — shows what the player needs to do
// ─────────────────────────────────────────────────────────────────────────────

class _ChallengeCard extends StatelessWidget {
  final _PracticeMode mode;
  final _Challenge challenge;
  final AppThemeNotifier theme;

  const _ChallengeCard({
    required this.mode,
    required this.challenge,
    required this.theme,
  });

  Color get _diffColor {
    switch (challenge.difficulty) {
      case _Difficulty.easy:
        return const Color(0xFF4CAF50);
      case _Difficulty.medium:
        return const Color(0xFFFFB300);
      case _Difficulty.hard:
        return const Color(0xFFF44336);
    }
  }

  String get _diffLabel {
    switch (challenge.difficulty) {
      case _Difficulty.easy:
        return 'EASY';
      case _Difficulty.medium:
        return 'MEDIUM';
      case _Difficulty.hard:
        return 'HARD';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = mode == _PracticeMode.regexToDfa
        ? theme.accent
        : theme.accentGreen;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.07),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Mode chip
              _Chip(
                label: mode.label,
                color: accentColor,
              ),
              const SizedBox(width: 8),
              // Difficulty chip
              _Chip(
                label: _diffLabel,
                color: _diffColor,
              ),
              const Spacer(),
              // Alphabet
              Text(
                'Σ = {${(challenge.alphabet.toList()..sort()).join(', ')}}',
                style: GoogleFonts.courierPrime(
                  color: theme.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // The regex (shown large and prominent)
          if (mode == _PracticeMode.regexToDfa) ...[
            Text(
              'REGULAR EXPRESSION',
              style: GoogleFonts.orbitron(
                color: theme.textDim,
                fontSize: 8,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.accent.withOpacity(0.2)),
              ),
              child: SelectableText(
                challenge.regex,
                style: GoogleFonts.courierPrime(
                  color: theme.accent,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ] else ...[
            // DFA→REGEX: no description shown — alphabet is the only hint
            Text(
              'ALPHABET',
              style: GoogleFonts.orbitron(
                color: theme.textDim,
                fontSize: 8,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.accentGreen.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: theme.accentGreen.withOpacity(0.20)),
              ),
              child: Text(
                'Σ = {${(challenge.alphabet.toList()..sort()).join(', ')}}',
                style: GoogleFonts.courierPrime(
                  color: theme.accentGreen,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Task instruction
          Row(
            children: [
              Icon(
                mode == _PracticeMode.regexToDfa
                    ? Icons.edit_outlined
                    : Icons.keyboard_outlined,
                color: theme.textDim,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  mode == _PracticeMode.regexToDfa
                      ? 'Draw a DFA on the canvas below whose language equals this regex.'
                      : 'Type a regular expression below that describes exactly this language.',
                  style: GoogleFonts.sourceCodePro(
                    color: theme.textDim,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DFA drawing area  (REGEX → DFA mode)
//
//  Uses the same automata sandbox the game uses, just embedded here.
//  The player draws; we read the FA out via callback.
// ─────────────────────────────────────────────────────────────────────────────

class _DfaDrawingArea extends StatefulWidget {
  final _Challenge challenge;
  final bool submitted;
  final _GradeResult? gradeResult;
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onFaChanged;
  final AppThemeNotifier theme;

  const _DfaDrawingArea({
    super.key,
    required this.challenge,
    required this.submitted,
    required this.gradeResult,
    required this.onFaChanged,
    required this.theme,
  });

  @override
  State<_DfaDrawingArea> createState() => _DfaDrawingAreaState();
}

class _DfaDrawingAreaState extends State<_DfaDrawingArea> {
  // The player's in-progress FA lives here; the embedded AutomataDrawer
  // mutates these via its onChanged callback.
  Map<String, NodeData> _nodes = {};
  Map<String, LineData> _lines = {};
  StartArrowData? _start;

  void _onFaChanged(
    Map<String, NodeData> nodes,
    Map<String, LineData> lines,
    StartArrowData? start,
  ) {
    _nodes = nodes;
    _lines = lines;
    _start = start;
    widget.onFaChanged(nodes, lines, start);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.borderMid),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // The actual drawing canvas — imported from the existing widget.
          // AutomataDrawer exposes an onChanged callback that we use.
          Positioned.fill(
            child: AutomataDrawerEmbed(
              mode: AutomataMode.ndfa,
              initialNodes: const {},
              initialLines: const {},
              initialStart: null,
              onChanged: _onFaChanged,
              readOnly: widget.submitted && (widget.gradeResult?.correct ?? false),
            ),
          ),

          // Watermark label
          Positioned(
            top: 10,
            right: 14,
            child: Text(
              'YOUR DFA',
              style: GoogleFonts.orbitron(
                color: theme.textDim.withOpacity(0.4),
                fontSize: 8,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Regex input area  (DFA → REGEX mode)
// ─────────────────────────────────────────────────────────────────────────────

class _RegexInputArea extends StatelessWidget {
  final _Challenge challenge;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitted;
  final _GradeResult? gradeResult;
  final AppThemeNotifier theme;

  const _RegexInputArea({
    super.key,
    required this.challenge,
    required this.controller,
    required this.focusNode,
    required this.submitted,
    required this.gradeResult,
    required this.theme,
  });

  // Show the equivalent DFA diagram (read-only) generated from the target regex.
  @override
  Widget build(BuildContext context) {
    final correct = gradeResult?.correct ?? false;
    final borderColor = !submitted
        ? theme.accentGreen.withOpacity(0.35)
        : correct
            ? const Color(0xFF4CAF50)
            : theme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Read-only DFA preview (so player can actually see the machine)
        Expanded(
          flex: 3,
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
                  child: _ReadOnlyDfaPreview(
                    regex: challenge.regex,
                    alphabet: challenge.alphabet,
                    theme: theme,
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 14,
                  child: Text(
                    'TARGET DFA  (read-only)',
                    style: GoogleFonts.orbitron(
                      color: theme.textDim.withOpacity(0.5),
                      fontSize: 8,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Regex text field
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'YOUR REGEX',
                  style: GoogleFonts.orbitron(
                    color: theme.textDim,
                    fontSize: 8,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly:
                        submitted && correct, // lock on correct answer
                    style: GoogleFonts.courierPrime(
                      color: !submitted
                          ? theme.textLight
                          : correct
                              ? const Color(0xFF4CAF50)
                              : theme.error,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g.  a*(ba+b)*',
                      hintStyle: GoogleFonts.courierPrime(
                        color: theme.textDim.withOpacity(0.5),
                        fontSize: 18,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      // pressing Enter submits
                    },
                  ),
                ),
                // Operator quick-reference
                Row(
                  children: [
                    _OpHint(op: '*', label: 'star', theme: theme),
                    const SizedBox(width: 10),
                    _OpHint(op: '+', label: 'or', theme: theme),
                    const SizedBox(width: 10),
                    _OpHint(op: '~', label: 'ε', theme: theme),
                    const SizedBox(width: 10),
                    _OpHint(op: '()', label: 'group', theme: theme),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OpHint extends StatelessWidget {
  final String op;
  final String label;
  final AppThemeNotifier theme;

  const _OpHint(
      {required this.op, required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: theme.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.accent.withOpacity(0.2)),
          ),
          child: Text(
            op,
            style: GoogleFonts.courierPrime(
              color: theme.accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.sourceCodePro(
            color: theme.textDim,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Read-only DFA preview widget
//  Builds the target DFA from the challenge regex and renders it read-only
//  using the same AutomataDrawerEmbed, but with readOnly: true.
// ─────────────────────────────────────────────────────────────────────────────

class _ReadOnlyDfaPreview extends StatefulWidget {
  final String regex;
  final Set<String> alphabet;
  final AppThemeNotifier theme;

  const _ReadOnlyDfaPreview({
    required this.regex,
    required this.alphabet,
    required this.theme,
  });

  @override
  State<_ReadOnlyDfaPreview> createState() => _ReadOnlyDfaPreviewState();
}

class _ReadOnlyDfaPreviewState extends State<_ReadOnlyDfaPreview> {
  Map<String, NodeData>? _nodes;
  Map<String, LineData>? _lines;
  StartArrowData? _start;
  String? _error;

  @override
  void initState() {
    super.initState();
    _build();
  }

  void _build() {
    final result = regexToDfa(widget.regex.replaceAll(' ', ''));
    if (result.isError) {
      _error = result.error;
    } else {
      _nodes = result.nodes;
      _lines = result.lines;
      _start = result.startArrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    if (_error != null) {
      return Center(
        child: Text(
          'Error building DFA: $_error',
          style:
              GoogleFonts.sourceCodePro(color: theme.error, fontSize: 12),
        ),
      );
    }

    if (_nodes == null) {
      return Center(
        child: CircularProgressIndicator(color: theme.accent),
      );
    }

    return AutomataDrawerEmbed(
      mode: AutomataMode.ndfa,
      initialNodes: _nodes!,
      initialLines: _lines!,
      initialStart: _start,
      onChanged: (_, __, ___) {}, // read-only; ignore
      readOnly: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Feedback banner
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackBanner extends StatelessWidget {
  final _GradeResult result;
  final _Challenge challenge;
  final _PracticeMode mode;
  final AppThemeNotifier theme;

  const _FeedbackBanner({
    required this.result,
    required this.challenge,
    required this.mode,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (result.error != null) {
      return _Banner(
        icon: Icons.warning_amber_rounded,
        color: theme.error,
        title: 'Cannot check yet',
        body: result.error!,
        theme: theme,
      );
    }

    if (result.correct) {
      return _Banner(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF4CAF50),
        title: 'Correct!',
        body: mode == _PracticeMode.regexToDfa
            ? 'Your DFA is equivalent to  ${challenge.regex}.'
            : 'Your regex describes the same language.',
        theme: theme,
      );
    }

    // Wrong — show counterexample
    final ce = result.counterexample ?? '';
    final ceDisplay = ce.isEmpty ? 'ε (empty string)' : '"$ce"';
    return _Banner(
      icon: Icons.close_rounded,
      color: theme.error,
      title: 'Not quite',
      body:
          'Counterexample: $ceDisplay\nYour machine and the target disagree on this string. Check it and try again.',
      theme: theme,
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final AppThemeNotifier theme;

  const _Banner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.orbitron(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.sourceCodePro(
                    color: theme.textLight,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action row
// ─────────────────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final bool submitted;
  final _GradeResult? gradeResult;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  final AppThemeNotifier theme;

  const _ActionRow({
    required this.submitted,
    required this.gradeResult,
    required this.onSubmit,
    required this.onSkip,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Parse error → "Try Again" + Skip
    if (submitted && gradeResult?.error != null) {
      return Row(
        children: [
          Expanded(
            child: _Btn(
              label: 'TRY AGAIN',
              icon: Icons.refresh_rounded,
              color: theme.accent,
              onTap: onSubmit,
            ),
          ),
          const SizedBox(width: 12),
          _Btn(
            label: 'SKIP',
            icon: Icons.skip_next_rounded,
            color: theme.textDim,
            small: true,
            onTap: onSkip,
          ),
        ],
      );
    }

    // Correct → "Next Challenge"
    if (submitted && (gradeResult?.correct ?? false)) {
      return _Btn(
        label: 'NEXT CHALLENGE',
        icon: Icons.arrow_forward_rounded,
        color: const Color(0xFF4CAF50),
        onTap: onSubmit, // onSubmit is wired to _nextChallenge at this point
      );
    }

    // Wrong → "Try Again" + Skip
    if (submitted && gradeResult != null) {
      return Row(
        children: [
          Expanded(
            child: _Btn(
              label: 'TRY AGAIN',
              icon: Icons.refresh_rounded,
              color: theme.error,
              onTap: onSkip, // go to next
            ),
          ),
          const SizedBox(width: 12),
          _Btn(
            label: 'SKIP',
            icon: Icons.skip_next_rounded,
            color: theme.textDim,
            small: true,
            onTap: onSkip,
          ),
        ],
      );
    }

    // Not yet submitted → "Check" + "Skip"
    return Row(
      children: [
        Expanded(
          child: _Btn(
            label: 'CHECK',
            icon: Icons.check_rounded,
            color: theme.accent,
            onTap: onSubmit,
          ),
        ),
        const SizedBox(width: 12),
        _Btn(
          label: 'SKIP',
          icon: Icons.skip_next_rounded,
          color: theme.textDim,
          small: true,
          onTap: onSkip,
        ),
      ],
    );
  }
}

class _Btn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool small;

  const _Btn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.small = false,
  });

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.symmetric(
          vertical: widget.small ? 10 : 14,
          horizontal: widget.small ? 16 : 20,
        ),
        decoration: BoxDecoration(
          color: _pressed
              ? widget.color.withOpacity(0.22)
              : widget.color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.color.withOpacity(_pressed ? 0.9 : 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon,
                color: widget.color, size: widget.small ? 16 : 18),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: GoogleFonts.orbitron(
                color: widget.color,
                fontSize: widget.small ? 8 : 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.orbitron(
          color: color,
          fontSize: 8,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataDrawerEmbed
//
//  Thin wrapper around AutomataCanvasEmbed so existing call-sites in this
//  file don't need to change.  The `mode` parameter is accepted for API
//  compatibility but AutomataCanvasEmbed is mode-agnostic at the canvas
//  level (mode-specific simulation is handled elsewhere).
// ─────────────────────────────────────────────────────────────────────────────

class AutomataDrawerEmbed extends StatelessWidget {
  final AutomataMode mode;
  final Map<String, NodeData> initialNodes;
  final Map<String, LineData> initialLines;
  final StartArrowData? initialStart;
  final void Function(
      Map<String, NodeData>, Map<String, LineData>, StartArrowData?) onChanged;
  final bool readOnly;

  const AutomataDrawerEmbed({
    super.key,
    required this.mode,
    required this.initialNodes,
    required this.initialLines,
    required this.initialStart,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return AutomataCanvasEmbed(
      initialNodes: initialNodes,
      initialLines: initialLines,
      initialStart: initialStart,
      onChanged: onChanged,
      readOnly: readOnly,
    );
  }
}