import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';
import 'token_replacements.dart'; // ← single source of truth

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
        : Colors.white;
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
    // When locked (e.g. placing the start arrow), do not allow selection/editing.
    final bool textFieldActive = _selected && !widget.lineMode && !widget.interactionLocked;
    final startText = getDisplayId(widget.data.id);
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
                    border: Border.all(color: _borderColor, width: 4),
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
                              border: Border.all(color: _borderColor, width: 3),
                            ),
                          )
                        : Container(
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
                  width: isBlackBox ? 118 : 80,
                  child: IgnorePointer(
                    ignoring: !textFieldActive,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: isBlackBox ? 20 : 30,
                        color: _borderColor,
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
                        hintStyle: TextStyle(color: widget.deleteMode ? Colors.red : Colors.white.withOpacity(0.35)),
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