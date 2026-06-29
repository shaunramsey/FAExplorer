import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SavedExportType { graph, blackBox }

class SavedExport {
  String name;
  String dsl;
  SavedExportType type;
  String blackBoxDescription;

  SavedExport({
    required this.name,
    required this.dsl,
    this.type = SavedExportType.graph,
    this.blackBoxDescription = '',
  });

  bool get isBlackBox => type == SavedExportType.blackBox;
}

/// Keys used in [SharedPreferences] for FAExplorer session data.
abstract final class PreferenceKeys {
  static const graphDsl = 'graph_dsl';
  static const savedExports = 'saved_exports';
  static const showSimulator = 'show_simulator';
  static const showHelpOverlay = 'show_help_overlay';
  static const simInput = 'sim_input';
  static const simStep = 'sim_step';
  /// JSON-encoded list of strings: content for tapes 2, 3, … (index 0 = tape 2).
  static const additionalTapeInputs = 'additional_tape_inputs';
}

class PersistedSnapshot {
  final String? graphDsl;
  final List<SavedExport> savedExports;
  final bool showSimulator;
  final bool showHelpOverlay;
  final String simInput;
  final int simStep;
  /// Content for tapes 2, 3, … (index 0 = tape 2, index 1 = tape 3, …).
  /// Each string is the raw user input for that tape, tokenised the same way
  /// as [simInput].  Empty list means all extra tapes start blank.
  final List<String> additionalTapeInputs;

  const PersistedSnapshot({
    this.graphDsl,
    this.savedExports = const [],
    this.showSimulator = true,
    this.showHelpOverlay = false,
    this.simInput = '',
    this.simStep = -1,
    this.additionalTapeInputs = const [],
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
      additionalTapeInputs: _decodeTapeInputs(
        _prefs.getString(PreferenceKeys.additionalTapeInputs),
      ),
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
    List<String> additionalTapeInputs = const [],
  }) async {
    if (input.isEmpty) {
      await _prefs.remove(PreferenceKeys.simInput);
    } else {
      await _prefs.setString(PreferenceKeys.simInput, input);
    }
    await _prefs.setInt(PreferenceKeys.simStep, step);

    // Persist extra-tape inputs.  Remove the key entirely when all tapes are
    // blank so we don't store unnecessary noise for single-tape machines.
    final nonEmpty = additionalTapeInputs.map((s) => s).toList();
    final allBlank = nonEmpty.every((s) => s.isEmpty);
    if (allBlank) {
      await _prefs.remove(PreferenceKeys.additionalTapeInputs);
    } else {
      await _prefs.setString(
        PreferenceKeys.additionalTapeInputs,
        jsonEncode(nonEmpty),
      );
    }
  }

  Future<void> clearAll() async {
    await _prefs.remove(PreferenceKeys.graphDsl);
    await _prefs.remove(PreferenceKeys.savedExports);
    await _prefs.remove(PreferenceKeys.simInput);
    await _prefs.remove(PreferenceKeys.simStep);
    await _prefs.remove(PreferenceKeys.additionalTapeInputs);
  }

  static List<SavedExport> _decodeExports(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final result = <SavedExport>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          // Strict null checking with proper fallbacks
          final nameRaw = item['name'];
          final name = (nameRaw != null) ? nameRaw.toString().trim() : 'Export';
          
          final dslRaw = item['dsl'];
          final dsl = (dslRaw != null) ? dslRaw.toString() : '';
          
          final typeStr = item['type']?.toString().trim() ?? '';
          
          final descRaw = item['blackBoxDescription'];
          final desc = (descRaw != null) ? descRaw.toString() : '';
          
          result.add(SavedExport(
            name: name,
            dsl: dsl,
            type: typeStr == SavedExportType.blackBox.name
                ? SavedExportType.blackBox
                : SavedExportType.graph,
            blackBoxDescription: desc,
          ));
        } catch (_) {
          // Skip individual corrupt entries rather than aborting the whole list.
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Decodes a JSON-encoded list of tape-input strings.
  /// Returns an empty list on any parse error so callers always get a safe value.
  static List<String> _decodeTapeInputs(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [for (final item in list) item?.toString() ?? ''];
    } catch (_) {
      return [];
    }
  }
}