import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'token_replacements.dart';
import 'widgets/app_theme.dart';

class LinePainter extends CustomPainter {
  final LineGeometry geometry;
  final bool deleteMode;
  final bool highlighted;
  final Color defaultColor;
  final Color highlightColor;
  final Color deleteColor;

  const LinePainter({
    required this.geometry,
    required this.deleteMode,
    required this.highlighted,
    required this.defaultColor,
    required this.highlightColor,
    required this.deleteColor,
  });

  Color get _lineColor =>
      deleteMode ? deleteColor : highlighted ? highlightColor : defaultColor;

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
        ..color = _lineColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlighted ? 5 : 4
      ..color = _lineColor;

    if (geometry.hasCircle) {
      const double arrowLen = 15;
      final double shortenAngle = arrowLen / geometry.circleRadius!;
      final double signedShorten = geometry.sweepAngle! >= 0 ? shortenAngle : -shortenAngle;

      canvas.drawArc(
        Rect.fromCircle(center: geometry.circleCenter!, radius: geometry.circleRadius!),
        geometry.startAngle!,
        geometry.sweepAngle! - signedShorten,
        false,
        paint,
      );

      _drawArrow(canvas, geometry.endPoint, geometry.arrowAngle!);
    } else {
      const double arrowLen = 15;
      final double angle = atan2(
        geometry.endPoint.dy - geometry.startPoint.dy,
        geometry.endPoint.dx - geometry.startPoint.dx,
      );
      final Offset shortenedEnd = Offset(
        geometry.endPoint.dx - cos(angle) * arrowLen,
        geometry.endPoint.dy - sin(angle) * arrowLen,
      );

      final double angle2 =
          atan2(geometry.endPoint.dy - shortenedEnd.dy, geometry.endPoint.dx - shortenedEnd.dx);
      canvas.drawLine(geometry.startPoint, shortenedEnd, paint);

      _drawArrow(canvas, geometry.endPoint, angle2);
    }
  }

  @override
  bool shouldRepaint(LinePainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.highlighted != highlighted ||
      oldDelegate.deleteMode != deleteMode ||
      oldDelegate.defaultColor != defaultColor ||
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.deleteColor != deleteColor;
}

class LineWidget extends StatefulWidget {
  final LineData data;
  final Offset centerA;
  final Offset centerB;
  final bool deleteMode;
  final bool highlighted;
  final ValueChanged<String> onLabelChanged;

  const LineWidget({
    super.key,
    required this.data,
    required this.centerA,
    required this.centerB,
    required this.deleteMode,
    this.highlighted = false,
    required this.onLabelChanged,
  });

  @override
  State<LineWidget> createState() => _LineWidgetState();
}

class _LineWidgetState extends State<LineWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _editing = false;
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.data.label);
    _lineCount = '\n'.allMatches(widget.data.label).length + 1;
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

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

  Color _labelColor(AppThemeNotifier theme) {
    return widget.deleteMode
        ? theme.error
        : widget.highlighted
            ? theme.lineHighlight
            : theme.lineColor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final geometry = widget.data.computeGeometry(widget.centerA, widget.centerB);

    const double boxWidth = 120;
    const double lineHeight = 36.0;
    final double boxHeight = lineHeight * _lineCount;

    final Offset mid = widget.data.getTextBoxLocation(
      widget.centerA,
      widget.centerB,
      boxWidth,
      boxHeight,
      widget.data.label,
    );

    final labelColor = _labelColor(theme);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: LinePainter(
                geometry: geometry,
                deleteMode: widget.deleteMode,
                highlighted: widget.highlighted,
                defaultColor: theme.lineColor,
                highlightColor: theme.lineHighlight,
                deleteColor: theme.error,
              ),
            ),
          ),
        ),
        Positioned(
          left: mid.dx,
          top: mid.dy,
          child: SizedBox(
            width: boxWidth,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: GoogleFonts.courierPrime(
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
              onChanged: (value) {
                final parsed = parseTokenText(value);
                final newLineCount = '\n'.allMatches(parsed).length + 1;

                if (newLineCount != _lineCount) {
                  setState(() => _lineCount = newLineCount);
                }

                if (parsed != value) {
                  _controller.value = TextEditingValue(
                    text: parsed,
                    selection: TextSelection.collapsed(offset: parsed.length),
                  );
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
      ],
    );
  }
}
