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

import 'dart:convert'; // Provides jsonEncode/jsonDecode for serializing the completed-levels set to a string for SharedPreferences.

import 'package:shared_preferences/shared_preferences.dart'; // Key-value persistence API used by GameProgressStore.

import 'dialogs/equivalence_dialog.dart' // Import (not re-exported) just the two types this file's own code references directly.
    show
        AutomatonTypeResult, // The result object returned by AutomatonTypeChecker.check(...).
        ViolationSeverity; // Enum distinguishing hard errors from warnings within a type-check result.
import 'game_level.dart'; // Brings in GameLevel and LevelDifficulty, used throughout GameProgressStore.

export 'dialogs/equivalence_dialog.dart' // Re-export selected symbols so callers of game_data.dart don't need a separate import of equivalence_dialog.dart.
    show
        RequiredAutomatonType, // Enum describing what automaton type (DFA/NFA/etc.) a puzzle demands.
        AutomatonTypeResult, // Re-exported so UI code checking a puzzle's result type doesn't need the dialog import too.
        AutomatonViolation, // The individual violation record type.
        ViolationSeverity; // Re-exported severity enum.

// ═════════════════════════════════════════════════════════════════════════════
//  1. GAME PROGRESS STORE
// ═════════════════════════════════════════════════════════════════════════════

abstract final class GamePreferenceKeys { // Non-instantiable ("abstract final") holder class — purely a namespace for static key-building helpers/constants.
  static const completedLevels = 'game_completed_levels'; // The SharedPreferences key used for Hard-difficulty completed-level IDs (also the legacy/original key name).

  /// Completion key scoped to a difficulty.
  ///
  /// Hard completions use the legacy key so existing saves are honoured.
  /// Easy completions are stored under a separate key so the two difficulties
  /// track progress independently.
  static String completedKey(LevelDifficulty difficulty) => // Given a difficulty, returns which SharedPreferences key stores its completed-IDs list.
      difficulty == LevelDifficulty.hard // Hard difficulty keeps using the original/legacy key name for backward compatibility with existing saves.
          ? completedLevels
          : 'game_completed_levels_easy'; // Any other difficulty (i.e. Easy) gets its own distinct key.

  /// Per-level in-progress DSL scoped to difficulty.
  ///
  /// Hard uses the legacy key so existing work-in-progress is preserved.
  static String levelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) => // Builds the per-level, per-difficulty key for a player's in-progress automaton DSL text; difficulty defaults to Hard if omitted.
      difficulty == LevelDifficulty.hard // Hard keeps the original naming scheme (no "_easy" suffix) so old saves still resolve.
          ? 'game_level_dsl_$levelId'
          : 'game_level_dsl_${levelId}_easy'; // Easy gets a distinct key per level, suffixed with "_easy".
} // End of GamePreferenceKeys.

class GameProgressStore { // Wraps a SharedPreferences instance with typed, game-specific read/write methods.
  GameProgressStore._(this._prefs); // Private named constructor — forces callers through the async `open()` factory below instead of constructing directly.

  final SharedPreferences _prefs; // The underlying SharedPreferences instance this store reads/writes through.

  static Future<GameProgressStore> open() async { // Async factory: obtains the SharedPreferences singleton and wraps it.
    return GameProgressStore._(await SharedPreferences.getInstance()); // Await the platform-backed SharedPreferences instance, then construct the store around it.
  } // End of open().

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Loads the set of completed level IDs for [difficulty].
  Set<String> loadCompletedLevels([LevelDifficulty difficulty = LevelDifficulty.hard]) { // Reads and decodes the completed-level-ID set for a given difficulty (Hard by default).
    final raw = _prefs.getString(GamePreferenceKeys.completedKey(difficulty)); // Fetch the raw JSON string stored under this difficulty's key (or null if never written).
    if (raw == null || raw.isEmpty) return {}; // No saved data yet (or an empty string) — treat as "nothing completed".
    try {
      final list = jsonDecode(raw) as List<dynamic>; // Parse the JSON string into a dynamically-typed list.
      return {for (final item in list) item.toString()}; // Build a Set<String> by stringifying every element (set-comprehension syntax), so any JSON scalar type still lands as a String.
    } catch (_) {
      return {}; // Malformed/corrupt stored JSON — fail safe by reporting no completions rather than crashing.
    }
  } // End of loadCompletedLevels.

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> markCompleted(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async { // Marks a level complete on the given difficulty (defaults to Hard), with cross-difficulty propagation.
    // Always write to the requested difficulty.
    final current = loadCompletedLevels(difficulty); // Load the existing completed set for the requested difficulty.
    current.add(levelId); // Add this level's ID to that set.
    await _save(current, difficulty); // Persist the updated set back to SharedPreferences.

    // Completing on Hard is a strict superset of Easy — grant Easy too so the
    // player doesn't see an unearned gap in their badges.
    if (difficulty == LevelDifficulty.hard) { // Only cascade when the level was just completed on Hard...
      final easy = loadCompletedLevels(LevelDifficulty.easy); // ...by loading the current Easy-difficulty completed set...
      if (!easy.contains(levelId)) { // ...and only writing if this level isn't already marked complete on Easy (avoids a redundant write).
        easy.add(levelId); // Add the level to the Easy set too.
        await _save(easy, LevelDifficulty.easy); // Persist the updated Easy set.
      }
    }
  } // End of markCompleted.

  Future<void> markIncomplete(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async { // Removes a level from the completed set for one specific difficulty (no cross-difficulty cascade, unlike markCompleted).
    final current = loadCompletedLevels(difficulty); // Load the current completed set for this difficulty.
    current.remove(levelId); // Remove the level ID if present (no-op if it wasn't there).
    await _save(current, difficulty); // Persist the updated set.
  } // End of markIncomplete.

  /// Resets all progress for both difficulties.
  Future<void> resetAll() async { // Wipes completed-level data for both Hard and Easy.
    await _prefs.remove(GamePreferenceKeys.completedKey(LevelDifficulty.hard)); // Delete the Hard-difficulty completed-levels key entirely.
    await _prefs.remove(GamePreferenceKeys.completedKey(LevelDifficulty.easy)); // Delete the Easy-difficulty completed-levels key entirely.
  } // End of resetAll. Note: does not touch per-level DSL keys (levelDsl) — only completion status.

  // ── Per-level DSL (work-in-progress) ─────────────────────────────────────

  String? loadLevelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) => // Reads back a player's saved in-progress automaton DSL text for a level/difficulty, or null if none saved.
      _prefs.getString(GamePreferenceKeys.levelDsl(levelId, difficulty)); // Direct SharedPreferences string lookup using the composed key.

  Future<void> saveLevelDsl(String levelId, String dsl, [LevelDifficulty difficulty = LevelDifficulty.hard]) async { // Persists a player's current in-progress DSL text for a level/difficulty.
    await _prefs.setString(GamePreferenceKeys.levelDsl(levelId, difficulty), dsl); // Write the DSL string under the composed per-level-per-difficulty key.
  } // End of saveLevelDsl.

  Future<void> clearLevelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async { // Deletes any saved in-progress DSL for a level/difficulty (e.g. once the level is solved and no longer "in progress").
    await _prefs.remove(GamePreferenceKeys.levelDsl(levelId, difficulty)); // Remove the key entirely.
  } // End of clearLevelDsl.

  Future<void> _save(Set<String> ids, LevelDifficulty difficulty) async { // Private helper shared by markCompleted/markIncomplete: serializes and writes a completed-ID set.
    await _prefs.setString(
      GamePreferenceKeys.completedKey(difficulty), // Key depends on which difficulty is being saved.
      jsonEncode(ids.toList()), // Convert the Set to a List (Sets aren't directly JSON-encodable) then to a JSON string.
    );
  } // End of _save.

  // ── Derived queries ───────────────────────────────────────────────────────

  bool isCompleted(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) => // True if `levelId` is completed on exactly the given difficulty (default Hard).
      loadCompletedLevels(difficulty).contains(levelId); // Load that difficulty's set and check membership.

  /// A level is considered "completed" for unlock purposes if it has been beaten
  /// on either difficulty (easy or hard).
  bool isCompletedOnAnyDifficulty(String levelId) => // True if the level is completed on Hard OR Easy.
      isCompleted(levelId, LevelDifficulty.hard) || // Check Hard completion first...
      isCompleted(levelId, LevelDifficulty.easy); // ...then Easy completion (short-circuiting `||` skips the second check if the first is true).

  /// Returns the union of completed level IDs across both difficulties.
  ///
  /// Use this (rather than [loadCompletedLevels], which is scoped to a
  /// single difficulty and defaults to Hard) for any player-facing count —
  /// e.g. "N levels completed" on the mode-select screen — so Easy-only
  /// progress isn't invisible. This mirrors the union [isUnlocked] already
  /// uses for unlock-rule evaluation.
  Set<String> loadCompletedLevelsAnyDifficulty() => _completedOnAnyDifficulty(); // Public wrapper exposing the private union helper below, for player-facing totals.

  bool isUnlocked(GameLevel level) => // Whether a given level's unlock prerequisites are currently satisfied.
      level.unlockRule.isSatisfied(_completedOnAnyDifficulty()); // Delegate to the level's own unlock-rule object, passing in the union of completed IDs across both difficulties.

  /// Returns the union of all completed IDs across both difficulties.
  /// Used for unlock-rule evaluation so either completion counts.
  Set<String> _completedOnAnyDifficulty() => // Private helper computing the set union of Hard-completed and Easy-completed IDs.
      loadCompletedLevels(LevelDifficulty.hard) // Start from the Hard-difficulty completed set...
        ..addAll(loadCompletedLevels(LevelDifficulty.easy)); // ...then cascade-mutate it by adding all Easy-difficulty completed IDs too (cascade returns the same, now-merged set).

  /// Returns the unlock rule description for a locked level.
  String unlockHint(GameLevel level) => level.unlockRule.describe(); // Human-readable text explaining what's needed to unlock this level, delegated to the level's unlock-rule object.
} // End of GameProgressStore.

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
TypeCheckDisplayMessage? buildTypeErrorMessage(AutomatonTypeResult result) { // Converts a raw type-check result into a nullable, UI-ready display message.
  if (result.isCorrectType) return null; // No violations at all — nothing to show, so return null (caller treats this as "check passed").

  // Separate hard errors from warnings.
  final errors = result.violations // Start from the full list of violations...
      .where((v) => v.severity == ViolationSeverity.error) // ...keep only the ones flagged as hard errors...
      .toList(); // ...and materialize into a List.
  final warnings = result.violations // Same source list again...
      .where((v) => v.severity == ViolationSeverity.warning) // ...but keep only the soft-warning-severity ones this time...
      .toList(); // ...materialized into its own List.

  return TypeCheckDisplayMessage(
    headline: result.primaryMessage, // Top-line summary text taken straight from the check result.
    errors: errors.map((v) => v.message).toList(), // Extract just the human-readable message string from each error violation.
    warnings: warnings.map((v) => v.message).toList(), // Extract just the human-readable message string from each warning violation.
    // IDs for optional UI highlighting of offending states / transitions.
    affectedStateIds: // Collect every violation's affected state ID (if any) into a deduplicated Set for the canvas to highlight.
        result.violations.map((v) => v.affectedStateId).whereType<String>().toSet(), // map() may yield nulls; whereType<String>() filters those out before deduplicating via toSet().
    affectedLineIds: // Same idea, but for transition-line IDs instead of state IDs.
        result.violations.map((v) => v.affectedLineId).whereType<String>().toSet(), // Filters out null affectedLineId entries, then dedupes into a Set.
  );
} // End of buildTypeErrorMessage.

/// Plain-data class the UI layer consumes.  No Flutter dependency — convert
/// to your preferred widget / dialog in the presentation layer.
class TypeCheckDisplayMessage { // Immutable, framework-agnostic value object describing a type-check failure for display purposes.
  const TypeCheckDisplayMessage({ // Const constructor — all fields required, no defaults.
    required this.headline,
    required this.errors,
    required this.warnings,
    required this.affectedStateIds,
    required this.affectedLineIds,
  });

  /// Short banner text, e.g. "Your automaton is an NFA, but this puzzle
  /// requires a DFA."
  final String headline; // Top-level summary shown as a banner/toast.

  /// Each item is one bullet explaining a hard error (~-transition, duplicate
  /// transition for a symbol, multiple start states).
  final List<String> errors; // List of hard-error bullet strings.

  /// Each item is one bullet for a soft warning (missing transition).
  final List<String> warnings; // List of soft-warning bullet strings.

  /// State node IDs that could be highlighted red in the graph canvas.
  final Set<String> affectedStateIds; // IDs of graph nodes implicated by any violation, for optional highlighting.

  /// Transition line IDs that could be highlighted red in the graph canvas.
  final Set<String> affectedLineIds; // IDs of graph transition lines implicated by any violation, for optional highlighting.

  /// True when there are only warnings and no hard errors — the player is
  /// close but their DFA is incomplete rather than outright nondeterministic.
  bool get onlyWarnings => errors.isEmpty && warnings.isNotEmpty; // Derived getter: true only when there are zero hard errors but at least one warning.

  @override
  String toString() { // Debug/log-friendly rendering of the whole message (headline + bulleted errors/warnings).
    final buffer = StringBuffer()..writeln(headline); // Start a StringBuffer, immediately writing the headline as its first line (cascade keeps `buffer` as the result).
    for (final e in errors) { // For every hard-error message...
      buffer.writeln('  ✗ $e'); // ...append it as an indented bullet prefixed with a cross mark.
    }
    for (final w in warnings) { // For every warning message...
      buffer.writeln('  ⚠ $w'); // ...append it as an indented bullet prefixed with a warning triangle.
    }
    return buffer.toString().trim(); // Render the buffer to a String and trim any trailing newline/whitespace before returning.
  } // End of toString.
} // End of TypeCheckDisplayMessage.