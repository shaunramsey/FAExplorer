import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../simulator.dart';

class StringSimulatorPanel extends StatefulWidget {
  final GlobalKey boundaryKey;
  final AutomataSimulator simulator;
  final TextEditingController controller;
  final Map<String, NodeData> nodes;
  final VoidCallback onClose;
  final VoidCallback onTextChanged;
  final VoidCallback onStepChanged;

  const StringSimulatorPanel({
    super.key,
    required this.boundaryKey,
    required this.simulator,
    required this.controller,
    required this.nodes,
    required this.onClose,
    required this.onTextChanged,
    required this.onStepChanged,
  });

  @override
  State<StringSimulatorPanel> createState() => _StringSimulatorPanelState();
}

class _StringSimulatorPanelState extends State<StringSimulatorPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _afterTextChange() {
    widget.onTextChanged();
    setState(() {});
  }

  void _afterStepChange() {
    widget.onStepChanged();
    setState(() {});
  }

  String _stepLabel() {
    if (widget.simulator.tokens.isEmpty) return '—';
    if (widget.simulator.step < 0) return 'start';
    return '${widget.simulator.step} / ${widget.simulator.tokens.length}';
  }

  Widget _statusBox() {
    IconData icon;
    Color color;
    final atEnd = widget.simulator.step == widget.simulator.tokens.length && widget.simulator.tokens.isNotEmpty;
    if (!atEnd || widget.simulator.states.isEmpty) {
      icon = Icons.question_mark;
      color = Colors.grey.shade400;
    } else {
      final r = widget.simulator.finalResult();
      if (r == SimResult.accept) {
        icon = Icons.check;
        color = Colors.green;
      } else if (r == SimResult.reject) {
        icon = Icons.close;
        color = Colors.red;
      } else {
        icon = Icons.question_mark;
        color = Colors.orange;
      }
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black54, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _panelContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IgnorePointer(
              child: Text(
                'String Simulation',
                style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.close, size: 16, color: Colors.black54),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          style: GoogleFonts.courierPrime(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Enter input string…',
            hintStyle: GoogleFonts.courierPrime(fontSize: 12, color: Colors.black38),
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      widget.controller.clear();
                      widget.simulator.tokens = [];
                      widget.simulator.step = -1;
                      widget.simulator.states.clear();
                      widget.simulator.usedLines.clear();
                      _afterStepChange();
                    },
                  )
                : null,
          ),
          onChanged: (_) => _afterTextChange(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 20),
              tooltip: 'Go to start',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: widget.simulator.tokens.isEmpty
                  ? null
                  : () {
                      widget.simulator.step = -1;
                      _afterStepChange();
                    },
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              tooltip: 'Step back',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: (widget.simulator.step <= -1 || widget.simulator.tokens.isEmpty)
                  ? null
                  : () {
                      widget.simulator.step--;
                      _afterStepChange();
                    },
            ),
            const Spacer(),
            IgnorePointer(child: _statusBox()),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              tooltip: 'Step forward',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: (widget.simulator.tokens.isEmpty || widget.simulator.step >= widget.simulator.tokens.length)
                  ? null
                  : () {
                      widget.simulator.step++;
                      if (widget.simulator.step < widget.simulator.states.length) {
                        final states = widget.simulator.states[widget.simulator.step];
                        for (final nid in states) {
                          if (widget.nodes[nid]?.isHaltAccept == true) {
                            widget.simulator.step = widget.simulator.tokens.length;
                            break;
                          }
                        }
                      }
                      _afterStepChange();
                    },
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 20),
              tooltip: 'Go to end',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: (widget.simulator.tokens.isEmpty || widget.simulator.step == widget.simulator.tokens.length)
                  ? null
                  : () {
                      widget.simulator.step = widget.simulator.tokens.length;
                      _afterStepChange();
                    },
            ),
          ],
        ),
        IgnorePointer(
          child: Center(
            child: Text(
              _stepLabel(),
              style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black54),
            ),
          ),
        ),
        if (widget.simulator.tokens.isNotEmpty) ...[
          const SizedBox(height: 4),
          IgnorePointer(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(widget.simulator.tokens.length, (i) {
                  final consumed = widget.simulator.step > i;
                  final current = widget.simulator.step == i;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: current
                          ? Colors.lightBlueAccent.withValues(alpha: 0.4)
                          : consumed
                          ? Colors.grey.shade200
                          : Colors.transparent,
                      border: Border.all(
                        color: current ? Colors.lightBlueAccent : Colors.black26,
                        width: current ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.simulator.tokens[i],
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: consumed ? Colors.black38 : Colors.black,
                        fontWeight: current ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(12, 10, 12, 10);

    return Positioned(
      top: 12,
      left: 12,
      child: SizedBox(
        key: widget.boundaryKey,
        width: 280,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IgnorePointer(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.96),
                child: Padding(
                  padding: padding,
                  child: _panelContent(),
                ),
              ),
            ),
            Padding(
              padding: padding,
              child: _panelContent(),
            ),
          ],
        ),
      ),
    );
  }
}
