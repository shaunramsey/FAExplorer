import 'package:flutter/material.dart';
import 'dart:math';

// ─────────────────────────────────────────────
//  NodeData
// ─────────────────────────────────────────────
class NodeData {
  final String id;

  Offset position;
  String label;

  bool isAccept;

  final Set<String> connectedLineIds = {};

  NodeData({
    required this.id,
    required this.position,
    this.label = '',
    this.isAccept = false,
  });

  Offset get center => Offset(position.dx + 50, position.dy + 50);

  bool containsPoint(Offset point) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;

    return dx * dx + dy * dy <= 50 * 50;
  }
}

// ─────────────────────────────────────────────
//  LineData
// ─────────────────────────────────────────────
class LineData {
  final String id;

  final String nodeAId;
  final String nodeBId;

  double perpendicularPart;

  String label;

  LineData({
    required this.id,
    required this.nodeAId,
    required this.nodeBId,
    this.perpendicularPart = 0,
    this.label = '',
  });

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

  Offset midPoint(Offset centerA, Offset centerB) {
    return anchorPoint(centerA, centerB);
  }

  bool containsPoint(Offset point, Offset centerA, Offset centerB) {
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
    // Straight line
    if (perpendicularPart.abs() <= 5) {
      final mid = Offset(
        (centerA.dx + centerB.dx) / 2,
        (centerA.dy + centerB.dy) / 2,
      );

      final start = _closestOnCircle(centerA, mid);
      final end = _closestOnCircle(centerB, mid);

      return LineGeometry.straight(
        startPoint: start,
        endPoint: end,
        midPoint: Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2),
      );
    }

    // Arc
    final anchor = anchorPoint(centerA, centerB);

    double det(
      double a,
      double b,
      double c,
      double d,
      double e,
      double f,
      double g,
      double h,
      double i,
    ) {
      return a * e * i +
          b * f * g +
          c * d * h -
          a * f * h -
          b * d * i -
          c * e * g;
    }

    List<double> circleFromThreePoints(
      double x1,
      double y1,
      double x2,
      double y2,
      double x3,
      double y3,
    ) {
      double a = det(x1, y1, 1, x2, y2, 1, x3, y3, 1);
      double bx = -det(
        x1 * x1 + y1 * y1,
        y1,
        1,
        x2 * x2 + y2 * y2,
        y2,
        1,
        x3 * x3 + y3 * y3,
        y3,
        1,
      );
      double by = det(
        x1 * x1 + y1 * y1,
        x1,
        1,
        x2 * x2 + y2 * y2,
        x2,
        1,
        x3 * x3 + y3 * y3,
        x3,
        1,
      );
      double c = -det(
        x1 * x1 + y1 * y1,
        x1,
        y1,
        x2 * x2 + y2 * y2,
        x2,
        y2,
        x3 * x3 + y3 * y3,
        x3,
        y3,
      );

      double x = (-bx) / (2 * a);
      double y = (-by) / (2 * a);
      double radius = sqrt(bx * bx + by * by - 4 * a * c) / (2 * (a).abs());

      return [x, y, radius];
    }

    final circle = circleFromThreePoints(
      centerA.dx,
      centerA.dy,
      centerB.dx,
      centerB.dy,
      anchor.dx,
      anchor.dy,
    );

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

// ─────────────────────────────────────────────
//  LineGeometry
// ─────────────────────────────────────────────
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

  const LineGeometry.straight({
    required this.startPoint,
    required this.endPoint,
    required this.midPoint,
  }) : hasCircle = false,
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
