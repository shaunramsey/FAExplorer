// dart:math gives us trig (cos/sin/atan2) and pi, used throughout this file
// to turn two node centers into an angle/curve and to draw arrowheads.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// Gives widgets access to `context.watch<AppThemeNotifier>()` so line/node
// colors update live when the user changes the app's theme.
import 'package:provider/provider.dart';

//this file is purely the *visual* (widget/painter) layer on top of that data model.
import '../models.dart';
import '../token_replacements.dart';
import 'app_theme.dart';

// Length (in logical pixels) of the arrowhead from its tip back to its base.
const _arrowLen = 15.0;
// Half-width of the arrowhead's base (how far each "wing" flares out to the
// side of the shaft direction). Together with _arrowLen this fixes the
// triangle shape drawn by _drawArrowhead.
const _arrowWing = 9.0;

/// Draws a solid filled triangular arrowhead whose tip sits at [tip],
/// pointing in the direction given by [angle] (radians, standard atan2
/// convention: 0 = pointing along +x, increasing angle rotates toward +y).
///
/// Shared by every painter in this file (transition lines, the start arrow,
/// and the rubber-band drag preview) so all arrowheads look identical
/// regardless of which widget drew them.
void _drawArrowhead(Canvas canvas, Offset tip, double angle, Color color) {
  // Unit vector pointing in the direction the arrow travels (tip is at the
  // "front" of this direction).
  final dx = cos(angle);
  final dy = sin(angle);
  canvas.drawPath(
    Path()
      // Start the path exactly at the arrow's tip.
      ..moveTo(tip.dx, tip.dy)
      // Walk backwards along the shaft by _arrowLen, then out to one side
      // by _arrowWing (using the perpendicular (dy, -dx) direction) to
      // reach the first back corner of the triangle.
      ..lineTo(tip.dx - _arrowLen * dx + _arrowWing * dy, tip.dy - _arrowLen * dy - _arrowWing * dx)
      // Same backward step, but out to the *other* side, giving the second
      // back corner.
      ..lineTo(tip.dx - _arrowLen * dx - _arrowWing * dy, tip.dy - _arrowLen * dy + _arrowWing * dx)
      // Close back to the tip, completing the triangle.
      ..close(),
    // Solid fill (no stroke) in the caller-supplied color.
    Paint()..color = color..style = PaintingStyle.fill,
  );
}
/// CustomPainter that draws a single transition edge (the curved/straight
/// line plus its terminal arrowhead) between two states. Pre-computed
/// geometry is handed in via [geometry] — this class only knows how to
/// render it, not how to compute it (that's [LineData.computeGeometry] in
/// models.dart).
class LinePainter extends CustomPainter {
  // Straight-line or circular-arc geometry (endpoints, and, for self-loops
  // and curved edges, the supporting circle) to render.
  final LineGeometry geometry;
  // True while the canvas is in "tap something to delete it" mode; swaps
  // the stroke to [deleteColor] as a hover/afford cue.
  final bool deleteMode;
  // True while this transition is part of the active simulation step (or
  // otherwise explicitly highlighted); swaps the stroke to [highlightColor].
  final bool highlighted;
  // True when this transition is flagged by puzzle-mode validation (e.g.
  // nondeterminism); swaps the stroke to [errorColor].
  final bool isError;
  final Color defaultColor;
  final Color highlightColor;
  final Color deleteColor;
  // Falls back to a fixed red if the caller doesn't supply a theme-specific
  // error color.
  final Color errorColor;

  /// Accessibility "flash": 1.0 = fully opaque, down to a dimmer floor and
  /// back, looping. Only actually applied when [highlighted] or [isError]
  /// is true (see [_lineColor]) — passing 1.0 here is equivalent to no pulse.
  final double pulseOpacity;

  const LinePainter({
    required this.geometry,
    required this.deleteMode,
    required this.highlighted,
    this.isError = false,
    required this.defaultColor,
    required this.highlightColor,
    required this.deleteColor,
    this.errorColor = const Color(0xFFFF1744),
    this.pulseOpacity = 1.0,
  });

  /// Resolves the final stroke color for this frame: picks the base color
  /// by priority (delete > error > highlighted > default), then, if the
  /// line is in a "flash-worthy" state, applies the current [pulseOpacity]
  /// on top of it.
  Color get _lineColor {
    // Priority order matters: delete-mode hover cue wins over everything
    // else, then puzzle errors, then simulation highlighting, then the
    // theme's plain line color.
    final base = deleteMode
        ? deleteColor
        : isError
            ? errorColor
            : highlighted
                ? highlightColor
                : defaultColor;

    // Delete-mode is a transient hover cue, not a state worth flashing.
    final pulsing = !deleteMode && (highlighted || isError);
    // Only spend the alpha blend when actually pulsing; otherwise return
    // the base color untouched (pulseOpacity may be a stale/irrelevant
    // value when not pulsing).
    return pulsing ? base.withValues(alpha: pulseOpacity) : base;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      // Highlighted edges get a slightly thicker stroke so the active
      // simulation step reads clearly even without color vision.
      ..strokeWidth = highlighted ? 5 : 4
      ..color = _lineColor;

    // Curved edges (self-loops, and any transition whose geometry was
    // computed as an arc rather than a straight segment) are drawn as a
    // circular arc; everything else falls into the `else` branch below.
    if (geometry.hasCircle) {
      const double arrowLen = 15;
      // Convert the linear arrow length into an *angular* amount to trim
      // off the end of the arc, so the arrowhead (drawn separately below)
      // doesn't overlap/overdraw the arc's stroked path. arc length =
      // radius * angle, so angle = arcLength / radius.
      final double shortenAngle = arrowLen / geometry.circleRadius!;
      // The arc can sweep in either rotational direction; trimming must
      // shorten it from the "end" side regardless of sign, so mirror the
      // sign of shortenAngle to match sweepAngle's sign.
      final double signedShorten = geometry.sweepAngle! >= 0 ? shortenAngle : -shortenAngle;

      canvas.drawArc(
        Rect.fromCircle(center: geometry.circleCenter!, radius: geometry.circleRadius!),
        geometry.startAngle!,
        // Full sweep minus the trimmed-off end segment reserved for the
        // arrowhead.
        geometry.sweepAngle! - signedShorten,
        // useCenter = false: draw an open arc, not a pie-slice.
        false,
        paint,
      );

      // Arrowhead is drawn separately at the *untrimmed* endpoint/angle
      // (geometry.arrowAngle is precomputed in models.dart specifically
      // for this purpose), so its tip lands exactly where the arc would
      // have ended.
      _drawArrowhead(canvas, geometry.endPoint, geometry.arrowAngle!, _lineColor);
    } else {
      const double arrowLen = 15;
      // Straight-line case: compute the direction from start to end so we
      // know which way the arrowhead should point and which way to trim
      // the line's endpoint.
      final double angle = atan2(
        geometry.endPoint.dy - geometry.startPoint.dy,
        geometry.endPoint.dx - geometry.startPoint.dx,
      );
      // Pull the drawn line's endpoint back by arrowLen along that
      // direction, so the stroked segment stops where the arrowhead's
      // base begins instead of poking through the triangle.
      final Offset shortenedEnd = Offset(
        geometry.endPoint.dx - cos(angle) * arrowLen,
        geometry.endPoint.dy - sin(angle) * arrowLen,
      );

      // Recompute the angle from the *shortened* end to the true end.
      // For a straight line this is mathematically identical to `angle`
      // above (same direction, just measured from a point further back
      // along it) — recomputing rather than reusing `angle` keeps this
      // branch symmetric with the arc branch above, where the arrow angle
      // genuinely does differ from the raw sweep direction.
      final double angle2 =
          atan2(geometry.endPoint.dy - shortenedEnd.dy, geometry.endPoint.dx - shortenedEnd.dx);
      canvas.drawLine(geometry.startPoint, shortenedEnd, paint);

      _drawArrowhead(canvas, geometry.endPoint, angle2, _lineColor);
    }
  }

  @override
  // Repaint whenever any visual input changes. geometry is a value object
  // from models.dart (presumably with value equality), so this correctly
  // skips repainting on rebuilds where nothing actually moved or changed
  // color/state.
  bool shouldRepaint(LinePainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.highlighted != highlighted ||
      oldDelegate.isError != isError ||
      oldDelegate.deleteMode != deleteMode ||
      oldDelegate.defaultColor != defaultColor ||
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.deleteColor != deleteColor ||
      oldDelegate.errorColor != errorColor ||
      oldDelegate.pulseOpacity != pulseOpacity;
}

/// The interactive widget for a single transition edge: combines the
/// [LinePainter] (drawn line + arrowhead) with an editable text field for
/// the transition's label, positioned at the edge's midpoint. Stateful
/// because it owns the label's [TextEditingController]/[FocusNode] and an
/// accessibility pulse animation.
class LineWidget extends StatefulWidget {
  final LineData data;
  // Screen-space centers of the two nodes this transition connects.
  // Recomputed by the parent canvas every frame the nodes move, so the
  // line always tracks its endpoints live.
  final Offset centerA;
  final Offset centerB;
  final bool deleteMode;
  final bool highlighted;

  /// True when this transition is flagged as part of a puzzle-mode
  /// violation (e.g. nondeterminism, missing transition). Paints with the
  /// theme's error color and pulses alongside [highlighted], so puzzle
  /// feedback gets the same accessibility treatment as simulation
  /// highlighting.
  final bool isError;

  /// When true, the label text field is displayed but not editable — the
  /// player can still tap it to select/copy text, but keystrokes cannot
  /// change it. Used for read-only previews (e.g. study mode's "target DFA"
  /// diagram) so the label can't visibly get typed over. Does NOT affect
  /// dragging the line's curve — that's handled by the parent canvas and is
  /// still allowed so the player can reposition things for legibility.
  final bool interactionLocked;

  // Fired with the field's final text when editing ends (focus lost), so
  // the parent can persist it into the underlying LineData/model.
  final ValueChanged<String> onLabelChanged;

  const LineWidget({
    super.key,
    required this.data,
    required this.centerA,
    required this.centerB,
    required this.deleteMode,
    this.highlighted = false,
    this.isError = false,
    this.interactionLocked = false,
    required this.onLabelChanged,
  });

  @override
  State<LineWidget> createState() => _LineWidgetState();
}

class _LineWidgetState extends State<LineWidget> with SingleTickerProviderStateMixin {
  // Backs the label TextField; seeded from widget.data.label and kept in
  // sync with it (in either direction) — see didUpdateWidget below.
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  // Local echo of whether the label field currently has focus, tracked so
  // didUpdateWidget can tell "the model changed underneath us" apart from
  // "the user is mid-edit" and avoid clobbering in-progress typing.
  bool _editing = false;
  // Number of lines currently in the label, used to size the label's
  // bounding box (boxHeight = lineHeight * _lineCount in build()) since
  // labels can wrap/contain manual newlines.
  int _lineCount = 1;

  // ── Accessibility "flash" pulse ──────────────────────────────────────────
  // Loops continuously whenever this line is highlighted/errored and the
  // flashHighlights setting is on; _syncPulse starts/stops it idempotently
  // from build() so it doesn't restart mid-fade on every rebuild.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.data.label);
    // Seed the line-count from the initial label so the very first build()
    // sizes the text box correctly, before any onChanged has fired.
    _lineCount = '\n'.allMatches(widget.data.label).length + 1;
    _focusNode = FocusNode()..addListener(_onFocusChange);

    // Pulse animation used for the accessibility "flash" — a full
    // opaque-to-dim-and-back cycle takes 1.2s; started/stopped on demand
    // by _syncPulse rather than always running.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Fades between fully opaque and 30% opacity, eased in/out so the
    // pulse feels organic rather than linear/mechanical.
    _pulseOpacity = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  /// FocusNode listener: tracks edit state locally and, the moment focus is
  /// *lost* (i.e. the user tapped/tabbed away), commits the field's current
  /// text up to the parent via [LineWidget.onLabelChanged]. Nothing is
  /// committed on every keystroke — only on blur.
  void _onFocusChange() {
    final focused = _focusNode.hasFocus;

    setState(() => _editing = focused);

    if (!focused) {
      widget.onLabelChanged(_controller.text);
    }
  }

  @override
  void didUpdateWidget(LineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Pull in external label changes (e.g. programmatic edits, undo/redo,
    // loading a saved automaton) — but only while the user isn't actively
    // typing, so we never overwrite their in-progress keystrokes.
    if (!_editing && widget.data.label != _controller.text) {
      _controller.text = widget.data.label;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Idempotently starts or stops the looping pulse animation to match
  /// [shouldPulse]. Called every build() with the freshly-computed desired
  /// state; the `isAnimating`/`value` guards mean calling this repeatedly
  /// with the same answer is a no-op and won't restart the animation
  /// mid-fade (which would cause a visible stutter).
  void _syncPulse(bool shouldPulse) {
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        // reverse: true makes repeat() ping-pong between begin and end
        // instead of jumping back to begin each cycle, giving a smooth
        // breathing effect.
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating || _pulseController.value != 0) {
      _pulseController
        ..stop()
        // Reset to 0 (fully opaque, per the Tween) so the line doesn't
        // freeze mid-fade when highlighting turns off.
        ..value = 0;
    }
  }

  /// Priority-ordered label text color, mirroring [LinePainter._lineColor]'s
  /// priority (delete > error > highlighted > default) but without the
  /// pulse-opacity blend — the label text itself doesn't pulse, only the
  /// line stroke does (see build() below, where pulseOpacity is passed only
  /// to LinePainter, not used for labelColor).
  Color _labelColor(AppThemeNotifier theme) {
    return widget.deleteMode
        ? theme.error
        : widget.isError
            ? theme.error
            : widget.highlighted
                ? theme.lineHighlight
                : theme.lineColor;
  }

  @override
  Widget build(BuildContext context) {
    // Subscribing via context.watch means this whole widget rebuilds
    // whenever the app theme changes (colors, flashHighlights toggle).
    final theme = context.watch<AppThemeNotifier>();
    // Straight-line vs. arc geometry is recomputed fresh every build from
    // the current node centers, so dragging either endpoint node updates
    // the line's shape immediately.
    final geometry = widget.data.computeGeometry(widget.centerA, widget.centerB);

    // Fixed per-line box width; height grows with how many lines the
    // (possibly multi-line) label currently occupies.
    const double boxWidth = kLabelBoxWidth;
    const double lineHeight = kLabelLineHeight;
    final double boxHeight = lineHeight * _lineCount;

    // Where to place the label's text box: usually the edge's midpoint,
    // offset perpendicular to the line (exact placement logic lives in
    // LineData.getTextBoxLocation in models.dart, which also knows how to
    // handle self-loops).
    final Offset mid = widget.data.getTextBoxLocation(
      widget.centerA,
      widget.centerB,
      boxWidth,
      boxHeight,
      widget.data.label,
    );

    final labelColor = _labelColor(theme);

    // Delete-mode is a transient hover cue, not worth flashing.
    final shouldPulse = theme.flashHighlights &&
        !widget.deleteMode &&
        (widget.highlighted || widget.isError);
    _syncPulse(shouldPulse);

    return Stack(
      children: [
        // The drawn line + arrowhead sits behind the label and never
        // intercepts touches/clicks of its own (IgnorePointer) — dragging
        // and tapping on the edge is handled by the parent canvas, not by
        // this painter layer.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              // Rebuilds just this CustomPaint (not the whole widget) on
              // every pulse animation tick, so the flashing stroke is
              // cheap to animate.
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: LinePainter(
                    geometry: geometry,
                    deleteMode: widget.deleteMode,
                    highlighted: widget.highlighted,
                    isError: widget.isError,
                    defaultColor: theme.lineColor,
                    highlightColor: theme.lineHighlight,
                    deleteColor: theme.error,
                    errorColor: theme.error,
                    // Only feed the live pulse value in while actually
                    // pulsing; otherwise always fully opaque.
                    pulseOpacity: shouldPulse ? _pulseOpacity.value : 1.0,
                  ),
                );
              },
            ),
          ),
        ),
        // The editable label, positioned on top of the line at `mid`.
        Positioned(
          left: mid.dx,
          top: mid.dy,
          child: SizedBox(
            width: boxWidth,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              // See LineWidget.interactionLocked doc: read-only previews
              // can still be tapped/selected, just not typed into.
              readOnly: widget.interactionLocked,
              textAlign: TextAlign.center,
              // Unbounded line count + multiline keyboard/newline action:
              // labels can wrap onto multiple lines (e.g. long symbol
              // lists like "a,b,c").
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: GoogleFonts.courierPrime(
                fontSize: 30,
                // height: 1 keeps line spacing tight/typewriter-like
                // rather than using the font's default (larger) leading.
                height: 1,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
              onChanged: (value) {
                // Normalize raw typed input into canonical tokens (e.g.
                // arrow/epsilon shorthand) via the shared parser.
                final parsed = parseTokenText(value);
                final newLineCount = '\n'.allMatches(parsed).length + 1;

                // Grow/shrink the label box immediately as line count
                // changes, so wrapping text never gets visually clipped.
                if (newLineCount != _lineCount) {
                  setState(() => _lineCount = newLineCount);
                }

                // If parsing rewrote the text (token substitution), push
                // the corrected text back into the controller and put the
                // cursor at the end.
                if (parsed != value) {
                  _controller.value = TextEditingValue(
                    text: parsed,
                    selection: TextSelection.collapsed(offset: parsed.length),
                  );
                }
              },
              decoration: InputDecoration(
                // Fully chromeless field — no underline/border in any
                // state — so it reads as a floating label, not a form
                // input.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                // Placeholder shown for an empty/epsilon-style label.
                hintText: '~',
                isDense: true,
                hintStyle: TextStyle(
                  color: widget.deleteMode
                      ? theme.error
                      : theme.lineColor.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The free-floating arrow that points at the automaton's start state.
/// Unlike [LineWidget], it connects to only one node (the start state) and
/// its other end dangles in space at a user-adjustable angle/length — see
/// [StartArrowData.direction] in models.dart for how that's stored.
class StartArrowWidget extends StatefulWidget {
  final StartArrowData data;
  // Screen-space center of the start state's node.
  final Offset nodeCenter;

  final VoidCallback? onDelete;
  final bool deleteMode;
  final bool highlighted;

  /// When true, the label text field is displayed but not editable (see
  /// [LineWidget.interactionLocked] for rationale). Dragging the arrow to
  /// reposition it is handled by the parent canvas and is unaffected.
  final bool interactionLocked;

  const StartArrowWidget({
    super.key,
    required this.data,
    required this.nodeCenter,
    this.onDelete,
    this.deleteMode = false,
    this.highlighted = false,
    this.interactionLocked = false,
  });

  @override
  State<StartArrowWidget> createState() => _StartArrowWidgetState();
}

class _StartArrowWidgetState extends State<StartArrowWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  // Line count for the (rare, but supported) multi-line start-arrow label,
  // same purpose as _LineWidgetState._lineCount above.
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.data.label);
    _focusNode = FocusNode();

    _lineCount = '\n'.allMatches(widget.data.label).length + 1;
  }

  @override
  void didUpdateWidget(covariant StartArrowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Same external-change sync as LineWidget, but gated on focus rather
    // than a separate `_editing` flag — equivalent in effect since focus
    // is only lost after onChanged has already committed the latest text
    // into widget.data.label (see onChanged below).
    if (!_focusNode.hasFocus && _controller.text != widget.data.label) {
      _controller.text = widget.data.label;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // START ARROW GEOMETRY
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    // Unit vector from the node outward toward where the arrow's tail
    // sits — this is the user-adjustable "which way does the start arrow
    // point in from" direction.
    var dir = widget.data.direction();

    // Guard against a degenerate/undefined direction: distance == 0 means
    // no direction has been set yet (e.g. a freshly-created start arrow),
    // and (-1, 0) is called out explicitly as a direction that historically
    // produced visual issues (likely a due-north/due-west edge case in
    // whatever produced widget.data.direction()). Both fall back to a
    // fixed diagonal (up-and-to-the-left, normalized: -0.7071 ≈ -√2/2).
    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    // Fixed standoff from the node's center to where the arrow's tip
    // (`end`) sits — keeps the arrowhead just outside the node's circle
    // rather than overlapping it.
    const double radius = 50;

    // `end`: the arrow's tip, `radius` px out from the node center along
    // `dir`. `start`: further out again by the user-configurable
    // `widget.data.length`, i.e. how long the visible shaft is.
    final end = Offset(widget.nodeCenter.dx + dir.dx * radius, widget.nodeCenter.dy + dir.dy * radius);
    final start = Offset(end.dx + dir.dx * widget.data.length, end.dy + dir.dy * widget.data.length);
    // Angle of the shaft, pointing from start toward end (i.e. the
    // direction the arrowhead should face) — passed to _ArrowPainter.
    final arrowAngle = atan2(end.dy - start.dy, end.dx - start.dx);
    // Perpendicular to `dir` (rotate 90°: (x,y) -> (-y,x)), used below to
    // offset the label sideways off the shaft so it doesn't sit directly
    // on top of the line.
    final perp = Offset(-dir.dy, dir.dx);

    const double boxWidth = kLabelBoxWidth;
    const double lineHeight = kLabelLineHeight;
    final double boxHeight = lineHeight * _lineCount;

    // Place the label box centered 30px to the side of the shaft's `start`
    // end (the tail, farthest from the node), then shift by half its own
    // width/height so `labelOffset` is a top-left corner suitable for
    // Positioned.
    final labelOffset = Offset(start.dx + perp.dx * 30 - boxWidth / 2, start.dy + perp.dy * 30 - boxHeight / 2);

    return Stack(
      children: [
        // The drawn shaft + arrowhead. Sized to fill infinitely (rather
        // than a tight bounding box) because `start`/`end` are absolute
        // coordinates relative to the parent Stack, not relative to this
        // CustomPaint's own box.
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ArrowPainter(
              start: start,
              end: end,
              angle: arrowAngle,
              deleteMode: widget.deleteMode,
              strokeColor: widget.deleteMode ? theme.error : theme.lineColor,
            ),
          ),
        ),

        // The editable label, positioned off to the side of the shaft's
        // tail end (see labelOffset above).
        Positioned(
          left: labelOffset.dx,
          top: labelOffset.dy,
          child: SizedBox(
            width: boxWidth,
            // Unlike LineWidget's label, this one wraps its TextField in a
            // GestureDetector + AbsorbPointer combo: the TextField itself
            // absorbs/ignores taps (AbsorbPointer, absorbing: true), and
            // the surrounding GestureDetector is what actually handles
            // taps — routing them to either delete-mode deletion or
            // manually requesting focus. This lets a single tap both
            // dismiss any prior editing state and immediately focus this
            // field in one gesture, rather than relying on the TextField's
            // own (sometimes finicky) built-in tap-to-focus handling.
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,

              onTap: () {
                if (widget.deleteMode) {
                  widget.onDelete?.call();
                  return;
                }

                if (!_focusNode.hasFocus) {
                  FocusScope.of(context).requestFocus(_focusNode);
                }
              },

              child: AbsorbPointer(
                absorbing: true,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  readOnly: widget.interactionLocked,

                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,

                  textAlign: TextAlign.center,

                  style: GoogleFonts.courierPrime(
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.bold,
                    color: widget.deleteMode ? theme.error : theme.lineColor,
                  ),

                  // Use the shared parser from token_replacements.dart
                  onChanged: (value) {
                    final parsed = parseTokenText(value);

                    if (parsed != value) {
                      _controller.value = TextEditingValue(
                        text: parsed,
                        selection: TextSelection.collapsed(offset: parsed.length),
                      );
                    }

                    // Unlike LineWidget (which commits only on blur via
                    // onLabelChanged), the start arrow writes straight
                    // into widget.data.label on every keystroke — there's
                    // no separate onLabelChanged callback for this widget.
                    widget.data.label = parsed;

                    final newLineCount = '\n'.allMatches(parsed).length + 1;

                    if (newLineCount != _lineCount) {
                      setState(() {
                        _lineCount = newLineCount;
                      });
                    }
                  },

                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: '~',
                    isDense: true,
                    hintStyle: TextStyle(
                      color: widget.deleteMode
                          ? theme.error
                          : theme.lineColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints the start-state arrow's straight shaft plus arrowhead. Simpler
/// than [LinePainter] since the start arrow is never curved and has no
/// highlight/error state of its own — only delete-mode affects its color.
class _ArrowPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  // Precomputed shaft direction (radians); passed in rather than
  // recomputed here since the caller (build() above) already derived it
  // once for both the shaft and the label's perpendicular offset.
  final double angle;
  final bool deleteMode;
  final Color strokeColor;

  const _ArrowPainter({
    required this.start,
    required this.end,
    required this.angle,
    required this.strokeColor,
    this.deleteMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4
      ..color = strokeColor;
      // Note: no `..style = PaintingStyle.stroke` here — Paint defaults to
      // PaintingStyle.fill, but drawLine ignores `style` entirely and
      // always strokes, so this has no visible effect.

    const double arrowLen = 15;

    // Same "pull the line back so it doesn't poke through the arrowhead"
    // trick as LinePainter's straight-line branch.
    final shortenedEnd = Offset(end.dx - cos(angle) * arrowLen, end.dy - sin(angle) * arrowLen);

    canvas.drawLine(start, shortenedEnd, paint);

    _drawArrowhead(canvas, end, angle, strokeColor);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    // Always repaints unconditionally, unlike LinePainter's field-by-field
    // comparison — cheap enough for a single short arrow that it's not
    // worth the bookkeeping to skip unnecessary repaints.
    return true;
  }
}

/// Temporary line-with-arrowhead drawn while the user is dragging out a new
/// transition (link mode). Shares [_drawArrowhead] with [LinePainter] and
/// [_ArrowPainter] so the rubber-band preview matches the committed edge style.
class RubberBandPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  const RubberBandPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lineColor = color.withValues(alpha: 0.85);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = lineColor;

    final angle = atan2(end.dy - start.dy, end.dx - start.dx);
    final shortenedEnd = Offset(end.dx - cos(angle) * _arrowLen, end.dy - sin(angle) * _arrowLen);

    canvas.drawLine(start, shortenedEnd, paint);

    _drawArrowhead(canvas, end, angle, lineColor);
  }

  @override
  bool shouldRepaint(RubberBandPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.end != end || oldDelegate.color != color;
}

class Node extends StatefulWidget {
  final NodeData data;
  final bool lineMode;
  final bool interactionLocked;
  final ValueChanged<String> onLabelChanged;

  final bool Function(String label, String nodeId) isLabelTaken;
  final ValueChanged<bool>? onDuplicateStateChanged;

  final VoidCallback? onLineModeSelect;
  final VoidCallback? onDoubleTap;

  final bool deleteMode;
  final VoidCallback? onDelete;

  final bool highlighted;

  /// True when this state is flagged as part of a puzzle-mode violation
  /// (e.g. it's an extra/incorrect state, or involved in a nondeterminism
  /// error). Paints with the theme's error color and pulses alongside
  /// [highlighted], so puzzle feedback gets the same accessibility
  /// treatment as simulation highlighting.
  final bool isError;

  /// Called when the user taps the tape-routing button on a black-box node.
  final VoidCallback? onBlackBoxTapeEdit;

  /// Called when the user taps the edit-program button on a black-box node.
  final VoidCallback? onBlackBoxEdit;

  /// Total number of tapes the TM is currently configured with. Used by the
  /// node to show a mismatch warning on the tape badge when the node's
  /// [NodeData.blackBoxReadTape] or [NodeData.blackBoxWriteTape] is out of
  /// range. Defaults to 1 (no warning shown in non-TM modes).
  final int tapeCount;

  const Node({
    super.key,
    required this.data,
    required this.lineMode,
    this.interactionLocked = false,
    required this.onLabelChanged,
    required this.isLabelTaken,
    this.onDuplicateStateChanged,
    this.onLineModeSelect,
    this.onDoubleTap,
    required this.deleteMode,
    this.onDelete,
    this.highlighted = false,
    this.isError = false,
    this.onBlackBoxTapeEdit,
    this.onBlackBoxEdit,
    this.tapeCount = 1,
  });

  @override
  State<Node> createState() => _NodeState();
}

class _OctagonPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _OctagonPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final path = Path();

    const cut = 12.0;

    path.moveTo(cut, 0);
    path.lineTo(size.width - cut, 0);
    path.lineTo(size.width, cut);
    path.lineTo(size.width, size.height - cut);
    path.lineTo(size.width - cut, size.height);
    path.lineTo(cut, size.height);
    path.lineTo(0, size.height - cut);
    path.lineTo(0, cut);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NodeState extends State<Node> with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _selected = false;

  // ── Accessibility "flash" pulse ──────────────────────────────────────────
  // Loops continuously whenever this node is highlighted/duplicate/errored
  // and the flashHighlights setting is on; _syncPulse starts/stops it
  // idempotently from build() so it doesn't restart mid-fade on rebuild.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.data.label);
    _focusNode = FocusNode()..addListener(_onFocusChange);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseOpacity = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(Node oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_selected && widget.data.label != _controller.text) {
      _controller.text = widget.data.label;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _select() {
    if (!_selected) {
      setState(() => _selected = true);
      _focusNode.requestFocus();
    }
  }

  void _deselect() {
    final value = _controller.text;

    setState(() {
      _selected = false;
    });

    widget.onLabelChanged(value);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _deselect();
    }
  }

  void _syncPulse(bool shouldPulse) {
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating || _pulseController.value != 0) {
      _pulseController
        ..stop()
        ..value = 0;
    }
  }

  Color _borderColor(AppThemeNotifier theme, {required bool isDuplicate}) {
    return widget.deleteMode
        ? theme.nodeBorderDelete
        : widget.highlighted
        ? theme.nodeBorderHighlight
        : widget.isError
        ? theme.error
        : isDuplicate
        ? theme.nodeBorderDuplicate
        : _selected
        ? theme.nodeBorderSelected
        : theme.nodeBorder;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final isDuplicate = widget.isLabelTaken(_controller.text, widget.data.id);
    final borderColor = _borderColor(theme, isDuplicate: isDuplicate);

    // Delete-mode and plain "selected" are not flash-worthy states — delete
    // is a transient hover cue, and selection is just an editing cursor.
    final shouldPulse = theme.flashHighlights &&
        !widget.deleteMode &&
        (widget.highlighted || widget.isError || isDuplicate);
    _syncPulse(shouldPulse);

    // When locked (e.g. placing the start arrow), do not allow selection/editing.
    final bool textFieldActive = _selected && !widget.lineMode && !widget.interactionLocked;
    final startText = nodeIdToAlpha(widget.data.id);
    final isBlackBox = widget.data.isBlackBox;
    final nodeWidth = isBlackBox ? 140.0 : 100.0;
    final nodeHeight = 100.0;

    return Positioned(
      top: widget.data.position.dy,
      left: widget.data.position.dx,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (widget.interactionLocked) return;
          if (widget.deleteMode) {
            widget.onDelete?.call();
            return;
          }
          if (widget.lineMode) {
            widget.onLineModeSelect?.call();
          } else {
            _select();
          }
        },
        onDoubleTap: widget.onDoubleTap,
        child: SizedBox(
          width: nodeWidth,
          height: nodeHeight,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final pulseColor = shouldPulse
                  ? borderColor.withValues(alpha: _pulseOpacity.value)
                  : borderColor;
              return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: isBlackBox ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: isBlackBox ? BorderRadius.circular(10) : null,
                    border: Border.all(color: pulseColor, width: 4),
                  ),
                ),
              ),

              if (widget.data.isAccept && widget.data.canToggleNormalAccept)
                Center(
                  child: IgnorePointer(
                    child: isBlackBox
                        ? Container(
                            width: 118,
                            height: 78,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: pulseColor, width: 3),
                            ),
                          )
                        : Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: pulseColor, width: 4),
                            ),
                          ),
                  ),
                ),

              if (widget.data.isHaltAccept)
                Center(
                  child: IgnorePointer(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.acceptState,
                        border: Border.all(color: pulseColor, width: 4),
                      ),
                    ),
                  ),
                ),

              if (widget.data.isHaltReject)
                Center(
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size(60, 60),
                      painter: _OctagonPainter(color: theme.rejectState, borderColor: pulseColor),
                    ),
                  ),
                ),

              Center(
                child: SizedBox(
                  width: isBlackBox ? 118 : 80,
                  child: IgnorePointer(
                    ignoring: !textFieldActive,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: isBlackBox ? 20 : 30,
                        color: borderColor,
                      ),
                      textAlign: TextAlign.center,
                      onEditingComplete: _deselect,
                      onTapOutside: (_) => _deselect(),

                      onChanged: (value) {
                        // Use the shared parser from token_replacements.dart
                        final parsed = parseTokenText(value);

                        String finalText = parsed;

                        bool haltAccept = false;
                        bool haltReject = false;

                        if (parsed.startsWith('<<') && parsed.endsWith('>>')) {
                          haltAccept = true;
                          finalText = parsed.substring(2, parsed.length - 2);
                        } else if (parsed.startsWith('>>') && parsed.endsWith('<<')) {
                          haltReject = true;
                          finalText = parsed.substring(2, parsed.length - 2);
                        }

                        widget.data.applyHaltFromLabel(
                          haltAccept: haltAccept,
                          haltReject: haltReject,
                        );

                        if (finalText != _controller.text) {
                          _controller.value = TextEditingValue(
                            text: finalText,
                            selection: TextSelection.collapsed(offset: finalText.length),
                          );
                        }

                        setState(() {});
                      },

                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        hintText: isBlackBox ? 'BLACK BOX' : startText,
                        hintStyle: TextStyle(
                          color: widget.deleteMode
                              ? theme.nodeBorderDelete
                              : theme.nodeBorder.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Black-box bottom bar
              // Shows the edit-program button so the inner DSL remains
              // accessible. Tape routing is now encoded directly in outgoing
              // line labels (RWD triples per tape) so the old R:/W: badge
              // and tape-routing dialog are no longer needed here.
              if (isBlackBox)
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Edit-program button
                      if (!widget.deleteMode && !widget.interactionLocked)
                        Tooltip(
                          message: 'Edit program',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.lineMode
                                ? null
                                : widget.onBlackBoxEdit,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: theme.bg.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: borderColor.withValues(alpha: 0.55),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.edit_note,
                                size: 14,
                                color: borderColor.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
              );
            },
          ),
        ),
      ),
    );
  }
}
