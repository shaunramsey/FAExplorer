import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import '../pda_simulator.dart';
import '../simulator.dart';
import '../tm_simulator.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Speed levels (ms per step)
// ─────────────────────────────────────────────────────────────────────────────
const _kSpeedLabels = ['0.5×', '1×', '2×', '4×'];
const _kSpeedMs = [1200, 700, 350, 150];

// ─────────────────────────────────────────────────────────────────────────────
//  StringSimulatorPanel
//
//  Indexing contract (matches AutomataSimulator):
//    step == -1  → initial epsilon-closure shown; no chip highlighted
//    step ==  k  → states[k+1] active; the transition that just fired consumed
//                  tokens[k]; chip k is highlighted
//    step == len → all consumed; result shown; no chip highlighted
// ─────────────────────────────────────────────────────────────────────────────
class StringSimulatorPanel extends StatefulWidget {
  const StringSimulatorPanel({
    super.key,
    required this.boundaryKey,
    required this.simulator,
    this.pdaSimulator,
    this.tmSimulator,
    required this.controller,
    required this.nodes,
    required this.onClose,
    required this.onTextChanged,
    required this.onStepChanged,
  });

  final GlobalKey boundaryKey;
  final AutomataSimulator simulator;
  final PdaSimulator? pdaSimulator;
  final dynamic tmSimulator;
  final TextEditingController controller;
  final Map<String, NodeData> nodes;
  final VoidCallback onClose;
  final VoidCallback onTextChanged;
  final VoidCallback onStepChanged;

  @override
  State<StringSimulatorPanel> createState() => _StringSimulatorPanelState();
}

class _StringSimulatorPanelState extends State<StringSimulatorPanel>
    with SingleTickerProviderStateMixin {
  bool _playing = false;
  int _speedIndex = 1;
  Timer? _playTimer;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  final ScrollController _tapeScroll = ScrollController();
  final List<GlobalKey> _chipKeys = [];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _stopPlayback();
    _pulseCtrl.dispose();
    _tapeScroll.dispose();
    super.dispose();
  }

  // ── playback ─────────────────────────────────────────────────────────────

  void _syncTmStep() {
    final tm = widget.tmSimulator as TmSimulator?;
    if (tm != null) {
      tm.step = widget.simulator.step;
    }
  }

  void _startPlayback() {
    if (_playing) return;
    final tm = widget.tmSimulator as TmSimulator?;
    final maxStep = tm != null
        ? (tm.steps.isEmpty ? 0 : tm.steps.length - 1)
        : widget.simulator.tokens.length;
    if (widget.simulator.step >= maxStep) {
      setState(() => widget.simulator.step = -1);
      _syncTmStep();
      widget.onStepChanged();
    }
    setState(() => _playing = true);
    _scheduleNextStep();
  }

  void _stopPlayback() {
    _playing = false;
    _playTimer?.cancel();
    _playTimer = null;
  }

  void _scheduleNextStep() {
    _playTimer?.cancel();
    _playTimer = Timer(Duration(milliseconds: _kSpeedMs[_speedIndex]), _tick);
  }

  void _tick() {
    if (!mounted) return;
    final sim = widget.simulator;
    final tm = widget.tmSimulator as TmSimulator?;
    final maxStep = tm != null
        ? (tm.steps.isEmpty ? 0 : tm.steps.length - 1)
        : sim.tokens.length;
    if (sim.step >= maxStep) {
      setState(_stopPlayback);
      widget.onStepChanged();
      return;
    }
    setState(() => sim.step++);
    _syncTmStep();
    widget.onStepChanged();
    _scrollToCurrentChip();
    if (sim.step >= maxStep) {
      setState(_stopPlayback);
    } else {
      _scheduleNextStep();
    }
  }

  void _togglePlayback() {
    if (_playing) {
      setState(_stopPlayback);
    } else {
      _startPlayback();
    }
  }

  void _stepBack() {
    _stopPlayback();
    if (widget.simulator.step > -1) {
      setState(() => widget.simulator.step--);
      _syncTmStep();
      widget.onStepChanged();
      _scrollToCurrentChip();
    }
  }

  void _stepForward() {
    _stopPlayback();
    final tm = widget.tmSimulator as TmSimulator?;
    final maxStep = tm != null
        ? (tm.steps.isEmpty ? 0 : tm.steps.length - 1)
        : widget.simulator.tokens.length;
    if (widget.simulator.step < maxStep) {
      setState(() => widget.simulator.step++);
      _syncTmStep();
      widget.onStepChanged();
      _scrollToCurrentChip();
    }
  }

  void _rewind() {
    _stopPlayback();
    setState(() => widget.simulator.step = -1);
    _syncTmStep();
    widget.onStepChanged();
    _scrollToChip(0);
  }

  void _skipToEnd() {
    _stopPlayback();
    final tm = widget.tmSimulator as TmSimulator?;
    final maxStep = tm != null
        ? (tm.steps.isEmpty ? 0 : tm.steps.length - 1)
        : widget.simulator.tokens.length;
    setState(() => widget.simulator.step = maxStep);
    _syncTmStep();
    widget.onStepChanged();
    _scrollToChip(widget.simulator.tokens.length - 1);
  }

  // ── scroll ───────────────────────────────────────────────────────────────

  void _scrollToCurrentChip() {
    final idx = widget.simulator.step;
    if (idx >= 0 && idx < widget.simulator.tokens.length) {
      _scrollToChip(idx);
    }
  }

  void _scrollToChip(int idx) {
    if (idx < 0 || idx >= _chipKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _chipKeys[idx].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // ── result ────────────────────────────────────────────────────────────────

  SimResult? get _currentResult {
    final sim = widget.simulator;
    final pda = widget.pdaSimulator;
    final tm  = widget.tmSimulator as TmSimulator?;

    if (tm != null) {
      if (tm.steps.isEmpty) return null;
      final r = tm.result;
      if (r == TmResult.running) return null;
      return r == TmResult.accept ? SimResult.accept : SimResult.reject;
    }

    if (pda != null) {
      if (pda.tokens.isEmpty && pda.steps.isEmpty) return null;
      final r = pda.finalResult();
      return r == PdaSimResult.accept ? SimResult.accept : SimResult.reject;
    }

    if (sim.tokens.isEmpty && sim.states.isEmpty) return null;
    return sim.finalResult();
  }

  Color _resultColor(SimResult r) {
    switch (r) {
      case SimResult.accept:
        return Colors.green.shade700;
      case SimResult.reject:
        return Colors.red.shade700;
    }
  }

  String _resultLabel(SimResult r) {
    switch (r) {
      case SimResult.accept:
        return 'ACCEPT';
      case SimResult.reject:
        return 'REJECT';
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sim = widget.simulator;
    final tokens = sim.tokens;
    final step = sim.step;
    final tm = widget.tmSimulator as TmSimulator?;
    final isTmMode = tm != null;

    // In TM mode the number of simulation steps is independent of input length.
    final maxStep = isTmMode
        ? (tm.steps.isEmpty ? 0 : tm.steps.length - 1)
        : tokens.length;

    // Keep chip key list in sync with token count.
    if (_chipKeys.length != tokens.length) {
      _chipKeys
        ..clear()
        ..addAll(List.generate(tokens.length, (_) => GlobalKey()));
    }

    final atStart    = step <= -1;
    final atEnd      = step >= maxStep;
    final hasTokens  = isTmMode ? tm.steps.isNotEmpty : tokens.isNotEmpty;
    final result     = _currentResult;
    // In TM mode the machine may halt before the user reaches atEnd, so
    // show the result banner as soon as a definitive result is available.
    final showResult = result != null && (atEnd || isTmMode);

    // Chip k is highlighted when step == k (transition for tokens[k] just fired).
    // step == -1 or step == tokens.length → no chip highlighted.
    final currentChipIndex = (step >= 0 && step < tokens.length) ? step : -1;

    // Get TM tape view if available
    final tapeView = isTmMode ? tm.tapeView : null;

    return Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: widget.boundaryKey,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 0, 0),
          width: 250,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                child: Row(
                  children: [
                    const Icon(Icons.science, size: 14, color: Colors.purple),
                    const SizedBox(width: 6),
                    Text(
                      'Simulator',
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      onPressed: widget.onClose,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Input field
                    TextField(
                      controller: widget.controller,
                      onChanged: (_) {
                        _stopPlayback();
                        widget.onTextChanged();
                      },
                      style: GoogleFonts.courierPrime(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Input string…',
                        hintStyle: GoogleFonts.courierPrime(
                          color: Colors.black38,
                          fontSize: 13,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),

                    // Token/Tape display
                    if (isTmMode && tapeView != null) ...[
                      // TM tape view with head position
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          controller: _tapeScroll,
                          scrollDirection: Axis.horizontal,
                          itemCount: tapeView.cells.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 2),
                          itemBuilder: (context, i) {
                            final isHeadHere = i == tapeView.headIndex;
                            final cell = tapeView.cells[i];
                            return _TapeCellChip(
                              cell: cell,
                              isHead: isHeadHere,
                              pulseAnim: _pulseAnim,
                            );
                          },
                        ),
                      ),
                    ] else if (hasTokens) ...[
                      // PDA/DFA token tape
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 32,
                        child: ListView.separated(
                          controller: _tapeScroll,
                          scrollDirection: Axis.horizontal,
                          itemCount: tokens.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 3),
                          itemBuilder: (context, i) {
                            final isCurrent  = i == currentChipIndex;
                            final isConsumed = i < currentChipIndex;
                            return _TokenChip(
                              key: _chipKeys[i],
                              token: tokens[i],
                              isCurrent: isCurrent,
                              isConsumed: isConsumed,
                              pulseAnim: _pulseAnim,
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 4),

                    // Transport buttons row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TransportBtn(
                          icon: Icons.skip_previous,
                          tooltip: 'Rewind',
                          onPressed: (hasTokens && !atStart) ? _rewind : null,
                        ),
                        _TransportBtn(
                          icon: Icons.chevron_left,
                          tooltip: 'Step back',
                          onPressed: (hasTokens && !atStart) ? _stepBack : null,
                        ),
                        // Play/pause
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Material(
                            color: (hasTokens && !atEnd)
                                ? (_playing
                                    ? const Color.fromARGB(255, 208, 0, 255)
                                    : Colors.black87)
                                : Colors.black12,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: (hasTokens && !atEnd) ? _togglePlayback : null,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  _playing ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 17,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _TransportBtn(
                          icon: Icons.chevron_right,
                          tooltip: 'Step forward',
                          onPressed: (hasTokens && !atEnd) ? _stepForward : null,
                        ),
                        _TransportBtn(
                          icon: Icons.skip_next,
                          tooltip: 'Skip to end',
                          onPressed: (hasTokens && !atEnd) ? _skipToEnd : null,
                        ),
                      ],
                    ),

                    // Speed selector row
                    if (hasTokens) ...[
                      const SizedBox(height: 4),
                      SegmentedButton<int>(
                        segments: List.generate(
                          _kSpeedLabels.length,
                          (i) => ButtonSegment<int>(
                            value: i,
                            label: Text(
                              _kSpeedLabels[i],
                              style: GoogleFonts.courierPrime(fontSize: 10),
                            ),
                          ),
                        ),
                        selected: {_speedIndex},
                        onSelectionChanged: (s) {
                          setState(() => _speedIndex = s.first);
                          if (_playing) {
                            _playTimer?.cancel();
                            _scheduleNextStep();
                          }
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 4),
                          ),
                        ),
                        showSelectedIcon: false,
                      ),
                    ],

                    // Result banner
                    if (showResult) ...[
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _resultColor(result).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _resultColor(result).withOpacity(0.5),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _resultLabel(result),
                            style: GoogleFonts.courierPrime(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _resultColor(result),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
//  Small transport icon button
// ─────────────────────────────────────────────────────────────────────────────
class _TransportBtn extends StatelessWidget {
  const _TransportBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Token chip
// ─────────────────────────────────────────────────────────────────────────────
class _TokenChip extends StatelessWidget {
  const _TokenChip({
    super.key,
    required this.token,
    required this.isCurrent,
    required this.isConsumed,
    required this.pulseAnim,
  });

  final String token;
  final bool isCurrent;
  final bool isConsumed;
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, child) =>
            Transform.scale(scale: pulseAnim.value, child: child),
        child: _chip(
          bg: const Color.fromARGB(255, 208, 0, 255),
          fg: Colors.white,
          border: const Color.fromARGB(255, 160, 0, 200),
          bold: true,
        ),
      );
    }
    if (isConsumed) {
      return _chip(
        bg: Colors.grey.shade200,
        fg: Colors.black38,
        border: Colors.grey.shade300,
        bold: false,
      );
    }
    return _chip(
      bg: Colors.transparent,
      fg: Colors.black87,
      border: Colors.black26,
      bold: false,
    );
  }

  Widget _chip({
    required Color bg,
    required Color fg,
    required Color border,
    required bool bold,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Center(
        child: Text(
          token,
          style: GoogleFonts.courierPrime(
            fontSize: 12,
            color: fg,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tape cell chip (for TM mode)
// ─────────────────────────────────────────────────────────────────────────────
class _TapeCellChip extends StatelessWidget {
  const _TapeCellChip({
    required this.cell,
    required this.isHead,
    required this.pulseAnim,
  });

  final String cell;
  final bool isHead;
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
    if (isHead) {
      return AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, child) =>
            Transform.scale(scale: pulseAnim.value, child: child),
        child: Container(
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 208, 0, 255),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: const Color.fromARGB(255, 160, 0, 200),
              width: 1.2,
            ),
          ),
          child: Center(
            child: Text(
              cell == kBlank ? '∅' : cell,
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.black26, width: 1),
      ),
      child: Center(
        child: Text(
          cell == kBlank ? '∅' : cell,
          style: GoogleFonts.courierPrime(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}