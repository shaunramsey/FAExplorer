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
///
/// Order here doesn't matter for correctness (randomStudyAlphabet shuffles
/// before drawing), but it's kept in a readable digits-then-letters order
/// for anyone skimming the source.
///
/// Count check: 10 digits + 24 letters (26 minus 'l' and 'o') = 34 symbols
/// total. That's the ceiling for `size` in randomStudyAlphabet below.
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
///
/// Implementation notes:
///   - `rng` is passed in (rather than constructed here) so callers control
///     seeding — e.g. tests can pass a seeded Random for determinism, and
///     production call sites can share one Random instance across a whole
///     generation session instead of constructing a fresh unseeded one per
///     challenge (repeatedly constructing `Random()` in a tight loop can
///     produce correlated sequences on some platforms since it's commonly
///     seeded from the clock).
///   - The assert below is debug-only (stripped in release builds per Dart
///     semantics), so a bad `size` argument will silently misbehave in
///     release rather than throw — see BUG note below.
Set<String> randomStudyAlphabet(Random rng, {int size = 2}) {
  // Guards the two ways `size` could be invalid:
  //   size <= 0            -> take(size) would yield an empty/negative-length
  //                            iteration (take() actually clamps negative to 0,
  //                            so size <= 0 just silently returns an empty set
  //                            in release mode rather than failing loudly).
  //   size > pool.length    -> take(size) would just return the whole
  //                            34-element pool instead of an error, silently
  //                            giving the caller fewer symbols than requested.
  //
  // NOTE (potential issue): this assert is compiled out of release builds.
  // If a caller ever passes e.g. `size: 40` or `size: 0` in production, this
  // function will NOT throw — it will silently return a smaller-than-
  // requested (or empty) set instead of surfacing the bug. Callers that rely
  // on getting exactly `size` distinct symbols back should not depend on
  // this assert catching misuse in release builds.
  assert(size > 0 && size <= kStudySymbolPool.length,
      'size must be between 1 and ${kStudySymbolPool.length}');

  // Copy the const pool into a growable/mutable List (List.of makes a new
  // list; shuffling the const list in place would throw, since const lists
  // are unmodifiable) and shuffle it using the caller-supplied Random so the
  // draw order is fully controlled by `rng`.
  final shuffled = List<String>.of(kStudySymbolPool)..shuffle(rng);

  // Take the first `size` symbols post-shuffle and collect them into a Set.
  // Using a Set (rather than a List) both documents "these are meant to be
  // distinct" and would silently de-duplicate if the pool ever contained a
  // repeat — though it currently doesn't, so this is purely defensive.
  return shuffled.take(size).toSet();
}