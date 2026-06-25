import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'data/automata_session_store.dart';
import 'preferences_store.dart';
import 'node.dart';
import 'line.dart';
import 'start_arrow.dart';
import 'dsl_code.dart';
import 'simulator.dart';
import 'pda_simulator.dart';
import 'saved_export.dart';
import 'dialogs/automata_dialogs.dart';
import 'dialogs/batch_simulator_dialog.dart';
import 'dialogs/equivalence_dialog.dart';
import 'dialogs/fa_to_regex_dialog.dart';
import 'widgets/automata_drawer.dart';
import 'widgets/app_theme.dart';
import 'widgets/help_overlay.dart';
import 'widgets/palette_fab.dart';
import 'widgets/rubber_band_painter.dart';
import 'widgets/string_simulator_panel.dart';
import 'widgets/pda_stack_panel.dart';
import 'tm_simulator.dart';
import 'widgets/tm_config_panel.dart';
import 'widgets/black_box_input_dialog.dart';
import 'widgets/regex_panel.dart';
import 'regex_engine.dart';

class AutomataScreen extends StatefulWidget {
  const AutomataScreen({
    super.key,
    required this.sessionStore,
    this.isGuest = false,
    this.userEmail,
    this.onSignOut,
    this.onGoToGame,
  });

  final AutomataSessionStore sessionStore;
  final bool isGuest;
  final String? userEmail;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onGoToGame;

  @override
  State<AutomataScreen> createState() => _AutomataScreenState();
}

class _AutomataScreenState extends State<AutomataScreen> with WidgetsBindingObserver {
  final Map<String, NodeData> _nodes = {};
  final Map<String, LineData> _lines = {};

  bool _lineMode = false;
  bool _placingStartArrow = false;
  bool _deleteMode = false;

  bool _showHelpOverlay = false;
  bool _showSimulator = true;
  bool _showRegexPanel = false;   // ← shown automatically when mode == regex
  String? _regexPanelInitialText; // ← pre-filled when coming from FA→Regex
  AutomataMode _automataMode = AutomataMode.ndfa;

  StartArrowData? _startArrow;

  bool _draggingStartArrow = false;

  String? _draggingNodeId;
  String? _draggingLineId;
  String? _lineSourceNodeId;

  Offset? _lastPanPosition;
  Offset? _lastTapPosition;
  Offset? _rubberBandEnd;

  // Canvas panning
  bool _isPanningCanvas = false;

  int _nodeCounter = 0;
  int _lineCounter = 0;

  final FocusNode _focusNode = FocusNode();

  final List<SavedExport> _savedExports = [];

  late final AutomataSimulator _simulator;
  late final PdaSimulator _pdaSimulator;     // ← NEW
  late final TmSimulator _tmSimulator;       // ← TM
  final GlobalKey _simulatorPanelBoundaryKey = GlobalKey();

  /// Which tape tab is active in the string-simulator panel (0-based).
  /// Only meaningful in TM mode with more than one tape.
  int _activeTapeIndex = 0;

  /// Input strings for tapes 2, 3, … (index 0 = tape 2, index 1 = tape 3, …).
  /// Each controller holds what the user typed for that tape.
  /// The list grows/shrinks with [_tmSimulator.tapeCount].
  final List<TextEditingController> _tapeControllers = [];
  Timer? _persistTimer;
  bool _persistenceReady = false;
  bool _loadingPrefs = true;

  Future<void> _openBatchSimulatorDialog() => showBatchSimulatorDialog(
        context,
        simulator: _simulator,
        startArrow: _startArrow,
      );

  GraphState get _graphState => GraphState(
        nodes: _nodes,
        lines: _lines,
        startArrow: _startArrow,
        nodeCounter: _nodeCounter,
        lineCounter: _lineCounter,
        automataMode: _automataMode,
      );

  // ────────────────────────────────────────────────────────────────────────
  // STRING SIMULATION (delegates to AutomataSimulator)
  // ────────────────────────────────────────────────────────────────────────
  final TextEditingController _simController = TextEditingController();

  /// Whether we are at the final step and the result is accepted.
  bool get _isAtAcceptedFinalStep {
    if (_simulator.tokens.isEmpty) return false;
    if (_simulator.step != _simulator.tokens.length) return false;
    return _simulator.finalResult() == SimResult.accept;
  }

  /// At the accepted final step, union all nodes/lines from every step to
  /// highlight the complete accepted path. Otherwise show only the current step.
  Set<String> get _simActiveNodes {
    if (_automataMode == AutomataMode.pda) {
      return _pdaSimulator.activeNodes;
    }
    if (_automataMode == AutomataMode.tm) {
      return _tmSimulator.activeNodes;
    }
    if (_isAtAcceptedFinalStep) {
      return _simulator.states.expand((s) => s).toSet();
    }
    return _simulator.activeNodes;
  }

  Set<String> get _simActiveLines {
    if (_automataMode == AutomataMode.pda) {
      return _pdaSimulator.activeLines;
    }
    if (_automataMode == AutomataMode.tm) {
      return _tmSimulator.activeLines;
    }
    if (_isAtAcceptedFinalStep) {
      return _simulator.usedLines.expand((s) => s).toSet();
    }
    return _simulator.activeLines;
  }

  void _refreshSimulation() {
    // Only skip the rebuild when there is truly nothing to simulate: no input
    // text, no start arrow, and the simulator has never run.  In particular,
    // DO NOT skip when a start arrow exists — black-box DSL edits must always
    // propagate even if the user hasn't typed an input string yet.
    if (_simController.text.isEmpty &&
        _startArrow == null &&
        _simulator.states.isEmpty) {
      return;
    }
    _simRebuild();
    _schedulePersist();
  }

  void _schedulePersist() {
    if (!_persistenceReady) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  Future<void> _persistNow() async {
    if (!_persistenceReady) return;

    await widget.sessionStore.save(
      PersistedSnapshot(
        graphDsl: _exportToDsl(),
        savedExports: List<SavedExport>.from(_savedExports),
        showSimulator: _showSimulator,
        showHelpOverlay: _showHelpOverlay,
        simInput: _simController.text,
        simStep: _simulator.step,
        additionalTapeInputs: _tapeControllers.map((c) => c.text).toList(),
      ),
    );
  }

  Future<void> _loadPreferences() async {
    final snapshot = await widget.sessionStore.load();

    if (snapshot.graphDsl != null && snapshot.graphDsl!.trim().isNotEmpty) {
      try {
        final state = DslCodec.importFromDsl(snapshot.graphDsl!);
        _nodes
          ..clear()
          ..addAll(state.nodes);
        _lines
          ..clear()
          ..addAll(state.lines);
        _startArrow = state.startArrow;
        _nodeCounter = state.nodeCounter;
        _lineCounter = state.lineCounter;
        _automataMode = state.automataMode;
      } catch (_) {
        // Ignore corrupt saved graphs.
      }
    }

    _savedExports.addAll(snapshot.savedExports);
    _showSimulator = snapshot.showSimulator;
    _showHelpOverlay = snapshot.showHelpOverlay;
    _simController.text = snapshot.simInput;
    _simulator.step = snapshot.simStep;

    // Restore extra-tape inputs.  _simRebuild() will grow _tapeControllers to
    // the right length; we pre-populate them here so the text is already set
    // when _simRebuild calls rebuild() on the TM simulator.
    for (int i = 0; i < snapshot.additionalTapeInputs.length; i++) {
      // Grow the list if needed (it may still be empty at this point).
      while (_tapeControllers.length <= i) {
        _tapeControllers.add(TextEditingController());
      }
      _tapeControllers[i].text = snapshot.additionalTapeInputs[i];
    }

    if (_simController.text.isNotEmpty || _startArrow != null) {
      _simRebuild();
    }

    _persistenceReady = true;

    if (mounted) {
      setState(() => _loadingPrefs = false);
    }
  }

  /// Scans all transition labels and black-box DSLs in the current graph to
  /// find the highest tape index referenced anywhere, then returns that value
  /// (minimum 1).  This drives [TmSimulator.tapeCount] so the simulator always
  /// allocates enough tapes even when the user hasn't manually added them via
  /// the tape tab strip.
  int _autoDetectTapeCount() {
    int maxTape = 1;

    // Helper: extract the highest tape index mentioned in a single label string
    // using the same formats the simulator parsers accept.
    void scanLabel(String label) {
      if (label.trim().isEmpty) return;

      for (final raw in label.split('\n')) {
        final s = raw.trim();
        if (s.isEmpty) continue;

        // bN compound format: "1:aXR,b2,2:01S" — scan for N: prefixes.
        final prefixes = RegExp(r'(\d+):').allMatches(s);
        for (final m in prefixes) {
          final n = int.tryParse(m.group(1)!);
          if (n != null && n > maxTape) maxTape = n;
        }

        // Compact 3*N shorthand without tape prefixes: aXRa1L = 2 tapes.
        // Only count this when there are no N: prefixes and no commas (to
        // avoid misinterpreting bN compound labels).
        if (!s.contains(':') && !s.contains(',')) {
          final runes = s.runes.toList();
          if (runes.length >= 6 && runes.length % 3 == 0) {
            bool allDirsValid = true;
            final inferredTapes = runes.length ~/ 3;
            for (int i = 0; i < inferredTapes; i++) {
              final d = String.fromCharCode(runes[i * 3 + 2]).toUpperCase();
              if (d != 'R' && d != 'L' && d != 'S' && d != '~') {
                allDirsValid = false;
                break;
              }
            }
            if (allDirsValid && inferredTapes > maxTape) maxTape = inferredTapes;
          }
        }
      }
    }

    for (final line in _lines.values) {
      scanLabel(line.label);
    }

    // Also scan DSLs inside black-box nodes — their labels count toward the
    // outer tape count because _executeBlackBoxDsl sets tapeCount = outerTapeCount.
    for (final node in _nodes.values) {
      if (!node.isBlackBox || node.blackBoxDsl.trim().isEmpty) continue;
      try {
        final graph = DslCodec.importFromDsl(node.blackBoxDsl);
        for (final innerLine in graph.lines.values) {
          scanLabel(innerLine.label);
        }
      } catch (_) {
        // Malformed DSL — ignore.
      }
    }

    return maxTape;
  }

  void _simRebuild() {
    _simulator.rebuild(_simController.text, startArrow: _startArrow);
    if (_simulator.step > _simulator.tokens.length) {
      _simulator.step = _simulator.tokens.length;
    }
    _pdaSimulator.rebuild(_simController.text, startArrow: _startArrow);
    if (_pdaSimulator.step > _pdaSimulator.tokens.length) {
      _pdaSimulator.step = _pdaSimulator.tokens.length;
    }
    // Auto-detect required tape count from the graph so the simulator always
    // has enough tapes even if the user hasn't manually added them via the UI.
    // Only raise the count; never silently lower it below what the user set.
    final detectedTapes = _autoDetectTapeCount();
    if (detectedTapes > _tmSimulator.tapeCount) {
      _tmSimulator.tapeCount = detectedTapes;
      // Also clamp the active tape index so the UI tab stays valid.
      if (_activeTapeIndex >= _tmSimulator.tapeCount) {
        _activeTapeIndex = _tmSimulator.tapeCount - 1;
      }
    }
    // Ensure _tapeControllers has exactly (tapeCount - 1) entries.
    while (_tapeControllers.length < _tmSimulator.tapeCount - 1) {
      _tapeControllers.add(TextEditingController());
    }
    while (_tapeControllers.length > _tmSimulator.tapeCount - 1) {
      _tapeControllers.removeLast().dispose();
    }
    final additionalInputs = _tapeControllers.map((c) => c.text).toList();
    _tmSimulator.rebuild(
      _simController.text,
      startArrow: _startArrow,
      additionalTapeInputs: additionalInputs,
    );
  }

  void _cancelRubberBand() {
    _lineSourceNodeId = null;
    _rubberBandEnd = null;
  }

  bool _hitStartArrowSimple(Offset point) {
    if (_startArrow == null) return false;

    final node = _nodes[_startArrow!.nodeId];
    if (node == null) return false;

    var dir = _startArrow!.direction();

    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    const double radius = 50;

    final end = Offset(node.center.dx + dir.dx * radius, node.center.dy + dir.dy * radius);

    final start = Offset(end.dx + dir.dx * _startArrow!.length, end.dy + dir.dy * _startArrow!.length);

    // Large tap target around the tail tip
    if ((point - start).distance < 44) return true;

    final line = end - start;
    final lenSq = line.dx * line.dx + line.dy * line.dy;

    if (lenSq == 0) return false;

    double t = ((point.dx - start.dx) * line.dx + (point.dy - start.dy) * line.dy) / lenSq;

    t = t.clamp(0.0, 1.0);

    final projection = Offset(start.dx + line.dx * t, start.dy + line.dy * t);

    return (point - projection).distance < 44;
  }

  bool _isLabelTaken(String label, String currentId) {
    final normalized = label.trim();

    if (normalized.isEmpty) return false;

    return _nodes.values.any((n) => n.id != currentId && n.label.trim() == normalized);
  }

  bool _canStartLineFrom(String? nodeId) {
    if (nodeId == null) return false;
    return _nodes[nodeId]?.canHaveOutgoingTransitions ?? false;
  }

  String _nextId(String prefix) {
    if (prefix == 'n') {
      return '$prefix${_nodeCounter++}';
    }

    return '$prefix${_lineCounter++}';
  }

  void _deleteLine(String lineId) {
    final line = _lines[lineId];

    if (line == null) return;

    _nodes[line.nodeAId]?.connectedLineIds.remove(lineId);

    _nodes[line.nodeBId]?.connectedLineIds.remove(lineId);

    _lines.remove(lineId);
    _refreshSimulation();
  }

  void _deleteNode(String nodeId) {
    final node = _nodes[nodeId];

    if (node == null) return;

    for (final lineId in node.connectedLineIds.toList()) {
      _deleteLine(lineId);
    }

    if (_startArrow?.nodeId == nodeId) {
      _startArrow = null;
    }

    _nodes.remove(nodeId);
    _refreshSimulation();
  }

  @override
  void initState() {
    super.initState();

    _focusNode.requestFocus();

    _simulator = AutomataSimulator(
      nodes: _nodes,
      lines: _lines,
    );

    _pdaSimulator = PdaSimulator(         // ← NEW
      nodes: _nodes,
      lines: _lines,
    );

    _tmSimulator = TmSimulator(           // ← TM
      nodes: _nodes,
      lines: _lines,
    );

    _simController.addListener(_schedulePersist);
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    if (_persistenceReady) {
      unawaited(_persistNow());
    }
    WidgetsBinding.instance.removeObserver(this);
    _simController.removeListener(_schedulePersist);
    _focusNode.dispose();
    _simController.dispose();
    for (final c in _tapeControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _persistTimer?.cancel();
      unawaited(_persistNow());
    }
  }

  void _reset() {
    setState(() {
      _nodes.clear();
      _lines.clear();

      _draggingNodeId = null;
      _draggingLineId = null;
      _lineSourceNodeId = null;

      _startArrow = null;

      _nodeCounter = 0;
      _lineCounter = 0;

      _isPanningCanvas = false;
    });
    _simulator.tokens = [];
    _simulator.step = -1;
    _simulator.states.clear();
    _simulator.usedLines.clear();
    _simController.clear();
    _schedulePersist();
  }

  String _exportToDsl() => DslCodec.exportToDsl(_graphState);


  void _applyGraphState(GraphState state) {
    setState(() {
      _nodes
        ..clear()
        ..addAll(state.nodes);
      _lines
        ..clear()
        ..addAll(state.lines);
      _startArrow = state.startArrow;
      _nodeCounter = state.nodeCounter;
      _lineCounter = state.lineCounter;
      _automataMode = state.automataMode;
      _draggingNodeId = null;
      _draggingLineId = null;
      _lineSourceNodeId = null;
    });
    _refreshSimulation();
  }

  String? _importFromDsl(String src) {
    try {
      _applyGraphState(DslCodec.importFromDsl(src));
      return null;
    } catch (e) {
      return 'Parse error: $e';
    }
  }

  String? _importFromSvg(String svg) {
    try {
      _applyGraphState(DslCodec.importFromSvg(svg));
      return null;
    } catch (e) {
      return 'SVG import failed: $e';
    }
  }

  void _showExportDialog() {
    showExportDialog(
  context,
  dsl: _exportToDsl(),
  savedExportCount: _savedExports.length,
  nodes: _nodes,
  lines: _lines,
  startArrow: _startArrow,
  graphState: _graphState,
  onSave: (name, dsl) {
        setState(() {
          _savedExports.insert(0, SavedExport(name: name, dsl: dsl));
        });
        _schedulePersist();
      },
    );
  }

  void _showImportDialog() {
    showImportDialog(
      context,
      onImport: (text, {required bool isSvg}) =>
          isSvg ? _importFromSvg(text) : _importFromDsl(text),
    );
  }

  /// Called by [RegexPanel] when the user converts a regex to NFA or DFA.
  /// The resulting graph is loaded onto the canvas; the mode is switched to
  /// NDFA so the standard NFA/DFA simulator drives it.
  void _onRegexConvert(RegexConversionResult result, bool isDfa) {
    final nextCounter = result.nodes.length;
    final lineCount = result.lines.length;
    // Remap node/line counters to avoid collisions with any existing content.
    final state = GraphState(
      nodes: result.nodes,
      lines: result.lines,
      startArrow: result.startArrow,
      nodeCounter: nextCounter,
      lineCounter: lineCount,
      automataMode: AutomataMode.ndfa,   // always simulate as NDFA/DFA
    );
    _applyGraphState(state);
    // Keep the regex panel open and stay in regex mode so the user can
    // tweak the expression and re-convert without reopening the panel.
    setState(() {
      _automataMode = AutomataMode.regex;
      _showRegexPanel = true;
    });
    _schedulePersist();
  }

  void _showEquivalenceDialog() {
    showEquivalenceDialog(
      context,
      initialDsl: _exportToDsl(),
    );
  }

  /// Opens the NFA/DFA → Regex dialog.  The user can optionally load the
  /// derived expression directly into the Regex Panel.
  void _showFaToRegexDialog() {
    showFaToRegexDialog(
      context,
      nodes: _nodes,
      lines: _lines,
      startArrow: _startArrow,
      onLoadIntoRegexPanel: (regex) {
        setState(() {
          _automataMode = AutomataMode.regex;
          _showRegexPanel = true;
          _regexPanelInitialText = regex;
        });
        _schedulePersist();
      },
    );
  }

  void _setLineMode(bool value) {
    setState(() {
      _lineMode = value;
    });
  }


  /// Inserts a black-box node onto the canvas backed by [save]'s DSL.
  ///
  /// The node is placed at a default position offset so it does not stack on
  /// top of existing nodes.  The canvas is NOT replaced — the new node is
  /// added alongside whatever is already there.
  void _insertAsBlackBoxNode(SavedExport save) {
    setState(() {
      final id = _nextId('n');

      // Place the node in a sensible default position, offset from existing
      // nodes so it does not land exactly on top of them.
      Offset position = const Offset(300, 300);
      if (_nodes.isNotEmpty) {
        final last = _nodes.values.last;
        position = last.position + const Offset(120, 0);
      }

      final node = NodeData(id: id, position: position);
      node.label = save.name;
      node.isBlackBox = true;
      node.blackBoxDsl = save.dsl;

      _nodes[id] = node;
    });
    _schedulePersist();
  }

  /// Opens a dialog letting the user view/edit the inner machine (DSL) and
  /// description that a black-box node runs against the tape(s) it touches.
  /// Tape routing is now encoded directly in the outgoing line labels
  /// (RWD triples per tape, e.g. aXRa1R), so there is no separate
  /// tape-routing dialog — only the DSL editor is needed here.
  Future<void> _showBlackBoxEditDialog(NodeData node) async {
    final changed = await BlackBoxEditDialog.show(
      context,
      node: node,
    );
    if (changed == true) {
      setState(() {
        _refreshSimulation();
      });
      _schedulePersist();
    }
  }

  void _showExportHistory() {
    showExportHistoryDialog(
      context,
      savedExports: _savedExports,
      onImportDsl: _importFromDsl,
      onInsertBlackBox: _insertAsBlackBoxNode,
      onListChanged: () {
        setState(() {});
        _schedulePersist();
      },
    );
  }


  void _onKeyEvent(KeyEvent event) {
    final isShift =
        event.logicalKey == LogicalKeyboardKey.shiftLeft || event.logicalKey == LogicalKeyboardKey.shiftRight;

    if (!isShift) return;

    if (event is KeyDownEvent) {
      setState(() {
        _lineMode = !_lineMode;
        _draggingLineId = null;
        _draggingNodeId = null;

        _cancelRubberBand();
      });
    }
  }

  NodeData? _nodeAt(Offset point) {
    for (final node in _nodes.values) {
      if (node.containsPoint(point)) {
        return node;
      }
    }

    return null;
  }

  LineData? _lineAt(Offset point) {
    for (final line in _lines.values) {
      final nodeA = _nodes[line.nodeAId];
      final nodeB = _nodes[line.nodeBId];

      if (nodeA == null || nodeB == null) continue;

      if (line.containsPoint(point, nodeA.center, nodeB.center)) {
        return line;
      }
    }

    return null;
  }

  bool _hitStartArrow(Offset point) {
    if (_startArrow == null) return false;

    final node = _nodes[_startArrow!.nodeId];

    if (node == null) return false;

    var dir = _startArrow!.direction();

    // Default top-left
    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    const double radius = 50;

    final end = Offset(node.center.dx + dir.dx * radius, node.center.dy + dir.dy * radius);

    final start = Offset(end.dx + dir.dx * _startArrow!.length, end.dy + dir.dy * _startArrow!.length);

    // Large tap target around the tail tip
    if ((point - start).distance < 44) return true;

    final line = end - start;

    final lenSq = line.dx * line.dx + line.dy * line.dy;

    if (lenSq == 0) return false;

    double t = ((point.dx - start.dx) * line.dx + (point.dy - start.dy) * line.dy) / lenSq;

    t = t.clamp(0.0, 1.0);

    final projection = Offset(start.dx + line.dx * t, start.dy + line.dy * t);

    final distance = (point - projection).distance;

    return distance < 44;
  }

  bool _isPointerOverSimulatorPanel(Offset globalPosition) {
    if (!_showSimulator) return false;

    final panelBox =
        _simulatorPanelBoundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (panelBox == null || !panelBox.hasSize) return false;

    final local = panelBox.globalToLocal(globalPosition);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx < panelBox.size.width &&
        local.dy < panelBox.size.height;
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (_lineMode) return;
    if (_isPointerOverSimulatorPanel(details.globalPosition)) return;

    final clickedNode = _nodeAt(details.localPosition);

    if (clickedNode != null) return;

    setState(() {
      final pos = details.localPosition - const Offset(50, 50);

      final id = _nextId('n');

      _nodes[id] = NodeData(id: id, position: pos);
    });
    _schedulePersist();
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;

    _draggingNodeId = null;
    _draggingLineId = null;
    _isPanningCanvas = false;

    if (_deleteMode) {
      final node = _nodeAt(pos);

      if (node != null) {
        setState(() {
          _deleteNode(node.id);
        });
        return;
      }

      final line = _lineAt(pos);

      if (line != null) {
        setState(() {
          _deleteLine(line.id);
        });
        return;
      }

      if (_hitStartArrowSimple(pos)) {
        setState(() {
          _startArrow = null;
        });
        _refreshSimulation();
        return;
      }

      return;
    }

    final node = _nodeAt(pos);

    if (node != null) {
      if (_lineMode) {
        if (_canStartLineFrom(node.id)) {
          _lineSourceNodeId = node.id;
        }
      } else {
        _draggingNodeId = node.id;
      }
    } else {
      if (_hitStartArrow(pos)) {
        _draggingStartArrow = true;
        return;
      }

      final line = _lineAt(pos);

      if (line != null) {
        _draggingLineId = line.id;
      } else if (!_lineMode) {
        // Nothing hit — pan the canvas
        _isPanningCanvas = true;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isPanningCanvas) {
      setState(() {
        for (final node in _nodes.values) {
          node.position = node.position + details.delta;
        }
      });
      return;
    }

    if (_draggingNodeId != null) {
      setState(() {
        final node = _nodes[_draggingNodeId!]!;

        node.position = node.position + details.delta;
      });
    } else if (_draggingStartArrow && _startArrow != null) {
      setState(() {
        final node = _nodes[_startArrow!.nodeId]!;

        final center = node.center;

        final mouse = details.localPosition;

        final dir = Offset(mouse.dx - center.dx, mouse.dy - center.dy);

        final dist = dir.distance;

        if (dist > 10) {
          _startArrow!.offset = Offset(dir.dx / dist, dir.dy / dist);

          _startArrow!.length = max(40, dist - 50);
        }
      });
    } else if (_draggingLineId != null) {
      setState(() {
        final line = _lines[_draggingLineId!]!;

        final nodeA = _nodes[line.nodeAId]!;
        final nodeB = _nodes[line.nodeBId]!;

        if (line.nodeAId == line.nodeBId) {
          final center = nodeA.center;

          final mouse = _lastPanPosition ?? center;

          final previous = mouse - details.delta;

          final oldAngle = atan2(previous.dy - center.dy, previous.dx - center.dx);

          final newAngle = atan2(mouse.dy - center.dy, mouse.dx - center.dx);

          line.selfLoopAngle += newAngle - oldAngle;

          return;
        }

        final dx = nodeB.center.dx - nodeA.center.dx;
        final dy = nodeB.center.dy - nodeA.center.dy;

        final length = sqrt(dx * dx + dy * dy);

        if (length != 0) {
          final perpDx = dy / length;
          final perpDy = -dx / length;

          line.perpendicularPart += details.delta.dx * perpDx + details.delta.dy * perpDy;
        }
      });
    }
    _refreshSimulation();
  }

  void _onPanEnd(DragEndDetails details) {
    if (_lineMode && _lineSourceNodeId != null) {
      final destNode = _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;

      if (destNode != null) {
        final srcId = _lineSourceNodeId!;
        final destId = destNode.id;

        if (!_canStartLineFrom(srcId)) {
          _cancelRubberBand();
          _lineSourceNodeId = null;
          return;
        }

        final alreadyExists = _lines.values.any((line) => line.nodeAId == srcId && line.nodeBId == destId);

        if (!alreadyExists) {
          setState(() {
            final id = _nextId('l');

            final line = LineData(id: id, nodeAId: srcId, nodeBId: destId);

            _lines[id] = line;

            _nodes[srcId]?.connectedLineIds.add(id);
            _nodes[destId]?.connectedLineIds.add(id);
          });
        }
      } else {
        _cancelRubberBand();
      }

      _lineSourceNodeId = null;
    }

    _draggingNodeId = null;
    _draggingLineId = null;
    _draggingStartArrow = false;
    _isPanningCanvas = false;

    _lastPanPosition = null;
    _cancelRubberBand();
    _refreshSimulation();
  }

  void _onPanUpdateWithTracking(DragUpdateDetails details) {
    _lastPanPosition = details.localPosition;

    _onPanUpdate(details);

    if (_lineSourceNodeId != null && _lineMode) {
      setState(() {
        _rubberBandEnd = details.localPosition;
      });
    } else {
      if (_lineSourceNodeId != null || _rubberBandEnd != null) {
        setState(_cancelRubberBand);
      }
    }
  }

  void _setShowHelpOverlay(bool value) {
    setState(() => _showHelpOverlay = value);
    _schedulePersist();
  }

  void _setShowSimulator(bool value) {
    setState(() => _showSimulator = value);
    _schedulePersist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      drawer: AutomataDrawer(
        showHelpOverlay: _showHelpOverlay,
        showSimulator: _showSimulator,
        automataMode: _automataMode,
        isGuest: widget.isGuest,
        accountLabel: widget.isGuest
            ? 'Guest (local only)'
            : widget.userEmail,
        onShowHelpChanged: _setShowHelpOverlay,
        onShowSimulatorChanged: _setShowSimulator,
        onModeChanged: (mode) {
          setState(() {
            _automataMode = mode;
            _activeTapeIndex = 0; // reset tape selection on mode switch
            _simRebuild();
            if (mode == AutomataMode.pda) {
              _pdaSimulator.step = _simulator.step;
            } else if (mode == AutomataMode.tm) {
              _tmSimulator.step = _simulator.step.clamp(-1, _tmSimulator.maxStep);
            }
            // Auto-show the regex panel when entering regex mode,
            // auto-hide it when leaving.
            _showRegexPanel = (mode == AutomataMode.regex);
          });
          _schedulePersist();
        },
        onBatchSimulator: _openBatchSimulatorDialog,
        onEquivalenceChecker: _showEquivalenceDialog,
        onFaToRegex: _showFaToRegexDialog,
        onExport: _showExportDialog,
        onImport: _showImportDialog,
        onExportHistory: _showExportHistory,
        onReset: _reset,
        onSignOut: widget.onSignOut,
        onGoToGame: widget.onGoToGame,
      ),

      appBar: AppBar(
        title: const Text('Automata Designer'),
        actions: [
          if (widget.isGuest)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('Guest'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),

      floatingActionButton: Builder(
        builder: (context) {
          final theme = context.watch<AppThemeNotifier>();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PaletteFab(
                heroTag: 'startArrow',
                tooltip: 'Set start state',
                icon: Icons.play_arrow,
                active: _placingStartArrow,
                activeColor: const Color(0xFFFF6D00),
                onPressed: () =>
                    setState(() => _placingStartArrow = !_placingStartArrow),
              ),
              const SizedBox(height: 10),
              PaletteFab(
                heroTag: 'deleteMode',
                tooltip: 'Delete mode',
                icon: Icons.delete_outline,
                active: _deleteMode,
                activeColor: Theme.of(context).colorScheme.error,
                onPressed: () => setState(() {
                  _deleteMode = !_deleteMode;
                  if (_deleteMode) {
                    _lineMode = false;
                    _placingStartArrow = false;
                  }
                }),
              ),
              const SizedBox(height: 10),
              PaletteFab(
                heroTag: 'lineMode',
                tooltip: _lineMode ? 'Exit line mode' : 'Enter line mode',
                icon: _lineMode ? Icons.timeline : Icons.add_link,
                active: _lineMode,
                activeColor: theme.accent,
                onPressed: () => _setLineMode(!_lineMode),
              ),
              const SizedBox(height: 10),
              PaletteFab(
                heroTag: 'toggleSim',
                tooltip: _showSimulator ? 'Hide simulator' : 'Show simulator',
                icon: Icons.science,
                active: _showSimulator,
                activeColor: theme.accent,
                small: true,
                onPressed: () => _setShowSimulator(!_showSimulator),
              ),
            ],
          );
        },
      ),

      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,

                onTapDown: (details) {
            _lastTapPosition = details.localPosition;

            if (_placingStartArrow) {
              final tappedNode = _nodeAt(details.localPosition);

              if (tappedNode != null) {
                setState(() {
                  _startArrow = StartArrowData(nodeId: tappedNode.id);

                  _refreshSimulation();

                  _placingStartArrow = false;
                });
              }
            }
          },

          onTap: () {
            if (_lastTapPosition == null || _nodeAt(_lastTapPosition!) == null) {
              _focusNode.requestFocus();
            }

            _lastTapPosition = null;
          },

          onDoubleTapDown: _onDoubleTapDown,

          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdateWithTracking,
          onPanEnd: _onPanEnd,

          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_startArrow != null && _nodes[_startArrow!.nodeId] != null)
                Positioned.fill(
                  child: StartArrowWidget(
                    data: _startArrow!,
                    nodeCenter: _nodes[_startArrow!.nodeId]!.center,

                    deleteMode: _deleteMode,
                    highlighted: _simulator.step == -1 && _simulator.tokens.isNotEmpty,

                    onDelete: () {
                      setState(() {
                        _startArrow = null;
                      });
                    },
                  ),
                ),

              if (_lineSourceNodeId != null && _rubberBandEnd != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: RubberBandPainter(start: _nodes[_lineSourceNodeId!]!.center, end: _rubberBandEnd!, color: Colors.lightBlueAccent),
                    ),
                  ),
                ),

              ..._lines.values.map((line) {
                final nodeA = _nodes[line.nodeAId];
                final nodeB = _nodes[line.nodeBId];

                if (nodeA == null || nodeB == null) {
                  return const SizedBox.shrink();
                }

                return KeyedSubtree(
                  key: ValueKey(line.id),
                  child: Positioned.fill(
                    child: LineWidget(
                      data: line,
                      centerA: nodeA.center,
                      centerB: nodeB.center,
                      deleteMode: _deleteMode,
                      highlighted: _simActiveLines.contains(line.id),
                      onLabelChanged: (text) {
                        setState(() {
                          line.label = text;
                          _refreshSimulation();
                        });
                      },
                    ),
                  ),
                );
              }),

              ..._nodes.values.map(
                (node) => Node(
                  key: ValueKey(node.id),
                  data: node,
                  lineMode: _lineMode,
                  deleteMode: _deleteMode,
                  highlighted: _simActiveNodes.contains(node.id),

                  isLabelTaken: _isLabelTaken,

                  onLabelChanged: (text) {
                    setState(() {
                      node.label = text;
                      _refreshSimulation();
                    });
                  },

                  onLineModeSelect: () {
                    if (_lineMode && _canStartLineFrom(node.id)) {
                      _lineSourceNodeId = node.id;
                    }
                  },

                  onDoubleTap: () {
                    if (!node.canToggleNormalAccept) return;
                    setState(() {
                      node.isAccept = !node.isAccept;
                    });
                    _refreshSimulation();
                  },

                  onDelete: () {
                    setState(() {
                      _deleteNode(node.id);
                    });
                  },

                  onBlackBoxEdit: node.isBlackBox
                      ? () => _showBlackBoxEditDialog(node)
                      : null,
                ),
              ),
            ],
          ),
        ),
            ),
            if (_showHelpOverlay) const HelpOverlay(),
            if (_showSimulator)
              StringSimulatorPanel(
                boundaryKey: _simulatorPanelBoundaryKey,
                simulator: _simulator,
                pdaSimulator: _automataMode == AutomataMode.pda ? _pdaSimulator : null,
                tmSimulator: _automataMode == AutomataMode.tm ? _tmSimulator : null,
                controller: _simController,
                nodes: _nodes,
                onClose: () => _setShowSimulator(false),
                onTextChanged: () {
                  setState(() {
                    _simRebuild();
                    _simulator.step = -1;
                    _pdaSimulator.step = -1;          // ← NEW
                  });
                  _schedulePersist();
                },
                onStepChanged: () {
                  _pdaSimulator.step = _simulator.step; // keep in sync
                  setState(() {});
                  _schedulePersist();
                },
                tapeNames: _automataMode == AutomataMode.tm
                    ? List.generate(
                        _tmSimulator.tapeCount,
                        (i) => 'Tape ${i + 1}',
                      )
                    : const [],
                activeTapeIndex: _activeTapeIndex,
                additionalTapeControllers: _automataMode == AutomataMode.tm
                    ? _tapeControllers
                    : const [],
                onTapeInputChanged: () {
                  setState(() => _simRebuild());
                  _schedulePersist();
                },
                onTapeSelected: (i) => setState(() => _activeTapeIndex = i),
                onTapeAdded: _automataMode == AutomataMode.tm
                    ? () {
                        setState(() {
                          _tmSimulator.tapeCount += 1;
                          _activeTapeIndex = _tmSimulator.tapeCount - 1;
                          // _simRebuild will grow _tapeControllers to match.
                        });
                        _simRebuild();
                        _schedulePersist();
                      }
                    : null,
                onTapeRemoved: _automataMode == AutomataMode.tm &&
                        _tmSimulator.tapeCount > 1
                    ? (int i) {
                        setState(() {
                          _tmSimulator.tapeCount =
                              (_tmSimulator.tapeCount - 1).clamp(1, 99);
                          if (_activeTapeIndex >= _tmSimulator.tapeCount) {
                            _activeTapeIndex = _tmSimulator.tapeCount - 1;
                          }
                        });
                        _simRebuild();
                        _schedulePersist();
                      }
                    : null,
              ),

            // ── PDA Stack Panel ────────────────────────────────────────
            if (_showSimulator && _automataMode == AutomataMode.pda)
              PdaStackPanel(simulator: _pdaSimulator, nodes: _nodes),

            // ── TM Config Panel ───────────────────────────────────────
            if (_showSimulator && _automataMode == AutomataMode.tm)
              TmConfigPanel(simulator: _tmSimulator, nodes: _nodes),

            // ── Regex Panel ───────────────────────────────────────────
            if (_automataMode == AutomataMode.regex && _showRegexPanel)
              RegexPanel(
                onConvert: _onRegexConvert,
                onClose: () => setState(() => _showRegexPanel = false),
                initialText: _regexPanelInitialText,
                onInitialTextConsumed: () =>
                    setState(() => _regexPanelInitialText = null),
              ),

            // ── Regex show-panel FAB (when panel is closed) ───────────
            if (_automataMode == AutomataMode.regex && !_showRegexPanel)
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 16),
                  child: FloatingActionButton.extended(
                    heroTag: 'regexOpen',
                    onPressed: () => setState(() => _showRegexPanel = true),
                    icon: const Icon(Icons.text_fields),
                    label: const Text('Open Regex'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}