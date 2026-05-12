import 'package:flutter/material.dart';
import "utility_math.dart";
import "dart:math";

class Line extends CustomPainter {
  late Offset nodeA;
  late Offset nodeB;

  late double parallelPart = 0.5;
  late double perpendicularPart = 0.1;
  late double lineAngleAdjust = 0.0;

  Line({
    required this.nodeA,
    required this.nodeB,
  });

  //aOrB is TRUE for A, and FALSE for B
  List<double> closestPointOnCircle(bool aOrB, double x, double y) {
    double dx;
    double dy;
    double finalX;
    double finalY;

    if (aOrB) {
      dx = x - nodeA.dx;
      dy = y - nodeA.dy;
      double scale = sqrt(dx * dx + dy * dy);
      finalX = nodeA.dx + dx * 50 / scale;
      finalY = nodeA.dy + dy * 50 / scale;
    } else {
      dx = x - nodeB.dx;
      dy = y - nodeB.dy;
      double scale = sqrt(dx * dx + dy * dy);
      finalX = nodeB.dx + dx * 50 / scale;
      finalY = nodeB.dy + dy * 50 / scale;
    }
    return [finalX, finalY];
  }

  late bool hasCircle = false;
  late double startX;
  late double startY;
  late double endX;
  late double endY;

  late double startAngle;
  late double endAngle;
  late double circleX;
  late double circleY;
  late double circleRadius;
  late double reverseScale;
  late bool isReversed;

  Offset getAnchorPoint() {
    double dx = nodeB.dx - nodeA.dx;
    double dy = nodeB.dy - nodeA.dy;
    double scale = sqrt(dx * dx + dy * dy);

    double x = nodeA.dx + dx * parallelPart + dy * perpendicularPart / scale;
    double y = nodeA.dy + dy * parallelPart - dx * perpendicularPart / scale;
    //debugPrint("getAnchorPoint: Node A: (${nodeA.dx}, ${nodeA.dy}), Node B: (${nodeB.dx}, ${nodeB.dy})");
    //debugPrint("Anchor point: ($x, $y) ($dx, $dy), perp: $perpendicularPart, scale: $scale");
    return Offset(x, y);
  }

  void getEndPointsAndCircle() {
    if (perpendicularPart == 0.0) {
      double midX = (nodeA.dx + nodeB.dx) / 2;
      double midY = (nodeA.dy + nodeB.dy) / 2;
      List<double> start = closestPointOnCircle(true, midX, midY);
      List<double> end = closestPointOnCircle(false, midX, midY);

      hasCircle = false;
      startX = start[0];
      startY = start[1];
      endX = end[0];
      endY = end[1];
    } else {
      debugPrint("Calculating circle...");
      Offset anchor = getAnchorPoint();
      List<double> circle = circleFromThreePoints(nodeA.dx, nodeA.dy, nodeB.dx,
          nodeB.dy, anchor.dx, anchor.dy);
      isReversed = (perpendicularPart > 0);

      reverseScale = isReversed ? 1 : -1;
      startAngle = atan2(nodeA.dy - circle[1], nodeA.dx - circle[0])
          - reverseScale * 50 / circle[2];

      endAngle = atan2(nodeB.dy - circle[1], nodeB.dx - circle[0])
          - reverseScale * 50 / circle[2];
      while (startAngle < 0) {
        startAngle += 2 * pi;
      }
      while (endAngle < startAngle) {
        endAngle += 2 * pi;
      }
      startX = circle[0] + circle[2] * cos(startAngle);
      startY = circle[1] + circle[2] * sin(startAngle);

      endX = circle[0] + circle[2] * cos(endAngle);
      endY = circle[1] + circle[2] * sin(endAngle);
      hasCircle = true;
      circleX = circle[0];
      circleY = circle[1];
      circleRadius = circle[2];
    }
  }
 // The equivalent to drawArrow in Evans code
  void drawArrow(Canvas canvas, double x, double y, double angle) {
    Path path = Path();
    Paint fillPaint = Paint()
      .. color = Colors.black
      .. style = PaintingStyle.fill;
    // The dx and dy values are calculated using the cosine and sine of the angle, respectively. These values represent the direction of the arrowhead based on the angle provided. The angle is typically calculated from the line's direction, ensuring that the arrowhead points in the correct direction.
    double dx = cos(angle);
    double dy = sin(angle);

    // The numbers 15 and 9 are arbitrary values that control the size of the arrowhead. You can adjust them to make the arrowhead larger or smaller as needed. 
    int num1 = 15;
    int num2 = 9;
    // The path is constructed by moving to the tip of the arrow (x, y) and then drawing two lines to create the arrowhead. The first line goes in the direction opposite to the arrow's direction (using -num1 * dx and -num1 * dy) and is offset by a perpendicular component (using num2 * dy and num2 * dx) to create the two sides of the arrowhead.
    path.moveTo(x, y);
    path.lineTo(x - num1 * dx + num2 * dy, y - num1 * dy - num2 * dx);
    path.lineTo(x - num1 * dx - num2 * dy, y - num1 * dy + num2 * dx);
    canvas.drawPath(path, fillPaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    getEndPointsAndCircle();
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black
      ..strokeWidth = 4.0;

    if (hasCircle) {
      double sweepAngle = 0;

      sweepAngle = -reverseScale * (startAngle - endAngle);
      // canvas.drawArc(Rect.fromCircle(
      //     center: Offset(circleX, circleY),
      //     radius: circleRdaius),
      //     startAngle, sweepAngle, false, paint);
 
      canvas.drawArc(Rect.fromCircle( center: Offset(circleX, circleY), radius: circleRadius), startAngle, sweepAngle, false, paint);
      drawArrow(canvas, endX, endY, endAngle + reverseScale * (pi / 2));
    } else {
      canvas.drawLine(nodeA, nodeB, paint);
      drawArrow(canvas, endX, endY, atan2(endY - startY, endX - startX));
    }
  }

  @override
  shouldRepaint(covariant CustomPainter oldPainter) {
    return false;
  }
}