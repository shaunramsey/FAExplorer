import '../preferences_store.dart';

/// Loads and saves automata workspace data (graph, exports, simulator, UI).
abstract class AutomataSessionStore {
  Future<PersistedSnapshot> load();

  Future<void> save(PersistedSnapshot snapshot);
}

class LocalSessionStore implements AutomataSessionStore {
  LocalSessionStore(this._prefs);

  final PreferencesStore _prefs;

  static Future<LocalSessionStore> open() async {
    return LocalSessionStore(await PreferencesStore.open());
  }

  @override
  Future<PersistedSnapshot> load() async => _prefs.load();

  @override
  Future<void> save(PersistedSnapshot snapshot) async {
    await _prefs.saveGraphDsl(snapshot.graphDsl ?? '');
    await _prefs.saveSavedExports(snapshot.savedExports);
    await _prefs.saveUi(
      showSimulator: snapshot.showSimulator,
      showHelpOverlay: snapshot.showHelpOverlay,
    );
    await _prefs.saveSimulator(
      input: snapshot.simInput,
      step: snapshot.simStep,
      additionalTapeInputs: snapshot.additionalTapeInputs,
    );
  }
}