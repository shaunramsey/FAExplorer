import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  State<StartArrowWidget> createState() => _StartArrowWidgetState();
}

class _StartArrowWidgetState extends State<StartArrowWidget> {
  late final TextEditingController _controller;

  late final FocusNode _focusNode;

  int _lineCount = 1;

  static const Map<String, String> _replacements = {
    '\\0': '∅',
    'ALPHA': 'α',
    'BETA': 'β',
    'GAMMA': 'γ',
    'ZETA': 'ζ',
    'ETA': 'η',
    'THETA': 'θ',
    'IOTA': 'ι',
    'KAPPA': 'κ',
    'LAMDA': 'λ',
    'DELTA': 'δ',
    'EPSILON': 'ε',
    'MU': 'μ',
    'PI': 'π',
    'SIGMA': 'σ',
    'OMEGA': 'ω',
    'PHI': 'φ',
    'GAMMA_CAP': 'Γ',
    'DELTA_CAP': 'Δ',
    'PI_CAP': 'Π',
    'SIGMA_CAP': 'Σ',
    'OMEGA_CAP': 'Ω',
    'PHI_CAP': 'Φ',
    'INFINITY': '∞',
    'SQRT': '√',
    'PLUSMINUS': '±',
    'NOTEQUAL': '≠',
    'LESSEQ': '≤',
    'GREATEREQ': '≥',
    'APPROX': '≈',
    'MULTIPLY': '×',
    'DIVIDE': '÷',
    'LEFT': '←',
    'RIGHT': '→',
    'UP': '↑',
    'DOWN': '↓',
    'LEFTRIGHT': '↔',
    'CHECK': '✓',
    'X': '✗',
    'STAR': '★',
    'HEART': '♥',
    'BULLET': '•',
    'ELLIPSIS': '…',
    'COPY': '©',
    'REGISTERED': '®',
    'TRADEMARK': '™',
    'DEGREE': '°',
    'PARAGRAPH': '¶',
    'SECTION': '§',
  };

  String parseNodeText(String input) {
    return input.replaceAllMapped(
      RegExp(r'\\?\[\[(.*?)\]\]'),
      (match) {
        final full = match.group(0)!;

        if (full.startsWith(r'\')) {
          return full.substring(1);
        }

        final key = (match.group(1) ?? '').trim();

        if (key.startsWith('/')) {
          final text = key.substring(1);

          return text.characters
              .map((ch) => ch == ' ' ? ch : '$ch\u0338')
              .join();
        }

        return _replacements[key] ?? full;
      },
    );
  }

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

    if (!_focusNode.hasFocus &&
        _controller.text != widget.data.label) {
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
    // ─────────────────────────────────────────────
    // START ARROW GEOMETRY
    // ─────────────────────────────────────────────

    var dir = widget.data.direction();

    // Default top-left direction
    if (dir.distance == 0 || (dir.dx == -1 && dir.dy == 0)) {
      dir = const Offset(-0.7071, -0.7071);
    }

    const double radius = 50;

    // Point on circle edge
    final end = Offset(
      widget.nodeCenter.dx + dir.dx * radius,
      widget.nodeCenter.dy + dir.dy * radius,
    );

    // Extend outward from circle
    final start = Offset(
      end.dx + dir.dx * widget.data.length,
      end.dy + dir.dy * widget.data.length,
    );

    final arrowAngle = atan2(
      end.dy - start.dy,
      end.dx - start.dx,
    );

    final perp = Offset(-dir.dy, dir.dx);

    const double boxWidth = 120;
    const double lineHeight = 36.0;

    final double boxHeight = lineHeight * _lineCount;

    final labelOffset = Offset(
      start.dx + perp.dx * 30 - boxWidth / 2,
      start.dy + perp.dy * 30 - boxHeight / 2,
    );

    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ArrowPainter(
              start: start,
              end: end,
              angle: arrowAngle,
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
                  ),

                  onChanged: (value) {
                    final parsed = parseNodeText(value);

                    if (parsed != value) {
                      _controller.value = TextEditingValue(
                        text: parsed,
                        selection: TextSelection.collapsed(
                          offset: parsed.length,
                        ),
                      );
                    }

                    widget.data.label = parsed;

                    final newLineCount =
                        '\n'.allMatches(parsed).length + 1;

                    if (newLineCount != _lineCount) {
                      setState(() {
                        _lineCount = newLineCount;
                      });
                    }
                  },

                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '~',
                    isDense: true,
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

  const _ArrowPainter({
    required this.start,
    required this.end,
    required this.angle,
  });

  void _drawArrow(Canvas canvas, Offset tip, double angle) {
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

    const double arrowLen = 15;

    final shortenedEnd = Offset(
      end.dx - cos(angle) * arrowLen,
      end.dy - sin(angle) * arrowLen,
    );

    canvas.drawLine(
      start,
      shortenedEnd,
      paint,
    );

    _drawArrow(canvas, end, angle);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return true;
  }
}