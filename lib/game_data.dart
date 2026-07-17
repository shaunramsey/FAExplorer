// ─────────────────────────────────────────────────────────────────────────────
//  game_data.dart
//
//  Non-visual game logic, in one place:
//    1. GameProgressStore — persists completed level IDs & in-progress DSL
//       via SharedPreferences.
//    2. Puzzle type validation — helpers that check a player's automaton
//       against the DFA/NFA type a puzzle requires.
//
//  Level *content* (GameLevel definitions) lives separately in game_level.dart.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dialogs/equivalence_dialog.dart'
    show
        AutomatonTypeResult,
        ViolationSeverity;
import 'game_level.dart';

// Re-exports so callers that only need "the game progress/type-check API"
// can `import 'game_data.dart'` alone, without also having to know that
// these particular types actually live in dialogs/equivalence_dialog.dart.
// Keeps the type-checking implementation swappable/relocatable without
// breaking every import site across the game module.
export 'dialogs/equivalence_dialog.dart'
    show
        RequiredAutomatonType,
        AutomatonTypeResult,
        AutomatonViolation,
        ViolationSeverity;

// ═════════════════════════════════════════════════════════════════════════════
//  1. GAME PROGRESS STORE
// ═════════════════════════════════════════════════════════════════════════════

/// Centralizes every SharedPreferences *key name* the game mode uses, so key
/// strings are computed in exactly one place rather than being hand-typed
/// (and potentially mistyped/duplicated) at each call site.
abstract final class GamePreferenceKeys {
  static const completedLevels = 'game_completed_levels';

  /// Completion key scoped to a difficulty.
  ///
  /// Hard completions use the legacy key so existing saves are honoured.
  /// Easy completions are stored under a separate key so the two difficulties
  /// track progress independently.
  static String completedKey(LevelDifficulty difficulty) =>
      difficulty == LevelDifficulty.hard
          // Reuses the pre-existing 'game_completed_levels' key verbatim so
          // that a player upgrading from a version of the app that predates
          // the Easy/Hard split doesn't lose their previously-earned
          // completions — those old saves are implicitly "Hard" completions
          // under the new scheme.
          ? completedLevels
          : 'game_completed_levels_easy';

  /// Per-level in-progress DSL scoped to difficulty.
  ///
  /// Hard uses the legacy key so existing work-in-progress is preserved.
  static String levelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) =>
      difficulty == LevelDifficulty.hard
          ? 'game_level_dsl_$levelId'
          : 'game_level_dsl_${levelId}_easy';
}

/// Wraps a SharedPreferences instance with typed, game-specific read/write
/// methods. One instance is created (via [open]) near app startup and
/// shared by reference across every screen that needs progress data (see
/// main.dart's AppGate, which owns the single instance).
class GameProgressStore {
  GameProgressStore._(this._prefs);

  final SharedPreferences _prefs;

  /// Async factory: SharedPreferences.getInstance() itself does the actual
  /// disk I/O (reading the platform's preferences file into memory once),
  /// after which every method below is synchronous — SharedPreferences
  /// caches everything in memory after the initial load, it's not doing a
  /// disk round-trip per call.
  static Future<GameProgressStore> open() async {
    return GameProgressStore._(await SharedPreferences.getInstance());
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Loads the set of completed level IDs for [difficulty].
  ///
  /// Returns a *fresh* Set on every call (decoded from the raw JSON string
  /// each time) — there is no in-memory cache of the decoded Set kept
  /// between calls, so callers are free to mutate the returned Set without
  /// corrupting this store's internal state, but repeated calls do repeat
  /// the JSON decode work (see the performance note on
  /// `_completedOnAnyDifficulty` further down, which calls this twice).
  Set<String> loadCompletedLevels([LevelDifficulty difficulty = LevelDifficulty.hard]) {
    final raw = _prefs.getString(GamePreferenceKeys.completedKey(difficulty));
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      // `.toString()` on each decoded element rather than a direct cast —
      // defensive against the stored JSON containing non-string values
      // (shouldn't happen given _save always writes `List<String>`, but
      // guards against manually-edited or corrupted preference data rather
      // than throwing a cast error).
      return {for (final item in list) item.toString()};
    } catch (_) {
      // Any decode failure (malformed JSON, wrong shape, etc.) degrades to
      // "no levels completed" rather than crashing or propagating the
      // error — a corrupted progress entry is treated the same as no
      // progress at all, rather than for example wiping the raw string or
      // surfacing an error to the user.
      return {};
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Marks [levelId] complete for [difficulty] (defaults to Hard).
  ///
  /// Completing on Hard also silently grants the same level's Easy
  /// completion (see the comment inline below) — but note the reverse
  /// (marking a level *incomplete*) does NOT symmetrically revoke that
  /// auto-granted Easy completion; see [markIncomplete]'s doc comment for
  /// why that asymmetry may be worth revisiting.
  Future<void> markCompleted(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async {
    // Always write to the requested difficulty.
    final current = loadCompletedLevels(difficulty);
    current.add(levelId);
    await _save(current, difficulty);

    // Completing on Hard is a strict superset of Easy — grant Easy too so the
    // player doesn't see an unearned gap in their badges.
    if (difficulty == LevelDifficulty.hard) {
      final easy = loadCompletedLevels(LevelDifficulty.easy);
      if (!easy.contains(levelId)) {
        easy.add(levelId);
        await _save(easy, LevelDifficulty.easy);
      }
      // (`if (!easy.contains(...))` is a pure optimization to skip an
      // unnecessary write when Easy was already completed independently —
      // `current.add`/`_save` above are unconditional because a Set.add on
      // an already-present element is a harmless no-op, but a SharedPreferences
      // write is comparatively more expensive, hence guarding this one.)
    }
  }

  /// Marks [levelId] incomplete for [difficulty] (defaults to Hard).
  ///
  /// NOTE (possible asymmetry / design gap): unlike [markCompleted], this
  /// does NOT cascade across difficulties. Concretely: if a player
  /// completes a level on Hard (which — per markCompleted above — also
  /// auto-grants Easy), and then this method is called to mark that same
  /// level incomplete on Hard, the auto-granted Easy completion is left
  /// untouched. The player would end up in a state where the level shows
  /// as "not completed" on Hard but still "completed" on Easy, even though
  /// they never explicitly beat it on Easy — the Easy badge was only ever
  /// earned indirectly via the Hard completion that's now being revoked.
  /// Whether this is the intended behavior (progress is sticky / never
  /// silently taken away) or an oversight (the two methods should mirror
  /// each other) isn't obvious from this file alone — worth confirming
  /// against how/why markIncomplete is actually invoked elsewhere in the
  /// app (e.g. is it only used for a "redo this level" flow, where leaving
  /// the Easy badge alone is actually desirable?).
  Future<void> markIncomplete(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async {
    final current = loadCompletedLevels(difficulty);
    current.remove(levelId);
    await _save(current, difficulty);
  }

  /// Resets all progress for both difficulties.
  ///
  /// NOTE (possible gap): this clears the two completed-levels keys, but
  /// does NOT clear any per-level in-progress DSL saved via
  /// [saveLevelDsl]/[GamePreferenceKeys.levelDsl] (keys of the form
  /// `game_level_dsl_<id>` / `game_level_dsl_<id>_easy`). Those keys are
  /// per-level (one SharedPreferences key per level ID, per difficulty), so
  /// clearing "all of them" would require this method to know the full set
  /// of level IDs that might have a saved draft — which it doesn't have
  /// direct access to here (that list lives in game_level.dart). Practical
  /// effect: after a player uses whatever UI flow calls resetAll()
  /// (presumably something like a "reset progress" settings action), their
  /// completion badges are cleared, but reopening a level they'd previously
  /// worked on will still silently restore their old in-progress automaton
  /// draft rather than starting from a blank canvas. If "reset" is meant to
  /// be a full wipe, this is a real gap; if per-level drafts are
  /// intentionally meant to survive a progress reset, this is fine as-is —
  /// worth clarifying which behavior is intended.
  Future<void> resetAll() async {
    await _prefs.remove(GamePreferenceKeys.completedKey(LevelDifficulty.hard));
    await _prefs.remove(GamePreferenceKeys.completedKey(LevelDifficulty.easy));
  }

  // ── Per-level DSL (work-in-progress) ─────────────────────────────────────

  /// Loads a previously-saved in-progress automaton DSL string for
  /// [levelId]/[difficulty], or null if the player never saved a draft
  /// (or already cleared it via [clearLevelDsl]).
  String? loadLevelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) =>
      _prefs.getString(GamePreferenceKeys.levelDsl(levelId, difficulty));

  Future<void> saveLevelDsl(String levelId, String dsl, [LevelDifficulty difficulty = LevelDifficulty.hard]) async {
    await _prefs.setString(GamePreferenceKeys.levelDsl(levelId, difficulty), dsl);
  }

  Future<void> clearLevelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async {
    await _prefs.remove(GamePreferenceKeys.levelDsl(levelId, difficulty));
  }

  /// Shared write helper: encodes a Set of level IDs as a JSON array string
  /// and writes it under the appropriate difficulty-scoped key.
  /// `ids.toList()` is used because JSON arrays don't have a canonical
  /// "Set" encoding via jsonEncode — Sets aren't directly encodable, so
  /// this converts to a List first (order is whatever Dart's Set iteration
  /// order happens to produce, which is insertion order for a standard
  /// LinkedHashSet — not alphabetical/sorted — but order doesn't matter
  /// here since callers only ever check membership, never rely on
  /// position).
  Future<void> _save(Set<String> ids, LevelDifficulty difficulty) async {
    await _prefs.setString(
      GamePreferenceKeys.completedKey(difficulty),
      jsonEncode(ids.toList()),
    );
  }

  // ── Derived queries ───────────────────────────────────────────────────────

  bool isCompleted(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) =>
      loadCompletedLevels(difficulty).contains(levelId);

  /// A level is considered "completed" for unlock purposes if it has been beaten
  /// on either difficulty (easy or hard).
  bool isCompletedOnAnyDifficulty(String levelId) =>
      isCompleted(levelId, LevelDifficulty.hard) ||
      isCompleted(levelId, LevelDifficulty.easy);

  /// Returns the union of completed level IDs across both difficulties.
  ///
  /// Use this (rather than [loadCompletedLevels], which is scoped to a
  /// single difficulty and defaults to Hard) for any player-facing count —
  /// e.g. "N levels completed" on the mode-select screen — so Easy-only
  /// progress isn't invisible. This mirrors the union [isUnlocked] already
  /// uses for unlock-rule evaluation.
  Set<String> loadCompletedLevelsAnyDifficulty() => _completedOnAnyDifficulty();

  /// True when [level]'s unlock prerequisites are satisfied by the
  /// player's combined (Hard ∪ Easy) completion set.
  ///
  /// NOTE (minor perf consideration, not a correctness bug): each call to
  /// `isUnlocked` re-decodes both difficulty's JSON from SharedPreferences
  /// from scratch via `_completedOnAnyDifficulty()` (which itself calls
  /// `loadCompletedLevels` twice). If this is called once per level while
  /// rendering a long level-select list (e.g. inside a ListView.builder's
  /// itemBuilder, once per visible item, on every rebuild), that's
  /// O(visible levels) redundant JSON decodes per frame rather than one
  /// shared decode reused across all of them. Not wrong, just something to
  /// watch if the level list grows large or level-select re-renders
  /// frequently — callers rendering many levels at once may want to call
  /// `loadCompletedLevelsAnyDifficulty()` themselves once and pass the
  /// result down, rather than calling `isUnlocked` per level.
  bool isUnlocked(GameLevel level) =>
      level.unlockRule.isSatisfied(_completedOnAnyDifficulty());

  /// Returns the union of all completed IDs across both difficulties.
  /// Used for unlock-rule evaluation so either completion counts.
  Set<String> _completedOnAnyDifficulty() =>
      // loadCompletedLevels(hard) returns a *fresh* Set each call (see its
      // doc comment above), so mutating it in place via the cascade
      // (`..addAll(...)`) is safe — it isn't aliased to anything this store
      // keeps internally, it's just a throwaway Set being built up and
      // returned.
      loadCompletedLevels(LevelDifficulty.hard)
        ..addAll(loadCompletedLevels(LevelDifficulty.easy));

  /// Returns the unlock rule description for a locked level.
  String unlockHint(GameLevel level) => level.unlockRule.describe();
}

// ═════════════════════════════════════════════════════════════════════════════
//  2. PUZZLE TYPE VALIDATION
//
//  Player-facing formatting for DFA-vs-NFA validation results.
//
//  The check itself is AutomatonTypeChecker.check(...) (see
//  dialogs/equivalence_dialog.dart) — called directly from the puzzle
//  screen's submission path. buildTypeErrorMessage() below turns that result
//  into a structured, displayable message:
//
//    final typeResult = AutomatonTypeChecker.check(
//      nodes: currentNodes,
//      lines: currentLines,
//      startArrow: currentStartArrow,
//      alphabet: puzzle.alphabet,
//      required: puzzle.requiredAutomatonType,
//    );
//
//    final msg = buildTypeErrorMessage(typeResult);
//    if (msg != null) {
//      // Show msg.headline as a banner / toast.
//      // Optionally list msg.errors / msg.warnings in an expanded panel.
//      return; // block progression
//    }
//
//    // … proceed with the normal correctness check …
// ═════════════════════════════════════════════════════════════════════════════

// ─── Convenience widget helper ────────────────────────────────────────────────

/// Produces a structured, player-facing error message from a failed type check.
///
/// Returns null when [result] reports no violations (the automaton is correct).
///
/// Use this in the UI layer:
///
///   final msg = buildTypeErrorMessage(typeResult);
///   if (msg != null) showErrorBanner(msg);
///
TypeCheckDisplayMessage? buildTypeErrorMessage(AutomatonTypeResult result) {
  // Early-out: nothing to display when the automaton already satisfies the
  // puzzle's required type. Keeps every call site from having to
  // separately check `result.isCorrectType` itself.
  if (result.isCorrectType) return null;

  // Separate hard errors from warnings. `errors` block progression (an
  // actual DFA-determinism violation, e.g. an ε-transition where none is
  // allowed); `warnings` are softer, non-blocking notes (see `onlyWarnings`
  // below) — e.g. a DFA that's technically valid but has a missing
  // transition for some symbol, which is still "a DFA" but incomplete.
  final errors = result.violations
      .where((v) => v.severity == ViolationSeverity.error)
      .toList();
  final warnings = result.violations
      .where((v) => v.severity == ViolationSeverity.warning)
      .toList();

  return TypeCheckDisplayMessage(
    headline: result.primaryMessage,
    errors: errors.map((v) => v.message).toList(),
    warnings: warnings.map((v) => v.message).toList(),
    // IDs for optional UI highlighting of offending states / transitions.
    // `.whereType<String>()` both filters out any violation that has no
    // affected-state/line ID (a null `affectedStateId`/`affectedLineId`)
    // AND narrows the type from `String?` to `String` in one step — a
    // concise idiom for "collect the non-null values" without an explicit
    // null check inside a `.where()`.
    affectedStateIds:
        result.violations.map((v) => v.affectedStateId).whereType<String>().toSet(),
    affectedLineIds:
        result.violations.map((v) => v.affectedLineId).whereType<String>().toSet(),
  );
}

/// Plain-data class the UI layer consumes.  No Flutter dependency — convert
/// to your preferred widget / dialog in the presentation layer.
class TypeCheckDisplayMessage {
  const TypeCheckDisplayMessage({
    required this.headline,
    required this.errors,
    required this.warnings,
    required this.affectedStateIds,
    required this.affectedLineIds,
  });

  /// Short banner text, e.g. "Your automaton is an NFA, but this puzzle
  /// requires a DFA."
  final String headline;

  /// Each item is one bullet explaining a hard error (~-transition, duplicate
  /// transition for a symbol, multiple start states).
  final List<String> errors;

  /// Each item is one bullet for a soft warning (missing transition).
  final List<String> warnings;

  /// State node IDs that could be highlighted red in the graph canvas.
  final Set<String> affectedStateIds;

  /// Transition line IDs that could be highlighted red in the graph canvas.
  final Set<String> affectedLineIds;

  /// True when there are only warnings and no hard errors — the player is
  /// close but their DFA is incomplete rather than outright nondeterministic.
  bool get onlyWarnings => errors.isEmpty && warnings.isNotEmpty;

  /// Debug/log-friendly rendering: headline, then one indented bullet line
  /// per error (✗) and warning (⚠). Not used for the actual in-app UI
  /// (that's built from the individual `headline`/`errors`/`warnings`
  /// fields directly by whatever widget consumes this class) — this is a
  /// convenience for print-debugging or log output.
  @override
  String toString() {
    final buffer = StringBuffer()..writeln(headline);
    for (final e in errors) {
      buffer.writeln('  ✗ $e');
    }
    for (final w in warnings) {
      buffer.writeln('  ⚠ $w');
    }
    // `.trim()` removes the final trailing newline `writeln` leaves behind
    // after the last bullet, so callers that print this (e.g. `print(msg)`,
    // which itself appends a newline) don't end up with a visible blank
    // line at the end.
    return buffer.toString().trim();
  }
}