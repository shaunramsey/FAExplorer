import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import 'app_theme.dart';
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
    this.tapeNames = const [],
    this.activeTapeIndex = 0,
    this.onTapeSelected,
    this.onTapeAdded,
    this.onTapeRemoved,
    this.onTapeRenamed,
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

  /// Names of all available tapes (e.g. ["Tape 1", "Tape 2"]).
  /// If this list has fewer than 2 entries, the tab strip is hidden
  /// (single-tape mode), preserving the original layout.
  final List<String> tapeNames;

  /// Index of the currently active tape within [tapeNames].
  final int activeTapeIndex;

  /// Called when the user taps a tape tab to switch to it.
  final ValueChanged<int>? onTapeSelected;

  /// Called when the user taps the "add tape" button. Should append a new
  /// tape and make it active.
  final VoidCallback? onTapeAdded;

  /// Called when the user removes the tape at the given index.
  final ValueChanged<int>? onTapeRemoved;

  /// Called when the user renames the tape at the given index to the given name.
  final void Function(int index, String name)? onTapeRenamed;

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

  // ── string history ────────────────────────────────────────────────────────
  final List<String> _strings = [''];
  int _stringIndex = 0;

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

  // ── string history navigation ─────────────────────────────────────────────

  void _saveCurrentString() {
    _strings[_stringIndex] = widget.controller.text;
  }

  void _applyString(int newIndex) {
    _saveCurrentString();
    setState(() => _stringIndex = newIndex);
    widget.controller.text = _strings[_stringIndex];
    _stopPlayback();
    widget.onTextChanged();
  }

  void _prevString() {
    if (_stringIndex > 0) _applyString(_stringIndex - 1);
  }

  void _nextString() {
    _saveCurrentString();
    if (_stringIndex < _strings.length - 1) {
      _applyString(_stringIndex + 1);
    } else {
      setState(() {
        _strings.add('');
        _stringIndex = _strings.length - 1;
      });
      widget.controller.text = '';
      _stopPlayback();
      widget.onTextChanged();
    }
  }

  void _deleteCurrentString() {
    if (_strings.length <= 1) return;
    setState(() {
      _strings.removeAt(_stringIndex);
      if (_stringIndex >= _strings.length) _stringIndex = _strings.length - 1;
    });
    widget.controller.text = _strings[_stringIndex];
    _stopPlayback();
    widget.onTextChanged();
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
    final theme = context.watch<AppThemeNotifier>();
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

    final currentChipIndex = (step >= 0 && step < tokens.length) ? step : -1;

    final tapeView = isTmMode ? tm.tapeView : null;

    return Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: widget.boundaryKey,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 0, 0),
          width: 250,
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.borderMid, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: theme.accent.withOpacity(0.04),
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
                    Icon(Icons.science, size: 14, color: theme.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Simulator',
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.textLight,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, size: 14, color: theme.textMid),
                      onPressed: widget.onClose,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: theme.borderMid),

              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Input field with string navigation arrows
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _StringNavArrow(
                          icon: Icons.arrow_left,
                          tooltip: 'Previous string',
                          enabled: _stringIndex > 0,
                          onPressed: _prevString,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: TextField(
                            controller: widget.controller,
                            onChanged: (v) {
                              _strings[_stringIndex] = v;
                              _stopPlayback();
                              widget.onTextChanged();
                            },
                            style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
                            cursorColor: theme.accent,
                            decoration: InputDecoration(
                              hintText: 'Input string…',
                              hintStyle: GoogleFonts.courierPrime(
                                color: theme.textDim,
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
                                borderSide: BorderSide(color: theme.borderMid),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: theme.borderMid),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: theme.accent, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        _StringNavArrow(
                          icon: Icons.arrow_right,
                          tooltip: _stringIndex < _strings.length - 1
                              ? 'Next string'
                              : 'Add new string',
                          enabled: true,
                          onPressed: _nextString,
                        ),
                      ],
                    ),

                    // String counter + delete
                    if (_strings.length > 1) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${_stringIndex + 1} / ${_strings.length}',
                            style: GoogleFonts.courierPrime(
                              fontSize: 10,
                              color: theme.textDim,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: _deleteCurrentString,
                            child: Tooltip(
                              message: 'Delete this string',
                              child: Icon(
                                Icons.close,
                                size: 11,
                                color: theme.textDim,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

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
                            final isConsumed = currentChipIndex >= 0 ? i < currentChipIndex : i < step;
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
                                    ? theme.panelHighlight
                                    : theme.borderMid)
                                : theme.bg,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: (hasTokens && !atEnd) ? _togglePlayback : null,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  _playing ? Icons.pause : Icons.play_arrow,
                                  color: theme.textLight,
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
                              style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textMid),
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
//  String navigation arrow button
// ─────────────────────────────────────────────────────────────────────────────
class _StringNavArrow extends StatelessWidget {
  const _StringNavArrow({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          width: 22,
          height: 30,
          decoration: BoxDecoration(
            color: enabled
                ? theme.surface
                : theme.bg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: enabled ? theme.borderMid : theme.borderMid.withOpacity(0.4),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? theme.textMid : theme.textDim.withOpacity(0.35),
          ),
        ),
      ),
    );
  }
}
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
    final theme = context.watch<AppThemeNotifier>();
    return IconButton(
      icon: Icon(icon, size: 17, color: onPressed != null ? theme.textLight : theme.textDim),
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
    final theme = context.watch<AppThemeNotifier>();

    if (isCurrent) {
      return AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, child) =>
            Transform.scale(scale: pulseAnim.value, child: child),
        child: _chip(
          bg: theme.panelHighlight,
          fg: theme.textLight,
          border: theme.panelHighlight.withOpacity(0.75),
          bold: true,
        ),
      );
    }
    if (isConsumed) {
      return _chip(
        bg: theme.gridLine,
        fg: theme.textDim,
        border: theme.borderMid,
        bold: false,
      );
    }
    return _chip(
      bg: Colors.transparent,
      fg: theme.textMid,
      border: theme.borderMid,
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
    final theme = context.watch<AppThemeNotifier>();

    if (isHead) {
      return AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, child) =>
            Transform.scale(scale: pulseAnim.value, child: child),
        child: Container(
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: theme.panelHighlight,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: theme.panelHighlight.withOpacity(0.75),
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
        color: theme.gridLine,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.borderMid, width: 1),
      ),
      child: Center(
        child: Text(
          cell == kBlank ? '∅' : cell,
          style: GoogleFonts.courierPrime(
            fontSize: 12,
            color: theme.textMid,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}