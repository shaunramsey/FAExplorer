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

export 'dialogs/equivalence_dialog.dart'
    show
        RequiredAutomatonType,
        AutomatonTypeResult,
        AutomatonViolation,
        ViolationSeverity;

// ═════════════════════════════════════════════════════════════════════════════
//  1. GAME PROGRESS STORE
// ═════════════════════════════════════════════════════════════════════════════

abstract final class GamePreferenceKeys {
  static const completedLevels = 'game_completed_levels';

  /// Completion key scoped to a difficulty.
  ///
  /// Hard completions use the legacy key so existing saves are honoured.
  /// Easy completions are stored under a separate key so the two difficulties
  /// track progress independently.
  static String completedKey(LevelDifficulty difficulty) =>
      difficulty == LevelDifficulty.hard
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

class GameProgressStore {
  GameProgressStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<GameProgressStore> open() async {
    return GameProgressStore._(await SharedPreferences.getInstance());
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Loads the set of completed level IDs for [difficulty].
  Set<String> loadCompletedLevels([LevelDifficulty difficulty = LevelDifficulty.hard]) {
    final raw = _prefs.getString(GamePreferenceKeys.completedKey(difficulty));
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return {for (final item in list) item.toString()};
    } catch (_) {
      return {};
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

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
    }
  }

  Future<void> markIncomplete(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async {
    final current = loadCompletedLevels(difficulty);
    current.remove(levelId);
    await _save(current, difficulty);
  }

  /// Resets all progress for both difficulties.
  Future<void> resetAll() async {
    await _prefs.remove(GamePreferenceKeys.completedKey(LevelDifficulty.hard));
    await _prefs.remove(GamePreferenceKeys.completedKey(LevelDifficulty.easy));
  }

  // ── Per-level DSL (work-in-progress) ─────────────────────────────────────

  String? loadLevelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) =>
      _prefs.getString(GamePreferenceKeys.levelDsl(levelId, difficulty));

  Future<void> saveLevelDsl(String levelId, String dsl, [LevelDifficulty difficulty = LevelDifficulty.hard]) async {
    await _prefs.setString(GamePreferenceKeys.levelDsl(levelId, difficulty), dsl);
  }

  Future<void> clearLevelDsl(String levelId, [LevelDifficulty difficulty = LevelDifficulty.hard]) async {
    await _prefs.remove(GamePreferenceKeys.levelDsl(levelId, difficulty));
  }

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

  bool isUnlocked(GameLevel level) =>
      level.unlockRule.isSatisfied(_completedOnAnyDifficulty());

  /// Returns the union of all completed IDs across both difficulties.
  /// Used for unlock-rule evaluation so either completion counts.
  Set<String> _completedOnAnyDifficulty() =>
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
  if (result.isCorrectType) return null;

  // Separate hard errors from warnings.
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

  @override
  String toString() {
    final buffer = StringBuffer()..writeln(headline);
    for (final e in errors) {
      buffer.writeln('  ✗ $e');
    }
    for (final w in warnings) {
      buffer.writeln('  ⚠ $w');
    }
    return buffer.toString().trim();
  }
}
