import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

// ─────────────────────────────────────────────────────────────────────────────
//  GraphState
//
//  A plain-data snapshot of the canvas: nodes, lines, start arrow, counters,
//  and the current simulation mode.  Used by:
//
//    • DslCodec.exportToDsl / importFromDsl
//    • LatexExporter.export / LatexImporter.import
//    • automata_screen.dart  (_graphState getter, _applyGraphState)
//    • automata_screen_work.dart  (same)
//    • automata_dialogs.dart  (showExportDialog, _runBlackBox)
//
//  Add `import 'graph_state.dart';` to models.dart (or wherever you keep your
//  barrel exports) so that all existing `import 'models.dart'` callers pick it
//  up automatically.
// ─────────────────────────────────────────────────────────────────────────────

class GraphState {
  const GraphState({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.nodeCounter,
    required this.lineCounter,
    this.automataMode = AutomataMode.ndfa,
  });

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;
  final int nodeCounter;
  final int lineCounter;

  /// Current simulation mode (NDFA / PDA / TM).
  ///
  /// Defaults to [AutomataMode.ndfa] so that callers which do not pass the
  /// field (e.g. [LatexImporter], the dummy fallback in [_LatexExportDialog])
  /// still compile without change.
  final AutomataMode automataMode;
}