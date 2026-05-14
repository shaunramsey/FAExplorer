import 'package:flutter/material.dart';
import 'models.dart';

class Node extends StatefulWidget {
  final NodeData data;
  final bool lineMode;
  final ValueChanged<String> onLabelChanged;
  final VoidCallback? onLineModeSelect;
  final VoidCallback? onDoubleTap;

  const Node({
    super.key,
    required this.data,
    required this.lineMode,
    required this.onLabelChanged,
    this.onLineModeSelect,
    this.onDoubleTap,
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
    // Only overwrite the field when we are not the active editor
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
    if (!_focusNode.hasFocus) _deselect();
  }

  Color get _borderColor => _selected ? Colors.lightBlueAccent : Colors.black;

  @override
  Widget build(BuildContext context) {
    // The TextField must NEVER participate in the gesture arena unless
    // the node is actively selected for editing.  If it can receive
    // pointer-down events it wins the arena and the parent canvas pan
    // detector never fires, breaking both node drag and line drag.
    final bool textFieldActive = _selected && !widget.lineMode;
    String getDisplayId(String rawId) {
      // Extract number from ids like "n0", "n26", etc.
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
    final startText = getDisplayId(widget.data.id);

    return Positioned(
      top: widget.data.position.dy,
      left: widget.data.position.dx,
      // translucent: this node's GestureDetector handles tap/doubleTap
      // but does NOT block the parent GestureDetector from seeing pans.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
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
              // ── Outer circle ───────────────────────────────────────
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _borderColor, width: 4),
                  ),
                ),
              ),

              // ── Accept-state inner ring ────────────────────────────
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

              // ── Label text field ───────────────────────────────────
              // IgnorePointer when not actively editing so that all
              // pointer-downs on an unselected node fall through to the
              // GestureDetector above (and then to the parent canvas pan).
              Center(
                child: SizedBox(
                  width: 80,
                  child: IgnorePointer(
                    ignoring: !textFieldActive,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 30,
                        fontFamily: 'Courier',
                        color: _borderColor,
                      ),
                      textAlign: TextAlign.center,
                      onEditingComplete: _deselect,
                      onTapOutside: (_) => _deselect(),
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
