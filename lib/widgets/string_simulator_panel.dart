import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import '../pda_simulator.dart';
import '../simulator.dart';
import '../tm_simulator.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme palette (mirrors main.dart)
// ─────────────────────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF05080F);
const _kSurface   = Color(0xFF0A0F18);
const _kBorderMid = Color(0xFF1A2535);
const _kAccent    = Color(0xFF00E5FF);
const _kTextLight = Color(0xFFCDD5E0);
const _kTextMid   = Color(0xFF6B7E96);
const _kTextDim   = Color(0xFF3A4A5E);

// ─────────────────────────────────────────────────────────────────────────────
//  Speed levels (ms per step)
// ─────────────────────────────────────────────────────────────────────────────
const _kSpeedLabels = ['0.5×', '1×', '2×', '4×'];
const _kSpeedMs = [1200, 700, 350, 150];

// ─────────────────────────────────────────────────────────────────────────────
//  StringSimulatorPanel
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
      tm.step = widget.simulator.step.clamp(-1, tm.maxStep);
    }
  }

  void _startPlayback() {
    if (_playing) return;
    final tm = widget.tmSimulator as TmSimulator?;
    final maxStep = tm != null
        ? tm.maxStep
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
    if (tm != null) {
      final appended = tm.computeNext();
      if (appended) {
        setState(() => sim.step = tm.maxStep);
        _syncTmStep();
        widget.onStepChanged();
        if (_playing) _scheduleNextStep();
      } else {
        if (_playing) setState(_stopPlayback);
      }
      return;
    }

    final maxStep = sim.tokens.length;
    if (sim.step >= maxStep) {
      setState(_stopPlayback);
      widget.onStepChanged();
      return;
    }
    setState(() => sim.step++);
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
    if (tm != null) {
      if (widget.simulator.step < tm.maxStep) {
        setState(() => widget.simulator.step++);
        _syncTmStep();
        widget.onStepChanged();
        return;
      }
      final appended = tm.computeNext();
      if (appended) {
        setState(() => widget.simulator.step = tm.maxStep);
        _syncTmStep();
        widget.onStepChanged();
      } else {
        _syncTmStep();
        widget.onStepChanged();
      }
      return;
    }

    final maxStep = widget.simulator.tokens.length;
    if (widget.simulator.step < maxStep) {
      setState(() => widget.simulator.step++);
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
    if (tm != null) {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      bool progressed = false;
      while (DateTime.now().isBefore(deadline)) {
        final beforeLen = tm.steps.length;
        final appended = tm.computeNext();
        if (!appended) break;
        progressed = true;
        if (DateTime.now().isAfter(deadline) && tm.steps.length > beforeLen) {
          tm.undoLastStep();
          break;
        }
      }
      if (progressed) {
        setState(() => widget.simulator.step = tm.maxStep);
        _syncTmStep();
        widget.onStepChanged();
      }
      return;
    }

    final maxStep = widget.simulator.tokens.length;
    setState(() => widget.simulator.step = maxStep);
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
        return const Color(0xFF1FD99A);
      case SimResult.reject:
        return const Color(0xFFFF1744);
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

    final maxStep = isTmMode
        ? tm.maxStep
        : tokens.length;

    if (_chipKeys.length != tokens.length) {
      _chipKeys
        ..clear()
        ..addAll(List.generate(tokens.length, (_) => GlobalKey()));
    }

    final atStart = step <= -1;
    final hasTokens = isTmMode ? tm.steps.isNotEmpty : tokens.isNotEmpty;

    bool atEnd;
    if (isTmMode) {
      final snap = tm.currentSnapshot;
      if (snap == null) {
        atEnd = true;
      } else if (snap.configs.isEmpty) {
        atEnd = true;
      } else {
        bool anyHaltAccept = false;
        bool allHalted = true;
        for (final c in snap.configs) {
          final node = widget.nodes[c.nodeId];
          if (node == null) continue;
          if (node.isHaltAccept) anyHaltAccept = true;
          final isHalt = node.isHaltAccept || node.isHaltReject;
          if (!isHalt) allHalted = false;
        }
        atEnd = anyHaltAccept || allHalted;
      }
    } else {
      atEnd = step >= maxStep;
    }
    final result     = _currentResult;
    final showResult = result != null && (atEnd || isTmMode);

    final currentChipIndex = (step > 0 && step <= tokens.length) ? step - 1 : -1;

    final tapeView = isTmMode ? tm.tapeView : null;

    return Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: widget.boundaryKey,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 0, 0),
          width: 250,
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorderMid, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: _kAccent.withOpacity(0.04),
                blurRadius: 24,
                spreadRadius: -4,
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
                    Icon(Icons.science, size: 14, color: _kAccent),
                    const SizedBox(width: 6),
                    Text(
                      'Simulator',
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _kTextLight,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, size: 14, color: _kTextMid),
                      onPressed: widget.onClose,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: _kBorderMid),

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
                      style: GoogleFonts.courierPrime(fontSize: 13, color: _kTextLight),
                      cursorColor: _kAccent,
                      decoration: InputDecoration(
                        hintText: 'Input string…',
                        hintStyle: GoogleFonts.courierPrime(
                          color: _kTextDim,
                          fontSize: 13,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF080D14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _kBorderMid),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _kBorderMid),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _kAccent, width: 1.5),
                        ),
                      ),
                    ),

                    // Token/Tape display
                    if (isTmMode && tapeView != null) ...[
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
                            final isConsumed = currentChipIndex >= 0
                                ? i < currentChipIndex
                                : i < step;
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
                                    : _kBorderMid)
                                : _kBg,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: (hasTokens && !atEnd) ? _togglePlayback : null,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  _playing ? Icons.pause : Icons.play_arrow,
                                  color: _kTextLight,
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
                          tooltip: isTmMode ? 'Fast forward (5s)' : 'Skip to end',
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
                              style: GoogleFonts.courierPrime(fontSize: 10, color: _kTextMid),
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
      icon: Icon(icon, size: 17, color: onPressed != null ? _kTextLight : _kTextDim),
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
        bg: const Color(0xFF0D1620),
        fg: _kTextDim,
        border: const Color(0xFF1A2535),
        bold: false,
      );
    }
    return _chip(
      bg: Colors.transparent,
      fg: _kTextMid,
      border: _kBorderMid,
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
        color: const Color(0xFF0D1620),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _kBorderMid, width: 1),
      ),
      child: Center(
        child: Text(
          cell == kBlank ? '∅' : cell,
          style: GoogleFonts.courierPrime(
            fontSize: 12,
            color: _kTextMid,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}