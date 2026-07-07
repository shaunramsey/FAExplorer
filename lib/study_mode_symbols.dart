// ─────────────────────────────────────────────────────────────────────────────
//  study_mode_symbols.dart
//
//  Shared alphabet-symbol pool for Study Mode challenge generation.
//
//  Before this file existed, study_mode_screen.dart and study_mode_pda.dart
//  each leaned on a small fixed set of symbol pairs (things like a/b, 0/1,
//  x/y), and several PDA challenges even picked ONE pair for the entire
//  batch. That's why levels felt repetitive — after a few rounds you'd
//  already seen every symbol combination the generator was capable of
//  producing.
//
//  The fix: one shared pool covering the full alphanumeric range, and one
//  function — randomStudyAlphabet() — that every challenge generator calls
//  for itself, per challenge, so symbols never get reused across a batch.
//
//  Scope of the pool:
//    • Digits 0-9 and lowercase letters a-z — "alphanumeric", per the ask.
//    • No uppercase. Two reasons: it doubles the chance of visually-similar
//      pairs (c/C, o/O, s/S, ...), and the PDA reference-solution builder
//      (pda_study_solutions.dart) uses uppercase letters ('A', 'B', 'X') as
//      internal stack-marker labels — keeping the alphabet lowercase-only
//      means a randomly drawn symbol can never collide with a stack marker.
//    • 'l' and 'o' are left out — lowercase L reads as "1" and lowercase O
//      reads as "0" in most UI fonts, which is exactly the kind of
//      confusing-symbol problem the ask calls out.
//    • Regex syntax characters — '(', ')', '*', '+' — are never part of this
//      pool. They're structural operators the regex templates themselves
//      splice in; the alphabet pool only ever supplies the literal symbols
//      a regex/DFA/PDA reads, never the operators that combine them.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

/// The full pool of symbols study-mode challenges may draw from.
const List<String> kStudySymbolPool = [
  // Digits.
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  // Lowercase letters, excluding 'l' and 'o' (see file header).
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n', 'p', 'q',
  'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
];

/// Draws [size] distinct symbols at random from [kStudySymbolPool].
///
/// Call this once per *challenge*, not once per batch — that's the whole
/// point. Every study-mode generator (regex templates, description
/// templates, PDA challenges) should call this itself for each individual
/// challenge it builds, so a session never settles into a couple of
/// recurring symbols.
Set<String> randomStudyAlphabet(Random rng, {int size = 2}) {
  assert(size > 0 && size <= kStudySymbolPool.length,
      'size must be between 1 and ${kStudySymbolPool.length}');
  final shuffled = List<String>.of(kStudySymbolPool)..shuffle(rng);
  return shuffled.take(size).toSet();
}