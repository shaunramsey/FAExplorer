import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'token_replacements.dart'; // ← single source of truth
import 'widgets/app_theme.dart';

class StartArrowWidget extends StatefulWidget {
  final StartArrowData data;
  final Offset nodeCenter;

  final VoidCallback? onDelete;
  final bool deleteMode;
  final bool highlighted;

  const StartArrowWidget({
    super.key,
    required this.data,
    required this.nodeCenter,
    this.onDelete,
    this.deleteMode = false,
    this.highlighted = false,
  });

  @override
  State<StartArrowWidget> createState() => _StartArrowWidgetState();
}

class _StartArrowWidgetState extends State<StartArrowWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

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
    // ─────────────────────────────────────────────
    // START ARROW GEOMETRY
    // ─────────────────────────────────────────────

    var dir = widget.data.direction();

    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    const double radius = 50;

    final end = Offset(widget.nodeCenter.dx + dir.dx * radius, widget.nodeCenter.dy + dir.dy * radius);
    final start = Offset(end.dx + dir.dx * widget.data.length, end.dy + dir.dy * widget.data.length);
    final arrowAngle = atan2(end.dy - start.dy, end.dx - start.dx);
    final perp = Offset(-dir.dy, dir.dx);

    const double boxWidth = 120;
    const double lineHeight = 36.0;
    final double boxHeight = lineHeight * _lineCount;

    final labelOffset = Offset(start.dx + perp.dx * 30 - boxWidth / 2, start.dy + perp.dy * 30 - boxHeight / 2);

    return Stack(
      children: [
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

        Positioned(
          left: labelOffset.dx,
          top: labelOffset.dy,
          child: SizedBox(
            width: boxWidth,
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
                          : theme.lineColor.withOpacity(0.6),
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

class _ArrowPainter extends CustomPainter {
  final Offset start;
  final Offset end;
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

  void _drawArrow(Canvas canvas, Offset tip, double angle) {
    const len = 15;
    const wing = 9;

    final dx = cos(angle);
    final dy = sin(angle);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - len * dx + wing * dy, tip.dy - len * dy - wing * dx)
      ..lineTo(tip.dx - len * dx - wing * dy, tip.dy - len * dy + wing * dx)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4
      ..color = strokeColor;

    const double arrowLen = 15;

    final shortenedEnd = Offset(end.dx - cos(angle) * arrowLen, end.dy - sin(angle) * arrowLen);

    canvas.drawLine(start, shortenedEnd, paint);

    _drawArrow(canvas, end, angle);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return true;
  }
}