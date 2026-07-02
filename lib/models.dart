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
  });

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
      const textDistance = 65.0;
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
      const loopRadius = 35.0;
      const centerDistance = 65.0;
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

    List<double> circleFromThreePoints(double x1, double y1, double x2, double y2, double x3, double y3) {
      final a = det(x1, y1, 1, x2, y2, 1, x3, y3, 1);
      final bx = -det(x1 * x1 + y1 * y1, y1, 1, x2 * x2 + y2 * y2, y2, 1, x3 * x3 + y3 * y3, y3, 1);
      final by = det(x1 * x1 + y1 * y1, x1, 1, x2 * x2 + y2 * y2, x2, 1, x3 * x3 + y3 * y3, x3, 1);
      final c = -det(x1 * x1 + y1 * y1, x1, y1, x2 * x2 + y2 * y2, x2, y2, x3 * x3 + y3 * y3, x3, y3);
      final x = (-bx) / (2 * a);
      final y = (-by) / (2 * a);
      final radius = sqrt(bx * bx + by * by - 4 * a * c) / (2 * a.abs());
      return [x, y, radius];
    }

    final circle = circleFromThreePoints(centerA.dx, centerA.dy, centerB.dx, centerB.dy, anchor.dx, anchor.dy);
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