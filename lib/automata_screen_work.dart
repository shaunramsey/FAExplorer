import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'widgets/automata_drawer.dart';
import 'widgets/help_overlay.dart';
import 'widgets/rubber_band_painter.dart';
import 'widgets/string_simulator_panel.dart';
import 'widgets/pda_stack_panel.dart';
import 'tm_simulator.dart';
import 'widgets/tm_config_panel.dart';

class AutomataScreen extends StatefulWidget {
  const AutomataScreen({
    super.key,
    required this.sessionStore,
    this.isGuest = false,
    this.userEmail,
    this.onSignOut,
  });

  final AutomataSessionStore sessionStore;
  final bool isGuest;
  final String? userEmail;
  final Future<void> Function()? onSignOut;

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
  AutomataMode _automataMode = AutomataMode.ndfa;          // ← NEW

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
    if (_automataMode == AutomataMode.tm) {
      return _tmSimulator.activeNodes;
    }
    if (_automataMode == AutomataMode.pda) {
      // Use _simulator.step directly so we never lag one frame behind the
      // onStepChanged callback that would normally sync _pdaSimulator.step.
      final idx = _simulator.step + 1;
      if (idx < 0 || idx >= _pdaSimulator.steps.length) return {};
      return _pdaSimulator.steps[idx].activeNodeIds;
    }
    if (_isAtAcceptedFinalStep) {
      return _simulator.states.expand((s) => s).toSet();
    }
    return _simulator.activeNodes;
  }

  Set<String> get _simActiveLines {
    if (_automataMode == AutomataMode.tm) {
      return _tmSimulator.activeLines;
    }
    if (_automataMode == AutomataMode.pda) {
      // Use _simulator.step directly — same reason as above.
      if (_simulator.step < 0) return {};
      final idx = _simulator.step + 1;
      if (idx < 0 || idx >= _pdaSimulator.steps.length) return {};
      return _pdaSimulator.steps[idx].usedLineIds;
    }
    if (_isAtAcceptedFinalStep) {
      return _simulator.usedLines.expand((s) => s).toSet();
    }
    return _simulator.activeLines;
  }

  void _refreshSimulation() {
    if (_simController.text.isEmpty && _simulator.states.isEmpty) {
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
        _automataMode =
            state.pdaMode ? AutomataMode.pda : AutomataMode.ndfa;
        _normalizeReversePairs();
      } catch (_) {
        // Ignore corrupt saved graphs.
      }
    }

    _savedExports.addAll(snapshot.savedExports);
    _showSimulator = snapshot.showSimulator;
    _showHelpOverlay = snapshot.showHelpOverlay;
    _simController.text = snapshot.simInput;
    _simulator.step = snapshot.simStep;

    if (_simController.text.isNotEmpty || _startArrow != null) {
      _simRebuild();
    }

    _persistenceReady = true;

    if (mounted) {
      setState(() => _loadingPrefs = false);
    }
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
    _tmSimulator.rebuild(_simController.text, startArrow: _startArrow);
    if (_tmSimulator.step > _tmSimulator.maxStep) {
      _tmSimulator.step = _tmSimulator.maxStep;
    }
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


  /// Ensures every line with a negative perpendicularPart is flipped positive.
  /// Because each line's perpendicular normal is derived from its own A→B
  /// direction (flipped for a reverse line), +55 on both lines in a pair
  /// naturally curves them to opposite sides — a negative value is never needed.
  void _normalizeReversePairs() {
    for (final line in _lines.values) {
      if (line.perpendicularPart < 0) {
        line.perpendicularPart = line.perpendicularPart.abs();
      }
    }
  }

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
      _automataMode =
          state.pdaMode ? AutomataMode.pda : AutomataMode.ndfa;
      _draggingNodeId = null;
      _draggingLineId = null;
      _lineSourceNodeId = null;
      _normalizeReversePairs();
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

  void _showEquivalenceDialog() {
    showEquivalenceDialog(
      context,
      initialDsl: _exportToDsl(),
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
      final nodeA = _nodes[line.nodeAId]!;
      final nodeB = _nodes[line.nodeBId]!;

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
    // Pure canvas pan doesn't change the graph — skip refresh so the
    // simulator step/state is preserved while the user scrolls.
    if (!_isPanningCanvas) {
      _refreshSimulation();
    }
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

            // If a line already exists in the opposite direction (destId → srcId),
            // both lines get +55. Each line's perpendicular normal is computed
            // from its own A→B direction, which is flipped for the reverse line,
            // so +55 on both naturally curves them to opposite sides of the chord.
            const double defaultPerp = 20.0;
            final _reverseMatches = _lines.values
                .where((l) => l.nodeAId == destId && l.nodeBId == srcId)
                .toList();
            final reverseLine = _reverseMatches.isNotEmpty ? _reverseMatches.first : null;

            final line = LineData(
              id: id,
              nodeAId: srcId,
              nodeBId: destId,
              perpendicularPart: reverseLine != null ? defaultPerp : 0,
            );

            if (reverseLine != null) {
              reverseLine.perpendicularPart = defaultPerp;
            }

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

    // Capture whether we were panning before clearing the flag.
    final wasPanningCanvas = _isPanningCanvas;
    _isPanningCanvas = false;

    _lastPanPosition = null;
    _rubberBandEnd = null;
    _cancelRubberBand();
    _lineSourceNodeId = null;
    _rubberBandEnd = null;
    // Don't rebuild the simulation if we were only panning the canvas —
    // nothing in the graph changed, so the current step should be preserved.
    if (!wasPanningCanvas) {
      _refreshSimulation();
    }
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
    _simRebuild();

    if (_automataMode == AutomataMode.pda) {
      _pdaSimulator.step = _simulator.step;
    }
  });

  _schedulePersist();
},
        onBatchSimulator: _openBatchSimulatorDialog,
        onEquivalenceChecker: _showEquivalenceDialog,
        onExport: _showExportDialog,
        onImport: _showImportDialog,
        onExportHistory: _showExportHistory,
        onReset: _reset,
        onSignOut: widget.onSignOut,
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

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'startArrow',
            tooltip: 'Set start state',
            backgroundColor: _placingStartArrow ? Colors.orange : null,
            onPressed: () {
              setState(() {
                _placingStartArrow = !_placingStartArrow;
              });
            },
            child: const Icon(Icons.play_arrow),
          ),

          const SizedBox(height: 12),

          FloatingActionButton(
            heroTag: 'deleteMode',
            tooltip: 'Delete mode',
            backgroundColor: _deleteMode ? Colors.red : null,
            onPressed: () {
              setState(() {
                _deleteMode = !_deleteMode;

                if (_deleteMode) {
                  _lineMode = false;
                  _placingStartArrow = false;
                }
              });
            },
            child: const Icon(Icons.delete),
          ),

          const SizedBox(height: 12),

          FloatingActionButton(
            heroTag: 'lineMode',
            tooltip: _lineMode ? 'Exit line mode' : 'Enter line mode',
            backgroundColor: _lineMode ? Colors.lightBlueAccent : null,
            onPressed: () => _setLineMode(!_lineMode),
            child: Icon(_lineMode ? Icons.timeline : Icons.add_link),
          ),

          const SizedBox(height: 12),

          FloatingActionButton.small(
            heroTag: 'toggleSim',
            tooltip: _showSimulator ? 'Hide simulator' : 'Show simulator',
            backgroundColor: _showSimulator ? Colors.purple.shade100 : null,
            onPressed: () => _setShowSimulator(!_showSimulator),
            child: const Icon(Icons.science, size: 20),
          ),
        ],
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
                      painter: RubberBandPainter(start: _nodes[_lineSourceNodeId!]!.center, end: _rubberBandEnd!, color:Colors.lightBlueAccent),
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
                pdaSimulator:
    _automataMode == AutomataMode.pda
        ? _pdaSimulator
        : null,
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
                  setState(() {
                    _pdaSimulator.step = _simulator.step; // sync inside setState
                  });
                  _schedulePersist();
                },
              ),

            // ── PDA Stack Panel ────────────────────────────────────────
            if (_showSimulator &&
    _automataMode == AutomataMode.pda)
              PdaStackPanel(simulator: _pdaSimulator, nodes: _nodes),
          ],
        ),
      ),
    );
  }
}