import 'package:flutter/material.dart';
import 'dart:math';

import 'models.dart';

class StartArrowWidget extends StatefulWidget {
  final StartArrowData data;

  final Offset nodeCenter;

  const StartArrowWidget({
    super.key,
    required this.data,
    required this.nodeCenter,
  });

  @override
  State<StartArrowWidget> createState() =>
      _StartArrowWidgetState();
}

class _StartArrowWidgetState
    extends State<StartArrowWidget> {
  late final TextEditingController
      _controller;

  late final FocusNode _focusNode;

  int _lineCount = 1;

  @override
  void initState() {
    super.initState();

    _controller =
        TextEditingController(
      text: widget.data.label,
    );

    _focusNode = FocusNode();

    _lineCount =
        '\n'
            .allMatches(
              widget.data.label,
            )
            .length +
        1;
  }

  @override
  void didUpdateWidget(
    covariant StartArrowWidget oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (!_focusNode.hasFocus &&
        _controller.text !=
            widget.data.label) {
      _controller.text =
          widget.data.label;
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
    final dir =
        widget.data.direction();

    final end = Offset(
      widget.nodeCenter.dx -
          dir.dx * 50,
      widget.nodeCenter.dy -
          dir.dy * 50,
    );

    final start = Offset(
      end.dx -
          dir.dx *
              widget.data.length,
      end.dy -
          dir.dy *
              widget.data.length,
    );

    final labelOffset = Offset(
      start.dx -
          120 -
          dir.dx * 20,
      start.dy -
          25 -
          dir.dy * 20,
    );

    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ArrowPainter(
              start: start,
              end: end,
            ),
          ),
        ),

        Positioned(
          left: labelOffset.dx,
          top: labelOffset.dy,

          child: SizedBox(
            width: 120,

            child: TextField(
              controller: _controller,

              focusNode: _focusNode,

              maxLines: null,

              keyboardType:
                  TextInputType.multiline,

              textInputAction:
                  TextInputAction.newline,

              textAlign:
                  TextAlign.center,

              style: const TextStyle(
                fontSize: 30,
                fontWeight:
                    FontWeight.bold,
                fontFamily:
                    'Courier',
              ),

              onChanged: (value) {
                widget.data.label =
                    value;

                final newLineCount =
                    '\n'
                            .allMatches(
                              value,
                            )
                            .length +
                        1;

                if (newLineCount !=
                    _lineCount) {
                  setState(() {
                    _lineCount =
                        newLineCount;
                  });
                }
              },

              decoration:
                  const InputDecoration(
                border:
                    InputBorder.none,

                enabledBorder:
                    InputBorder.none,

                focusedBorder:
                    InputBorder.none,

                hintText: '~',

                isDense: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter
    extends CustomPainter {
  final Offset start;
  final Offset end;

  const _ArrowPainter({
    required this.start,
    required this.end,
  });

  void _drawArrow(
    Canvas canvas,
    Offset tip,
    double angle,
  ) {
    const len = 15;
    const wing = 9;

    final dx = cos(angle);
    final dy = sin(angle);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - len * dx + wing * dy,
        tip.dy - len * dy - wing * dx,
      )
      ..lineTo(
        tip.dx - len * dx - wing * dy,
        tip.dy - len * dy + wing * dx,
      )
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4
      ..color = Colors.black;

    canvas.drawLine(
      start,
      end,
      paint,
    );

    final angle = atan2(
      end.dy - start.dy,
      end.dx - start.dx,
    );

    _drawArrow(
      canvas,
      end,
      angle,
    );
  }

  @override
  bool shouldRepaint(
    covariant _ArrowPainter oldDelegate,
  ) {
    return true;
  }
}