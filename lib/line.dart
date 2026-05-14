import 'package:flutter/material.dart';
import 'dart:math';
import 'models.dart';

class LinePainter extends CustomPainter {
  final LineGeometry geometry;

  const LinePainter({required this.geometry});

  void _drawArrow(Canvas canvas, Offset tip, double angle) {
    const len  = 15;
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
        ..color = Colors.black
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color       = Colors.black;

    if (geometry.hasCircle) {
      canvas.drawArc(
        Rect.fromCircle(
          center: geometry.circleCenter!,
          radius: geometry.circleRadius!,
        ),
        geometry.startAngle!,
        geometry.sweepAngle!,
        false,
        paint,
      );
      _drawArrow(canvas, geometry.endPoint, geometry.arrowAngle!);
    } else {
      canvas.drawLine(geometry.startPoint, geometry.endPoint, paint);
      _drawArrow(
        canvas,
        geometry.endPoint,
        atan2(
          geometry.endPoint.dy - geometry.startPoint.dy,
          geometry.endPoint.dx - geometry.startPoint.dx,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(LinePainter oldDelegate) =>
      oldDelegate.geometry != geometry;
}

class LineWidget extends StatefulWidget {
  final LineData data;
  final Offset centerA;
  final Offset centerB;
  final ValueChanged<String> onLabelChanged;

  const LineWidget({
    super.key,
    required this.data,
    required this.centerA,
    required this.centerB,
    required this.onLabelChanged,
  });

  @override
  State<LineWidget> createState() => _LineWidgetState();
}

class _LineWidgetState extends State<LineWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.data.label);
    _focusNode  = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final focused = _focusNode.hasFocus;
    setState(() => _editing = focused);
    if (!focused) widget.onLabelChanged(_controller.text);
  }

  @override
  void didUpdateWidget(LineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Don't clobber text the user is actively typing
    if (!_editing && widget.data.label != _controller.text) {
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
    final geometry = widget.data.computeGeometry(widget.centerA, widget.centerB);
    final mid      = geometry.midPoint;

    const double boxWidth  = 120;
    const double boxHeight = 40;

    return Stack(
      children: [
        // ── Arc / straight line + arrowhead ──────────────────────────
        // MUST be transparent to pointer events so it does not swallow
        // pan gestures on the canvas or block hit-testing of other lines.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: LinePainter(geometry: geometry),
            ),
          ),
        ),

// ── Floating label ────────────────────────────────────────────
Positioned(
  left: mid.dx - boxWidth / 2,
  top: mid.dy - boxHeight / 2,
  child: SizedBox(
    width: boxWidth,
    height: boxHeight,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,

      // ONLY handle taps here
      onTap: () {
        if (!_focusNode.hasFocus) {
          FocusScope.of(context).requestFocus(_focusNode);
        }
      },

      // Do NOT define pan handlers here.
      // This allows drag gestures to reach the parent canvas.

      child: AbsorbPointer(
        // Prevent TextField itself from swallowing drags.
        // We manually focus it via GestureDetector above.
        absorbing: true,

        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            hintText: '~',
            
                ),
          onTapOutside: (_) => _focusNode.unfocus(),
              ),
             ),
           ),
          ),
        ),
      ],
    );
  }
}