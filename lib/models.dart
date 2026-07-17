import 'package:flutter/material.dart';
import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
//  Shared utility: base-26 node ID → letter label
// ─────────────────────────────────────────────────────────────────────────────

/// Converts an internal node id like `"n0"`, `"n1"`, … `"n25"`, `"n26"` into
/// the spreadsheet-column-style letter label a user actually sees: A, B, …,
/// Z, AA, AB, …, ZZ, AAA, … This is a *bijective* base-26 encoding (there is
/// no "digit zero" — after Z comes AA, not "A0"), which is why the loop below
/// isn't a plain base conversion.
String nodeIdToAlpha(String rawId) {
  // Strip the leading "n" and parse the numeric part, e.g. "n7" -> 7.
  final number = int.tryParse(rawId.replaceFirst('n', ''));
  // Anything that isn't a well-formed "n<number>" id (or is negative) is
  // returned unchanged — callers such as black-box nodes or malformed ids
  // fall back to showing the raw id rather than crashing on a bad parse.
  if (number == null || number < 0) return rawId;
  int n = number;
  String result = '';
  // do/while (not while) so n = 0 still runs the body once and produces 'A'
  // instead of an empty string.
  do {
    // n % 26 picks the current letter (0='A' .. 25='Z'), prepended so the
    // most-significant letter ends up first as n shrinks across iterations.
    result = String.fromCharCode(65 + (n % 26)) + result;
    // The "-1" here is what makes this bijective base-26 rather than a
    // normal base-26 conversion: without it, n=26 would produce "BA"
    // (treating 26 as "1,0" in base 26); with it, n=26 correctly rolls over
    // to "AA" the same way a spreadsheet's columns go ...Z, AA, AB....
    n = (n ~/ 26) - 1;
  } while (n >= 0);
  return result;
}

/// Picks the label to display for [nodeId] in the UI: the user-entered
/// label if there is one (disambiguated if it collides with another node's
/// label), otherwise the auto-generated letter name from [nodeIdToAlpha].
String displayNodeLabel(String nodeId, Map<String, NodeData> nodes) {
  final node = nodes[nodeId];
  // Id not found in the map at all — nothing sensible to show but the raw id.
  if (node == null) return nodeId;

  final trimmedLabel = node.label.trim();
  // No user-entered label: fall back to the auto letter name (A, B, AA, …).
  if (trimmedLabel.isEmpty) {
    return nodeIdToAlpha(node.id);
  }

  // Look for any *other* node whose (trimmed) label is exactly the same
  // text — two states can otherwise easily end up both labeled e.g. "q0" if
  // the user copy-pasted or renamed carelessly.
  final hasDuplicate = nodes.values.any(
    (other) => other.id != node.id && other.label.trim() == trimmedLabel,
  );

  // Unique label: show it plain, no need to disambiguate.
  if (!hasDuplicate) return trimmedLabel;

  // Duplicate label: append the internal id (uppercased, e.g. "N3") so the
  // two same-named states remain visually distinguishable, e.g. "q0:N3".
  return '$trimmedLabel:${node.id.toUpperCase()}';
}

// ─────────────────────────────────────────────────────────────────────────────
//  NodeData
// ─────────────────────────────────────────────────────────────────────────────

/// A single state/node in an automaton graph: its position, visual flags,
/// and (for Turing-machine "black box" nodes) the sub-program it represents.
class NodeData {
  // Stable identity for this node (e.g. "n0"); never reassigned after
  // construction, so lines/edges can safely key off it long-term.
  final String id;

  Offset position;  // top-left of the node's bounding box (see `center` below)
  String label;     // user-entered display text; may be empty (see displayNodeLabel)

  bool isAccept;       // draws the normal double-ring "accepting state" indicator
  bool isHaltAccept;   // Turing-machine halt-and-accept state (own visual, not the ring)
  bool isHaltReject;   // Turing-machine halt-and-reject state (own visual, not the ring)
  bool isBlackBox;     // renders as a wider rectangular "sub-program" box instead of a circle
  String blackBoxDescription; // free-text human summary shown on/near the box
  String blackBoxDsl;         // the actual DSL source of the black box's sub-program

  /// 1-based index of the tape this black-box reads from.
  int blackBoxReadTape;

  /// 1-based index of the tape this black-box writes to / edits.
  int blackBoxWriteTape;

  /// 1-based tape indices that this black box's outgoing-line compact
  /// triples ("RWD" per tape, e.g. `10R`) address, in the order given.
  ///
  /// Empty (the default) preserves the original behavior: a label of N
  /// triples maps triple i → tape i+1 in order, so a box that only wants to
  /// touch tape 3 of a 3-tape machine must pad with placeholders for the
  /// tapes it doesn't care about — e.g. `~~S~~S10R`.
  ///
  /// When set — e.g. `[3]` — every outgoing line's label only needs to
  /// spell out the tapes listed here, in this order. So with
  /// `blackBoxActiveTapes = [3]`, the label `10R` alone means "tape 3: read
  /// 1, write 0, move Right" — no padding needed. Every tape *not* listed
  /// is left completely untouched when the transition fires, exactly as if
  /// it had an explicit `~~S` triple.
  List<int> blackBoxActiveTapes;

  // Ids of every LineData currently attached to this node (either end).
  // Kept as a Set (not a List) since a node/line pair is either connected or
  // it isn't — duplicates would be meaningless — and Set membership tests
  // (used when cleaning up a deleted node's lines) are O(1).
  final Set<String> connectedLineIds = {};

  NodeData({
    required this.id,
    required this.position,
    this.label = '',
    this.isAccept = false,
    this.isHaltAccept = false,
    this.isHaltReject = false,
    this.isBlackBox = false,
    this.blackBoxDescription = '',
    this.blackBoxDsl = '',
    this.blackBoxReadTape = 1,
    this.blackBoxWriteTape = 1,
    List<int>? blackBoxActiveTapes,
    // Dart constructor defaults must be const, so a mutable `[]` can't be
    // written directly in the parameter list above (that would risk every
    // instance sharing one literal list, depending on how the const pool
    // works). Taking a nullable parameter and materializing a fresh empty
    // list here guarantees each NodeData gets its own independent list.
  }) : blackBoxActiveTapes = blackBoxActiveTapes ?? <int>[];

  bool get isHaltState => isHaltAccept || isHaltReject;

  /// Halt states cannot start outgoing transitions.
  bool get canHaveOutgoingTransitions => !isHaltState;

  /// Halt states use their own accept/reject visuals, not the normal accept ring.
  bool get canToggleNormalAccept => !isHaltState;

  /// Sets the two halt flags from parsed label text, and — since halt states
  /// render their own accept/reject indicator rather than the normal
  /// double-ring — clears the ordinary `isAccept` flag whenever the node
  /// becomes a halt state, so the two visual systems never both apply at once.
  void applyHaltFromLabel({required bool haltAccept, required bool haltReject}) {
    isHaltAccept = haltAccept;
    isHaltReject = haltReject;
    if (isHaltState) isAccept = false;
  }

  /// The node's visual centre point. Black-box nodes are drawn as a wider
  /// 140×100 rectangle (see `containsPoint` below), so their centre sits at
  /// +70/+50 from `position`; ordinary circular nodes use a 100×100 box
  /// centred at +50/+50.
  Offset get center => isBlackBox
      ? Offset(position.dx + 70, position.dy + 50)
      : Offset(position.dx + 50, position.dy + 50);

  /// Hit-test used for taps/drags: is [point] inside this node's shape?
  bool containsPoint(Offset point) {
    if (isBlackBox) {
      // Rectangular hit box matching the 140×100 black-box visual.
      return point.dx >= position.dx &&
          point.dx <= position.dx + 140 &&
          point.dy >= position.dy &&
          point.dy <= position.dy + 100;
    }
    // Circular hit box: point is inside if its squared distance from
    // `center` is within radius 50 squared (avoids an unnecessary sqrt).
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return dx * dx + dy * dy <= 50 * 50;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LineData
// ─────────────────────────────────────────────────────────────────────────────

// Compiled once at module level — avoids re-allocating on every simulation step.
final _labelSplitter = RegExp(r'[,\n]');

// ─────────────────────────────────────────────────────────────────────────────
//  Self-loop geometry constants
//
//  Shared by LineData.computeGeometry / getTextBoxLocation below AND by
//  study_mode_pda.dart's layout post-processor, which has to reproduce this
//  geometry ahead of time to keep nodes clear of self-loops. Previously the
//  layout post-processor re-typed these as separate hardcoded literals with
//  a comment saying "from models.dart" — if these ever changed here, that
//  copy would silently go stale. Import and reference these instead.
// ─────────────────────────────────────────────────────────────────────────────

/// Radius of the circle drawn for a self-loop.
const double kSelfLoopRadius = 35.0;

/// Distance from the owning node's centre to the self-loop circle's centre.
const double kSelfLoopCenterDistance = 65.0;

/// Distance from the self-loop circle's edge to its label textbox centre.
const double kSelfLoopTextDistance = 65.0;

/// Width of a transition-label textbox, as rendered by LineWidget and
/// StartArrowWidget in graph_widgets.dart. Also used by the study-mode
/// layout post-processors (study_mode_pda.dart, study_mode_screen.dart) to
/// predict label placement ahead of the actual render — previously each of
/// those four call sites re-typed "120" by hand.
const double kLabelBoxWidth = 120.0;

/// Height of a single line of transition-label text — multiply by the
/// number of lines in a label to get the full textbox height. Same
/// four-way duplication concern as [kLabelBoxWidth].
const double kLabelLineHeight = 36.0;

/// A transition edge between two nodes (or a self-loop, when [nodeAId] ==
/// [nodeBId]). Owns both the raw data (label, curvature) and the geometry
/// math needed to turn that data into drawable points/arcs.
class LineData {
  // Stable identity for this edge.
  final String id;

  // The two endpoints. Immutable by design: retargeting a transition to a
  // different node means creating a new LineData, not mutating one in place.
  final String nodeAId;
  final String nodeBId;

  // How far (and to which side) the line's control point is displaced from
  // the straight A→B midpoint. 0 (or anything with |value| <= 5, see
  // computeGeometry) draws a straight line; positive/negative bow the curve
  // to one side or the other. Not used for self-loops.
  double perpendicularPart;

  // Angle (radians) pointing outward from the owning node toward where a
  // self-loop's circle sits. Default -pi/2 is "straight up" (screen Y grows
  // downward, so a negative Y direction points up).
  double selfLoopAngle;

  String label;

  LineData({
    required this.id,
    required this.nodeAId,
    required this.nodeBId,
    this.perpendicularPart = 0,
    this.selfLoopAngle = -pi / 2,
    this.label = '',
  });

  /// Split this line's label into its individual alternatives (comma- or
  /// newline-separated), trimmed.  Used by the FA simulator hot-path.
  List<String> get labelAlternatives =>
      label.split(_labelSplitter).map((s) => s.trim()).toList();

  /// The curve's control/"bend" point: the midpoint between [centerA] and
  /// [centerB], displaced perpendicular to the A→B line by
  /// [perpendicularPart]. A straight line (perpendicularPart == 0) reduces
  /// this to the plain midpoint.
  Offset anchorPoint(Offset centerA, Offset centerB) {
    final dx = centerB.dx - centerA.dx;
    final dy = centerB.dy - centerA.dy;
    final scale = sqrt(dx * dx + dy * dy); // distance between the two centres
    // Coincident centres would make the perpendicular direction undefined;
    // in practice this case is a self-loop and is handled by the callers'
    // own self-loop branches before reaching here, but guard anyway.
    if (scale == 0) return centerA;
    // Unit vector perpendicular to A→B, obtained by rotating the normalized
    // (dx, dy) direction 90°: (dx, dy) -> (dy, -dx).
    final perpDx = dy / scale;
    final perpDy = -dx / scale;
    return Offset(
      centerA.dx + dx * 0.5 + perpDx * perpendicularPart,
      centerA.dy + dy * 0.5 + perpDy * perpendicularPart,
    );
  }

  /// Top-left corner at which to draw this line's label textbox (size
  /// [width] × [height]), given the two node centres and the (possibly
  /// multi-line) [label] text.
  Offset getTextBoxLocation(Offset centerA, Offset centerB, double width, double height, String label) {
    final dx = centerB.dx - centerA.dx;
    final dy = centerB.dy - centerA.dy;
    final scale = sqrt(dx * dx + dy * dy);

    // ── Self-loop case: centres coincide (within 1px) ─────────────────────
    if ((centerA - centerB).distance < 1) {
      // Reuse the same arc math computeGeometry uses, so the label always
      // tracks the loop's actual on-screen circle rather than an
      // independently-guessed position.
      final geometry = computeGeometry(centerA, centerB);
      final loopCenter = geometry.circleCenter!;
      final radius = geometry.circleRadius!;
      final angle = selfLoopAngle;
      final outward = Offset(cos(angle), sin(angle));
      const textDistance = kSelfLoopTextDistance;
      // Textbox sits further out along the same outward direction as the
      // loop itself, past the circle's edge by `textDistance`.
      final textCenter = Offset(
        loopCenter.dx + outward.dx * (radius + textDistance),
        loopCenter.dy + outward.dy * (radius + textDistance),
      );
      return Offset(textCenter.dx - width / 2, textCenter.dy - height / 2);
    }

    // Same degenerate guard as anchorPoint — shouldn't be reachable given
    // the self-loop branch above already handles coincident centres, but
    // kept for safety.
    if (scale == 0) return centerA;

    final perpDx = dy / scale;
    final perpDy = -dx / scale;
    const double fontSize = 30; // rough estimate of the label's rendered font size, in px
    // Which side of the line the box should sit on, matching whichever way
    // the curve itself bends (so the label never crosses over the arc).
    final double fontScale = perpendicularPart < 0 ? -1 : 1;

    // Longest individual line of (possibly multi-line) label text, and how
    // many lines it has — both feed the heuristic width/height offset below.
    int textLength = 0;
    label.split('\n').forEach((line) {
      if (line.length > textLength) textLength = line.length;
    });
    final int numberOfLines = label.split('\n').length;

    // Heuristic offset that nudges the textbox further from the line as the
    // label text gets longer/taller, so long labels don't end up centred
    // right on top of the curve. The magic numbers (9px/char, 25px pad,
    // fontSize/4 per extra line) are tuned to roughly match the actual
    // rendered text size rather than derived from an exact formula.
    final double whw = width / 2 - 9 * perpDx * fontScale * textLength - 25 * perpDx * fontScale;
    double whh = height / 2 - perpDy * fontScale * fontSize * numberOfLines / 2;
    if (fontScale * perpDy < 0 && numberOfLines > 1) {
      whh -= perpDy * fontScale * fontSize * (numberOfLines / 4);
    }

    final wh = Offset(whw, whh);
    // Start from the curve's anchor/midpoint, push one extra `fontSize`
    // further out along the perpendicular (so the box clears the line
    // itself rather than sitting right on it), then shift by `wh` to land
    // on the box's top-left corner instead of its centre.
    return Offset(
      centerA.dx + dx * 0.5 + perpDx * perpendicularPart - wh.dx,
      centerA.dy + dy * 0.5 + perpDy * (perpendicularPart + fontScale * fontSize) - wh.dy,
    );
  }

  /// Alias for [anchorPoint] — same computation, kept as a separate name for
  /// call sites that think of it as "the curve's midpoint" rather than "the
  /// curve's bend control point".
  Offset midPoint(Offset centerA, Offset centerB) => anchorPoint(centerA, centerB);

  /// Hit-test for taps/drags on the line itself (not its endpoints).
  bool containsPoint(Offset point, Offset centerA, Offset centerB) {
    if ((centerA - centerB).distance < 1) {
      // Self-loop: hit if the point falls within a 25px-wide ring around
      // the loop circle's circumference (rather than requiring an exact
      // on-the-circle tap).
      final geometry = computeGeometry(centerA, centerB);
      final center = geometry.circleCenter!;
      final radius = geometry.circleRadius!;
      final dx = point.dx - center.dx;
      final dy = point.dy - center.dy;
      final dist = sqrt(dx * dx + dy * dy);
      return (dist - radius).abs() < 25;
    }

    // Non-self-loop: approximate the whole line by its anchor/midpoint and
    // accept taps within 50px of that single point. Simple, and adequate
    // given how gently these curves bend in practice, but it does mean a
    // tap near one of the line's *ends* (far from the midpoint) on a long
    // or sharply-curved line may not register.
    final anchor = anchorPoint(centerA, centerB);
    final dx = point.dx - anchor.dx;
    final dy = point.dy - anchor.dy;
    return dx * dx + dy * dy <= 50 * 50;
  }

  /// The point on the radius-50 circle around [center], in the direction of
  /// [target]. Used to trim a line's drawn start/end so it stops at a
  /// node's visual boundary instead of its exact centre.
  static Offset _closestOnCircle(Offset center, Offset target) {
    final dx = target.dx - center.dx;
    final dy = target.dy - center.dy;
    final dist = sqrt(dx * dx + dy * dy);
    // target coincides with center: no well-defined direction, so just
    // return the centre itself rather than dividing by zero.
    if (dist == 0) return center;
    return Offset(center.dx + dx * 50 / dist, center.dy + dy * 50 / dist);
  }

  /// Computes full drawable geometry (straight segment or arc, plus arrow
  /// angle) for this line between [centerA] and [centerB].
  LineGeometry computeGeometry(Offset centerA, Offset centerB) {
    // ── Self loop ────────────────────────────────────────────────
    if ((centerA - centerB).distance < 1) {
      final angle = selfLoopAngle;
      final outward = Offset(cos(angle), sin(angle));
      const loopRadius = kSelfLoopRadius;
      const centerDistance = kSelfLoopCenterDistance;
      // The loop's own circle centre sits offset from the node, out along
      // the chosen `selfLoopAngle` direction.
      final circleCenter = Offset(
        centerA.dx + outward.dx * centerDistance,
        centerA.dy + outward.dy * centerDistance,
      );
      // Angle (from the loop circle's centre) pointing back at the owning
      // node — i.e. the direction "into" the node.
      final towardNodeAngle = atan2(centerA.dy - circleCenter.dy, centerA.dx - circleCenter.dx);
      // The loop isn't drawn as a full circle: it leaves a small gap facing
      // the node (so the arc has a visible start/end rather than looking
      // like a closed ring merged into the node), sized by gapAngle on
      // either side of `towardNodeAngle`.
      const gapAngle = 0.85;
      final startAngle = towardNodeAngle + gapAngle;
      final sweepAngle = 2 * pi - (gapAngle * 2);
      final endAngle = startAngle + sweepAngle;
      final startPt = Offset(circleCenter.dx + loopRadius * cos(startAngle), circleCenter.dy + loopRadius * sin(startAngle));
      final endPt = Offset(circleCenter.dx + loopRadius * cos(endAngle), circleCenter.dy + loopRadius * sin(endAngle));
      // Point diametrically opposite the gap — the "far side" of the loop,
      // farthest from the owning node.
      final midAngle = startAngle + sweepAngle / 2;
      final midPt = Offset(circleCenter.dx + loopRadius * cos(midAngle), circleCenter.dy + loopRadius * sin(midAngle));
      return LineGeometry.arc(
        startPoint: startPt,
        endPoint: endPt,
        midPoint: midPt,
        circleCenter: circleCenter,
        circleRadius: loopRadius,
        startAngle: startAngle,
        sweepAngle: sweepAngle,
        // Arrowhead angle: perpendicular to the radius at the end point
        // (tangent direction), with a small -pi/12 (~15°) adjustment so the
        // arrowhead visually points back into the loop rather than dead-on
        // perpendicular.
        arrowAngle: endAngle + pi / 2 - pi / 12,
      );
    }

    // ── Straight line ────────────────────────────────────────────
    // Below this curvature threshold the bend is visually imperceptible, so
    // just draw a straight segment rather than fitting an arc through it.
    if (perpendicularPart.abs() <= 5) {
      final mid = Offset((centerA.dx + centerB.dx) / 2, (centerA.dy + centerB.dy) / 2);
      // Trim both ends to sit on each node's boundary circle (facing the
      // midpoint) rather than at the exact node centres.
      final start = _closestOnCircle(centerA, mid);
      final end = _closestOnCircle(centerB, mid);
      return LineGeometry.straight(
        startPoint: start,
        endPoint: end,
        midPoint: Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2),
      );
    }

    // ── Normal arc ───────────────────────────────────────────────
    // The curve is defined as the unique circle passing through both node
    // centres and the bend/anchor point; anchor is pulled off-centre by
    // `perpendicularPart`, so this two-point-plus-anchor circle always
    // exists unless the three points end up (nearly) collinear.
    final anchor = anchorPoint(centerA, centerB);

    // Generic 3x3 determinant, used below to solve for the circle passing
    // through three given points (circumcircle formula).
    double det(double a, double b, double c, double d, double e, double f, double g, double h, double i) {
      return a * e * i + b * f * g + c * d * h - a * f * h - b * d * i - c * e * g;
    }

    // Degenerate-case fallback: identical to the "straight line" branch
    // above, reused if the three points don't determine a finite circle.
    LineGeometry straightFallback() {
      final mid = Offset((centerA.dx + centerB.dx) / 2, (centerA.dy + centerB.dy) / 2);
      final start = _closestOnCircle(centerA, mid);
      final end = _closestOnCircle(centerB, mid);
      return LineGeometry.straight(
        startPoint: start,
        endPoint: end,
        midPoint: Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2),
      );
    }

    // Standard circumcenter/circumradius-via-determinants construction:
    // solves for the centre (x, y) and radius of the circle through
    // (x1,y1), (x2,y2), (x3,y3). Returns null when the points are (nearly)
    // collinear — the `a` determinant vanishes and no finite circle fits —
    // or when the resulting radius comes out non-finite/degenerate.
    List<double>? circleFromThreePoints(double x1, double y1, double x2, double y2, double x3, double y3) {
      final a = det(x1, y1, 1, x2, y2, 1, x3, y3, 1);
      if (a.abs() < 1e-6) return null;
      final bx = -det(x1 * x1 + y1 * y1, y1, 1, x2 * x2 + y2 * y2, y2, 1, x3 * x3 + y3 * y3, y3, 1);
      final by = det(x1 * x1 + y1 * y1, x1, 1, x2 * x2 + y2 * y2, x2, 1, x3 * x3 + y3 * y3, x3, 1);
      final c = -det(x1 * x1 + y1 * y1, x1, y1, x2 * x2 + y2 * y2, x2, y2, x3 * x3 + y3 * y3, x3, y3);
      final x = (-bx) / (2 * a);
      final y = (-by) / (2 * a);
      final radius = sqrt(bx * bx + by * by - 4 * a * c) / (2 * a.abs());
      if (!radius.isFinite || radius < 1e-6) return null;
      return [x, y, radius];
    }

    final circle = circleFromThreePoints(centerA.dx, centerA.dy, centerB.dx, centerB.dy, anchor.dx, anchor.dy);
    if (circle == null) return straightFallback();
    final cx = circle[0];
    final cy = circle[1];
    final r = circle[2];
    // Which way around the circle the arc should sweep, matching the side
    // the anchor (and therefore perpendicularPart) bends toward.
    final direction = perpendicularPart > 0 ? 1.0 : -1.0;

    // Angles from the circle's centre to each node's centre...
    double startAngle = atan2(centerA.dy - cy, centerA.dx - cx);
    double endAngle = atan2(centerB.dy - cy, centerB.dx - cx);
    // ...then nudged inward by (50 / r) radians — an angular approximation
    // of "move 50px (the node radius) along the circle's circumference" —
    // so the drawn arc starts/ends at each node's boundary rather than at
    // its exact centre. The nudge direction follows `direction` so both
    // ends move consistently toward the interior of the intended sweep.
    startAngle += direction * (50 / r);
    endAngle -= direction * (50 / r);

    double sweepAngle;
    if (direction > 0) {
      // Unwrap endAngle forward by full turns until it's ahead of
      // startAngle, so the arc sweeps the intended (counter-clockwise-ish)
      // way around rather than whatever short way atan2's wrapping implies.
      while (endAngle < startAngle) {
        endAngle += 2 * pi;
      }
      sweepAngle = endAngle - startAngle;
    } else {
      // Mirror image of the above for the opposite sweep direction.
      while (startAngle < endAngle) {
        startAngle += 2 * pi;
      }
      sweepAngle = endAngle - startAngle;
    }

    final startPt = Offset(cx + r * cos(startAngle), cy + r * sin(startAngle));
    final endPt = Offset(cx + r * cos(endAngle), cy + r * sin(endAngle));
    final midAngle = startAngle + sweepAngle / 2;
    final midPt = Offset(cx + r * cos(midAngle), cy + r * sin(midAngle));

    return LineGeometry.arc(
      startPoint: startPt,
      endPoint: endPt,
      midPoint: midPt,
      circleCenter: Offset(cx, cy),
      circleRadius: r,
      startAngle: startAngle,
      sweepAngle: sweepAngle,
      // Tangent-perpendicular angle at the arc's end point, oriented by
      // `direction`, so the arrowhead appears to follow the curve into the
      // destination node rather than pointing along some unrelated angle.
      arrowAngle: endAngle + direction * (pi / 2),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  StartArrowData
// ─────────────────────────────────────────────────────────────────────────────

/// The free-floating arrow that marks an automaton's start state — it has no
/// source node of its own, just a direction/length pointing into [nodeId].
class StartArrowData {
  String nodeId;     // the state this arrow points into
  Offset offset;      // (unnormalized) direction the arrow's tail extends from the node
  double length;      // shaft length, in px
  String label;       // rarely-used text near the arrow (often empty)

  StartArrowData({required this.nodeId, this.offset = const Offset(-1, 0), this.length = 100, this.label = ''});

  /// Normalized direction the arrow points, derived from [offset].
  Offset direction() {
    final dist = offset.distance;
    // Zero-length offset has no defined direction; fall back to the
    // default leftward heading rather than producing NaN.
    if (dist == 0) return const Offset(-1, 0);
    return Offset(offset.dx / dist, offset.dy / dist);
  }

  /// True when [point] is near the start-arrow shaft or tail (for drag/delete).
  bool containsPoint(Offset point, Offset nodeCenter, {double tapRadius = 44}) {
    var dir = direction();
    // Special-cases the (-1, 0) default direction (as well as a genuinely
    // zero-length offset): rather than a literal due-left heading, the
    // default start arrow is instead treated here as pointing diagonally
    // up-left. This keeps the tap target lined up with however the default
    // start arrow is actually drawn on screen (see the widget that renders
    // it) instead of assuming a plain horizontal shaft.
    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    const radius = 50.0; // matches NodeData's circular hit/visual radius
    // `end` sits on the node's boundary circle in direction `dir`; `tail` is
    // further out from there by the full shaft `length`.
    final end = Offset(nodeCenter.dx + dir.dx * radius, nodeCenter.dy + dir.dy * radius);
    final tail = Offset(end.dx + dir.dx * length, end.dy + dir.dy * length);

    // Direct hit on the tail end of the shaft.
    if ((point - tail).distance < tapRadius) return true;

    // Otherwise, project `point` onto the shaft segment (tail -> end) and
    // test distance to the closest point on that segment — standard
    // point-to-segment distance via a clamped scalar projection `t`.
    final seg = end - tail;
    final lenSq = seg.dx * seg.dx + seg.dy * seg.dy;
    if (lenSq == 0) return false; // degenerate zero-length shaft: nothing to hit-test against
    final t = ((point.dx - tail.dx) * seg.dx + (point.dy - tail.dy) * seg.dy) / lenSq;
    final proj = Offset(
      tail.dx + seg.dx * t.clamp(0.0, 1.0),
      tail.dy + seg.dy * t.clamp(0.0, 1.0),
    );
    return (point - proj).distance < tapRadius;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LineGeometry
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable output of [LineData.computeGeometry]: everything a widget needs
/// to actually paint a transition line — either a straight segment or an arc
/// — plus where to place its arrowhead.
class LineGeometry {
  // Discriminates which of the two named constructors built this instance;
  // when false, all the arc-only fields below are null.
  final bool hasCircle;

  final Offset startPoint;
  final Offset endPoint;
  final Offset midPoint;

  // Only populated for arcs (including self-loops); null for straight lines.
  final Offset? circleCenter;
  final double? circleRadius;
  final double? startAngle;
  final double? sweepAngle;
  final double? arrowAngle;

  const LineGeometry.straight({required this.startPoint, required this.endPoint, required this.midPoint})
      : hasCircle = false,
        circleCenter = null,
        circleRadius = null,
        startAngle = null,
        sweepAngle = null,
        arrowAngle = null;

  const LineGeometry.arc({
    required this.startPoint,
    required this.endPoint,
    required this.midPoint,
    required this.circleCenter,
    required this.circleRadius,
    required this.startAngle,
    required this.sweepAngle,
    required this.arrowAngle,
  }) : hasCircle = true;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Canonical automaton layout post-processor
//
//  Runs a convergence loop that pushes nodes apart so that:
//
//    A. No two nodes' circles overlap each other.
//    B. No node sits on top of the straight chord between two OTHER nodes it
//       isn't connected to.
//    C. No node overlaps another line's label textbox.
//    D. No node overlaps a self-loop (circle or label textbox) that isn't its
//       own.
//    E. When a single node has multiple self-loops, their angles are spread
//       out evenly so their labels don't stack on top of each other.
//
//  This is the single shared implementation used by:
//    • study mode's read-only solution previews (PDA and regex/DFA),
//    • the regex-to-NFA/DFA sandbox conversion (regex_engine.dart),
//    • DSL import (import_export.dart),
//  — any place that builds or lays out a graph programmatically rather than
//  from live user dragging (drag-and-drop already avoids overlap interactively
//  and isn't touched by this function).
//
//  The algorithm only ever *moves nodes apart* when a clearance check fails,
//  so it is convergent and a no-op on a layout that's already well-formed —
//  safe to call unconditionally, including on round-tripped positions.
// ─────────────────────────────────────────────────────────────────────────────

/// Applies the canonical collision-avoidance layout pass to [nodes] and
/// [lines] in place.
///
/// [setDefaultPerpendicular] — when true (the default, matching the original
/// study-mode behavior), every non-self-loop line is given a default
/// perpendicularPart of 30 before the convergence loop runs, so transitions
/// arc gently instead of drawing as perfectly straight, easily-overlapping
/// lines. Callers that already assign their own curvature (e.g. the regex
/// engine's bidirectional-pair bending, or DSL-imported explicit curve
/// values) should pass false to avoid clobbering it.
void applyAutomatonLayout(
  Map<String, NodeData> nodes,
  Map<String, LineData> lines, {
  bool setDefaultPerpendicular = true,
}) {
  // ── Pass 1: default perpendicularPart on all non-self-loop lines ───────────
  if (setDefaultPerpendicular) {
    for (final line in lines.values) {
      if (line.nodeAId != line.nodeBId) {
        line.perpendicularPart = 30.0;
      }
    }
  }

  // ── Shared constants ───────────────────────────────────────────────────────
  const double nodeRadius     = 50.0;               // visual radius of a state circle
  const double nodeDiameter   = nodeRadius * 2;
  const double minNodeGap     = nodeDiameter + 40.0; // minimum centre-to-centre distance
  const double clearance      = nodeRadius + 30.0;   // min dist: node centre ↔ chord
  const double textBuffer     = 14.0;                // extra padding around textbox rect
  const double boxWidth       = kLabelBoxWidth;       // must match LineWidget — see above
  const double lineHeight     = kLabelLineHeight;      // single-line height in LineWidget — see above
  const double selfLoopRadius = kSelfLoopRadius;       // loop circle radius — see above
  const double selfLoopCenterDist = kSelfLoopCenterDistance; // centre offset for loop — see above
  const int    iterations     = 30;                  // convergence passes

  // Helper: push node away from an axis-aligned rect.
  // Returns true if a push was applied.
  bool pushNodeFromRect(
    NodeData node,
    double rLeft,
    double rTop,
    double rRight,
    double rBottom,
  ) {
    final nc = node.center;
    // Closest point on the rect to the node centre (clamping handles the
    // node being anywhere: inside, beside an edge, or off a corner).
    final closestX = nc.dx.clamp(rLeft, rRight);
    final closestY = nc.dy.clamp(rTop, rBottom);
    final dxFromBox = nc.dx - closestX;
    final dyFromBox = nc.dy - closestY;
    final distFromBox = sqrt(dxFromBox * dxFromBox + dyFromBox * dyFromBox);

    if (distFromBox < nodeRadius) {
      final push = nodeRadius - distFromBox + 2.0; // +2 px safety margin

      final Offset pushDir;
      if (distFromBox < 0.5) {
        // Node centre is (essentially) inside the rect, so dxFromBox/
        // dyFromBox are ~zero and don't give a usable push direction.
        // Instead push away from the rect's own centre.
        final rcx = (rLeft + rRight) / 2;
        final rcy = (rTop + rBottom) / 2;
        final awayDx = nc.dx - rcx;
        final awayDy = nc.dy - rcy;
        final awayLen = sqrt(awayDx * awayDx + awayDy * awayDy);
        // Node centre also happens to coincide with the rect's centre
        // exactly (awayLen ~ 0 too) — arbitrarily push straight down
        // rather than leaving it stuck with no direction at all.
        pushDir = awayLen < 0.5
            ? const Offset(0, 1)
            : Offset(awayDx / awayLen, awayDy / awayLen);
      } else {
        // Normal case: push directly away from the closest point on the rect.
        pushDir = Offset(dxFromBox / distFromBox, dyFromBox / distFromBox);
      }

      node.position = Offset(
        node.position.dx + pushDir.dx * push,
        node.position.dy + pushDir.dy * push,
      );
      return true;
    }
    return false;
  }

  // ── Convergence loop ───────────────────────────────────────────────────────
  for (int iter = 0; iter < iterations; iter++) {
    bool anyMoved = false;
    final nodeList = nodes.values.toList();

    // ── Check A: node-node minimum distance ─────────────────────────────────
    for (int i = 0; i < nodeList.length; i++) {
      final na = nodeList[i];
      if (na.isBlackBox) continue; // black boxes use their own (wider) rect and are exempt from this circle-vs-circle check
      for (int j = i + 1; j < nodeList.length; j++) {
        final nb = nodeList[j];
        if (nb.isBlackBox) continue;

        final cA = na.center;
        final cB = nb.center;
        final dx = cB.dx - cA.dx;
        final dy = cB.dy - cA.dy;
        final dist = sqrt(dx * dx + dy * dy);

        // dist > 0.1 guards against a divide-by-(near)zero in ux/uy below,
        // in the unlikely case two nodes end up sitting exactly on top of
        // each other.
        if (dist < minNodeGap && dist > 0.1) {
          final overlap = (minNodeGap - dist) / 2.0 + 2.0;
          final ux = dx / dist;
          final uy = dy / dist;
          // Push both nodes apart equally.
          na.position = Offset(na.position.dx - ux * overlap, na.position.dy - uy * overlap);
          nb.position = Offset(nb.position.dx + ux * overlap, nb.position.dy + uy * overlap);
          anyMoved = true;
        }
      }
    }

    // ── Checks B+C+D: per-line clearance for every node ─────────────────────
    for (final node in nodeList) {
      if (node.isBlackBox) continue; // same exemption as check A

      for (final line in lines.values) {
        final isSelfLoop = line.nodeAId == line.nodeBId;

        if (isSelfLoop) {
          // ── Check D: self-loop textbox must not overlap OTHER nodes ─────
          // The loop belongs to its own node; we only care if it overlaps a
          // *different* node's circle.
          if (line.nodeAId == node.id) continue;

          final ownerNode = nodes[line.nodeAId];
          if (ownerNode == null) continue; // stale line referencing a deleted node

          // Compute self-loop textbox centre (mirrors LineData.getTextBoxLocation).
          final oc = ownerNode.center;
          final angle = line.selfLoopAngle; // default: -π/2 (straight up)
          final outward = Offset(cos(angle), sin(angle));
          final loopCenter = Offset(
            oc.dx + outward.dx * selfLoopCenterDist,
            oc.dy + outward.dy * selfLoopCenterDist,
          );
          const textDistance = kSelfLoopTextDistance;
          final textCenter = Offset(
            loopCenter.dx + outward.dx * (selfLoopRadius + textDistance),
            loopCenter.dy + outward.dy * (selfLoopRadius + textDistance),
          );

          if (line.label.isNotEmpty) {
            // Approximate textbox rect using the shared fixed-width/
            // per-line-height constants (kLabelBoxWidth/kLabelLineHeight)
            // rather than the more precise character-metrics estimate that
            // getTextBoxLocation uses — good enough for a collision check.
            final lineCount = '\n'.allMatches(line.label).length + 1;
            final boxHeight = lineHeight * lineCount;
            final tLeft   = textCenter.dx - boxWidth / 2 - textBuffer;
            final tTop    = textCenter.dy - boxHeight / 2 - textBuffer;
            final tRight  = textCenter.dx + boxWidth / 2 + textBuffer;
            final tBottom = textCenter.dy + boxHeight / 2 + textBuffer;

            if (pushNodeFromRect(node, tLeft, tTop, tRight, tBottom)) {
              anyMoved = true;
            }
          }

          // Also keep OTHER nodes away from the loop circle itself.
          final nc = node.center;
          final dxLoop = nc.dx - loopCenter.dx;
          final dyLoop = nc.dy - loopCenter.dy;
          final distLoop = sqrt(dxLoop * dxLoop + dyLoop * dyLoop);
          final minDist = nodeRadius + selfLoopRadius + 10.0;
          if (distLoop < minDist && distLoop > 0.1) {
            final push = minDist - distLoop + 2.0;
            final ux = dxLoop / distLoop;
            final uy = dyLoop / distLoop;
            node.position = Offset(
              node.position.dx + ux * push,
              node.position.dy + uy * push,
            );
            anyMoved = true;
          }
          continue; // self-loop handling done; skip the non-self-loop checks below for this line
        }

        // Non-self-loop: skip if this line directly touches the node.
        if (line.nodeAId == node.id || line.nodeBId == node.id) continue;

        final nodeA = nodes[line.nodeAId];
        final nodeB = nodes[line.nodeBId];
        if (nodeA == null || nodeB == null) continue; // stale line referencing a deleted node

        final cA = nodeA.center;
        final cB = nodeB.center;

        // ── Check B: chord clearance ────────────────────────────────────
        // NOTE: this checks distance to the straight *chord* between the
        // two endpoint centres, not the (possibly curved) rendered arc —
        // an approximation that's cheap and good enough given the gentle
        // curvature these lines use.
        {
          final nc = node.center;
          final abx = cB.dx - cA.dx;
          final aby = cB.dy - cA.dy;
          final abLen = sqrt(abx * abx + aby * aby);

          if (abLen >= 1) {
            // Scalar projection of node onto the A→B line, as a fraction
            // of the A→B length (t=0 at A, t=1 at B).
            final t = ((nc.dx - cA.dx) * abx + (nc.dy - cA.dy) * aby) /
                (abLen * abLen);
            // Only consider the node "near" this chord if its projection
            // falls (approximately) between the two endpoints — the small
            // -0.05/1.05 margin catches nodes just past either end too.
            if (t >= -0.05 && t <= 1.05) {
              final closestX = cA.dx + t * abx;
              final closestY = cA.dy + t * aby;
              final dxFromChord = nc.dx - closestX;
              final dyFromChord = nc.dy - closestY;
              final distFromChord =
                  sqrt(dxFromChord * dxFromChord + dyFromChord * dyFromChord);

              if (distFromChord < clearance) {
                final push = clearance - distFromChord + 2.0;
                final Offset perp;
                if (distFromChord < 0.5) {
                  // Node sits (almost) exactly on the chord: dxFromChord/
                  // dyFromChord don't give a usable direction, so instead
                  // push perpendicular to the chord itself (rotate the A→B
                  // direction 90°).
                  perp = Offset(aby / abLen, -abx / abLen);
                } else {
                  perp = Offset(
                      dxFromChord / distFromChord, dyFromChord / distFromChord);
                }
                node.position = Offset(
                  node.position.dx + perp.dx * push,
                  node.position.dy + perp.dy * push,
                );
                anyMoved = true;
              }
            }
          }
        }

        // ── Check C: non-self-loop textbox clearance ────────────────────
        if (line.label.isNotEmpty) {
          // Re-derive line/box height fresh in case check B just moved the
          // node (the pushNodeFromRect call below reads `node.center` live).
          final lineCount = '\n'.allMatches(line.label).length + 1;
          final double boxHeight = lineHeight * lineCount;

          // Unlike the self-loop branch above, this reuses the real
          // LineData.getTextBoxLocation (with the fixed boxWidth/boxHeight
          // constants standing in for the more precise per-character
          // estimate) so the collision rect matches the line's actual
          // curvature, not just its endpoint chord.
          final Offset topLeft = line.getTextBoxLocation(
              cA, cB, boxWidth, boxHeight, line.label);

          final rLeft   = topLeft.dx - textBuffer;
          final rTop    = topLeft.dy - textBuffer;
          final rRight  = topLeft.dx + boxWidth  + textBuffer;
          final rBottom = topLeft.dy + boxHeight + textBuffer;

          if (pushNodeFromRect(node, rLeft, rTop, rRight, rBottom)) {
            anyMoved = true;
          }
        }
      }
    }

    // ── Check E: self-loop textbox spacing between nodes on same node ────────
    // When a node has multiple self-loops (shouldn't happen after merge, but
    // guard anyway) or its own self-loop label would overlap itself, adjust
    // selfLoopAngle to spread them out.
    final selfLoopsByNode = <String, List<LineData>>{};
    for (final line in lines.values) {
      if (line.nodeAId == line.nodeBId) {
        selfLoopsByNode.putIfAbsent(line.nodeAId, () => []).add(line);
      }
    }
    for (final entry in selfLoopsByNode.entries) {
      final loopsOnNode = entry.value;
      if (loopsOnNode.length <= 1) continue; // nothing to spread apart
      // Spread multiple self-loops evenly around the node.
      final angleStep = (2 * pi) / loopsOnNode.length;
      for (int i = 0; i < loopsOnNode.length; i++) {
        loopsOnNode[i].selfLoopAngle = -pi / 2 + angleStep * i;
      }
    }

    // Converged: no node needed to move this pass, so further iterations
    // would be no-ops — stop early instead of running all `iterations` passes.
    if (!anyMoved) break;
  }
}