import 'dart:math';
import 'package:flutter/material.dart';

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
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: 0.85);

    canvas.drawLine(start, end, paint);

    final angle = atan2(end.dy - start.dy, end.dx - start.dx);
    const len = 14.0;
    const wing = 8.0;
    final dx = cos(angle);
    final dy = sin(angle);

    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - len * dx + wing * dy, end.dy - len * dy - wing * dx)
      ..lineTo(end.dx - len * dx - wing * dy, end.dy - len * dy + wing * dx)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(RubberBandPainter old) =>
      old.start != start || old.end != end || old.color != color;
}
