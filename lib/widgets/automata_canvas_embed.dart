import 'dart:math';
// atan2, sqrt, max — used for line-curve/self-loop geometry and start-arrow
// direction math further down.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// KeyEvent / KeyDownEvent / LogicalKeyboardKey — for the Shift-toggles-
// line-mode keyboard shortcut.
import 'package:provider/provider.dart';
// context.watch<AppThemeNotifier>() in _MiniToolbar's build().

import '../models.dart';
// NodeData, LineData, StartArrowData, GraphState — the automaton data model
// this widget edits/renders.
import '../import_export.dart';
// Not directly referenced by name in the visible code below, but presumably
// used transitively via GraphState or kept for parity with sibling canvas
// files (AutomataScreen) this was extracted from.
import 'graph_widgets.dart';
// Node, LineWidget, StartArrowWidget, RubberBandPainter, PaletteFab — the
// low-level rendering widgets this file composes.
import 'app_theme.dart';
// AppThemeNotifier, used only in _MiniToolbar.

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataCanvasEmbed
//
//  A self-contained automata canvas suitable for embedding inside any widget
//  (e.g. the study-mode drawing area or a read-only DFA preview).
//
//  Provides the full draw / edit experience — double-tap to create states,
//  drag to move, line-mode rubber-band to draw transitions, draggable start
//  arrow, delete mode, canvas panning — without any session persistence,
//  simulators, or Scaffold chrome.
//
//  [initialNodes] / [initialLines] / [initialStart]
//      Seed the canvas on first build.  Deep-copied internally so the caller's
//      maps are never mutated.
//
//  [onChanged]
//      Fired after every structural edit so the caller can read the current FA
//      state for grading or other purposes.
//
//  [readOnly]
//      When true, disables structural editing and hides the toolbar: no
//      creating/deleting nodes or transitions, no drawing new transitions,
//      no toggling accept states, and labels can't be typed into. Dragging
//      is still allowed — individual nodes, line curves, and the start
//      arrow can all be repositioned, and dragging empty space pans the
//      whole diagram — so the user can pull things apart if the automatic
//      layout leaves anything overlapping or hard to read. Used to show the
//      "target DFA" preview in study mode.
// ─────────────────────────────────────────────────────────────────────────────

class AutomataCanvasEmbed extends StatefulWidget {
  final Map<String, NodeData> initialNodes;
  final Map<String, LineData> initialLines;
  final StartArrowData? initialStart;
  final void Function(
          Map<String, NodeData>, Map<String, LineData>, StartArrowData?)
      onChanged;
  // Positional-only params (no named args) — the caller gets the full
  // current graph state (nodes, lines, start arrow) as three separate maps
  // rather than a single GraphState object, even though GraphState exists
  // and is used internally (see `_graphState` getter below).
  final bool readOnly;

  const AutomataCanvasEmbed({
    super.key,
    required this.initialNodes,
    required this.initialLines,
    required this.initialStart,
    // Required despite being nullable (StartArrowData?) — callers must
    // explicitly pass `null` for "no start arrow yet" rather than omitting it.
    required this.onChanged,
    this.readOnly = false,
    // Defaults to editable — readOnly is an opt-in restriction, not the
    // default behavior.
  });

  @override
  State<AutomataCanvasEmbed> createState() => _AutomataCanvasEmbedState();
}

class _AutomataCanvasEmbedState extends State<AutomataCanvasEmbed> {
  // ── FA state ────────────────────────────────────────────────────────────
  late final Map<String, NodeData> _nodes;
  late final Map<String, LineData> _lines;
  // Both `late final` — the reference to the Map itself never changes after
  // initState() (it's always the same deep-copied Map instance), but the
  // Map's *contents* are mutated freely throughout (add/remove entries,
  // mutate NodeData/LineData fields in place).
  StartArrowData? _startArrow;
  // Not `final` — unlike _nodes/_lines, the start arrow is a single
  // nullable value that gets wholesale reassigned (set to null, or replaced
  // with a new StartArrowData) rather than mutated in place... except where
  // it's mutated in place too (see _onPanUpdate's offset/length adjustment
  // below) — so it's actually treated both ways depending on the operation.

  // Counter high-water marks so new IDs never collide with existing ones.
  int _nodeCounter = 0;
  int _lineCounter = 0;
  // "High-water mark" rather than `_nodes.length`/`_lines.length` — IDs are
  // never reused even after deletions, so counters only ever increase (see
  // _nextNodeId/_nextLineId below), guaranteeing uniqueness without needing
  // to re-scan existing IDs on every creation.

  // ── Interaction modes ───────────────────────────────────────────────────
  bool _lineMode = false;
  bool _placingStartArrow = false;
  bool _deleteMode = false;
  // Mutually exclusive in practice — every toggle handler below (keyboard
  // and _MiniToolbar callbacks) turns the other two off when one is turned
  // on, though nothing in the type system enforces that; it's convention
  // maintained by hand at each call site.

  // ── Drag state ──────────────────────────────────────────────────────────
  bool _draggingStartArrow = false;
  String? _draggingNodeId;
  String? _draggingLineId;
  String? _lineSourceNodeId;
  // Set when a line-mode drag begins on a valid source node; distinct from
  // _draggingLineId, which is for dragging an *existing* line's curve, not
  // drawing a brand-new one.
  bool _isPanningCanvas = false;

  Offset? _lastPanPosition;
  // Tracked separately from Flutter's own DragUpdateDetails because
  // _onPanEnd (a DragEndDetails callback) has no `localPosition` of its own
  // — this field remembers the last known pointer position from the most
  // recent DragUpdateDetails so _onPanEnd can still do hit-testing.
  Offset? _rubberBandEnd;
  // Current end-point of the line-mode "rubber band" preview line, updated
  // as the user drags before releasing on a destination node.

  // ── Unique hero tags (multiple embeds can coexist on-screen) ────────────
  final Object _startArrowTag = Object();
  final Object _lineModeTag = Object();
  final Object _deleteModeTag = Object();
  // Plain `Object()` instances used purely for their identity (`==`
  // defaults to identity for a bare Object) — Flutter's Hero widget
  // requires heroTag to be unique across the whole Navigator/screen, and
  // since PaletteFab presumably wraps a Hero-tagged FAB, using a fresh
  // Object per embed instance (rather than a String like 'lineMode')
  // guarantees no collision even if two AutomataCanvasEmbeds are visible
  // at once (e.g. side-by-side comparison views).

  // ── Keyboard (Shift toggles line mode, mirrors AutomataScreen/GamePuzzle) ─
  final FocusNode _focusNode = FocusNode();

  // ────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Deep-copy so we never mutate the caller's maps.
    _nodes = Map.of(widget.initialNodes);
    _lines = Map.of(widget.initialLines);
    // Note: `Map.of` is a *shallow* copy — it copies the map's key/value
    // entries into a new Map, but the NodeData/LineData *values* themselves
    // are the same object instances as in widget.initialNodes/initialLines.
    // Since this class does mutate NodeData/LineData fields in place
    // (position, label, etc. — see _onPanUpdate, onNodeLabelChanged, etc.),
    // that in-place mutation *does* affect the caller's original objects
    // too, despite the comment's "we never mutate the caller's maps" claim
    // — only the Map *structure* (which keys exist) is protected from
    // mutation, not the node/line objects it points to.
    _startArrow = widget.initialStart;

    // Set counters above any existing ID numbers to avoid collisions.
    for (final id in _nodes.keys) {
      final n = int.tryParse(id.replaceFirst('n', ''));
      // Assumes node IDs follow the 'n<number>' convention (as generated by
      // _nextNodeId below) — an ID that doesn't match this pattern (e.g. a
      // custom/imported ID) silently yields `null` from tryParse and is
      // just skipped rather than raising an error.
      if (n != null && n >= _nodeCounter) _nodeCounter = n + 1;
      // Finds the maximum existing numeric suffix and sets the counter one
      // past it, so the very next _nextNodeId() call can't collide with any
      // ID already present in the seeded graph.
    }
    for (final id in _lines.keys) {
      final n = int.tryParse(id.replaceFirst('l', ''));
      if (n != null && n >= _lineCounter) _lineCounter = n + 1;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ── Keyboard handling ───────────────────────────────────────────────────
  //
  //  Shift toggles line mode, same as the sandbox (AutomataScreen) and game
  //  (GamePuzzle) canvases. Disabled in readOnly mode: there's no toolbar to
  //  reflect the toggle and lineMode is permanently forced false there.
  void _onKeyEvent(KeyEvent event) {
    if (widget.readOnly) return;
    // Early-out for readOnly — matches the doc comment: no point toggling
    // _lineMode when the canvasBody built in build() (see below) hardcodes
    // lineMode: false for readOnly mode regardless of this field's value.

    final isShift = event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight;
    // Either shift key works — checked by logical key, not physical key,
    // so this behaves consistently across keyboard layouts.
    if (!isShift) return;

    if (event is KeyDownEvent) {
      // Only fires on key-down, not key-up or (if applicable) repeat
      // events — a Shift *tap* toggles the mode once; holding Shift down
      // doesn't repeatedly toggle it (KeyDownEvent only fires once per
      // physical press, not on OS key-repeat, for modifier keys).
      setState(() {
        _lineMode = !_lineMode;
        if (_lineMode) {
          _placingStartArrow = false;
          _deleteMode = false;
          // Entering line mode cancels the other two exclusive modes —
          // mirrors the mutual-exclusivity convention noted above.
        } else {
          // Leaving line mode: clear any in-progress drag state so a
          // half-finished node-drag or line-drag doesn't carry over into
          // whatever mode comes next.
          _draggingLineId = null;
          _draggingNodeId = null;
          _cancelRubberBand();
        }
      });
    }
  }

  // ── Change notification ─────────────────────────────────────────────────
  void _notify() => widget.onChanged(_nodes, _lines, _startArrow);
  // Called after essentially every structural mutation throughout this
  // file — always passes the *live* _nodes/_lines maps (not copies), so
  // the parent's onChanged callback sees the same mutable objects this
  // widget continues to edit afterward; the parent must not assume it owns
  // an independent snapshot.

  // ── ID generation ───────────────────────────────────────────────────────
  String _nextNodeId() => 'n${_nodeCounter++}';
  String _nextLineId() => 'l${_lineCounter++}';
  // Post-increment (`_nodeCounter++`) — the returned ID uses the counter's
  // value *before* incrementing, then bumps it for next time; this is the
  // 'n<number>' format that initState()'s ID-scanning loop above expects.

  GraphState get _graphState => GraphState(
        nodes: _nodes,
        lines: _lines,
        startArrow: _startArrow,
        nodeCounter: _nodeCounter,
        lineCounter: _lineCounter,
      );
  // A getter (not a cached field) — reconstructs a fresh GraphState object
  // from current fields on every access. Used below purely for its
  // hit-testing helper methods (nodeAt/lineAt/hitStartArrow), not stored or
  // passed anywhere itself.

  // ── Hit-testing helpers ─────────────────────────────────────────────────

  bool _isLabelTaken(String label, String currentId) {
    final t = label.trim();
    if (t.isEmpty) return false;
    // An empty label is never considered "taken" — presumably multiple
    // states are allowed to sit unlabeled simultaneously without triggering
    // a duplicate-label warning.
    return _nodes.values.any((n) => n.id != currentId && n.label.trim() == t);
    // Excludes the node currently being renamed (`currentId`) from the
    // comparison — otherwise a node would always "conflict" with its own
    // unchanged label.
  }

  bool _canStartLineFrom(String? id) =>
      _nodes[id]?.canHaveOutgoingTransitions ?? false;
  // `_nodes[id]` on a null `id` is itself safe (Map lookup with a null key
  // just returns null, doesn't throw) — the `?.` and `?? false` combination
  // means both "no such node" and "node exists but disallows outgoing
  // transitions" resolve to `false` uniformly.

  NodeData? _nodeAt(Offset pt) => _graphState.nodeAt(pt);

  LineData? _lineAt(Offset pt) => _graphState.lineAt(pt);

  bool _hitStartArrow(Offset pt) => _graphState.hitStartArrow(pt);
  // All three hit-testing helpers are thin delegations to GraphState's own
  // geometry logic (defined in models.dart) — this class doesn't implement
  // any hit-testing math itself, only orchestrates when to call it.

  // ── Deletion helpers ────────────────────────────────────────────────────

  void _cancelRubberBand() {
    _lineSourceNodeId = null;
    _rubberBandEnd = null;
  }
  // Note: does NOT call setState() itself — every call site below wraps
  // this in its own setState(_cancelRubberBand) or similar, so this method
  // is a plain synchronous state-clearing helper, not a self-contained UI
  // update.

  void _deleteLine(String id) {
    final line = _lines[id];
    if (line == null) return;
    _nodes[line.nodeAId]?.connectedLineIds.remove(id);
    _nodes[line.nodeBId]?.connectedLineIds.remove(id);
    // Cleans up both endpoint nodes' back-references to this line before
    // removing the line itself — prevents connectedLineIds from
    // accumulating stale IDs pointing at lines that no longer exist. `?.`
    // guards against either endpoint node having already been deleted.
    _lines.remove(id);
    _notify();
  }

  void _deleteNode(String id) {
    final node = _nodes[id];
    if (node == null) return;
    for (final lid in node.connectedLineIds.toList()) {
      // `.toList()` — takes a snapshot copy of the ID list before iterating,
      // since _deleteLine() below mutates connectedLineIds (via the
      // `?.remove(id)` calls above) as a side effect of each iteration;
      // iterating directly over the live list while removing from it would
      // risk a concurrent-modification error.
      _deleteLine(lid);
      // Deletes every line touching this node first, so no line is left
      // dangling with an endpoint that no longer exists in _nodes.
    }
    if (_startArrow?.nodeId == id) _startArrow = null;
    // If this node was the start state, clear the start arrow entirely
    // rather than leaving it pointing at a deleted node.
    _nodes.remove(id);
    _notify();
  }

  // ── Gesture handlers (extracted from AutomataScreen) ────────────────────

  void _onDoubleTapDown(TapDownDetails d) {
    if (_lineMode) return;
    // Double-tap creates nodes only outside line mode — in line mode,
    // double-tap is repurposed elsewhere (see onNodeDoubleTap's callback in
    // build() below, which uses double-tap on an *existing* node to place
    // the start arrow instead).
    if (_nodeAt(d.localPosition) != null) return;
    // Don't create a new node on top of an existing one — double-tapping a
    // node hits Node's own onDoubleTap handler instead (accept-state toggle).
    setState(() {
      final id = _nextNodeId();
      _nodes[id] = NodeData(
        id: id,
        position: d.localPosition - const Offset(50, 50),
        // Offsets the new node so the tap point lands at its *center*
        // rather than its top-left corner — assumes a roughly 100x100
        // node size (half of that, 50, subtracted from each axis).
      );
    });
    _notify();
  }

  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;
    _draggingNodeId    = null;
    _draggingLineId    = null;
    _isPanningCanvas   = false;
    _draggingStartArrow = false;
    // Resets all drag-target flags at the start of every new pan gesture,
    // before any of the mode-specific branches below decide which one (if
    // any) should become true for this particular gesture.

    if (_deleteMode) {
      // In delete mode, a "pan start" (i.e. first touch/click) doesn't
      // begin a drag at all — it's treated as a tap-to-delete instead,
      // checked in priority order: node, then line, then start arrow.
      final node = _nodeAt(pos);
      if (node != null) {
        setState(() => _deleteNode(node.id));
        return;
      }
      final line = _lineAt(pos);
      if (line != null) {
        setState(() => _deleteLine(line.id));
        return;
      }
      if (_hitStartArrow(pos)) {
        setState(() {
          _startArrow = null;
          _notify();
          // Note: _notify() is called *inside* the setState callback here,
          // unlike _deleteNode/_deleteLine's pattern of calling _notify()
          // after setState() returns — functionally equivalent (setState's
          // callback runs synchronously), just an inconsistent style
          // between this inline branch and the extracted helper methods.
        });
        return;
      }
      return;
      // Tapped empty space in delete mode: nothing happens, deliberately —
      // no fallback to canvas panning while delete mode is active.
    }

    if (_lineMode) {
      final node = _nodeAt(pos);
      if (node != null && _canStartLineFrom(node.id)) {
        _lineSourceNodeId = node.id;
        // Note: no setState() here — this just primes state for the
        // upcoming _onPanUpdateWithTracking calls, which will setState()
        // once the rubber-band actually needs to render (see below).
      }
      return;
      // If the pan started on a node that can't have outgoing transitions,
      // or on empty space, _lineSourceNodeId stays null and no line gets
      // drawn for this gesture — but note there's no fallback to canvas
      // panning here either, unlike the equivalent branch in normal mode.
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
      _isPanningCanvas = true;
      // Only in normal (non-line, non-delete) mode does touching empty
      // space fall back to panning the whole canvas.
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isPanningCanvas) {
      setState(() {
        for (final n in _nodes.values) {
          n.position = n.position + d.delta;
          // Moves every node by the same per-frame delta — panning is
          // simulated by translating all node positions together rather
          // than by an actual canvas/viewport transform, so line/start-arrow
          // positions (which are derived from node.center) update for free.
        }
      });
      return;
    }

    if (_draggingNodeId != null) {
      setState(() {
        _nodes[_draggingNodeId!]!.position =
            _nodes[_draggingNodeId!]!.position + d.delta;
        // `!` used twice here (non-null Map value after non-null key
        // check) — safe since _draggingNodeId is only ever set to an ID
        // that exists in _nodes (see _onPanStart above), and nothing
        // between pan-start and pan-update removes that node except
        // delete-mode's own branch, which returns early and never sets
        // _draggingNodeId in the first place.
      });
      return;
    }

    if (_draggingStartArrow && _startArrow != null) {
      setState(() {
        final center = _nodes[_startArrow!.nodeId]!.center;
        final mouse  = d.localPosition;
        final dir    = Offset(mouse.dx - center.dx, mouse.dy - center.dy);
        // Vector from the start node's center to the current pointer
        // position — this determines both the direction the start arrow
        // points and (via its length) how far it extends.
        final dist   = dir.distance;
        if (dist > 10) {
          // Ignores tiny movements (<=10px from center) — prevents the
          // arrow's direction from jittering wildly when the drag begins
          // very close to the node's own center, where `dir` would be
          // near-zero and its normalized direction unstable.
          _startArrow!.offset = Offset(dir.dx / dist, dir.dy / dist);
          // Normalizes `dir` to a unit vector — `offset` stores only the
          // *direction* the arrow points, independent of drag distance.
          _startArrow!.length = max(40, dist - 50);
          // Arrow length tracks how far the pointer is from the node, minus
          // a fixed 50px (presumably to stop the arrowhead right at the
          // node's edge rather than at the pointer itself), floored at a
          // minimum visible length of 40px so the arrow never shrinks to
          // nothing even if the pointer is dragged very close to the node.
        }
      });
      return;
    }

    if (_draggingLineId != null) {
      setState(() {
        final line = _lines[_draggingLineId!]!;
        final a    = _nodes[line.nodeAId]!;
        final b    = _nodes[line.nodeBId]!;

        if (line.nodeAId == line.nodeBId) {
          // Self-loop: rotate the loop angle.
          final center = a.center;
          final prev   = (_lastPanPosition ?? center) - d.delta;
          // Reconstructs the *previous* frame's pointer position by
          // subtracting this frame's delta from the last known position
          // (falls back to `center` if this is the very first update event,
          // i.e. _lastPanPosition hasn't been set yet).
          final oldA   = atan2(prev.dy - center.dy, prev.dx - center.dx);
          final newA   = atan2(d.localPosition.dy - center.dy,
                               d.localPosition.dx - center.dx);
          // Computes the angle (relative to the node's center) of both the
          // previous and current pointer positions using atan2 — this is
          // the standard "angle of vector from origin" formula, where the
          // "origin" here is the node's own center rather than (0,0).
          line.selfLoopAngle += newA - oldA;
          // Accumulates the *change* in angle (not the absolute angle)
          // onto the loop's existing rotation — this means a self-loop
          // can be rotated smoothly through multiple partial drags without
          // snapping, and a full drag around the node adds a full 2π (with
          // atan2's wraparound handled implicitly by always taking the
          // delta between two nearby angles, not normalizing to [0, 2π)).
          return;
          // Returns early — a self-loop only rotates, it never gets the
          // perpendicular-arc curve adjustment below (which wouldn't make
          // geometric sense for a line whose two endpoints are the same
          // node).
        }

        // Curved arc: adjust perpendicular offset.
        final dx  = b.center.dx - a.center.dx;
        final dy  = b.center.dy - a.center.dy;
        final len = sqrt(dx * dx + dy * dy);
        // Vector from node A to node B, and its length — standard
        // Pythagorean distance.
        if (len != 0) {
          // Guards a divide-by-zero below in the unlikely case A and B sit
          // at the exact same position (distinct nodes with an identical
          // (dx, dy) of zero, which is different from the self-loop case
          // above since here nodeAId != nodeBId).
          line.perpendicularPart +=
              d.delta.dx * (dy / len) + d.delta.dy * (-dx / len);
          // (dy/len, -dx/len) is the unit vector perpendicular to the A→B
          // line (a 90° rotation of the normalized (dx, dy) direction).
          // Projecting the drag delta onto this perpendicular unit vector
          // via a dot product gives "how far, and in which perpendicular
          // direction, did this drag push the curve" — accumulated onto
          // `perpendicularPart`, which presumably controls how far the
          // rendered arc bows away from the straight A-B line.
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails _) {
    // Parameter named `_` — the DragEndDetails argument (velocity info) is
    // never used; only its *arrival* (gesture ended) matters here.
    if (_lineMode && _lineSourceNodeId != null) {
      // A line-drawing drag is being finalized.
      final dest = _lastPanPosition != null ? _nodeAt(_lastPanPosition!) : null;
      // Uses the tracked _lastPanPosition (from _onPanUpdateWithTracking)
      // rather than anything on DragEndDetails, since DragEndDetails itself
      // carries no position — only velocity.

      if (dest != null && _canStartLineFrom(_lineSourceNodeId!)) {
        // Re-checks _canStartLineFrom here even though it was already
        // checked in _onPanStart when _lineSourceNodeId was set — a
        // defensive re-validation in case the source node's
        // outgoing-transition eligibility could change mid-drag (e.g. due
        // to some other concurrent state change), though nothing in this
        // file itself would cause that between pan-start and pan-end.
        final src    = _lineSourceNodeId!;
        final exists = _lines.values.any(
            (l) => l.nodeAId == src && l.nodeBId == dest.id);
        // Checks only one direction (src -> dest), not the reverse (dest ->
        // src) — implies a line from B to A is considered a distinct,
        // separately-allowed transition from A to B (consistent with
        // automata transitions being directed).
        if (!exists) {
          setState(() {
            final id   = _nextLineId();
            final line = LineData(id: id, nodeAId: src, nodeBId: dest.id);
            _lines[id] = line;
            _nodes[src]?.connectedLineIds.add(id);
            _nodes[dest.id]?.connectedLineIds.add(id);
            // Registers the new line's ID with both endpoint nodes'
            // connectedLineIds — the inverse of what _deleteLine's cleanup
            // removes.
          });
          _notify();
        }
        // If a line already exists between these two nodes in this
        // direction, dropping on `dest` again silently does nothing (no
        // duplicate line, no error) — the drag just ends without effect.
      }

      setState(_cancelRubberBand);
      // Clears the rubber-band preview regardless of whether a line was
      // actually created — either way the drag-in-progress visual needs to
      // disappear once the gesture ends.
      _lineSourceNodeId = null;
      // Redundant with _cancelRubberBand() (which already nulls this) but
      // set again explicitly here outside the setState — likely just
      // belt-and-suspenders, has no additional effect since
      // _cancelRubberBand already did it inside the setState above.
    }

    _draggingNodeId     = null;
    _draggingLineId     = null;
    _draggingStartArrow = false;
    _isPanningCanvas    = false;
    _lastPanPosition    = null;
    // Resets every drag-related flag/field unconditionally at the end of
    // any pan gesture, not just line-mode ones — covers node-drag,
    // line-curve-drag, start-arrow-drag, and canvas-pan cleanup all in one
    // place.
    setState(_cancelRubberBand);
    // Called a second time (already invoked inside the `if` block above
    // when applicable) — harmless no-op if _lineSourceNodeId/_rubberBandEnd
    // are already null, but ensures the rubber band is cleared even for
    // gestures that never entered the `if (_lineMode ...)` branch at all
    // (technically unreachable here since _rubberBandEnd is only ever
    // set while in line mode, but kept for safety/symmetry).
    _notify();
    // Fires onChanged once at the very end covering whatever changed during
    // this entire gesture (position updates from _onPanUpdate don't call
    // _notify() themselves for node/canvas dragging — only line-drawing and
    // deletion do inline) — so the caller is notified once per completed
    // drag rather than on every intermediate frame.
  }

  void _onPanUpdateWithTracking(DragUpdateDetails d) {
    // Wraps _onPanUpdate to additionally maintain _lastPanPosition and the
    // rubber-band preview — this is the actual GestureDetector.onPanUpdate
    // callback wired up in build() below, not _onPanUpdate directly.
    _lastPanPosition = d.localPosition;
    _onPanUpdate(d);
    if (_lineSourceNodeId != null && _lineMode) {
      setState(() => _rubberBandEnd = d.localPosition);
      // While actively drawing a line, keep the rubber-band's end point
      // following the pointer every frame.
    } else if (_lineSourceNodeId != null || _rubberBandEnd != null) {
      setState(_cancelRubberBand);
      // Defensive cleanup: if either field is somehow still set but we're
      // no longer in the "drawing a line" state (e.g. _lineMode was
      // toggled off mid-drag via the Shift key), clear them so a stale
      // rubber band doesn't linger on screen.
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    final canvasBody = widget.readOnly
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Opaque hit-test behavior — the GestureDetector claims hits
            // across its entire bounds (including "empty" areas with no
            // painted content), not just where child widgets are visually
            // drawn; necessary so panning/dragging works when starting from
            // blank canvas space.
            // Read-only means "can't change the structure" — it doesn't mean
            // frozen in place. Reuse the same drag handlers as edit mode so
            // individual nodes/line-curves/the start arrow can be dragged
            // apart when the auto-layout leaves things overlapping or hard
            // to read; dragging empty space still pans everything at once.
            // _lineMode/_deleteMode/_placingStartArrow are permanently false
            // here (no toolbar to turn them on), so none of the structural
            // branches inside these handlers (new transitions, deletion,
            // start-arrow re-placement) can fire — only repositioning can.
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdateWithTracking,
            onPanEnd: _onPanEnd,
            // Note: no onDoubleTapDown or onTapDown wired up in read-only
            // mode — double-tap-to-create-node and tap-to-place-start-arrow
            // are structural edits, so they're simply omitted rather than
            // being handled and then no-op'd.
            child: _CanvasContents(
              nodes: _nodes,
              lines: _lines,
              startArrow: _startArrow,
              lineMode: false,
              deleteMode: false,
              placingStartArrow: false,
              lineSourceNodeId: null,
              rubberBandEnd: null,
              // All mode/drag-preview fields hardcoded to their "off"
              // values — even though this widget's own _lineMode/
              // _deleteMode/etc. fields exist and default to false anyway,
              // passing literals here makes the read-only rendering
              // path's intent explicit and immune to those fields ever
              // being mutated some other way.
              isLabelTaken: _isLabelTaken,
              interactionLocked: true,
              onNodeLabelChanged: (_, _) {},
              onLineModeSelect: (_) {},
              onNodeDoubleTap: (_) {},
              onNodeDelete: (_) {},
              onLineDelete: (_) {},
              onLineLabelChanged: (_, _) {},
              onStartArrowDelete: () {},
              // Every mutation callback is a no-op stub — _CanvasContents
              // still requires all of them (non-nullable function types),
              // but with interactionLocked: true and dragging handled at
              // this outer GestureDetector level instead, none of these
              // inner callbacks should ever actually fire from user
              // interaction in read-only mode.
            ),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: _onDoubleTapDown,
            onTapDown: (d) {
              if (!_placingStartArrow) return;
              final node = _nodeAt(d.localPosition);
              if (node != null) {
                setState(() {
                  _startArrow = StartArrowData(nodeId: node.id);
                  _placingStartArrow = false;
                  // Placing the start arrow automatically exits
                  // "placing" mode — a one-shot action, not a persistent
                  // toggle like line/delete mode.
                });
                _notify();
              }
              // Tapping empty space while placing the start arrow does
              // nothing and leaves _placingStartArrow still true, letting
              // the user try again.
            },
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdateWithTracking,
            onPanEnd: _onPanEnd,
            child: _CanvasContents(
              nodes: _nodes,
              lines: _lines,
              startArrow: _startArrow,
              lineMode: _lineMode,
              deleteMode: _deleteMode,
              placingStartArrow: _placingStartArrow,
              lineSourceNodeId: _lineSourceNodeId,
              rubberBandEnd: _rubberBandEnd,
              isLabelTaken: _isLabelTaken,
              interactionLocked: false,
              onNodeLabelChanged: (id, text) {
                setState(() => _nodes[id]!.label = text);
                _notify();
              },
              onLineModeSelect: (id) {
                if (_lineMode && _canStartLineFrom(id)) {
                  _lineSourceNodeId = id;
                  // No setState() call here — this fires from a tap-style
                  // selection on the Node widget itself (an alternate way
                  // to start a line besides dragging directly from empty
                  // space onto the node), and relies on the subsequent
                  // pan-update's setState to pick up the change visually.
                }
              },
              onNodeDoubleTap: (id) {
                // In line mode, double-tap is repurposed: instead of
                // toggling accept state, it drops the start arrow on
                // whichever node was double-clicked.
                if (_lineMode) {
                  if (_nodes[id] == null) return;
                  setState(() => _startArrow = StartArrowData(nodeId: id));
                  _notify();
                  return;
                }

                final node = _nodes[id];
                if (node == null || !node.canToggleNormalAccept) return;
                // Some node types (e.g. TM states with special semantics)
                // presumably can't be toggled as "accept" states via
                // double-tap — canToggleNormalAccept gates that.
                setState(() => node.isAccept = !node.isAccept);
                _notify();
              },
              onNodeDelete: (id) {
                setState(() => _deleteNode(id));
              },
              onLineDelete: (id) {
                setState(() => _deleteLine(id));
              },
              onLineLabelChanged: (id, text) {
                setState(() => _lines[id]!.label = text);
                _notify();
              },
              onStartArrowDelete: () {
                setState(() {
                  _startArrow = null;
                  _notify();
                });
              },
            ),
          );

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      // Grabs keyboard focus as soon as this widget builds, so the Shift
      // shortcut works immediately without the user needing to click into
      // the canvas first — could be a problem if multiple focusable
      // widgets/embeds exist on the same screen and only one should have
      // autofocus, but that's a caller-level concern.
      onKeyEvent: _onKeyEvent,
      child: Stack(
        children: [
          Positioned.fill(child: canvasBody),

          // ── Empty-canvas hint (edit mode only) ─────────────────────────
          if (!widget.readOnly && _nodes.isEmpty)
            // Only shown when editable AND there's nothing drawn yet — a
            // read-only preview with zero nodes (e.g. an unset target DFA)
            // shows no hint at all, just a blank canvas.
            Positioned.fill(
              child: IgnorePointer(
                // Purely decorative — must not intercept taps/drags meant
                // for the canvasBody GestureDetector beneath it in the
                // Stack.
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_outlined,
                          color: theme.textDim.withValues(alpha: 0.22), size: 36),
                      const SizedBox(height: 10),
                      Text(
                        'Double-tap to add a state\n'
                        'Drag node to move  ·  Use toolbar to draw transitions',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.textDim.withValues(alpha: 0.28),
                          // Very low alpha (0.22 icon / 0.28 text) — a
                          // faint watermark-style hint rather than a bold
                          // call-to-action, so it doesn't compete visually
                          // with actual content once nodes are added.
                          fontSize: 11,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Mini toolbar (edit mode only) ────────────────────────────
          if (!widget.readOnly)
            Positioned(
              right: 12,
              bottom: 12,
              // Fixed bottom-right placement, unlike a full Scaffold's FAB
              // (which the doc comment says this widget deliberately
              // avoids) — this positions the toolbar directly within the
              // embed's own Stack instead.
              child: _MiniToolbar(
                lineMode: _lineMode,
                placingStartArrow: _placingStartArrow,
                deleteMode: _deleteMode,
                startArrowTag: _startArrowTag,
                lineModeTag: _lineModeTag,
                deleteModeTag: _deleteModeTag,
                onStartArrowToggle: () => setState(() {
                  _placingStartArrow = !_placingStartArrow;
                  if (_placingStartArrow) {
                    _lineMode = false;
                    _deleteMode = false;
                  }
                }),
                onLineModeToggle: () => setState(() {
                  _lineMode = !_lineMode;
                  if (_lineMode) {
                    _placingStartArrow = false;
                    _deleteMode = false;
                  }
                }),
                onDeleteModeToggle: () => setState(() {
                  _deleteMode = !_deleteMode;
                  if (_deleteMode) {
                    _lineMode = false;
                    _placingStartArrow = false;
                  }
                }),
                // All three toggle callbacks follow the identical pattern:
                // flip this mode, and if it's now on, turn the other two
                // off — the mutual-exclusivity convention enforced by hand
                // at each of these three call sites (plus the Shift-key
                // handler above), not by any shared helper method.
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _CanvasContents — pure rendering widget for nodes, lines, start arrow
// ─────────────────────────────────────────────────────────────────────────────

class _CanvasContents extends StatelessWidget {
  // "Pure rendering" per the header comment — this widget holds no state of
  // its own; every interactive behavior is delegated back up to the parent
  // State via the callback fields below. It exists to separate "what does
  // the canvas look like right now" from "how do gestures mutate the FA",
  // which live in _AutomataCanvasEmbedState above.
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;

  final bool lineMode;
  final bool deleteMode;
  final bool placingStartArrow;
  final String? lineSourceNodeId;
  final Offset? rubberBandEnd;

  final bool Function(String label, String nodeId) isLabelTaken;

  /// True for the read-only preview mode: node/line/start-arrow labels are
  /// shown but can't be typed into. Does not affect dragging — positions
  /// can still be adjusted so the player can fix overlapping/hard-to-read
  /// layouts, only the label *text* is locked.
  final bool interactionLocked;
  // Distinct from `lineMode`/`deleteMode`/etc. above — those describe
  // *which* editing mode is active, while this describes whether editing
  // is possible *at all*. Passed straight through to the child Node/
  // LineWidget/StartArrowWidget widgets below.

  final void Function(String id, String text) onNodeLabelChanged;
  final void Function(String id) onLineModeSelect;
  final void Function(String id) onNodeDoubleTap;
  final void Function(String id) onNodeDelete;
  final void Function(String id) onLineDelete;
  final void Function(String id, String text) onLineLabelChanged;
  final VoidCallback onStartArrowDelete;
  // Seven callbacks, one per possible user-triggered mutation this widget's
  // children can report — none of them are nullable, so the parent
  // (_AutomataCanvasEmbedState.build()) must always supply all seven, even
  // if some are no-op stubs (as in the read-only branch above).

  const _CanvasContents({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.lineMode,
    required this.deleteMode,
    required this.placingStartArrow,
    required this.lineSourceNodeId,
    required this.rubberBandEnd,
    required this.isLabelTaken,
    required this.interactionLocked,
    required this.onNodeLabelChanged,
    required this.onLineModeSelect,
    required this.onNodeDoubleTap,
    required this.onNodeDelete,
    required this.onLineDelete,
    required this.onLineLabelChanged,
    required this.onStartArrowDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      // Allows children (e.g. a node dragged near the canvas edge, or a
      // curved line's arc) to render slightly outside the Stack's own
      // bounds without being clipped off — appropriate since this sits
      // inside a Positioned.fill within a larger Stack already.
      children: [
        // ── Start arrow ─────────────────────────────────────────────────
        if (startArrow != null && nodes[startArrow!.nodeId] != null)
          // Also guards against a dangling start arrow whose target node
          // no longer exists in `nodes` — shouldn't normally happen given
          // _deleteNode's cleanup in the parent, but avoids a null-lookup
          // crash if it ever does (e.g. a transient frame during a
          // multi-step state update).
          Positioned.fill(
            child: StartArrowWidget(
              data: startArrow!,
              nodeCenter: nodes[startArrow!.nodeId]!.center,
              deleteMode: deleteMode,
              interactionLocked: interactionLocked,
              onDelete: onStartArrowDelete,
            ),
          ),

        // ── Rubber band (line preview while dragging) ───────────────────
        if (lineSourceNodeId != null &&
            rubberBandEnd != null &&
            nodes[lineSourceNodeId!] != null)
          Positioned.fill(
            child: IgnorePointer(
              // The rubber-band preview line is purely visual — it must
              // not intercept the drag gesture that's producing it, which
              // is being handled by the outer GestureDetector, not by this
              // painted line itself.
              child: CustomPaint(
                painter: RubberBandPainter(
                  start: nodes[lineSourceNodeId!]!.center,
                  end: rubberBandEnd!,
                  color: Colors.lightBlueAccent,
                  // Hardcoded color, not theme-driven — unlike virtually
                  // everything else in this codebase's UI chrome, this
                  // in-progress preview line ignores AppThemeNotifier
                  // entirely.
                ),
              ),
            ),
          ),

        // ── Transition lines ────────────────────────────────────────────
        ...lines.values.map((line) {
          final a = nodes[line.nodeAId];
          final b = nodes[line.nodeBId];
          if (a == null || b == null) return const SizedBox.shrink();
          // Defensive: skip rendering any line whose endpoint(s) don't
          // currently exist in `nodes` — same "shouldn't happen given
          // proper cleanup, but don't crash if it does" posture as the
          // start-arrow check above.
          return KeyedSubtree(
            key: ValueKey(line.id),
            // Explicit key by line ID — ensures Flutter's element diffing
            // correctly matches each LineWidget to its underlying LineData
            // across rebuilds (e.g. when lines are added/removed/reordered
            // in the map), rather than potentially reusing/misattributing
            // widget state between different lines.
            child: Positioned.fill(
              child: LineWidget(
                data: line,
                centerA: a.center,
                centerB: b.center,
                deleteMode: deleteMode,
                highlighted: false,
                // Always false in this embed — highlighting (e.g. during
                // simulation step-through) isn't part of what this
                // "self-contained... without any... simulators" embed
                // supports, per the file's own header doc comment.
                interactionLocked: interactionLocked,
                onLabelChanged: (text) => onLineLabelChanged(line.id, text),
                // Closes over `line.id` from the surrounding .map() call —
                // each LineWidget gets its own callback bound to its own
                // specific line's ID.
              ),
            ),
          );
        }),

        // ── State nodes ─────────────────────────────────────────────────
        ...nodes.values.map((node) => Node(
              key: ValueKey(node.id),
              data: node,
              lineMode: lineMode,
              interactionLocked: interactionLocked || placingStartArrow,
              // Nodes are also locked (can't edit labels, etc.) while
              // placingStartArrow is active — makes sense since a tap on a
              // node during that mode should place the start arrow (see
              // the parent's onTapDown handler), not trigger normal
              // node-editing interactions.
              deleteMode: deleteMode,
              highlighted: false,
              // Same "no simulation highlighting" rationale as LineWidget
              // above.
              tapeCount: 1,
              // Hardcoded to a single tape — this embed doesn't support
              // multi-tape Turing Machines, consistent with it being a
              // general-purpose lightweight canvas rather than the full
              // AutomataScreen experience.
              isLabelTaken: isLabelTaken,
              onLabelChanged: (text) => onNodeLabelChanged(node.id, text),
              onLineModeSelect: () => onLineModeSelect(node.id),
              onDoubleTap: () => onNodeDoubleTap(node.id),
              onDelete: () => onNodeDelete(node.id),
            )),
        // Nodes are rendered *after* (on top of, in Stack order) lines and
        // the rubber band — so node hit-targets/visuals sit above line
        // curves passing near/through them, which is also why "lines take
        // priority over nodes" needed an explicit comment back in
        // _onPanStart's hit-testing (visual stacking order and hit-test
        // priority order are handled independently and don't automatically
        // agree).
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _MiniToolbar — compact FAB column placed inside the canvas
// ─────────────────────────────────────────────────────────────────────────────

class _MiniToolbar extends StatelessWidget {
  final bool lineMode;
  final bool placingStartArrow;
  final bool deleteMode;

  final Object startArrowTag;
  final Object lineModeTag;
  final Object deleteModeTag;
  // Passed in from the parent's per-instance _startArrowTag/_lineModeTag/
  // _deleteModeTag fields rather than generated here — keeps hero-tag
  // identity tied to the owning _AutomataCanvasEmbedState instance, not to
  // this stateless widget (which could otherwise be rebuilt with a fresh
  // identity on every parent build).

  final VoidCallback onStartArrowToggle;
  final VoidCallback onLineModeToggle;
  final VoidCallback onDeleteModeToggle;

  const _MiniToolbar({
    required this.lineMode,
    required this.placingStartArrow,
    required this.deleteMode,
    required this.startArrowTag,
    required this.lineModeTag,
    required this.deleteModeTag,
    required this.onStartArrowToggle,
    required this.onLineModeToggle,
    required this.onDeleteModeToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: 0.92),
        // Slightly translucent (92% opacity) rather than fully opaque —
        // lets a hint of the canvas show through behind the toolbar,
        // appropriate since it floats directly on top of the drawing
        // surface rather than sitting in separate chrome.
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.borderMid),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
            // Soft drop shadow to visually lift the toolbar off the canvas
            // content beneath it, reinforcing that it's a floating overlay
            // control, not part of the diagram itself.
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Set start-state arrow
          Tooltip(
            message: placingStartArrow
                ? 'Tap a state to set it as start'
                : 'Set start state',
            // Tooltip text changes based on current mode — while actively
            // placing, it becomes an instruction ("tap a state...") rather
            // than a static label of what the button does.
            child: PaletteFab(
              heroTag: startArrowTag,
              tooltip: 'Set start state',
              // PaletteFab's own `tooltip` param is set to the static
              // label regardless of `placingStartArrow`, unlike the
              // wrapping Tooltip widget's dynamic `message` above — so
              // there may be two overlapping tooltip sources here
              // (PaletteFab likely renders its own Tooltip internally
              // using this `tooltip` string, nested inside the outer one),
              // meaning the outer Tooltip's dynamic message may never
              // actually be reachable/visible if PaletteFab's internal
              // tooltip intercepts hover/long-press first.
              icon: Icons.play_arrow,
              active: placingStartArrow,
              activeColor: const Color(0xFFFF6D00),
              // A distinct hardcoded orange, not theme.accent — visually
              // distinguishes "placing start arrow" (orange) from "line
              // mode" (theme.accent, below) and "delete mode" (theme.error,
              // below), so the three toggle-able tools each get their own
              // recognizable active color.
              onPressed: onStartArrowToggle,
              small: true,
            ),
          ),
          const SizedBox(height: 6),

          // Line mode (draw transitions)
          PaletteFab(
            heroTag: lineModeTag,
            tooltip: lineMode ? 'Exit line mode' : 'Draw transition',
            icon: lineMode ? Icons.timeline : Icons.add_link,
            // Icon itself changes when active (add_link -> timeline),
            // unlike the start-arrow FAB above which keeps the same
            // play_arrow icon regardless of state (only its background/
            // border color changes via `active`).
            active: lineMode,
            activeColor: theme.accent,
            onPressed: onLineModeToggle,
            small: true,
          ),
          const SizedBox(height: 6),

          // Delete mode
          PaletteFab(
            heroTag: deleteModeTag,
            tooltip: 'Delete mode',
            icon: Icons.delete_outline,
            active: deleteMode,
            activeColor: theme.error,
            onPressed: onDeleteModeToggle,
            small: true,
          ),
        ],
      ),
    );
  }
}