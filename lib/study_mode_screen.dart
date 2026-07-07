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

import 'dialogs/equivalence_dialog.dart'
    show checkEquivalence, EquivalenceStatus;
import 'game_data.dart' show GameProgressStore;
import 'game_level.dart' show GameLevel, kAllLevels;
import 'models.dart';
import 'simulator.dart';
import 'study_mode_pda.dart';
import 'study_mode_symbols.dart';
import 'tutorial_screen.dart' show TutorialScreen;
import 'widgets/app_theme.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;
import 'widgets/automata_canvas_embed.dart';
import 'widgets/responsive_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Challenge pool
// ─────────────────────────────────────────────────────────────────────────────

class _Challenge {
  final String regex;
  final Set<String> alphabet;
  final _Difficulty difficulty;
  /// Plain-language description used by the DESCRIBE → FA mode.
  /// Null for challenges generated from regex templates.
  final String? description;

  const _Challenge({
    required this.regex,
    required this.alphabet,
    required this.difficulty,
    this.description,
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

/// Generates a fresh list of [count] randomised challenges.
List<_Challenge> _generateChallenges(Random rng, {int count = 30}) {
  final results = <_Challenge>[];

  // We'll cycle through difficulty buckets; the alphabet for each challenge
  // is drawn fresh below via randomStudyAlphabet() so puzzles don't cluster
  // around the same couple of symbols.
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
      final alphabet = randomStudyAlphabet(rng);
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
  // Exact three-symbol string
  _tExactThree,
];

String _tSingle(String a, String b, Random rng)      => rng.nextBool() ? a : b;
String _tExactTwo(String a, String b, Random rng)    => '$a$b';
String _tUnionTwo(String a, String b, Random rng)    => '$a+$b';
String _tStarA(String a, String b, Random rng)       => '$a*';
String _tStarUnion(String a, String b, Random rng)   => '($a+$b)*';
String _tABStar(String a, String b, Random rng)      => '$a$b*';
String _tStarAB(String a, String b, Random rng)      => '$a*$b';
String _tExactThree(String a, String b, Random rng)  {
  final s = [a, b, a];
  if (rng.nextBool()) s[1] = a;
  return s.join();
}

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
    '$a*($b$a+)*';
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
//  Description-challenge templates
//
//  Each entry is a factory that receives (firstSymbol, secondSymbol, rng) and
//  returns a ({description, regex, difficulty}) record.  The description is the
//  plain-English prompt shown to the player; the regex is used internally for
//  grading only.
// ─────────────────────────────────────────────────────────────────────────────

typedef _DescTemplate = ({String description, String regex, _Difficulty difficulty})
    Function(String a, String b, Random rng);

/// 30 description-challenge templates spread across easy / medium / hard.
const List<_DescTemplate> _kDescTemplates = [
  // ── Easy ──────────────────────────────────────────────────────────────────

  // Accepts only the empty string
  _dOnlyEmpty,
  // Accepts exactly one specific symbol
  _dExactlyOneSymbol,
  // Accepts any single symbol from the alphabet
  _dAnySingleSymbol,
  // Accepts all strings (including empty)
  _dAllStrings,
  // Accepts strings consisting entirely of one repeated symbol
  _dRepeatOneSymbol,
  // Accepts strings of length exactly 2
  _dLengthExactly2,
  // Accepts strings that start with a specific symbol
  _dStartsWith,
  // Accepts strings that end with a specific symbol
  _dEndsWith,
  // Accepts the two-symbol string in both orders
  _dBothOrders,

  // ── Medium ────────────────────────────────────────────────────────────────

  // Accepts strings containing at least one of each symbol
  _dContainsBoth,
  // Accepts strings where the first and last symbol are the same
  _dFirstEqualsLast,
  // Accepts strings with an even number of a specific symbol
  _dEvenCount,
  // Accepts strings with an odd number of a specific symbol
  _dOddCount,
  // Accepts non-empty strings of even length
  _dEvenLength,
  // Accepts strings that contain exactly one occurrence of a specific symbol
  _dExactlyOne,
  // Accepts strings that do NOT contain a specific symbol
  _dNoSymbol,
  // Accepts strings where the second character (if it exists) is a specific symbol
  _dSecondIsSymbol,
  // Accepts strings of length at most 3
  _dLengthAtMost3,
  // Accepts strings that are a palindrome of length ≤ 2 (~, a, b, aa, bb)
  _dShortPalindrome,

  // ── Hard ──────────────────────────────────────────────────────────────────

  // Accepts strings where every occurrence of 'a' is immediately followed by 'b'
  _dAAlwaysFollowedByB,
  // Accepts strings that contain the substring consisting of two identical symbols in a row
  _dContainsDouble,
  // Accepts strings where the number of 'a's and 'b's are both even
  _dBothEven,
  // Accepts strings whose length is a multiple of 3
  _dLengthMod3,
  // Accepts strings that begin AND end with the same symbol
  _dSameEnds,
  // Accepts strings that contain at least two occurrences of a specific symbol consecutively
  _dAtLeastTwoConsecutive,
  // Accepts strings where the third-to-last symbol (if reachable) is a specific symbol
  _dThirdFromEnd,
  // Accepts strings over {a,b} where the count of 'a' mod 3 equals 0
  _dCountMod3,
];

// ── Easy desc templates ───────────────────────────────────────────────────────

({String description, String regex, _Difficulty difficulty})
    _dOnlyEmpty(String a, String b, Random rng) => (
          description: 'Build an FA that accepts only the empty string (~) '
              'and rejects every non-empty string.',
          regex: '~',
          difficulty: _Difficulty.easy,
        );

({String description, String regex, _Difficulty difficulty})
    _dExactlyOneSymbol(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts exactly the one-character string '
        '"$sym" and nothing else.',
    regex: sym,
    difficulty: _Difficulty.easy,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dAnySingleSymbol(String a, String b, Random rng) => (
          description: 'Build an FA that accepts any string of length exactly 1 '
              '(i.e. either "$a" or "$b"), and rejects all other strings.',
          regex: '$a+$b',
          difficulty: _Difficulty.easy,
        );

({String description, String regex, _Difficulty difficulty})
    _dAllStrings(String a, String b, Random rng) => (
          description: 'Build an FA that accepts every possible string over '
              '{$a, $b}, including the empty string.',
          regex: '($a+$b)*',
          difficulty: _Difficulty.easy,
        );

({String description, String regex, _Difficulty difficulty})
    _dRepeatOneSymbol(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts strings made up of zero or more '
        'copies of "$sym" (including ~), and rejects any string that '
        'contains "${ sym == a ? b : a }".',
    regex: '$sym*',
    difficulty: _Difficulty.easy,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dLengthExactly2(String a, String b, Random rng) => (
          description: 'Build an FA that accepts all strings of length exactly 2 '
              'over the alphabet {$a, $b}.',
          regex: '($a+$b)($a+$b)',
          difficulty: _Difficulty.easy,
        );

({String description, String regex, _Difficulty difficulty})
    _dStartsWith(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts all non-empty strings that begin '
        'with "$sym".',
    regex: '$sym($a+$b)*',
    difficulty: _Difficulty.easy,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dEndsWith(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts all strings (including length 1) '
        'that end with "$sym".',
    regex: '($a+$b)*$sym',
    difficulty: _Difficulty.easy,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dBothOrders(String a, String b, Random rng) => (
          description: 'Build an FA that accepts exactly the two strings '
              '"$a$b" and "$b$a", and nothing else.',
          regex: '$a$b+$b$a',
          difficulty: _Difficulty.easy,
        );

// ── Medium desc templates ─────────────────────────────────────────────────────

({String description, String regex, _Difficulty difficulty})
    _dContainsBoth(String a, String b, Random rng) => (
          description: 'Build an FA that accepts strings over {$a, $b} that '
              'contain at least one "$a" AND at least one "$b" (in any order).',
          regex: '($a+$b)*$a($a+$b)*$b($a+$b)*+($a+$b)*$b($a+$b)*$a($a+$b)*',
          difficulty: _Difficulty.medium,
        );

({String description, String regex, _Difficulty difficulty})
    _dFirstEqualsLast(String a, String b, Random rng) => (
          description: 'Build an FA that accepts strings of length ≥ 1 where '
              'the first and last character are the same symbol.',
          regex: '$a($a+$b)*$a+$b($a+$b)*$b+$a+$b',
          difficulty: _Difficulty.medium,
        );

({String description, String regex, _Difficulty difficulty})
    _dEvenCount(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  final other = sym == a ? b : a;
  return (
    description: 'Build an FA that accepts strings over {$a, $b} that contain '
        'an even number of "$sym"s (zero counts as even).',
    regex: '$other*($sym$other*$sym$other*)*',
    difficulty: _Difficulty.medium,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dOddCount(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  final other = sym == a ? b : a;
  return (
    description: 'Build an FA that accepts strings over {$a, $b} that contain '
        'an odd number of "$sym"s (at least one).',
    regex: '$other*$sym($other*$sym$other*$sym$other*)*',
    difficulty: _Difficulty.medium,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dEvenLength(String a, String b, Random rng) => (
          description: 'Build an FA that accepts all strings over {$a, $b} '
              'whose length is even (including the empty string, which has length 0).',
          regex: '(($a+$b)($a+$b))*',
          difficulty: _Difficulty.medium,
        );

({String description, String regex, _Difficulty difficulty})
    _dExactlyOne(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  final other = sym == a ? b : a;
  return (
    description: 'Build an FA that accepts strings over {$a, $b} that contain '
        'exactly one "$sym" (surrounded by any number of "$other"s).',
    regex: '$other*$sym$other*',
    difficulty: _Difficulty.medium,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dNoSymbol(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  final other = sym == a ? b : a;
  return (
    description: 'Build an FA that accepts strings over {$a, $b} that contain '
        'no "$sym" at all (only "$other"s, or the empty string).',
    regex: '$other*',
    difficulty: _Difficulty.medium,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dSecondIsSymbol(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts all strings of length ≥ 2 where '
        'the second character is "$sym".',
    regex: '($a+$b)$sym($a+$b)*',
    difficulty: _Difficulty.medium,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dLengthAtMost3(String a, String b, Random rng) => (
          description: 'Build an FA that accepts strings over {$a, $b} of '
              'length 0, 1, 2, or 3 — rejecting anything longer.',
          regex:
              '~+($a+$b)+($a+$b)($a+$b)+($a+$b)($a+$b)($a+$b)',
          difficulty: _Difficulty.medium,
        );

({String description, String regex, _Difficulty difficulty})
    _dShortPalindrome(String a, String b, Random rng) => (
          description: 'Build an FA that accepts only strings of length ≤ 2 '
              'that read the same forwards and backwards: '
              '~, "$a", "$b", "$a$a", and "$b$b".',
          regex: '~+$a+$b+$a$a+$b$b',
          difficulty: _Difficulty.medium,
        );

// ── Hard desc templates ───────────────────────────────────────────────────────

({String description, String regex, _Difficulty difficulty})
    _dAAlwaysFollowedByB(String a, String b, Random rng) => (
          description: 'Build an FA that accepts strings over {$a, $b} where '
              'every "$a" is immediately followed by a "$b" '
              '(the string may start with "$b"s and end with "$b"s, but no '
              '"$a" appears at the end or before another "$a").',
          regex: '$b*($a$b+)*',
          difficulty: _Difficulty.hard,
        );

({String description, String regex, _Difficulty difficulty})
    _dContainsDouble(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts strings over {$a, $b} that contain '
        'at least one occurrence of "$sym$sym" as a consecutive substring.',
    regex: '($a+$b)*$sym$sym($a+$b)*',
    difficulty: _Difficulty.hard,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dBothEven(String a, String b, Random rng) => (
          description: 'Build an FA over {$a, $b} that accepts strings where '
              'the number of "$a"s is even AND the number of "$b"s is even '
              '(zero counts as even for both).',
          regex: '($a$a+$b$b+($a$b+$b$a)($a$a+$b$b)*($a$b+$b$a))*',
          difficulty: _Difficulty.hard,
        );

({String description, String regex, _Difficulty difficulty})
    _dLengthMod3(String a, String b, Random rng) => (
          description: 'Build an FA that accepts strings over {$a, $b} whose '
              'length is divisible by 3 (including the empty string).',
          regex: '(($a+$b)($a+$b)($a+$b))*',
          difficulty: _Difficulty.hard,
        );

({String description, String regex, _Difficulty difficulty})
    _dSameEnds(String a, String b, Random rng) => (
          description: 'Build an FA that accepts strings over {$a, $b} of '
              'length ≥ 2 where the first and last characters are the same, '
              'plus single-character strings "$a" and "$b".',
          regex: '$a($a+$b)*$a+$b($a+$b)*$b+$a+$b',
          difficulty: _Difficulty.hard,
        );

({String description, String regex, _Difficulty difficulty})
    _dAtLeastTwoConsecutive(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts strings over {$a, $b} that contain '
        'the substring "$sym$sym$sym" (three "$sym"s in a row) at least once.',
    regex: '($a+$b)*$sym$sym$sym($a+$b)*',
    difficulty: _Difficulty.hard,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dThirdFromEnd(String a, String b, Random rng) {
  final sym = rng.nextBool() ? a : b;
  return (
    description: 'Build an FA that accepts strings over {$a, $b} of length '
        '≥ 3 where the third character from the end is "$sym".',
    regex: '($a+$b)*$sym($a+$b)($a+$b)',
    difficulty: _Difficulty.hard,
  );
}

({String description, String regex, _Difficulty difficulty})
    _dCountMod3(String a, String b, Random rng) => (
          description: 'Build an FA that accepts strings over {$a, $b} where '
              'the number of "$a"s is a multiple of 3 (including zero).',
          regex: '$b*($a$b*$a$b*$a$b*)*',
          difficulty: _Difficulty.hard,
        );

/// Generates [count] description challenges from the template pool.
List<_Challenge> _generateDescriptionChallenges(Random rng,
    {int count = 15}) {
  final results = <_Challenge>[];
  final templates = List.of(_kDescTemplates)..shuffle(rng);

  for (int i = 0; i < count; i++) {
    final tmpl = templates[i % templates.length];
    final alphabet = randomStudyAlphabet(rng);
    final symbols = alphabet.toList()..sort();
    final a = symbols[0];
    final b = symbols.length > 1 ? symbols[1] : symbols[0];
    final r = tmpl(a, b, rng);
    results.add(_Challenge(
      regex: r.regex,
      alphabet: alphabet,
      difficulty: r.difficulty,
      description: r.description,
    ));
  }

  results.shuffle(rng);
  return results;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Practice mode enum
// ─────────────────────────────────────────────────────────────────────────────

enum _PracticeMode {
  regexToDfa('REGEX → DFA', Icons.functions),
  dfaToRegex('DFA → REGEX', Icons.account_tree_outlined),
  describeToFa('DESCRIBE → FA', Icons.lightbulb_outline_rounded),
  pdaToDraw('PDA → DRAW', Icons.layers_outlined);

  const _PracticeMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _AnyChallenge {
  final _Challenge? regexChallenge;
  final StudyPdaChallenge? pdaChallenge;

  const _AnyChallenge.regex(this.regexChallenge) : pdaChallenge = null;
  const _AnyChallenge.pda(this.pdaChallenge) : regexChallenge = null;

  bool get isPda => pdaChallenge != null;
  _Difficulty get difficulty => isPda
      ? switch (pdaChallenge!.difficulty) {
          StudyPdaDifficulty.easy => _Difficulty.easy,
          StudyPdaDifficulty.medium => _Difficulty.medium,
          StudyPdaDifficulty.hard => _Difficulty.hard,
        }
      : regexChallenge!.difficulty;
  String? get description =>
      regexChallenge?.description ?? pdaChallenge?.description;
  String? get hint => pdaChallenge?.hint;
  String get regex => regexChallenge?.regex ?? '';
  Set<String> get alphabet =>
      regexChallenge?.alphabet ?? pdaChallenge!.alphabet;
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

  /// Called when the user taps "GAME" — navigate to the level-select screen.
  final VoidCallback? onGoToGame;

  /// Called when the user taps the main-menu (home) icon — navigate back to
  /// [ModeSelectScreen]. Null when this screen isn't reachable from the menu.
  final VoidCallback? onGoToMenu;

  /// Used to open the tutorial library (so users can watch/re-watch the
  /// game-mode tutorial slideshows without leaving Study Mode) and to mark
  /// them completed once finished.
  final GameProgressStore? progressStore;

  const StudyModeScreen({
    super.key,
    VoidCallback? onGoToSandbox,
    this.onGoToStudy,
    this.onGoToGame,
    this.onGoToMenu,
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

  /// Which practice modes are currently selected (multi-select).
  Set<_PracticeMode> _selectedModes = {_PracticeMode.regexToDfa};

  /// The mode actually used for the current challenge — drawn from [_selectedModes].
  _PracticeMode _mode = _PracticeMode.regexToDfa;

  // The working queue — regex and PDA challenges.
  late List<_AnyChallenge> _queue;
  int _queueIndex = 0;

  // Session counters
  int _attempted = 0;
  int _correct = 0;

  // Per-round state
  _GradeResult? _gradeResult;
  bool _submitted = false;

  /// How many wrong (non-parse-error) attempts this round.
  int _wrongAttempts = 0;

  /// True once the player has exhausted all 3 tries — answer is revealed.
  bool _answerRevealed = false;

  static const int _maxTries = 3;

  /// Returns the appropriate mode for a given challenge.
  /// Description challenges always use describeToFa when that mode is selected;
  /// otherwise falls back to regexToDfa.
  _PracticeMode _pickModeForChallenge(_AnyChallenge challenge) {
    if (challenge.isPda) {
      if (_selectedModes.contains(_PracticeMode.pdaToDraw)) {
        return _PracticeMode.pdaToDraw;
      }
      return _PracticeMode.pdaToDraw;
    }
    final rc = challenge.regexChallenge!;
    if (rc.description != null &&
        _selectedModes.contains(_PracticeMode.describeToFa)) {
      return _PracticeMode.describeToFa;
    }
    final pool = _selectedModes
        .where((m) =>
            m != _PracticeMode.describeToFa &&
            m != _PracticeMode.pdaToDraw)
        .toList();
    if (pool.isEmpty) return _PracticeMode.regexToDfa;
    return pool[_rng.nextInt(pool.length)];
  }


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
    _mode = _pickModeForChallenge(_queue[_queueIndex]);
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
    final all = <_AnyChallenge>[];
    // Plain regex-template challenges (description == null) back REGEX→DFA
    // and DFA→REGEX only — they must not be queued for a describeToFa-only
    // session, or _pickModeForChallenge has nothing to fall back to but
    // regexToDfa and silently serves a regex prompt in a describe-only run.
    final wantsRegexTemplates = _selectedModes.contains(_PracticeMode.regexToDfa) ||
        _selectedModes.contains(_PracticeMode.dfaToRegex);
    if (wantsRegexTemplates) {
      all.addAll(_generateChallenges(_rng).map(_AnyChallenge.regex));
    }
    if (_selectedModes.contains(_PracticeMode.describeToFa)) {
      all.addAll(
          _generateDescriptionChallenges(_rng).map(_AnyChallenge.regex));
    }
    if (_selectedModes.contains(_PracticeMode.pdaToDraw)) {
      all.addAll(generateStudyPdaChallenges(_rng, count: 20)
          .map(_AnyChallenge.pda));
    }
    if (all.isEmpty) {
      all.addAll(_generateChallenges(_rng).map(_AnyChallenge.regex));
    }
    _queue = all..shuffle(_rng);
    _queueIndex = 0;
  }

  _AnyChallenge get _current => _queue[_queueIndex];

  void _nextChallenge() {
    _queueIndex++;
    if (_queueIndex >= _queue.length) _buildQueue();

    setState(() {
      _mode = _pickModeForChallenge(_queue[_queueIndex]);
      _gradeResult = null;
      _submitted = false;
      _wrongAttempts = 0;
      _answerRevealed = false;
      _playerNodes = {};
      _playerLines = {};
      _playerStart = null;
      _regexInputCtrl.clear();
    });

    _entryCtrl
      ..reset()
      ..forward();
  }

  /// Toggle a single mode on/off in [_selectedModes].
  /// At least one mode must remain selected at all times.
  void _toggleMode(_PracticeMode mode) {
    final next = Set<_PracticeMode>.of(_selectedModes);
    if (next.contains(mode)) {
      if (next.length == 1) return; // can't deselect the last one
      next.remove(mode);
    } else {
      next.add(mode);
    }
    // Mutate before _pickMode so it reads the updated set.
    _selectedModes = next;
    _buildQueue();
    final newMode = _pickModeForChallenge(_queue[_queueIndex]);
    setState(() {
      _mode = newMode;
      _gradeResult = null;
      _submitted = false;
      _wrongAttempts = 0;
      _answerRevealed = false;
      _playerNodes = {};
      _playerLines = {};
      _playerStart = null;
      _regexInputCtrl.clear();
    });
    _entryCtrl
      ..reset()
      ..forward();
  }

  /// Toggle "select all" — either enable every mode or reset to just [regexToDfa].
  void _toggleSelectAll() {
    final allSelected = _selectedModes.length == _PracticeMode.values.length;
    // Mutate before _pickMode so it reads the updated set.
    _selectedModes = allSelected
        ? {_PracticeMode.regexToDfa}
        : Set.of(_PracticeMode.values);
    _buildQueue();
    final newMode = _pickModeForChallenge(_queue[_queueIndex]);
    setState(() {
      _mode = newMode;
      _gradeResult = null;
      _submitted = false;
      _wrongAttempts = 0;
      _answerRevealed = false;
      _playerNodes = {};
      _playerLines = {};
      _playerStart = null;
      _regexInputCtrl.clear();
    });
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

    final targetResult =
        regexToDfa(_current.regex.replaceAll(' ', ''));
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
    final playerResult = regexToDfa(raw);
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

    if (eq.status == EquivalenceStatus.equivalent) {
      return const _GradeResult.correct();
    }
    return _GradeResult.wrong(eq.witness);
  }

  _GradeResult _gradePlayerPda() {
    if (_playerStart == null || _playerNodes.isEmpty) {
      return const _GradeResult.parseError(
          'Draw some states first, then hit Check.');
    }
    final grade = gradeStudyPda(
      nodes: _playerNodes,
      lines: _playerLines,
      start: _playerStart,
      challenge: _current.pdaChallenge!,
    );
    if (grade.correct) return const _GradeResult.correct();
    return _GradeResult.wrong(studyPdaFailureMessage(grade.failedCase!));
  }

  // ── Tutorial library ─────────────────────────────────────────────────────

  /// Opens a sheet listing every game-mode tutorial slideshow, so someone
  /// studying can watch (or re-watch) any of them without having to unlock
  /// or step through the corresponding game levels.
  void _openTutorials() {
    final store = widget.progressStore;
    if (store == null) return;

    final tutorials = kAllLevels.where((l) => l.isTutorial).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _TutorialLibrarySheet(
        tutorials: tutorials,
        onSelect: (level) {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TutorialScreen(
              level: level,
              progressStore: store,
            ),
          ));
        },
      ),
    );
  }

  void _submit() {
    final _GradeResult result;
    if (_mode == _PracticeMode.pdaToDraw) {
      result = _gradePlayerPda();
    } else if (_mode == _PracticeMode.dfaToRegex) {
      result = _gradePlayerRegex();
    } else {
      result = _gradePlayerDfa();
    }

    setState(() {
      _gradeResult = result;
      _submitted = true;
      // Only count genuine wrong answers (not parse errors) toward the try limit.
      if (result.error == null) {
        _attempted++;
        if (result.correct) {
          _correct++;
        } else {
          _wrongAttempts++;
          if (_wrongAttempts >= _maxTries) {
            _answerRevealed = true;
          }
        }
      }
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
            selectedModes: _selectedModes,
            onModeToggled: _toggleMode,
            onSelectAllToggled: _toggleSelectAll,
            correct: _correct,
            total: _attempted,
            onGoToSandbox: widget.onGoToSandbox,
            onGoToGame: widget.onGoToGame,
            onGoToMenu: widget.onGoToMenu,
            onOpenTutorials: widget.progressStore != null ? _openTutorials : null,
          ),
          Expanded(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _entryCtrl,
                curve: Curves.easeOut,
              ),
              child: _ChallengeBody(
                key: ValueKey('${_mode.name}:$_queueIndex'),
                mode: _mode,
                challenge: challenge,
                queueIndex: _queueIndex,
                queueTotal: _queue.length,
                gradeResult: _gradeResult,
                submitted: _submitted,
                wrongAttempts: _wrongAttempts,
                answerRevealed: _answerRevealed,
                maxTries: _maxTries,
                regexInputCtrl: _regexInputCtrl,
                regexInputFocus: _regexInputFocus,
                onPlayerFaChanged: (nodes, lines, start) {
                  _playerNodes = nodes;
                  _playerLines = lines;
                  _playerStart = start;
                },
                onSubmit: _submitted && _gradeResult?.error != null
                    ? _submit        // allow re-try on parse errors
                    : _submitted && (_gradeResult?.correct ?? false)
                        ? _nextChallenge
                        : _submitted && _answerRevealed
                            ? _nextChallenge
                            : _submitted
                                ? _submit   // wrong but tries remaining
                                : _submit,  // not yet submitted
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
  final Set<_PracticeMode> selectedModes;
  final ValueChanged<_PracticeMode> onModeToggled;
  final VoidCallback onSelectAllToggled;
  final int correct;
  final int total;
  final VoidCallback onGoToSandbox;
  final VoidCallback? onGoToGame;
  final VoidCallback? onGoToMenu;
  final VoidCallback? onOpenTutorials;

  const _TopBar({
    required this.mode,
    required this.selectedModes,
    required this.onModeToggled,
    required this.onSelectAllToggled,
    required this.correct,
    required this.total,
    required this.onGoToSandbox,
    this.onGoToGame,
    this.onGoToMenu,
    this.onOpenTutorials,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final allSelected = selectedModes.length == _PracticeMode.values.length;
    final compact = isCompactLayout(context);
    final hPad = responsiveHorizontalPadding(context);

    final modeChips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Select All" toggle chip
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: onSelectAllToggled,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: allSelected
                      ? theme.accentGreen.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: allSelected
                        ? theme.accentGreen.withValues(alpha: 0.8)
                        : theme.borderMid,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        allSelected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        key: ValueKey(allSelected),
                        size: 12,
                        color: allSelected ? theme.accentGreen : theme.textDim,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'ALL',
                      style: GoogleFonts.orbitron(
                        color: allSelected ? theme.accentGreen : theme.textDim,
                        fontSize: 8,
                        letterSpacing: 1.5,
                        fontWeight:
                            allSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Individual mode chips
          ..._PracticeMode.values.map((m) {
            final sel = selectedModes.contains(m);
            final chipColor = m == _PracticeMode.dfaToRegex
                ? theme.accentGreen
                : m == _PracticeMode.describeToFa
                    ? const Color(0xFFB47FFF)
                    : m == _PracticeMode.pdaToDraw
                        ? const Color(0xFF26C6DA)
                        : theme.accent;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onModeToggled(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel
                        ? chipColor.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: sel
                          ? chipColor.withValues(alpha: 0.8)
                          : theme.borderMid,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          sel
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          key: ValueKey(sel),
                          size: 12,
                          color: sel ? chipColor : theme.textDim,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        m.label,
                        style: GoogleFonts.orbitron(
                          color: sel ? chipColor : theme.textDim,
                          fontSize: 8,
                          letterSpacing: 1.5,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: compact ? 6 : 10),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PRACTICE',
                            style: GoogleFonts.orbitron(
                              color: theme.accent,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                          Text(
                            'MODE',
                            style: GoogleFonts.orbitron(
                              color: theme.textDim,
                              fontSize: 8,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (total > 0)
                        Text(
                          '$correct / $total',
                          style: GoogleFonts.orbitron(
                            color: theme.textMid,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Appearance',
                        icon: Icon(Icons.palette_outlined,
                            color: theme.textMid, size: 20),
                        onPressed: () => showAppThemeSettings(context),
                      ),
                      if (onOpenTutorials != null)
                        IconButton(
                          tooltip: 'Tutorials',
                          icon: Icon(Icons.school_outlined,
                              color: theme.textMid, size: 20),
                          onPressed: onOpenTutorials,
                        ),
                      MainMenuButton(onPressed: onGoToMenu),
                      if (onGoToGame != null)
                        TextButton(
                          onPressed: onGoToGame,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide(color: theme.borderMid),
                            ),
                          ),
                          child: Text(
                            'GAME',
                            style: GoogleFonts.orbitron(
                                color: theme.textDim,
                                fontSize: 8,
                                letterSpacing: 2),
                          ),
                        ),
                      TextButton(
                        onPressed: onGoToSandbox,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(color: theme.borderMid),
                          ),
                        ),
                        child: Text(
                          'SANDBOX',
                          style: GoogleFonts.orbitron(
                              color: theme.textDim,
                              fontSize: 8,
                              letterSpacing: 2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  modeChips,
                ],
              )
            : Row(
                children: [
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
                  Expanded(child: modeChips),
                  const SizedBox(width: 12),
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
                  IconButton(
                    tooltip: 'Appearance',
                    icon: Icon(Icons.palette_outlined,
                        color: theme.textMid, size: 20),
                    onPressed: () => showAppThemeSettings(context),
                  ),
                  if (onOpenTutorials != null)
                    IconButton(
                      tooltip: 'Tutorials',
                      icon: Icon(Icons.school_outlined,
                          color: theme.textMid, size: 20),
                      onPressed: onOpenTutorials,
                    ),
                  MainMenuButton(onPressed: onGoToMenu),
                  if (onGoToGame != null) ...[
                    TextButton(
                      onPressed: onGoToGame,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(color: theme.borderMid),
                        ),
                      ),
                      child: Text(
                        'GAME',
                        style: GoogleFonts.orbitron(
                            color: theme.textDim, fontSize: 8, letterSpacing: 2),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  TextButton(
                    onPressed: onGoToSandbox,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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
//  Tutorial library sheet
//
//  Lets someone in Study Mode watch any game-mode tutorial slideshow on
//  demand, without unlocking or stepping through the corresponding game
//  levels first. Opened from the school-cap icon in the top bar.
// ─────────────────────────────────────────────────────────────────────────────

class _TutorialLibrarySheet extends StatelessWidget {
  final List<GameLevel> tutorials;
  final ValueChanged<GameLevel> onSelect;

  const _TutorialLibrarySheet({
    required this.tutorials,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final accentColor = theme.tagColor('tutorial');

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(top: 60),
        decoration: BoxDecoration(
          color: theme.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: theme.borderMid),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // Grabber handle.
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.school_outlined, color: accentColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TUTORIALS',
                          style: GoogleFonts.orbitron(
                            color: theme.textLight,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          'Watch any lesson without unlocking it in Game mode',
                          style: GoogleFonts.sourceCodePro(
                            color: theme.textDim,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.borderMid.withValues(alpha: 0.6)),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: tutorials.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: theme.borderMid.withValues(alpha: 0.3),
                  indent: 20,
                  endIndent: 20,
                ),
                itemBuilder: (_, i) => _TutorialLibraryTile(
                  level: tutorials[i],
                  accentColor: accentColor,
                  theme: theme,
                  onTap: () => onSelect(tutorials[i]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _TutorialLibraryTile extends StatelessWidget {
  final GameLevel level;
  final Color accentColor;
  final AppThemeNotifier theme;
  final VoidCallback onTap;

  const _TutorialLibraryTile({
    required this.level,
    required this.accentColor,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withValues(alpha: 0.4)),
              ),
              child: Icon(Icons.play_arrow_rounded,
                  color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level.title,
                    style: GoogleFonts.orbitron(
                      color: theme.textLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    level.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sourceCodePro(
                      color: theme.textDim,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.textDim, size: 20),
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
  final _AnyChallenge challenge;
  final int queueIndex;
  final int queueTotal;
  final _GradeResult? gradeResult;
  final bool submitted;
  final int wrongAttempts;
  final bool answerRevealed;
  final int maxTries;
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
    required this.wrongAttempts,
    required this.answerRevealed,
    required this.maxTries,
    required this.regexInputCtrl,
    required this.regexInputFocus,
    required this.onPlayerFaChanged,
    required this.onSubmit,
    required this.onSkip,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final compact = isCompactLayout(context);
    final hPad = responsiveHorizontalPadding(context);
    final vGap = compact ? 6.0 : 12.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: compact ? 2 : 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProgressRow(
              index: queueIndex,
              total: queueTotal,
              theme: theme,
            ),

            SizedBox(height: vGap),

            // Challenge card — scrollable and height-capped so it can never
            // crowd out the drawing/input area below, which is what the
            // player actually needs room to see and work in.
            if (compact)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.18,
                ),
                child: SingleChildScrollView(
                  child: _ChallengeCard(
                    mode: mode,
                    challenge: challenge,
                    theme: theme,
                  ),
                ),
              )
            else
              _ChallengeCard(
                mode: mode,
                challenge: challenge,
                theme: theme,
              ),

            SizedBox(height: vGap),

            // Input area (drawing canvas for REGEX→DFA / DESCRIBE→FA, text field for DFA→REGEX)
            Expanded(
            child: mode == _PracticeMode.dfaToRegex
                ? _RegexInputArea(
                    challenge: challenge.regexChallenge!,
                    controller: regexInputCtrl,
                    focusNode: regexInputFocus,
                    submitted: submitted,
                    gradeResult: gradeResult,
                    theme: theme,
                  )
                : mode == _PracticeMode.pdaToDraw
                    ? StudyPdaDrawingArea(
                        challenge: challenge.pdaChallenge!,
                        submitted: submitted,
                        answerRevealed: answerRevealed,
                        lastCorrect: gradeResult?.correct,
                        onFaChanged: onPlayerFaChanged,
                        theme: theme,
                      )
                    : _DfaDrawingArea(
                        challenge: challenge.regexChallenge!,
                        submitted: submitted,
                        gradeResult: gradeResult,
                        answerRevealed: answerRevealed,
                        onFaChanged: onPlayerFaChanged,
                        theme: theme,
                      ),
          ),

          SizedBox(height: compact ? 8 : 14),

          // Feedback banner (shown after submission)
          if (gradeResult != null)
            _FeedbackBanner(
              result: gradeResult!,
              challenge: challenge,
              mode: mode,
              wrongAttempts: wrongAttempts,
              answerRevealed: answerRevealed,
              maxTries: maxTries,
              theme: theme,
            ),

          if (gradeResult != null) SizedBox(height: compact ? 6 : 12),

          // Action row
          _ActionRow(
            submitted: submitted,
            gradeResult: gradeResult,
            answerRevealed: answerRevealed,
            wrongAttempts: wrongAttempts,
            maxTries: maxTries,
            onSubmit: onSubmit,
            onSkip: onSkip,
            theme: theme,
            compact: compact,
          ),

          SizedBox(height: compact ? 4 : 12),
        ],
      ),
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
                  AlwaysStoppedAnimation(theme.accent.withValues(alpha: 0.6)),
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
  final _AnyChallenge challenge;
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
    final compact = isCompactLayout(context);
    final accentColor = mode == _PracticeMode.regexToDfa
        ? theme.accent
        : mode == _PracticeMode.describeToFa
            ? const Color(0xFFB47FFF)
            : mode == _PracticeMode.pdaToDraw
                ? const Color(0xFF26C6DA)
                : theme.accentGreen;

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1.5),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.07),
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
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          SizedBox(height: compact ? 8 : 16),

          // The regex (shown large and prominent)
          if (mode == _PracticeMode.regexToDfa) ...[
            if (!compact) ...[
              Text(
                'REGULAR EXPRESSION',
                style: GoogleFonts.orbitron(
                  color: theme.textDim,
                  fontSize: 8,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.accent.withValues(alpha: 0.2)),
              ),
              child: SelectableText(
                challenge.regex,
                style: GoogleFonts.courierPrime(
                  color: theme.accent,
                  fontSize: compact ? 18 : 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ] else if (mode == _PracticeMode.describeToFa) ...[
            // DESCRIBE → FA: show the plain-language description
            if (!compact) ...[
              Text(
                'LANGUAGE DESCRIPTION',
                style: GoogleFonts.orbitron(
                  color: theme.textDim,
                  fontSize: 8,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFB47FFF).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFB47FFF).withValues(alpha: 0.25)),
              ),
              child: Text(
                challenge.description ?? '',
                style: GoogleFonts.sourceCodePro(
                  color: const Color(0xFFD4AAFF),
                  fontSize: compact ? 12 : 14,
                  height: compact ? 1.3 : 1.55,
                ),
                maxLines: compact ? 3 : null,
                overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
              ),
            ),
          ] else if (mode == _PracticeMode.pdaToDraw) ...[
            if (!compact) ...[
              Text(
                'CONTEXT-FREE LANGUAGE',
                style: GoogleFonts.orbitron(
                  color: theme.textDim,
                  fontSize: 8,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF26C6DA).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF26C6DA).withValues(alpha: 0.25)),
              ),
              child: Text(
                challenge.description ?? '',
                style: GoogleFonts.sourceCodePro(
                  color: const Color(0xFF80DEEA),
                  fontSize: compact ? 12 : 14,
                  height: compact ? 1.3 : 1.55,
                ),
                maxLines: compact ? 3 : null,
                overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
              ),
            ),
            if (challenge.hint != null && !compact) ...[
              const SizedBox(height: 10),
              Text(
                challenge.hint!,
                style: GoogleFonts.sourceCodePro(
                  color: theme.textDim,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ] else ...[
            // DFA→REGEX: the alphabet already appears in the header row
            // above (Σ = {...}), so this just restates it as a small inline
            // chip instead of a large standalone block — that was taking up
            // card height that the DFA preview below could use instead.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.accentGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: theme.accentGreen.withValues(alpha: 0.20)),
              ),
              child: Text(
                'Σ = {${(challenge.alphabet.toList()..sort()).join(', ')}}',
                style: GoogleFonts.courierPrime(
                  color: theme.accentGreen,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],

          // Task instruction — on compact screens this is capped to one
          // line so it can never push the card past its height budget;
          // the full multi-line version only shows where there's room.
          if (!compact) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  mode == _PracticeMode.dfaToRegex
                      ? Icons.keyboard_outlined
                      : Icons.edit_outlined,
                  color: theme.textDim,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mode == _PracticeMode.regexToDfa
                        ? 'Draw a DFA on the canvas below whose language equals this regex.'
                        : mode == _PracticeMode.describeToFa
                            ? 'Draw a DFA on the canvas below whose language matches the description above.'
                            : mode == _PracticeMode.pdaToDraw
                                ? 'Draw a PDA on the canvas below that accepts exactly this language.'
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
  final bool answerRevealed;
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onFaChanged;
  final AppThemeNotifier theme;

  const _DfaDrawingArea({
    required this.challenge,
    required this.submitted,
    required this.gradeResult,
    required this.answerRevealed,
    required this.onFaChanged,
    required this.theme,
  });

  @override
  State<_DfaDrawingArea> createState() => _DfaDrawingAreaState();
}

class _DfaDrawingAreaState extends State<_DfaDrawingArea> {
  // The player's in-progress FA lives here; the embedded AutomataDrawer
  // mutates these via its onChanged callback.

  void _onFaChanged(
    Map<String, NodeData> nodes,
    Map<String, LineData> lines,
    StartArrowData? start,
  ) {
    widget.onFaChanged(nodes, lines, start);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final answerRevealed = widget.answerRevealed;

    // When the answer is revealed, swap to a read-only view of the correct DFA.
    if (answerRevealed) {
      return Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.5), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: _ReadOnlyDfaPreview(
                regex: widget.challenge.regex,
                alphabet: widget.challenge.alphabet,
                theme: theme,
              ),
            ),
            Positioned(
              top: 10,
              right: 14,
              child: Text(
                'CORRECT DFA  (read-only)',
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
                color: theme.textDim.withValues(alpha: 0.4),
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
        ? theme.accentGreen.withValues(alpha: 0.35)
        : correct
            ? const Color(0xFF4CAF50)
            : theme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Read-only DFA preview — takes all the room left over once the
        // regex box below claims only what it needs. This way the diagram
        // gets as much space as possible without ever squeezing the input
        // box down to the point where it's hard to read or type into.
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
                      color: theme.textDim.withValues(alpha: 0.5),
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

        // Regex text field — sized to fit its own content (label + one
        // line of input + operator hints), not squeezed to a flex share,
        // so it stays a fixed, comfortable size to read and type into no
        // matter how large the DFA preview above grows.
        Container(
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
              TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: submitted && correct, // lock on correct answer
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
                    color: theme.textDim.withValues(alpha: 0.5),
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
              const SizedBox(height: 10),
              // Operator quick-reference
              Row(
                children: [
                  _OpHint(op: '*', label: 'star', theme: theme),
                  const SizedBox(width: 10),
                  _OpHint(op: '+', label: 'or', theme: theme),
                  const SizedBox(width: 10),
                  _OpHint(op: '~', label: '~', theme: theme),
                  const SizedBox(width: 10),
                  _OpHint(op: '()', label: 'group', theme: theme),
                ],
              ),
            ],
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
            color: theme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.accent.withValues(alpha: 0.2)),
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
      _applyStudyModeLayout(_nodes!, _lines!);
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
      onChanged: (_, _, _) {}, // read-only; ignore
      readOnly: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Feedback banner
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackBanner extends StatelessWidget {
  final _GradeResult result;
  final _AnyChallenge challenge;
  final _PracticeMode mode;
  final int wrongAttempts;
  final bool answerRevealed;
  final int maxTries;
  final AppThemeNotifier theme;

  const _FeedbackBanner({
    required this.result,
    required this.challenge,
    required this.mode,
    required this.wrongAttempts,
    required this.answerRevealed,
    required this.maxTries,
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
            : mode == _PracticeMode.describeToFa
                ? 'Your FA correctly captures the described language!'
                : mode == _PracticeMode.pdaToDraw
                    ? 'Your PDA passes every oracle test case for this language.'
                    : 'Your regex describes the same language.',
        theme: theme,
      );
    }

    // Wrong — show counterexample and either tries-remaining or the answer.
    final ce = result.counterexample ?? '';
    final ceDisplay = ce.isEmpty ? '~ (empty string)' : '"$ce"';
    final triesLeft = maxTries - wrongAttempts;

    if (answerRevealed) {
      // 3 tries exhausted — show the canonical answer.
      final answerText = mode == _PracticeMode.dfaToRegex
          ? 'A correct regex for this language is:\n  ${challenge.regex}'
          : mode == _PracticeMode.pdaToDraw
              ? 'The correct PDA has been loaded on the canvas above — study it, then move on.'
              : 'The correct FA has been loaded on the canvas above — study it, then move on.';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Banner(
            icon: Icons.close_rounded,
            color: theme.error,
            title: 'Not quite — counterexample: $ceDisplay',
            body: 'Your machine and the target disagree on this string.',
            theme: theme,
          ),
          const SizedBox(height: 8),
          _Banner(
            icon: Icons.lightbulb_outline_rounded,
            color: const Color(0xFFFFB300),
            title: 'Answer revealed (3/3 tries used)',
            body: answerText,
            theme: theme,
          ),
        ],
      );
    }

    // Still has tries left.
    final triesMsg = triesLeft == 1
        ? '1 try remaining — next wrong answer will reveal the solution.'
        : '$triesLeft tries remaining.';

    return _Banner(
      icon: Icons.close_rounded,
      color: theme.error,
      title: 'Not quite — try ${wrongAttempts + 1} / $maxTries',
      body: 'Counterexample: $ceDisplay\n'
          'Your machine and the target disagree on this string. Check it and try again.\n'
          '$triesMsg',
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
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
  final bool answerRevealed;
  final int wrongAttempts;
  final int maxTries;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  final AppThemeNotifier theme;
  final bool compact;

  const _ActionRow({
    required this.submitted,
    required this.gradeResult,
    required this.answerRevealed,
    required this.wrongAttempts,
    required this.maxTries,
    required this.onSubmit,
    required this.onSkip,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 8.0 : 12.0;

    // Parse error → "Try Again" + Skip
    if (submitted && gradeResult?.error != null) {
      return Row(
        children: [
          Expanded(
            child: _Btn(
              label: 'TRY AGAIN',
              icon: Icons.refresh_rounded,
              color: theme.accent,
              compact: compact,
              onTap: onSubmit,
            ),
          ),
          SizedBox(width: gap),
          _Btn(
            label: 'SKIP',
            icon: Icons.skip_next_rounded,
            color: theme.textDim,
            small: true,
            compact: compact,
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
        compact: compact,
        onTap: onSubmit, // onSubmit is wired to _nextChallenge at this point
      );
    }

    // Answer revealed after 3 wrong tries → only "Next Challenge"
    if (submitted && answerRevealed) {
      return _Btn(
        label: 'NEXT CHALLENGE',
        icon: Icons.arrow_forward_rounded,
        color: const Color(0xFFFFB300),
        compact: compact,
        onTap: onSubmit,
      );
    }

    // Wrong but tries remaining → "Try Again" (re-submits) + Skip
    if (submitted && gradeResult != null) {
      final triesLeft = maxTries - wrongAttempts;
      return Row(
        children: [
          Expanded(
            child: _Btn(
              label: 'TRY AGAIN  ($triesLeft left)',
              icon: Icons.refresh_rounded,
              color: theme.error,
              compact: compact,
              onTap: onSubmit,
            ),
          ),
          SizedBox(width: gap),
          _Btn(
            label: 'SKIP',
            icon: Icons.skip_next_rounded,
            color: theme.textDim,
            small: true,
            compact: compact,
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
            compact: compact,
            onTap: onSubmit,
          ),
        ),
        SizedBox(width: gap),
        _Btn(
          label: 'SKIP',
          icon: Icons.skip_next_rounded,
          color: theme.textDim,
          small: true,
          compact: compact,
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
  final bool compact;

  const _Btn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.small = false,
    this.compact = false,
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
          vertical: widget.small ? (widget.compact ? 7 : 10) : (widget.compact ? 9 : 14),
          horizontal: widget.small ? 16 : 20,
        ),
        decoration: BoxDecoration(
          color: _pressed
              ? widget.color.withValues(alpha: 0.22)
              : widget.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.color.withValues(alpha: _pressed ? 0.9 : 0.5),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Study-mode layout post-processor
//
//  Applied to the solution graph after it is built from a regex or PDA spec,
//  before rendering it read-only.  Three passes:
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

  // ── Pass 2+3: move nodes off chord paths and label textboxes ──────────────
  const double nodeRadius  = 50.0;              // visual radius of a state circle
  const double clearance   = nodeRadius + 30.0; // min distance: node centre ↔ chord
  const double textBuffer  = 12.0;              // extra padding around textbox rect
  const double boxWidth    = kLabelBoxWidth;    // must match LineWidget / StartArrowWidget — see models.dart
  const double lineHeight  = kLabelLineHeight;  // single-line height used by those widgets — see models.dart
  const int    iterations  = 20;                // enough passes to propagate cascades

  for (int iter = 0; iter < iterations; iter++) {
    bool anyMoved = false;

    for (final node in nodes.values) {
      if (node.isBlackBox) continue;

      for (final line in lines.values) {
        // Skip lines that directly touch this node.
        if (line.nodeAId == node.id || line.nodeBId == node.id) continue;
        // Skip self-loops — they don't cross other nodes.
        if (line.nodeAId == line.nodeBId) continue;

        final nodeA = nodes[line.nodeAId];
        final nodeB = nodes[line.nodeBId];
        if (nodeA == null || nodeB == null) continue;

        final cA = nodeA.center;
        final cB = nodeB.center;

        // ── sub-check 2: chord clearance ─────────────────────────────────
        {
          final nc = node.center;

          // Vector from A to B.
          final abx = cB.dx - cA.dx;
          final aby = cB.dy - cA.dy;
          final abLen = sqrt(abx * abx + aby * aby);

          if (abLen >= 1) {
            // Project node centre onto the infinite line through A and B.
            final t = ((nc.dx - cA.dx) * abx + (nc.dy - cA.dy) * aby) / (abLen * abLen);

            // Only care if the projection falls between (or near) the endpoints.
            if (t >= -0.05 && t <= 1.05) {
              final closestX = cA.dx + t * abx;
              final closestY = cA.dy + t * aby;

              final dxFromChord = nc.dx - closestX;
              final dyFromChord = nc.dy - closestY;
              final distFromChord = sqrt(dxFromChord * dxFromChord + dyFromChord * dyFromChord);

              if (distFromChord < clearance) {
                final push = clearance - distFromChord;

                // Perpendicular direction away from the chord.
                // If the node is exactly on the chord (dist ≈ 0), push downward.
                final Offset perp;
                if (distFromChord < 0.5) {
                  perp = Offset(aby / abLen, -abx / abLen); // rotate AB by -90°
                } else {
                  perp = Offset(dxFromChord / distFromChord, dyFromChord / distFromChord);
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

        // ── sub-check 3: textbox clearance ───────────────────────────────
        // Re-fetch node.center after the potential chord push above so the
        // textbox test sees the already-updated position.
        if (line.label.isNotEmpty) {
          final nc = node.center;

          final lineCount = '\n'.allMatches(line.label).length + 1;
          final double boxHeight = lineHeight * lineCount;

          // Top-left corner of the label textbox, as rendered by LineWidget.
          final Offset topLeft =
              line.getTextBoxLocation(cA, cB, boxWidth, boxHeight, line.label);

          // Expand by textBuffer on all sides to give a small clearance gap.
          final double rLeft   = topLeft.dx - textBuffer;
          final double rTop    = topLeft.dy - textBuffer;
          final double rRight  = topLeft.dx + boxWidth  + textBuffer;
          final double rBottom = topLeft.dy + boxHeight + textBuffer;

          // Closest point on the (expanded) rect to the node centre.
          final closestX = nc.dx.clamp(rLeft, rRight);
          final closestY = nc.dy.clamp(rTop, rBottom);

          final dxFromBox = nc.dx - closestX;
          final dyFromBox = nc.dy - closestY;
          final distFromBox = sqrt(dxFromBox * dxFromBox + dyFromBox * dyFromBox);

          if (distFromBox < nodeRadius) {
            final push = nodeRadius - distFromBox;

            // Push direction: away from the closest point on the rect.
            // If the node centre is already inside the rect, push away from
            // the rect's centre instead.
            final Offset pushDir;
            if (distFromBox < 0.5) {
              final rcx = (rLeft + rRight) / 2;
              final rcy = (rTop + rBottom) / 2;
              final awayDx = nc.dx - rcx;
              final awayDy = nc.dy - rcy;
              final awayLen = sqrt(awayDx * awayDx + awayDy * awayDy);
              pushDir = awayLen < 0.5
                  ? const Offset(0, 1) // fallback: push straight down
                  : Offset(awayDx / awayLen, awayDy / awayLen);
            } else {
              pushDir = Offset(dxFromBox / distFromBox, dyFromBox / distFromBox);
            }

            node.position = Offset(
              node.position.dx + pushDir.dx * push,
              node.position.dy + pushDir.dy * push,
            );
            anyMoved = true;
          }
        }
      }
    }

    if (!anyMoved) break; // converged early
  }
}