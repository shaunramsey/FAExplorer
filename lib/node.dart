import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';

class Node extends StatefulWidget {
  final NodeData data;
  final bool lineMode;
  final ValueChanged<String> onLabelChanged;

  final bool Function(String label, String nodeId) isLabelTaken;
  final ValueChanged<bool>? onDuplicateStateChanged;

  final VoidCallback? onLineModeSelect;
  final VoidCallback? onDoubleTap;

  final bool deleteMode;
  final VoidCallback? onDelete;

  final bool highlighted;

  const Node({
    super.key,
    required this.data,
    required this.lineMode,
    required this.onLabelChanged,
    required this.isLabelTaken,
    this.onDuplicateStateChanged,
    this.onLineModeSelect,
    this.onDoubleTap,
    required this.deleteMode,
    this.onDelete,
    this.highlighted = false,
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

  Color get _borderColor {
    final isDuplicate = widget.isLabelTaken(_controller.text, widget.data.id);

    return widget.deleteMode
        ? Colors.red
        : widget.highlighted
        ? const Color.fromARGB(255, 208, 0, 255)
        : isDuplicate
        ? Colors.orange
        : _selected
        ? Colors.lightBlueAccent
        : Colors.black;
  }

  // ─────────────────────────────────────────────
  // TOKEN PARSER
  // ─────────────────────────────────────────────

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

      if (full.startsWith(r'\')) {
        return full.substring(1);
      }

      final key = (match.group(1) ?? '').trim();

      if (key.startsWith('/')) {
        final text = key.substring(1);
        return text.characters.map((ch) => ch == ' ' ? ch : '$ch\u0338').join();
      }

      return _replacements[key] ?? full;
    });
  }

  // ─────────────────────────────────────────────
  // NODE ID DISPLAY
  // ─────────────────────────────────────────────

  String getDisplayId(String rawId) {
    final number = int.tryParse(rawId.replaceFirst('n', ''));

    if (number == null || number < 0) return rawId;

    int n = number;
    String result = '';

    do {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = (n ~/ 26) - 1;
    } while (n >= 0);

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bool textFieldActive = _selected && !widget.lineMode;
    final startText = getDisplayId(widget.data.id);

    return Positioned(
      top: widget.data.position.dy,
      left: widget.data.position.dx,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
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
          width: 100,
          height: 100,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _borderColor, width: 4),
                  ),
                ),
              ),

              if (widget.data.isAccept)
                Center(
                  child: IgnorePointer(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _borderColor, width: 4),
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
                        color: Colors.green,
                        border: Border.all(color: _borderColor, width: 4),
                      ),
                    ),
                  ),
                ),

              if (widget.data.isHaltReject)
                Center(
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size(60, 60),
                      painter: _OctagonPainter(color: Colors.red, borderColor: _borderColor),
                    ),
                  ),
                ),

              Center(
                child: SizedBox(
                  width: 80,
                  child: IgnorePointer(
                    ignoring: !textFieldActive,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold, fontSize: 30, color: _borderColor),
                      textAlign: TextAlign.center,
                      onEditingComplete: _deselect,
                      onTapOutside: (_) => _deselect(),

                      onChanged: (value) {
                        final parsed = parseNodeText(value);

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

                        widget.data.isHaltAccept = haltAccept;
                        widget.data.isHaltReject = haltReject;

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
                        isDense: true,
                        hintText: startText,
                        hintStyle: TextStyle(color: widget.deleteMode ? Colors.red : Colors.black.withOpacity(0.7)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
