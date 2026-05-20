import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import 'models.dart';

class LinePainter extends CustomPainter {
  final LineGeometry geometry;
  final bool deleteMode;

  const LinePainter({required this.geometry, this.deleteMode = false});

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
        ..color = deleteMode ? Colors.red : Colors.black
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = deleteMode ? Colors.red : Colors.black;

    if (geometry.hasCircle) {
      // Shorten the arc so it ends at the base of the arrowhead (len=15)
      // rather than the tip, preventing the line from poking through.
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
      // Shorten the straight line to the base of the arrowhead (len=15).
      const double arrowLen = 15;
      final double angle = atan2(
        geometry.endPoint.dy - geometry.startPoint.dy,
        geometry.endPoint.dx - geometry.startPoint.dx,
      );
      final Offset shortenedEnd = Offset(
        geometry.endPoint.dx - cos(angle) * arrowLen,
        geometry.endPoint.dy - sin(angle) * arrowLen,
      );

      final double angle2 = atan2(geometry.endPoint.dy - shortenedEnd.dy, geometry.endPoint.dx - shortenedEnd.dx);
      canvas.drawLine(geometry.startPoint, shortenedEnd, paint);

      _drawArrow(canvas, geometry.endPoint, angle2);
    }
  }

  @override
  bool shouldRepaint(LinePainter oldDelegate) => oldDelegate.geometry != geometry;
}

class LineWidget extends StatefulWidget {
  final LineData data;
  final Offset centerA;
  final Offset centerB;
  final bool deleteMode;
  final ValueChanged<String> onLabelChanged;

  const LineWidget({
    super.key,
    required this.data,
    required this.centerA,
    required this.centerB,
    required this.deleteMode,
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

  // ─────────────────────────────────────────────
  // TOKEN PARSER
  // ─────────────────────────────────────────────

  static const Map<String, String> _replacements = {
    // Control
    '\\0': '∅',

    // Greek lowercase
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

    // Greek uppercase
    'GAMMA_CAP': 'Γ',
    'DELTA_CAP': 'Δ',
    'PI_CAP': 'Π',
    'SIGMA_CAP': 'Σ',
    'OMEGA_CAP': 'Ω',
    'PHI_CAP': 'Φ',

    // Math
    'INFINITY': '∞',
    'SQRT': '√',
    'PLUSMINUS': '±',
    'NOTEQUAL': '≠',
    'LESSEQ': '≤',
    'GREATEREQ': '≥',
    'APPROX': '≈',
    'MULTIPLY': '×',
    'DIVIDE': '÷',

    // Arrows
    'LEFT': '←',
    'RIGHT': '→',
    'UP': '↑',
    'DOWN': '↓',
    'LEFTRIGHT': '↔',

    // Misc
    'CHECK': '✓',
    'X': '✗',
    'STAR': '★',
    'HEART': '♥',
    'BULLET': '•',
    'QUESTION': '�',
    'ELLIPSIS': '…',
    'COPY': '©',
    'REGISTERED': '®',
    'TRADEMARK': '™',
    'DEGREE': '°',
    'PARAGRAPH': '¶',
    'SECTION': '§',
    'CURRENCY': '¤',
    'PILCROW': '¶',
    'PEACE': '☮',
    "YIN YANG": '☯',
    "SMILEY": '☺',
    "BLACK SMILEY": '☻',
    "SUN": '☀',
    "CLOUD": '☁',
    "UMBRELLA": '☂',
    "SNOWFLAKE": '❄',
    'SKULL': '☠',
    'SPADE': '♠',
    'CLUB': '♣',
    'DIAMOND': '♦',
    'MUSIC NOTE': '♪',
    'BEAMED EIGHTH NOTES': '♫',
    'RADIOACTIVE': '☢',
    'BIOHAZARD': '☣',
    'CLOVER': '☘',
    'HANDS': '☝',
    'MALE': '♂',
    'FEMALE': '♀',
    'STAR AND CRESCENT': '☪',
    'FALLING STAR': '☫',
    'HAMMER AND SICKLE': '☭',
    'HOT SPRINGS': '♨',
    'HOTEL': '🏨',
    'HOSPITAL': '🏥',
    'HOURGLASS': '⌛',
  };

  String parseNodeText(String input) {
    return input.replaceAllMapped(RegExp(r'\\?\[\[(.*?)\]\]'), (match) {
      final full = match.group(0)!;

      // Escaped token support
      // Example: \[[GAMMA]]
      if (full.startsWith(r'\')) {
        return full.substring(1);
      }

      final key = (match.group(1) ?? '').trim();

      // Diagonal-slash overlay: [[/word]] puts a combining solidus through each character
      if (key.startsWith('/')) {
        final text = key.substring(1);
        return text.characters.map((ch) => ch == ' ' ? ch : '$ch\u0338').join();
      }

      return _replacements[key] ?? full;
    });
  }

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

    // Don't overwrite text while typing
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

    const double boxWidth = 120;
    const double lineHeight = 36.0; // fontSize 30 + padding
    final double boxHeight = lineHeight * _lineCount;

    final Offset mid = widget.data.getTextBoxLocation(
      widget.centerA,
      widget.centerB,
      boxWidth,
      boxHeight,
      widget.data.label,
    );

    return Stack(
      children: [
        // ─────────────────────────────
        // LINE + ARROW
        // ─────────────────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: LinePainter(geometry: geometry, deleteMode: widget.deleteMode),
            ),
          ),
        ),

        // ─────────────────────────────
        // FLOATING LABEL
        // ─────────────────────────────
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
                color: widget.deleteMode ? Colors.red : Colors.black,
              ),
            
              // LIVE TOKEN PARSING
              onChanged: (value) {
                final parsed = parseNodeText(value);
            
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
            
              //onTapOutside: (_) => _focusNode.unfocus(),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '~',
                isDense: true,
                hintStyle: TextStyle(color: widget.deleteMode ? Colors.red : Colors.black.withOpacity(0.7)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
