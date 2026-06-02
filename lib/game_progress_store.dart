// ─────────────────────────────────────────────────────────────────────────────
//  Game progress store — persists completed level IDs via SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_level.dart';

abstract final class GamePreferenceKeys {
  static const completedLevels = 'game_completed_levels';
}

class GameProgressStore {
  GameProgressStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<GameProgressStore> open() async {
    return GameProgressStore._(await SharedPreferences.getInstance());
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Set<String> loadCompletedLevels() {
    final raw = _prefs.getString(GamePreferenceKeys.completedLevels);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return {for (final item in list) item.toString()};
    } catch (_) {
      return {};
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> markCompleted(String levelId) async {
    final current = loadCompletedLevels();
    current.add(levelId);
    await _save(current);
  }

  Future<void> markIncomplete(String levelId) async {
    final current = loadCompletedLevels();
    current.remove(levelId);
    await _save(current);
  }

  Future<void> resetAll() async {
    await _prefs.remove(GamePreferenceKeys.completedLevels);
  }

  Future<void> _save(Set<String> ids) async {
    await _prefs.setString(
      GamePreferenceKeys.completedLevels,
      jsonEncode(ids.toList()),
    );
  }

  // ── Derived queries ───────────────────────────────────────────────────────

  bool isCompleted(String levelId) =>
      loadCompletedLevels().contains(levelId);

  bool isUnlocked(GameLevel level) =>
      level.unlockRule.isSatisfied(loadCompletedLevels());

  /// Returns the unlock rule description for a locked level.
  String unlockHint(GameLevel level) => level.unlockRule.describe();
}