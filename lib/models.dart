import 'package:flutter/material.dart';
import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
//  Shared utility: base-26 node ID → letter label
// ─────────────────────────────────────────────────────────────────────────────
String nodeIdToAlpha(String rawId) {
  final number = int.tryParse(rawId.replaceFirst('n', ''));
  if (number == null || number < 0) return rawId;
  int n = number;
  String result = '';
  do {
    result = String.fromCharCode(65 + (n % 26)) + result;
    n = (n ~/ 26) - 1;
  } while (n >= 0);
  return result;
}

String displayNodeLabel(String nodeId, Map<String, NodeData> nodes) {
  final node = nodes[nodeId];
  if (node == null) return nodeId;

  final trimmedLabel = node.label.trim();
  if (trimmedLabel.isEmpty) {
    return nodeIdToAlpha(node.id);
  }

  final hasDuplicate = nodes.values.any(
    (other) => other.id != node.id && other.label.trim() == trimmedLabel,
  );

  if (!hasDuplicate) return trimmedLabel;

  return '$trimmedLabel:${node.id.toUpperCase()}';
}

// ─────────────────────────────────────────────────────────────────────────────
//  NodeData
// ─────────────────────────────────────────────────────────────────────────────
class NodeData {
  final String id;

  Offset position;
  String label;

  bool isAccept;
  bool isHaltAccept;
  bool isHaltReject;
  bool isBlackBox;
  String blackBoxDescription;
  String blackBoxDsl;

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
  }) : blackBoxActiveTapes = blackBoxActiveTapes ?? <int>[];

  bool get isHaltState => isHaltAccept || isHaltReject;

  /// Halt states cannot start outgoing transitions.
  bool get canHaveOutgoingTransitions => !isHaltState;

  /// Halt states use their own accept/reject visuals, not the normal accept ring.
  bool get canToggleNormalAccept => !isHaltState;

  void applyHaltFromLabel({required bool haltAccept, required bool haltReject}) {
    isHaltAccept = haltAccept;
    isHaltReject = haltReject;
    if (isHaltState) isAccept = false;
  }

  Offset get center => isBlackBox
      ? Offset(position.dx + 70, position.dy + 50)
      : Offset(position.dx + 50, position.dy + 50);

  bool containsPoint(Offset point) {
    if (isBlackBox) {
      return point.dx >= position.dx &&
          point.dx <= position.dx + 140 &&
          point.dy >= position.dy &&
          point.dy <= position.dy + 100;
    }
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

class LineData {
  final String id;

  final String nodeAId;
  final String nodeBId;

  double perpendicularPart;
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

  Offset anchorPoint(Offset centerA, Offset centerB) {
    final dx = centerB.dx - centerA.dx;
    final dy = centerB.dy - centerA.dy;
    final scale = sqrt(dx * dx + dy * dy);
    if (scale == 0) return centerA;
    final perpDx = dy / scale;
    final perpDy = -dx / scale;
    return Offset(
      centerA.dx + dx * 0.5 + perpDx * perpendicularPart,
      centerA.dy + dy * 0.5 + perpDy * perpendicularPart,
    );
  }

  Offset getTextBoxLocation(Offset centerA, Offset centerB, double width, double height, String label) {
    final dx = centerB.dx - centerA.dx;
    final dy = centerB.dy - centerA.dy;
    final scale = sqrt(dx * dx + dy * dy);

    if ((centerA - centerB).distance < 1) {
      final geometry = computeGeometry(centerA, centerB);
      final loopCenter = geometry.circleCenter!;
      final radius = geometry.circleRadius!;
      final angle = selfLoopAngle;
      final outward = Offset(cos(angle), sin(angle));
      const textDistance = kSelfLoopTextDistance;
      final textCenter = Offset(
        loopCenter.dx + outward.dx * (radius + textDistance),
        loopCenter.dy + outward.dy * (radius + textDistance),
      );
      return Offset(textCenter.dx - width / 2, textCenter.dy - height / 2);
    }

    if (scale == 0) return centerA;

    final perpDx = dy / scale;
    final perpDy = -dx / scale;
    const double fontSize = 30;
    final double fontScale = perpendicularPart < 0 ? -1 : 1;

    int textLength = 0;
    label.split('\n').forEach((line) {
      if (line.length > textLength) textLength = line.length;
    });
    final int numberOfLines = label.split('\n').length;

    final double whw = width / 2 - 9 * perpDx * fontScale * textLength - 25 * perpDx * fontScale;
    double whh = height / 2 - perpDy * fontScale * fontSize * numberOfLines / 2;
    if (fontScale * perpDy < 0 && numberOfLines > 1) {
      whh -= perpDy * fontScale * fontSize * (numberOfLines / 4);
    }

    final wh = Offset(whw, whh);
    return Offset(
      centerA.dx + dx * 0.5 + perpDx * perpendicularPart - wh.dx,
      centerA.dy + dy * 0.5 + perpDy * (perpendicularPart + fontScale * fontSize) - wh.dy,
    );
  }

  Offset midPoint(Offset centerA, Offset centerB) => anchorPoint(centerA, centerB);

  bool containsPoint(Offset point, Offset centerA, Offset centerB) {
    if ((centerA - centerB).distance < 1) {
      final geometry = computeGeometry(centerA, centerB);
      final center = geometry.circleCenter!;
      final radius = geometry.circleRadius!;
      final dx = point.dx - center.dx;
      final dy = point.dy - center.dy;
      final dist = sqrt(dx * dx + dy * dy);
      return (dist - radius).abs() < 25;
    }

    final anchor = anchorPoint(centerA, centerB);
    final dx = point.dx - anchor.dx;
    final dy = point.dy - anchor.dy;
    return dx * dx + dy * dy <= 50 * 50;
  }

  static Offset _closestOnCircle(Offset center, Offset target) {
    final dx = target.dx - center.dx;
    final dy = target.dy - center.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist == 0) return center;
    return Offset(center.dx + dx * 50 / dist, center.dy + dy * 50 / dist);
  }

  LineGeometry computeGeometry(Offset centerA, Offset centerB) {
    // ── Self loop ────────────────────────────────────────────────
    if ((centerA - centerB).distance < 1) {
      final angle = selfLoopAngle;
      final outward = Offset(cos(angle), sin(angle));
      const loopRadius = kSelfLoopRadius;
      const centerDistance = kSelfLoopCenterDistance;
      final circleCenter = Offset(
        centerA.dx + outward.dx * centerDistance,
        centerA.dy + outward.dy * centerDistance,
      );
      final towardNodeAngle = atan2(centerA.dy - circleCenter.dy, centerA.dx - circleCenter.dx);
      const gapAngle = 0.85;
      final startAngle = towardNodeAngle + gapAngle;
      final sweepAngle = 2 * pi - (gapAngle * 2);
      final endAngle = startAngle + sweepAngle;
      final startPt = Offset(circleCenter.dx + loopRadius * cos(startAngle), circleCenter.dy + loopRadius * sin(startAngle));
      final endPt = Offset(circleCenter.dx + loopRadius * cos(endAngle), circleCenter.dy + loopRadius * sin(endAngle));
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
        arrowAngle: endAngle + pi / 2 - pi / 12,
      );
    }

    // ── Straight line ────────────────────────────────────────────
    if (perpendicularPart.abs() <= 5) {
      final mid = Offset((centerA.dx + centerB.dx) / 2, (centerA.dy + centerB.dy) / 2);
      final start = _closestOnCircle(centerA, mid);
      final end = _closestOnCircle(centerB, mid);
      return LineGeometry.straight(
        startPoint: start,
        endPoint: end,
        midPoint: Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2),
      );
    }

    // ── Normal arc ───────────────────────────────────────────────
    final anchor = anchorPoint(centerA, centerB);

    double det(double a, double b, double c, double d, double e, double f, double g, double h, double i) {
      return a * e * i + b * f * g + c * d * h - a * f * h - b * d * i - c * e * g;
    }

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
    final direction = perpendicularPart > 0 ? 1.0 : -1.0;

    double startAngle = atan2(centerA.dy - cy, centerA.dx - cx);
    double endAngle = atan2(centerB.dy - cy, centerB.dx - cx);
    startAngle += direction * (50 / r);
    endAngle -= direction * (50 / r);

    double sweepAngle;
    if (direction > 0) {
      while (endAngle < startAngle) {
        endAngle += 2 * pi;
      }
      sweepAngle = endAngle - startAngle;
    } else {
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
      arrowAngle: endAngle + direction * (pi / 2),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  StartArrowData
// ─────────────────────────────────────────────────────────────────────────────
class StartArrowData {
  String nodeId;
  Offset offset;
  double length;
  String label;

  StartArrowData({required this.nodeId, this.offset = const Offset(-1, 0), this.length = 100, this.label = ''});

  Offset direction() {
    final dist = offset.distance;
    if (dist == 0) return const Offset(-1, 0);
    return Offset(offset.dx / dist, offset.dy / dist);
  }

  /// True when [point] is near the start-arrow shaft or tail (for drag/delete).
  bool containsPoint(Offset point, Offset nodeCenter, {double tapRadius = 44}) {
    var dir = direction();
    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    const radius = 50.0;
    final end = Offset(nodeCenter.dx + dir.dx * radius, nodeCenter.dy + dir.dy * radius);
    final tail = Offset(end.dx + dir.dx * length, end.dy + dir.dy * length);

    if ((point - tail).distance < tapRadius) return true;

    final seg = end - tail;
    final lenSq = seg.dx * seg.dx + seg.dy * seg.dy;
    if (lenSq == 0) return false;

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
class LineGeometry {
  final bool hasCircle;

  final Offset startPoint;
  final Offset endPoint;
  final Offset midPoint;

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
    final closestX = nc.dx.clamp(rLeft, rRight);
    final closestY = nc.dy.clamp(rTop, rBottom);
    final dxFromBox = nc.dx - closestX;
    final dyFromBox = nc.dy - closestY;
    final distFromBox = sqrt(dxFromBox * dxFromBox + dyFromBox * dyFromBox);

    if (distFromBox < nodeRadius) {
      final push = nodeRadius - distFromBox + 2.0; // +2 px safety margin

      final Offset pushDir;
      if (distFromBox < 0.5) {
        final rcx = (rLeft + rRight) / 2;
        final rcy = (rTop + rBottom) / 2;
        final awayDx = nc.dx - rcx;
        final awayDy = nc.dy - rcy;
        final awayLen = sqrt(awayDx * awayDx + awayDy * awayDy);
        pushDir = awayLen < 0.5
            ? const Offset(0, 1)
            : Offset(awayDx / awayLen, awayDy / awayLen);
      } else {
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
      if (na.isBlackBox) continue;
      for (int j = i + 1; j < nodeList.length; j++) {
        final nb = nodeList[j];
        if (nb.isBlackBox) continue;

        final cA = na.center;
        final cB = nb.center;
        final dx = cB.dx - cA.dx;
        final dy = cB.dy - cA.dy;
        final dist = sqrt(dx * dx + dy * dy);

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
      if (node.isBlackBox) continue;

      for (final line in lines.values) {
        final isSelfLoop = line.nodeAId == line.nodeBId;

        if (isSelfLoop) {
          // ── Check D: self-loop textbox must not overlap OTHER nodes ─────
          // The loop belongs to its own node; we only care if it overlaps a
          // *different* node's circle.
          if (line.nodeAId == node.id) continue;

          final ownerNode = nodes[line.nodeAId];
          if (ownerNode == null) continue;

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
          continue;
        }

        // Non-self-loop: skip if this line directly touches the node.
        if (line.nodeAId == node.id || line.nodeBId == node.id) continue;

        final nodeA = nodes[line.nodeAId];
        final nodeB = nodes[line.nodeBId];
        if (nodeA == null || nodeB == null) continue;

        final cA = nodeA.center;
        final cB = nodeB.center;

        // ── Check B: chord clearance ────────────────────────────────────
        {
          final nc = node.center;
          final abx = cB.dx - cA.dx;
          final aby = cB.dy - cA.dy;
          final abLen = sqrt(abx * abx + aby * aby);

          if (abLen >= 1) {
            final t = ((nc.dx - cA.dx) * abx + (nc.dy - cA.dy) * aby) /
                (abLen * abLen);
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
          final lineCount = '\n'.allMatches(line.label).length + 1;
          final double boxHeight = lineHeight * lineCount;

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
      if (loopsOnNode.length <= 1) continue;
      // Spread multiple self-loops evenly around the node.
      final angleStep = (2 * pi) / loopsOnNode.length;
      for (int i = 0; i < loopsOnNode.length; i++) {
        loopsOnNode[i].selfLoopAngle = -pi / 2 + angleStep * i;
      }
    }

    if (!anyMoved) break;
  }
}