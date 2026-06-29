import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../token_replacements.dart';
import 'app_theme.dart';

const _arrowLen = 15.0;
const _arrowWing = 9.0;

void _drawArrowhead(Canvas canvas, Offset tip, double angle, Color color) {
  final dx = cos(angle);
  final dy = sin(angle);
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - _arrowLen * dx + _arrowWing * dy, tip.dy - _arrowLen * dy - _arrowWing * dx)
      ..lineTo(tip.dx - _arrowLen * dx - _arrowWing * dy, tip.dy - _arrowLen * dy + _arrowWing * dx)
      ..close(),
    Paint()..color = color..style = PaintingStyle.fill,
  );
}
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

      _drawArrowhead(canvas, geometry.endPoint, geometry.arrowAngle!, _lineColor);
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

      _drawArrowhead(canvas, geometry.endPoint, angle2, _lineColor);
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
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // START ARROW GEOMETRY
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4
      ..color = strokeColor;

    const double arrowLen = 15;

    final shortenedEnd = Offset(end.dx - cos(angle) * arrowLen, end.dy - sin(angle) * arrowLen);

    canvas.drawLine(start, shortenedEnd, paint);

    _drawArrowhead(canvas, end, angle, strokeColor);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return true;
  }
}
class Node extends StatefulWidget {
  final NodeData data;
  final bool lineMode;
  final bool interactionLocked;
  final ValueChanged<String> onLabelChanged;

  final bool Function(String label, String nodeId) isLabelTaken;
  final ValueChanged<bool>? onDuplicateStateChanged;

  final VoidCallback? onLineModeSelect;
  final VoidCallback? onDoubleTap;

  final bool deleteMode;
  final VoidCallback? onDelete;

  final bool highlighted;

  /// Called when the user taps the tape-routing button on a black-box node.
  final VoidCallback? onBlackBoxTapeEdit;

  /// Called when the user taps the edit-program button on a black-box node.
  final VoidCallback? onBlackBoxEdit;

  /// Total number of tapes the TM is currently configured with. Used by the
  /// node to show a mismatch warning on the tape badge when the node's
  /// [NodeData.blackBoxReadTape] or [NodeData.blackBoxWriteTape] is out of
  /// range. Defaults to 1 (no warning shown in non-TM modes).
  final int tapeCount;

  const Node({
    super.key,
    required this.data,
    required this.lineMode,
    this.interactionLocked = false,
    required this.onLabelChanged,
    required this.isLabelTaken,
    this.onDuplicateStateChanged,
    this.onLineModeSelect,
    this.onDoubleTap,
    required this.deleteMode,
    this.onDelete,
    this.highlighted = false,
    this.onBlackBoxTapeEdit,
    this.onBlackBoxEdit,
    this.tapeCount = 1,
  });

  @override
  State<Node> createState() => _NodeState();
}

class _OctagonPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _OctagonPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final path = Path();

    const cut = 12.0;

    path.moveTo(cut, 0);
    path.lineTo(size.width - cut, 0);
    path.lineTo(size.width, cut);
    path.lineTo(size.width, size.height - cut);
    path.lineTo(size.width - cut, size.height);
    path.lineTo(cut, size.height);
    path.lineTo(0, size.height - cut);
    path.lineTo(0, cut);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NodeState extends State<Node> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _selected = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.data.label);
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(Node oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_selected && widget.data.label != _controller.text) {
      _controller.text = widget.data.label;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _select() {
    if (!_selected) {
      setState(() => _selected = true);
      _focusNode.requestFocus();
    }
  }

  void _deselect() {
    final value = _controller.text;

    setState(() {
      _selected = false;
    });

    widget.onLabelChanged(value);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _deselect();
    }
  }

  Color _borderColor(AppThemeNotifier theme) {
    final isDuplicate = widget.isLabelTaken(_controller.text, widget.data.id);

    return widget.deleteMode
        ? theme.nodeBorderDelete
        : widget.highlighted
        ? theme.nodeBorderHighlight
        : isDuplicate
        ? theme.nodeBorderDuplicate
        : _selected
        ? theme.nodeBorderSelected
        : theme.nodeBorder;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // NODE ID DISPLAY
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final borderColor = _borderColor(theme);

    // When locked (e.g. placing the start arrow), do not allow selection/editing.
    final bool textFieldActive = _selected && !widget.lineMode && !widget.interactionLocked;
    final startText = nodeIdToAlpha(widget.data.id);
    final isBlackBox = widget.data.isBlackBox;
    final nodeWidth = isBlackBox ? 140.0 : 100.0;
    final nodeHeight = 100.0;

    return Positioned(
      top: widget.data.position.dy,
      left: widget.data.position.dx,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (widget.interactionLocked) return;
          if (widget.deleteMode) {
            widget.onDelete?.call();
            return;
          }
          if (widget.lineMode) {
            widget.onLineModeSelect?.call();
          } else {
            _select();
          }
        },
        onDoubleTap: widget.onDoubleTap,
        child: SizedBox(
          width: nodeWidth,
          height: nodeHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: isBlackBox ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: isBlackBox ? BorderRadius.circular(10) : null,
                    border: Border.all(color: borderColor, width: 4),
                  ),
                ),
              ),

              if (widget.data.isAccept && widget.data.canToggleNormalAccept)
                Center(
                  child: IgnorePointer(
                    child: isBlackBox
                        ? Container(
                            width: 118,
                            height: 78,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor, width: 3),
                            ),
                          )
                        : Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: borderColor, width: 4),
                            ),
                          ),
                  ),
                ),

              if (widget.data.isHaltAccept)
                Center(
                  child: IgnorePointer(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.acceptState,
                        border: Border.all(color: borderColor, width: 4),
                      ),
                    ),
                  ),
                ),

              if (widget.data.isHaltReject)
                Center(
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size(60, 60),
                      painter: _OctagonPainter(color: theme.rejectState, borderColor: borderColor),
                    ),
                  ),
                ),

              Center(
                child: SizedBox(
                  width: isBlackBox ? 118 : 80,
                  child: IgnorePointer(
                    ignoring: !textFieldActive,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: isBlackBox ? 20 : 30,
                        color: borderColor,
                      ),
                      textAlign: TextAlign.center,
                      onEditingComplete: _deselect,
                      onTapOutside: (_) => _deselect(),

                      onChanged: (value) {
                        // Use the shared parser from token_replacements.dart
                        final parsed = parseTokenText(value);

                        String finalText = parsed;

                        bool haltAccept = false;
                        bool haltReject = false;

                        if (parsed.startsWith('<<') && parsed.endsWith('>>')) {
                          haltAccept = true;
                          finalText = parsed.substring(2, parsed.length - 2);
                        } else if (parsed.startsWith('>>') && parsed.endsWith('<<')) {
                          haltReject = true;
                          finalText = parsed.substring(2, parsed.length - 2);
                        }

                        widget.data.applyHaltFromLabel(
                          haltAccept: haltAccept,
                          haltReject: haltReject,
                        );

                        if (finalText != _controller.text) {
                          _controller.value = TextEditingValue(
                            text: finalText,
                            selection: TextSelection.collapsed(offset: finalText.length),
                          );
                        }

                        setState(() {});
                      },

                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        hintText: isBlackBox ? 'BLACK BOX' : startText,
                        hintStyle: TextStyle(
                          color: widget.deleteMode
                              ? theme.nodeBorderDelete
                              : theme.nodeBorder.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // â”€â”€ Black-box bottom bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              // Shows the edit-program button so the inner DSL remains
              // accessible. Tape routing is now encoded directly in outgoing
              // line labels (RWD triples per tape) so the old R:/W: badge
              // and tape-routing dialog are no longer needed here.
              if (isBlackBox)
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Edit-program button
                      if (!widget.deleteMode && !widget.interactionLocked)
                        Tooltip(
                          message: 'Edit program',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.lineMode
                                ? null
                                : widget.onBlackBoxEdit,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: theme.bg.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: borderColor.withOpacity(0.55),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.edit_note,
                                size: 14,
                                color: borderColor.withOpacity(0.85),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// (BlackBoxTapeBadge removed â€” tape routing is now encoded directly in
//  blackbox outgoing line labels as RWD triples per tape, e.g. aXRa1R.)
