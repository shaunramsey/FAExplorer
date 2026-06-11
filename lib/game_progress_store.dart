// ─────────────────────────────────────────────────────────────────────────────
//  Game progress store — persists completed level IDs via SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_level.dart';

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
    final current = loadCompletedLevels(difficulty);
    current.add(levelId);
    await _save(current, difficulty);
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