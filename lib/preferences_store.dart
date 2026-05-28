import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'saved_export.dart';

/// Keys used in [SharedPreferences] for FAExplorer session data.
abstract final class PreferenceKeys {
  static const graphDsl = 'graph_dsl';
  static const savedExports = 'saved_exports';
  static const showSimulator = 'show_simulator';
  static const showHelpOverlay = 'show_help_overlay';
  static const simInput = 'sim_input';
  static const simStep = 'sim_step';
}

class PersistedSnapshot {
  final String? graphDsl;
  final List<SavedExport> savedExports;
  final bool showSimulator;
  final bool showHelpOverlay;
  final String simInput;
  final int simStep;

  const PersistedSnapshot({
    this.graphDsl,
    this.savedExports = const [],
    this.showSimulator = true,
    this.showHelpOverlay = false,
    this.simInput = '',
    this.simStep = -1,
  });
}

class PreferencesStore {
  PreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PreferencesStore> open() async {
    return PreferencesStore(await SharedPreferences.getInstance());
  }

  PersistedSnapshot load() {
    final exportsJson = _prefs.getString(PreferenceKeys.savedExports);
    return PersistedSnapshot(
      graphDsl: _prefs.getString(PreferenceKeys.graphDsl),
      savedExports: _decodeExports(exportsJson),
      showSimulator: _prefs.getBool(PreferenceKeys.showSimulator) ?? true,
      showHelpOverlay: _prefs.getBool(PreferenceKeys.showHelpOverlay) ?? false,
      simInput: _prefs.getString(PreferenceKeys.simInput) ?? '',
      simStep: _prefs.getInt(PreferenceKeys.simStep) ?? -1,
    );
  }

  Future<void> saveGraphDsl(String dsl) async {
    if (dsl.trim().isEmpty) {
      await _prefs.remove(PreferenceKeys.graphDsl);
    } else {
      await _prefs.setString(PreferenceKeys.graphDsl, dsl);
    }
  }

  Future<void> saveSavedExports(List<SavedExport> exports) async {
    final encoded = jsonEncode(
      exports
          .map(
            (e) => {
              'name': e.name,
              'dsl': e.dsl,
              'type': e.type.name,
              'blackBoxDescription': e.blackBoxDescription,
            },
          )
          .toList(),
    );
    await _prefs.setString(PreferenceKeys.savedExports, encoded);
  }

  Future<void> saveUi({
    bool? showSimulator,
    bool? showHelpOverlay,
  }) async {
    if (showSimulator != null) {
      await _prefs.setBool(PreferenceKeys.showSimulator, showSimulator);
    }
    if (showHelpOverlay != null) {
      await _prefs.setBool(PreferenceKeys.showHelpOverlay, showHelpOverlay);
    }
  }

  Future<void> saveSimulator({
    required String input,
    required int step,
  }) async {
    if (input.isEmpty) {
      await _prefs.remove(PreferenceKeys.simInput);
    } else {
      await _prefs.setString(PreferenceKeys.simInput, input);
    }
    await _prefs.setInt(PreferenceKeys.simStep, step);
  }

  Future<void> clearAll() async {
    await _prefs.remove(PreferenceKeys.graphDsl);
    await _prefs.remove(PreferenceKeys.savedExports);
    await _prefs.remove(PreferenceKeys.simInput);
    await _prefs.remove(PreferenceKeys.simStep);
  }

  static List<SavedExport> _decodeExports(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>)
            SavedExport(
              name: item['name'] as String? ?? 'Export',
              dsl: item['dsl'] as String? ?? '',
              type: item['type'] == SavedExportType.blackBox.name
                  ? SavedExportType.blackBox
                  : SavedExportType.graph,
              blackBoxDescription: item['blackBoxDescription'] as String? ?? '',
            )
          else if (item is Map)
            SavedExport(
              name: item['name']?.toString() ?? 'Export',
              dsl: item['dsl']?.toString() ?? '',
              type: item['type']?.toString() == SavedExportType.blackBox.name
                  ? SavedExportType.blackBox
                  : SavedExportType.graph,
              blackBoxDescription:
                  item['blackBoxDescription']?.toString() ?? '',
            ),
      ];
    } catch (_) {
      return [];
    }
  }
}
