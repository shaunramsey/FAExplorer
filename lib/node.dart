import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';

class Node extends StatefulWidget {
  final NodeData data;
  final bool lineMode;
  final ValueChanged<String> onLabelChanged;
  final VoidCallback? onLineModeSelect;
  final VoidCallback? onDoubleTap;
  final bool deleteMode;
  final VoidCallback? onDelete;

  const Node({
    super.key,
    required this.data,
    required this.lineMode,
    required this.onLabelChanged,
    this.onLineModeSelect,
    this.onDoubleTap,
    required this.deleteMode,
    this.onDelete,
  });

  @override
  State<Node> createState() => _NodeState();
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
    setState(() => _selected = false);

    widget.onLabelChanged(_controller.text);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _deselect();
    }
  }

  Color get _borderColor => widget.deleteMode
      ? Colors.red
      : _selected
      ? Colors.lightBlueAccent
      : Colors.black;

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

  // ─────────────────────────────────────────────
  // NODE ID DISPLAY
  // ─────────────────────────────────────────────

  String getDisplayId(String rawId) {
    final number = int.tryParse(rawId.replaceFirst('n', ''));

    if (number == null || number < 0) {
      return rawId;
    }

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
              // ─────────────────────────────
              // OUTER CIRCLE
              // ─────────────────────────────
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _borderColor, width: 4),
                  ),
                ),
              ),

              // ─────────────────────────────
              // ACCEPT STATE INNER RING
              // ─────────────────────────────
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

              // ─────────────────────────────
              // TEXT FIELD
              // ─────────────────────────────
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

                      // LIVE TOKEN PARSING
                      onChanged: (value) {
                        final parsed = parseNodeText(value);

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

                        isDense: true,

                        hintText: startText,
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