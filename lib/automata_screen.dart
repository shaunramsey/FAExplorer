import 'dart:async';
// sqrt/atan2/max — used for perpendicular-offset math when dragging a
// transition's curve and for self-loop angle tracking.
import 'dart:math';

import 'package:flutter/material.dart';
// LogicalKeyboardKey / KeyEvent — used to detect the Shift key toggling
// line (link) mode via the physical keyboard, in addition to the FAB.
import 'package:flutter/services.dart';
// AppThemeNotifier is read via context.watch inside the FAB Builder below.
import 'package:provider/provider.dart';
// NodeData, LineData, StartArrowData, GraphState, AutomataMode, DslCodec —
// the whole in-memory graph model and its DSL import/export live here.
import 'models.dart';
// AutomataSessionStore / PersistedSnapshot / SavedExport — persistence
// layer this screen saves/restores its state through.
import 'persistence.dart';
// LineWidget, Node, StartArrowWidget, RubberBandPainter — the visual
// building blocks this screen arranges on the canvas.
import 'widgets/graph_widgets.dart';
// Export/import dialogs and the DSL round-trip helpers they call into.
import 'import_export.dart';
// AutomataSimulator / PdaSimulator / TmSimulator / SimResult — the three
// per-mode simulation engines this screen drives in parallel.
import 'simulator.dart';
import 'dialogs/automata_dialogs.dart';
import 'dialogs/batch_simulator_dialog.dart';
import 'dialogs/equivalence_dialog.dart';
import 'widgets/automata_drawer.dart';
import 'widgets/app_theme.dart';
import 'widgets/help_overlay.dart';
import 'widgets/black_box_input_dialog.dart';
// StringSimulatorPanel, PdaStackPanel, TmConfigPanel, RegexPanel — the
// floating side panels shown/hidden depending on _automataMode.
import 'widgets/sim_panels.dart';

/// Top-level screen for the automaton canvas editor: owns the entire graph
/// (nodes/lines/start-arrow), the three simulation engines (NFA/DFA, PDA,
/// TM), persistence, and every gesture handler for building/editing the
/// diagram. Everything else in this file (dialogs, panels, painters) is a
/// child of or callback from this one widget.
class AutomataScreen extends StatefulWidget {
  const AutomataScreen({
    super.key,
    required this.sessionStore,
    this.isGuest = false,
    this.userEmail,
    this.onSignOut,
    this.onGoToGame,
    this.onGoToStudy,
    this.onGoToMenu,
  });

  // Where this screen's graph/simulator/UI state is persisted to and
  // restored from — see _loadPreferences/_persistNow below.
  final AutomataSessionStore sessionStore;
  // Guest accounts get a "Guest (local only)" label in the drawer instead
  // of an email, and presumably skip cloud sync inside sessionStore itself.
  final bool isGuest;
  final String? userEmail;
  final Future<void> Function()? onSignOut;
  // Navigation hooks up to whatever hosts this screen (e.g. a bottom-nav
  // or menu shell); not read by name anywhere else in this file besides
  // being passed to the drawer/app bar below.
  final VoidCallback? onGoToGame;
  final VoidCallback? onGoToStudy;
  final VoidCallback? onGoToMenu;

  @override
  State<AutomataScreen> createState() => _AutomataScreenState();
}

class _AutomataScreenState extends State<AutomataScreen> with WidgetsBindingObserver {
  // The entire graph model: keyed by NodeData.id / LineData.id so lookups
  // during hit-testing and dragging are O(1) rather than list scans.
  final Map<String, NodeData> _nodes = {};
  final Map<String, LineData> _lines = {};

  // ── Toolbar / interaction modes ───────────────────────────────────────
  // These are mutually-adjusted (see the delete-mode FAB handler below,
  // which turns line mode and start-arrow placement off when delete mode
  // is switched on) so only one "editing gesture" interpretation is active
  // on the canvas at a time.
  bool _lineMode = false;
  bool _placingStartArrow = false;
  bool _deleteMode = false;

  bool _showHelpOverlay = false;
  bool _showSimulator = true;
  bool _showRegexPanel = false;   // ← shown automatically when mode == regex
  String? _regexPanelInitialText; // ← pre-filled when coming from FA→Regex
  AutomataMode _automataMode = AutomataMode.ndfa;

  // The free-floating start-state arrow; null until the user places one.
  StartArrowData? _startArrow;

  bool _draggingStartArrow = false;

  // Which node/line/(implicit start-node) is currently being dragged, if
  // any — mutually exclusive, set in _onPanStart and cleared in _onPanEnd.
  String? _draggingNodeId;
  String? _draggingLineId;
  // The node a link-mode drag started from, while the user is still
  // dragging out the rubber-band toward a destination node.
  String? _lineSourceNodeId;

  Offset? _lastPanPosition;
  Offset? _lastTapPosition;
  // Live pointer position while dragging out a new transition in line
  // mode; feeds RubberBandPainter's preview line. Null when not
  // link-dragging.
  Offset? _rubberBandEnd;

  // Canvas panning
  // True only when a pan gesture started on empty canvas (missed every
  // node/line/start-arrow) — see _onPanStart's final `else` branch.
  bool _isPanningCanvas = false;

  // Monotonically increasing counters used to mint new node/line IDs
  // ("n0", "n1", ... / "l0", "l1", ...) — see _nextId. Never decremented on
  // delete, so IDs are never reused within a session.
  int _nodeCounter = 0;
  int _lineCounter = 0;

  // Captures keyboard focus for the Shift-key line-mode toggle (see
  // _onKeyEvent) and is also the thing "de-focused" when tapping empty
  // canvas away from any text field.
  final FocusNode _focusNode = FocusNode();

  // In-session history of exports the user has explicitly saved (via the
  // export dialog) — separate from persistence's autosave of the live
  // graph; these are named snapshots the user can reload or insert as
  // black-box nodes later.
  final List<SavedExport> _savedExports = [];

  // One simulator engine per automaton kind, all kept alive and rebuilt in
  // parallel (see _simRebuild) regardless of which _automataMode is
  // currently active, so switching modes doesn't lose simulation state or
  // require a rebuild-from-scratch.
  late final AutomataSimulator _simulator;
  late final PdaSimulator _pdaSimulator;     // ← NEW
  late final TmSimulator _tmSimulator;       // ← TM
  // Used to hit-test whether a pointer/tap position falls inside the
  // floating string-simulator panel, so canvas gestures (panning, node
  // placement) don't fire through it.
  final GlobalKey _simulatorPanelBoundaryKey = GlobalKey();

  /// Which tape tab is active in the string-simulator panel (0-based).
  /// Only meaningful in TM mode with more than one tape.
  int _activeTapeIndex = 0;

  /// Input strings for tapes 2, 3, … (index 0 = tape 2, index 1 = tape 3, …).
  /// Each controller holds what the user typed for that tape.
  /// The list grows/shrinks with [_tmSimulator.tapeCount].
  final List<TextEditingController> _tapeControllers = [];
  // Debounce timer for autosave — see _schedulePersist, which restarts
  // this on every edit so rapid successive edits collapse into a single
  // save 400ms after the user stops.
  Timer? _persistTimer;
  // Guards against autosaving before the initial load has completed
  // (which would otherwise overwrite the just-loaded snapshot with a
  // still-empty in-memory graph).
  bool _persistenceReady = false;
  bool _loadingPrefs = true;

  /// Opens the "run many inputs at once" dialog, wired to whichever
  /// simulator matches the current mode (null for the others so the
  /// dialog knows only one is relevant).
  Future<void> _openBatchSimulatorDialog() => showBatchSimulatorDialog(
        context,
        simulator: _simulator,
        pdaSimulator: _automataMode == AutomataMode.pda ? _pdaSimulator : null,
        tmSimulator: _automataMode == AutomataMode.tm ? _tmSimulator : null,
        startArrow: _startArrow,
        currentInput: _simController.text,
        additionalTapeInputs: _tapeControllers.map((c) => c.text).toList(),
      );

  /// Bundles the current graph + counters + mode into an immutable
  /// snapshot value used everywhere the graph needs to be passed as a
  /// unit: export, DSL round-tripping, hit-testing (_graphState.nodeAt /
  /// lineAt / hitStartArrow below all delegate to this).
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
  // Backs the "type a string to simulate" input field in the simulator
  // panel; also the single source of truth for "what input string" every
  // simulator (_simulator/_pdaSimulator/_tmSimulator) is run against.
  final TextEditingController _simController = TextEditingController();

  /// Whether we are at the final recorded step (the round where the
  /// computation actually halted — see [AutomataSimulator.maxStep], which
  /// can be reached before every input token is consumed when a halt-accept
  /// state fires mid-string) and the result is accepted.
  bool get _isAtAcceptedFinalStep {
    if (_simulator.tokens.isEmpty) return false;
    if (_simulator.step != _simulator.maxStep) return false;
    return _simulator.finalResult() == SimResult.accept;
  }

  /// Which node IDs / line IDs should render as "highlighted" on the
  /// canvas right now, for whichever simulator matches [_automataMode].
  /// A Dart record (not a class) since it's a small, purely local return
  /// shape consumed only by the two call sites in build() below.
  ({Set<String> nodes, Set<String> lines}) get _simHighlight {
    switch (_automataMode) {
      case AutomataMode.pda:
        return (nodes: _pdaSimulator.activeNodes, lines: _pdaSimulator.activeLines);
      case AutomataMode.tm:
        return (nodes: _tmSimulator.activeNodes, lines: _tmSimulator.activeLines);
      default:
        // NFA/DFA special case: once the simulation has fully finished
        // and accepted (_isAtAcceptedFinalStep), highlight every state/
        // line that was ever touched across all branches explored, not
        // just the single "current step" set — this traces the full
        // accepting path(s) rather than just the last frontier.
        if (_isAtAcceptedFinalStep) {
          return (
            nodes: _simulator.states.expand((s) => s).toSet(),
            lines: _simulator.usedLines.expand((s) => s).toSet(),
          );
        }
        return (nodes: _simulator.activeNodes, lines: _simulator.activeLines);
    }
  }

  /// Re-runs every simulator against the current input/graph and schedules
  /// an autosave. Called after essentially every graph edit (label change,
  /// node/line add or delete, drag) so the simulator never goes stale.
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

  /// Debounced autosave trigger: (re)starts a 400ms timer, so a burst of
  /// rapid edits (e.g. dragging a node, or typing a label character by
  /// character) collapses into a single write via [_persistNow] once
  /// things settle rather than saving on every single change.
  void _schedulePersist() {
    if (!_persistenceReady) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  /// Serializes the current graph (as DSL) plus UI/session state into a
  /// [PersistedSnapshot] and writes it via [AutomataSessionStore.save].
  /// Failures are surfaced as a snackbar rather than thrown, since a save
  /// failure shouldn't crash or block continued editing.
  Future<void> _persistNow() async {
    if (!_persistenceReady) return;

    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save workspace: $e')),
        );
      }
    }
  }

  /// Runs once from [initState]: loads the last-saved snapshot, replays it
  /// into the in-memory graph/UI state, and only then flips
  /// [_persistenceReady] on — so nothing autosaves (and potentially
  /// overwrites the snapshot with an empty graph) until loading completes.
  Future<void> _loadPreferences() async {
    PersistedSnapshot snapshot;
    String? loadError;

    try {
      snapshot = await widget.sessionStore.load();
    } catch (e) {
      // Fall back to a blank/default snapshot rather than leaving the
      // screen stuck loading forever; the error is surfaced to the user
      // below once the widget is mounted.
      snapshot = const PersistedSnapshot();
      loadError = 'Could not load saved workspace. ($e)';
    }

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
      } catch (e) {
        // A corrupt/unparseable saved DSL shouldn't prevent the screen
        // from loading — just start blank and tell the user why.
        loadError = 'Could not restore saved graph. Starting with a blank canvas. ($e)';
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

    // Only bother re-running the simulators if there's something to
    // simulate (an input string typed, or a start state set) — mirrors
    // the same guard in _refreshSimulation.
    if (_simController.text.isNotEmpty || _startArrow != null) {
      _simRebuild();
      _syncSimulatorSteps();
    }

    _persistenceReady = true;

    if (mounted) {
      setState(() => _loadingPrefs = false);
      if (loadError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loadError)),
        );
      }
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

      // Multi-line labels list one transition instruction per line; scan
      // each independently.
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
          // A valid compact-shorthand label is a run of complete 3-rune
          // (read, write, direction) triples — anything else (wrong
          // length, or too short to be more than one tape) isn't this
          // format.
          if (runes.length >= 6 && runes.length % 3 == 0) {
            bool allDirsValid = true;
            final inferredTapes = runes.length ~/ 3;
            // Validate every triple's third rune is a legal direction
            // character; if even one isn't, this string isn't actually
            // compact-shorthand and shouldn't count toward the tape total.
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

  /// Propagates the NFA/DFA simulator's current step (the "master" step
  /// counter the UI's step slider drives) into the PDA and TM simulators,
  /// clamped to each one's own halting point.
  void _syncSimulatorSteps() {
    final savedStep = _simulator.step;
    // Clamp against each simulator's own maxStep (the round where its
    // computation actually halted), not tokens.length — the PDA or FA/NFA
    // computation can halt (halt-accept, or every branch dying) before every
    // token is consumed, and steps/states stop growing at that point.
    _pdaSimulator.step = savedStep.clamp(-1, _pdaSimulator.maxStep);
    _tmSimulator.step = savedStep.clamp(-1, _tmSimulator.maxStep);
  }

  /// Re-simulates the current input against all three engines and keeps
  /// the TM's tape count/tape-input controllers in sync with what the
  /// graph actually references. Called by [_refreshSimulation] and
  /// directly by several UI callbacks below when a full resimulation is
  /// needed without the "skip if nothing to simulate" guard.
  void _simRebuild() {
    _simulator.rebuild(_simController.text, startArrow: _startArrow);
    if (_simulator.step > _simulator.maxStep) {
      _simulator.step = _simulator.maxStep;
    }
    _pdaSimulator.rebuild(_simController.text, startArrow: _startArrow);
    if (_pdaSimulator.step > _pdaSimulator.maxStep) {
      _pdaSimulator.step = _pdaSimulator.maxStep;
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
    // (Tape 1's input lives in _simController, not in this list — hence
    // the -1: only tapes 2..N get their own controller here.)
    while (_tapeControllers.length < _tmSimulator.tapeCount - 1) {
      _tapeControllers.add(TextEditingController());
    }
    while (_tapeControllers.length > _tmSimulator.tapeCount - 1) {
      // Dispose controllers being dropped so their listeners/resources are
      // released rather than just orphaned.
      _tapeControllers.removeLast().dispose();
    }
    final additionalInputs = _tapeControllers.map((c) => c.text).toList();
    _tmSimulator.rebuild(
      _simController.text,
      startArrow: _startArrow,
      additionalTapeInputs: additionalInputs,
    );
    _syncSimulatorSteps();
  }

  /// Aborts an in-progress link-mode drag without creating a transition —
  /// called both when the drag ends over empty space and whenever the
  /// pointer stops being a valid rubber-band drag (see
  /// _onPanUpdateWithTracking).
  void _cancelRubberBand() {
    _lineSourceNodeId = null;
    _rubberBandEnd = null;
  }

  bool _hitStartArrow(Offset point) => _graphState.hitStartArrow(point);

  /// True if some *other* node already has this exact (trimmed) label —
  /// used both to show the duplicate-name border in [Node] and, presumably,
  /// to warn about ambiguous DSL export/import. Empty labels are never
  /// considered a duplicate (every state can be unlabeled).
  bool _isLabelTaken(String label, String currentId) {
    final normalized = label.trim();

    if (normalized.isEmpty) return false;

    return _nodes.values.any((n) => n.id != currentId && n.label.trim() == normalized);
  }

  /// Whether link-mode dragging is allowed to originate from this node —
  /// delegates to the model (e.g. false for a halt state, which can't have
  /// outgoing transitions).
  bool _canStartLineFrom(String? nodeId) {
    if (nodeId == null) return false;
    return _nodes[nodeId]?.canHaveOutgoingTransitions ?? false;
  }

  /// Mints the next unique ID for a new node ("n0", "n1", ...) or line
  /// ("l0", "l1", ...), depending on [prefix], incrementing the
  /// corresponding counter as a side effect.
  String _nextId(String prefix) {
    if (prefix == 'n') {
      return '$prefix${_nodeCounter++}';
    }

    return '$prefix${_lineCounter++}';
  }

  /// Removes a transition and detaches it from both endpoint nodes'
  /// connectedLineIds bookkeeping, then re-runs the simulation since the
  /// graph's transition function just changed.
  void _deleteLine(String lineId) {
    final line = _lines[lineId];

    if (line == null) return;

    _nodes[line.nodeAId]?.connectedLineIds.remove(lineId);

    _nodes[line.nodeBId]?.connectedLineIds.remove(lineId);

    _lines.remove(lineId);
    _refreshSimulation();
  }

  /// Removes a state and, transitively, every transition attached to it
  /// (via [_deleteLine], which also unhooks the *other* endpoint's
  /// bookkeeping — so deleting one node cleanly cleans up all its edges,
  /// not just the ones where it happens to be nodeA). Also clears the
  /// start arrow if it was pointing at this node.
  void _deleteNode(String nodeId) {
    final node = _nodes[nodeId];

    if (node == null) return;

    // toList() copies the id set first since _deleteLine mutates
    // connectedLineIds (including this node's own) while iterating.
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

    // Grab keyboard focus immediately so the Shift-key line-mode shortcut
    // works without the user having to click the canvas first.
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

    // Any edit to the input string (even ones not routed through a
    // dedicated onChanged callback below) should trigger an autosave.
    _simController.addListener(_schedulePersist);
    // Lets didChangeAppLifecycleState below flush a pending save when the
    // app is backgrounded/closed.
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    // Best-effort final save on teardown; fire-and-forget since dispose()
    // can't be async and the widget is going away regardless of the
    // outcome.
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
    // Flush any pending debounced save immediately when the app is about
    // to lose foreground/be killed — otherwise the last 400ms of edits
    // (see _schedulePersist) could be lost if the process is terminated
    // before the debounce timer fires.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _persistTimer?.cancel();
      unawaited(_persistNow());
    }
  }

  /// Wipes the entire canvas and simulator state back to a blank slate —
  /// wired to the drawer's "Reset" action. Also clears the input string,
  /// since a fresh empty graph has nothing meaningful to simulate.
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


  /// Replaces the entire live graph with [state] in one atomic setState —
  /// the common landing point for every "load a whole new graph" flow
  /// (DSL import, SVG import, regex conversion). Also clears any
  /// in-progress drag/link state, since the nodes/lines those referenced
  /// no longer exist after the swap.
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

  /// Parses [src] as DSL and applies it; returns null on success or a
  /// user-facing error string on failure (the import dialog displays
  /// whatever this returns rather than throwing).
  String? _importFromDsl(String src) {
    try {
      _applyGraphState(DslCodec.importFromDsl(src));
      return null;
    } catch (e) {
      return 'Parse error: $e';
    }
  }

  /// Same contract as [_importFromDsl] but for pasted SVG markup (e.g.
  /// exported from another automaton tool).
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
        // Anchors off Dart map insertion order (the most recently added
        // node), not spatial position — a reasonable heuristic for "put it
        // near whatever was placed last" without scanning every node's
        // coordinates.
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
    // Guard against the screen having been disposed while the dialog was
    // open (e.g. user navigated away) before touching context/setState.
    if (!mounted) return;
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


  /// Global keyboard shortcut: pressing either Shift key toggles line
  /// (link) mode on/off, mirroring the line-mode FAB. Only fires on
  /// key-down (not key-up/repeat) so holding Shift doesn't rapidly
  /// flicker the mode.
  void _onKeyEvent(KeyEvent event) {
    final isShift =
        event.logicalKey == LogicalKeyboardKey.shiftLeft || event.logicalKey == LogicalKeyboardKey.shiftRight;

    if (!isShift) return;

    if (event is KeyDownEvent) {
      setState(() {
        _lineMode = !_lineMode;
        // Toggling mode mid-drag would leave stale drag state referencing
        // a mode that no longer applies, so clear it defensively.
        _draggingLineId = null;
        _draggingNodeId = null;

        _cancelRubberBand();
      });
    }
  }

  NodeData? _nodeAt(Offset point) => _graphState.nodeAt(point);

  LineData? _lineAt(Offset point) => _graphState.lineAt(point);

  /// Whether a global-coordinate pointer position falls inside the
  /// currently-visible string-simulator panel's bounds, computed via its
  /// RenderBox. Used to suppress canvas gestures (double-tap-to-create,
  /// pan-to-drag) that would otherwise fire "through" the floating panel.
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

  /// Double-tapping empty canvas creates a new node centered on the tap
  /// point. Suppressed in line mode (double-tap there means something
  /// different on [Node] itself — dropping the start arrow) and over the
  /// simulator panel or an existing node (where double-tap toggles
  /// accept-state instead, handled by [Node.onDoubleTap]).
  void _onDoubleTapDown(TapDownDetails details) {
    if (_lineMode) return;
    if (_isPointerOverSimulatorPanel(details.globalPosition)) return;

    final clickedNode = _nodeAt(details.localPosition);

    if (clickedNode != null) return;

    setState(() {
      // Offset by half the node's ~100x100 footprint so the tap point
      // lands at the new node's center rather than its top-left corner.
      final pos = details.localPosition - const Offset(50, 50);

      final id = _nextId('n');

      _nodes[id] = NodeData(id: id, position: pos);
    });
    _schedulePersist();
  }

  /// Determines what a drag gesture is *about* the moment it begins:
  /// deleting (if delete mode is on), starting a new link (line mode),
  /// dragging an existing line's curve, dragging the start arrow, dragging
  /// a node, or panning the whole canvas — in that priority order. Only
  /// sets state flags here; the actual per-frame work happens in
  /// [_onPanUpdate].
  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;

    _draggingNodeId = null;
    _draggingLineId = null;
    _isPanningCanvas = false;

    if (_deleteMode) {
      // In delete mode, priority is node > line > start-arrow: deleting a
      // node already implicitly deletes its lines, so checking nodes
      // first avoids a redundant/ambiguous double-hit near a node's edge
      // where both a node and its own line could register.
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

      if (_hitStartArrow(pos)) {
        setState(() {
          _startArrow = null;
        });
        _refreshSimulation();
        return;
      }

      return;
    }

    if (_lineMode) {
      // Only nodes that can have outgoing transitions are valid drag
      // origins; tapping/dragging from an ineligible node (e.g. a halt
      // state) simply does nothing rather than starting a doomed link.
      final node = _nodeAt(pos);
      if (node != null && _canStartLineFrom(node.id)) {
        _lineSourceNodeId = node.id;
      }
      return;
    }

    // Lines take priority over nodes so transitions can be curved near states.
    final line = _lineAt(pos);
    if (line != null) {
      _draggingLineId = line.id;
      return;
    }

    if (_hitStartArrow(pos)) {
      _draggingStartArrow = true;
      return;
    }

    final node = _nodeAt(pos);
    if (node != null) {
      _draggingNodeId = node.id;
    } else {
      // Nothing hit — pan the canvas
      _isPanningCanvas = true;
    }
  }

  /// Applies the current frame's drag delta according to whichever mode
  /// [_onPanStart] decided we're in: panning the whole canvas (moves every
  /// node together), dragging a single node, adjusting the start arrow's
  /// direction/length, or reshaping a transition line (self-loop angle if
  /// it's a self-loop, otherwise perpendicular curve offset). Re-runs the
  /// simulation at the end since node/line geometry can affect hit-testing
  /// (though not simulation *results* — this is a bit conservative, but
  /// cheap given _refreshSimulation's own no-op guard).
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

        // Vector from the anchor node's center out to the current pointer
        // position — its normalized form becomes the arrow's direction.
        final dir = Offset(mouse.dx - center.dx, mouse.dy - center.dy);

        final dist = dir.distance;

        // Ignore tiny movements (dist <= 10) to avoid the direction
        // snapping erratically when the pointer is nearly on top of the
        // node's center (where atan2-style direction is numerically
        // unstable).
        if (dist > 10) {
          _startArrow!.offset = Offset(dir.dx / dist, dir.dy / dist);

          // Length is distance-from-node minus the fixed 50px standoff
          // (see StartArrowWidget's `radius` constant), floored at 40 so
          // the arrow never collapses to an unusably short stub.
          _startArrow!.length = max(40, dist - 50);
        }
      });
    } else if (_draggingLineId != null) {
      setState(() {
        final line = _lines[_draggingLineId!]!;

        final nodeA = _nodes[line.nodeAId]!;
        final nodeB = _nodes[line.nodeBId]!;

        if (line.nodeAId == line.nodeBId) {
          // Self-loop: instead of a perpendicular offset, dragging rotates
          // the loop around the node — track the pointer's angular change
          // since the last frame and add it to the loop's stored angle.
          final center = nodeA.center;

          final mouse = _lastPanPosition ?? center;

          // _lastPanPosition already includes this frame's movement (set
          // by _onPanUpdateWithTracking before calling this), so subtract
          // the delta back out to recover where the pointer was *before*
          // this frame, giving the correct incremental angle change.
          final previous = mouse - details.delta;

          final oldAngle = atan2(previous.dy - center.dy, previous.dx - center.dx);

          final newAngle = atan2(mouse.dy - center.dy, mouse.dx - center.dx);

          line.selfLoopAngle += newAngle - oldAngle;

          return;
        }

        // Ordinary (non-self-loop) line: project the drag delta onto the
        // direction perpendicular to the line connecting the two nodes,
        // and accumulate that as the line's curve offset.
        final dx = nodeB.center.dx - nodeA.center.dx;
        final dy = nodeB.center.dy - nodeA.center.dy;

        final length = sqrt(dx * dx + dy * dy);

        if (length != 0) {
          // Unit vector perpendicular to the A→B direction.
          final perpDx = dy / length;
          final perpDy = -dx / length;

          // Dot product of the drag delta with the perpendicular unit
          // vector — i.e. "how far did this frame's drag move things
          // sideways off the straight line", accumulated over the whole
          // drag.
          line.perpendicularPart += details.delta.dx * perpDx + details.delta.dy * perpDy;
        }
      });
    }
    _refreshSimulation();
  }

  /// Finalizes whatever drag was in progress. The only case that actually
  /// creates something is completing a link-mode drag over a valid
  /// destination node; every other drag kind (node move, line curve,
  /// start-arrow reposition, canvas pan) was already fully applied
  /// frame-by-frame in [_onPanUpdate], so this just clears the "currently
  /// dragging X" flags.
  void _onPanEnd(DragEndDetails details) {
    if (_lineMode && _lineSourceNodeId != null) {
      // Resolve the destination from the last known pointer position
      // rather than `details` (DragEndDetails doesn't carry a position).
      final destNode = _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;

      if (destNode != null) {
        final srcId = _lineSourceNodeId!;
        final destId = destNode.id;

        if (!_canStartLineFrom(srcId)) {
          _cancelRubberBand();
          _lineSourceNodeId = null;
          return;
        }

        // Prevent creating a second parallel transition between the same
        // ordered pair of states — multiple symbols on one transition
        // belong in that edge's (multi-line) label instead of as separate
        // edges.
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

  /// Wraps [_onPanUpdate] to also track the pointer's latest position (used
  /// by [_onPanEnd] to resolve a link-mode drop target, and by the
  /// self-loop-angle math in [_onPanUpdate] itself) and to drive the
  /// rubber-band preview line while a link-mode drag is in progress.
  void _onPanUpdateWithTracking(DragUpdateDetails details) {
    _lastPanPosition = details.localPosition;

    _onPanUpdate(details);

    if (_lineSourceNodeId != null && _lineMode) {
      setState(() {
        _rubberBandEnd = details.localPosition;
      });
    } else {
      // Clean up any stale rubber-band state left over from a mode switch
      // mid-drag (e.g. Shift toggled line mode off while dragging).
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
    // Block on the initial async load so the canvas never flashes an
    // empty graph before the persisted one arrives.
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
            // Carry the NFA/DFA simulator's step across into whichever
            // engine the new mode actually uses, so switching modes
            // doesn't reset the user's place in the simulation playback.
            if (mode == AutomataMode.pda) {
              _pdaSimulator.step = _simulator.step.clamp(-1, _pdaSimulator.maxStep);
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
      ),

      appBar: AppBar(
        title: const Text('Automata Designer'),
        actions: [
          MainMenuButton(onPressed: widget.onGoToMenu),
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

      // The vertical stack of mode-toggle FABs (start-arrow placement,
      // delete mode, line mode, simulator visibility). Wrapped in Builder
      // purely to get a context below the Scaffold for context.watch —
      // the outer build()'s context is above the Scaffold/Theme.of chain
      // used by the delete FAB's activeColor.
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
                  // Delete mode is mutually exclusive with the other two
                  // canvas-editing modes — entering it cancels whatever
                  // else was active so gestures aren't ambiguous.
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
          // Clip.none lets node/line content (and the label text fields
          // positioned relative to them) render slightly outside the
          // Stack's own bounds without being clipped off, e.g. near the
          // canvas edges.
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                // opaque: this outer GestureDetector claims every hit in
                // its area regardless of what's painted there, so canvas
                // panning/tapping works even over "empty" transparent
                // regions.
                behavior: HitTestBehavior.opaque,

                onTapDown: (details) {
            _lastTapPosition = details.localPosition;

            // Tapping a node while placing the start arrow commits that
            // node as the start state and exits placement mode.
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
            // A plain tap on empty canvas (not on any node) returns
            // keyboard focus to the canvas itself, e.g. after finishing
            // editing a label field — so the Shift-key line-mode shortcut
            // keeps working without an extra click.
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
              // Start-state arrow, only rendered once a start state has
              // actually been set and that node still exists (guards
              // against a stale _startArrow pointing at a just-deleted
              // node during the brief window before _deleteNode's null-out
              // takes effect).
              if (_startArrow != null && _nodes[_startArrow!.nodeId] != null)
                Positioned.fill(
                  child: StartArrowWidget(
                    data: _startArrow!,
                    nodeCenter: _nodes[_startArrow!.nodeId]!.center,

                    deleteMode: _deleteMode,
                    // Highlights the start arrow specifically at "step -1"
                    // — the pre-simulation state before any transition has
                    // been taken — so the user can see where a run begins.
                    highlighted: _simulator.step == -1 && _simulator.tokens.isNotEmpty,

                    onDelete: () {
                      setState(() {
                        _startArrow = null;
                      });
                    },
                  ),
                ),

              // Live preview line while dragging out a new transition in
              // line mode — drawn on top of everything below it but under
              // the committed lines/nodes drawn afterward.
              if (_lineSourceNodeId != null && _rubberBandEnd != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: RubberBandPainter(start: _nodes[_lineSourceNodeId!]!.center, end: _rubberBandEnd!, color: Colors.lightBlueAccent),
                    ),
                  ),
                ),

              // Every transition line, in Map iteration (insertion) order —
              // this means lines are painted before nodes, so node circles
              // sit visually on top of line endpoints.
              ..._lines.values.map((line) {
                final nodeA = _nodes[line.nodeAId];
                final nodeB = _nodes[line.nodeBId];

                // Defensive guard against a dangling reference (endpoint
                // node deleted without the line being cleaned up) — should
                // not normally happen given _deleteNode's cascade, but
                // fails soft rather than crashing if it ever does.
                if (nodeA == null || nodeB == null) {
                  return const SizedBox.shrink();
                }

                // ValueKey(line.id) via KeyedSubtree ensures each
                // LineWidget's State (and thus its TextEditingController/
                // FocusNode) stays associated with the same line across
                // rebuilds, rather than Flutter reusing State objects
                // positionally when the map's iteration order shifts.
                return KeyedSubtree(
                  key: ValueKey(line.id),
                  child: Positioned.fill(
                    child: LineWidget(
                      data: line,
                      centerA: nodeA.center,
                      centerB: nodeB.center,
                      deleteMode: _deleteMode,
                      highlighted: _simHighlight.lines.contains(line.id),
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

              // Every state/node, painted last so they render above all
              // lines.
              ..._nodes.values.map(
                (node) => Node(
                  // Node itself is a StatefulWidget, so its own `key:` here
                  // (rather than a wrapping KeyedSubtree) is sufficient to
                  // preserve its State identity across rebuilds.
                  key: ValueKey(node.id),
                  data: node,
                  lineMode: _lineMode,
                  deleteMode: _deleteMode,
                  highlighted: _simHighlight.nodes.contains(node.id),

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
                    // In line mode, double-tap is repurposed: instead of
                    // toggling accept state, it drops the start arrow on
                    // whichever node was double-clicked. This lets you set
                    // the start state without leaving line mode to hunt for
                    // the toolbar's "Set start state" button.
                    if (_lineMode) {
                      setState(() {
                        _startArrow = StartArrowData(nodeId: node.id);
                      });
                      _refreshSimulation();
                      return;
                    }

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
            // ── Help overlay ───────────────────────────────────────────
            // Full-screen contextual help, mode-aware (different content
            // per AutomataMode) — floats above the canvas but below the
            // simulator/config panels below it in this list.
            if (_showHelpOverlay)
              HelpOverlay(
                automataMode: _automataMode,
                onClose: () => _setShowHelpOverlay(false),
              ),
            // ── String simulator panel ────────────────────────────────
            // The floating panel with the input-string field, step
            // controls, and (in TM mode) the tape tab strip. Always
            // receives all three simulators, but only passes the
            // pda/tm ones through when the corresponding mode is active
            // (null otherwise) so the panel knows which extra UI to show.
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
                  // Editing the input string invalidates any in-progress
                  // step playback — reset every engine back to "not yet
                  // stepped" (-1) rather than leaving a step index that
                  // may no longer correspond to anything meaningful for
                  // the new string.
                  setState(() {
                    _simRebuild();
                    _simulator.step = -1;
                    _pdaSimulator.step = -1;          // ← NEW
                    _tmSimulator.step = -1;           // ← reset TM tracking too
                  });
                  _schedulePersist();
                },
                onStepChanged: () {
                  _syncSimulatorSteps();
                  setState(() {});
                  _schedulePersist();
                },
                // Tab labels for the tape strip — only meaningful in TM
                // mode; empty elsewhere since other modes have no tapes.
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
                // Both add/remove callbacks are null (disabling the
                // corresponding button in the panel) outside TM mode, and
                // remove is additionally null when only one tape remains
                // — a TM must always have at least one tape.
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
            // Shares _activeTapeIndex with the StringSimulatorPanel above so
            // switching tapes in either place keeps both views in sync,
            // instead of this panel being stuck showing tape 1 always.
            if (_showSimulator && _automataMode == AutomataMode.tm)
              TmConfigPanel(
                simulator: _tmSimulator,
                nodes: _nodes,
                activeTapeIndex: _activeTapeIndex,
                onTapeSelected: (i) => setState(() => _activeTapeIndex = i),
              ),

            // ── Regex Panel ───────────────────────────────────────────
            if (_automataMode == AutomataMode.regex && _showRegexPanel)
              RegexPanel(
                onConvert: _onRegexConvert,
                onClose: () => setState(() => _showRegexPanel = false),
                // Consumed once by the panel (which then calls
                // onInitialTextConsumed to null it back out) so reopening
                // the panel later doesn't re-populate stale text from a
                // previous FA→Regex conversion.
                initialText: _regexPanelInitialText,
                onInitialTextConsumed: () =>
                    setState(() => _regexPanelInitialText = null),
              ),

            // ── Regex show-panel FAB (when panel is closed) ───────────
            // Lets the user reopen the regex panel after closing it,
            // without having to leave regex mode entirely via the drawer.
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