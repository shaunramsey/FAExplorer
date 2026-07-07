// ─────────────────────────────────────────────────────────────────────────────
//  sim_panels.dart
//
//  Floating panels shown only while a simulation is active. Merged from the
//  formerly-separate pda_stack_panel.dart, tm_config_panel.dart,
//  regex_panel.dart, and string_simulator_panel.dart, which all lived in the
//  same "simulation UI" niche and shared theme/model dependencies:
//
//    • PdaStackPanel          — NPDA configurations (state, input, stack)
//    • TmConfigPanel          — NTM configurations (state, head, tape)
//    • RegexPanel             — regex → DFA conversion panel
//    • StringSimulatorPanel   — token/tape scrubber + playback transport
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../simulator.dart';
import 'app_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  PDA STACK PANEL
// ═════════════════════════════════════════════════════════════════════════════

/// Floating panel: NPDA configurations (state, remaining input, stack) per step.
class PdaStackPanel extends StatelessWidget {
  final PdaSimulator simulator;
  final Map<String, NodeData> nodes;

  const PdaStackPanel({
    super.key,
    required this.simulator,
    required this.nodes,
  });

  String _stateLabel(String nodeId) => displayNodeLabel(nodeId, nodes);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final configs = simulator.activeConfigs;
    final result = simulator.finalResult();
    final atEnd = simulator.step == simulator.maxStep;

    Color? headerColor;
    if (atEnd && simulator.tokens.isNotEmpty) {
      headerColor = switch (result) {
        PdaSimResult.accept => const Color(0xFF1FD99A),
        PdaSimResult.reject => const Color(0xFFFF1744),
      };
    }

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 480),
          child: Card(
            color: theme.surface,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.borderMid),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.layers, size: 18,
                          color: headerColor ?? theme.accent),
                      const SizedBox(width: 6),
                      Text(
                        'PDA (NPDA)',
                        style: GoogleFonts.courierPrime(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: headerColor ?? theme.textLight,
                        ),
                      ),
                      const Spacer(),
                      if (atEnd && simulator.tokens.isNotEmpty)
                        Text(
                          switch (result) {
                            PdaSimResult.accept => 'ACCEPT',
                            PdaSimResult.reject => 'REJECT',
                          },
                          style: GoogleFonts.courierPrime(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: headerColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    simulator.tokens.isEmpty
                        ? 'No input'
                        : simulator.step < 0
                            ? 'Before input'
                            : 'After token ${simulator.step} / ${simulator.tokens.length}',
                    style: GoogleFonts.courierPrime(fontSize: 11, color: theme.textDim),
                  ),
                  Divider(height: 16, color: theme.borderMid),
                  if (simulator.stackGrowthLoopDetected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Stopped: ~-closure stack became too large '
                        '(typical unbounded free-push like ~,~|X). '
                        'If you want to drain a loop, use ~,symbol|~.',
                        style: GoogleFonts.courierPrime(
                          fontSize: 12,
                          color: const Color(0xFFFF9E40),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (configs.isEmpty)
                    Text(
                      simulator.stackGrowthLoopDetected
                          ? 'Simulation aborted'
                          : 'No active configuration',
                      style: GoogleFonts.courierPrime(
                          fontSize: 13, color: const Color(0xFFFF1744)),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < configs.length; i++) ...[
                              if (configs.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'Configuration ${i + 1}',
                                    style: GoogleFonts.courierPrime(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: theme.textDim,
                                    ),
                                  ),
                                ),
                              _ConfigCard(
                                stateLabel: _stateLabel(configs[i].nodeId),
                                remaining: simulator.remainingInputAt(i),
                                stack: configs[i].stack,
                              ),
                              if (i < configs.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final String stateLabel;
  final String remaining;
  final List<String> stack;

  const _ConfigCard({
    required this.stateLabel,
    required this.remaining,
    required this.stack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RowLabel(label: 'state', value: stateLabel),
          const SizedBox(height: 4),
          _RowLabel(
            label: 'input',
            value: remaining.isEmpty ? '~' : remaining,
            muted: remaining.isEmpty,
          ),
          const SizedBox(height: 8),
          Text(
            'stack',
            style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
          ),
          const SizedBox(height: 4),
          _StackView(stack: stack),
        ],
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;

  const _RowLabel({
    required this.label,
    required this.value,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.courierPrime(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: muted ? theme.textDim : theme.textLight,
            ),
          ),
        ),
      ],
    );
  }
}

class _StackView extends StatelessWidget {
  final List<String> stack;

  const _StackView({required this.stack});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    if (stack.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: theme.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.borderMid),
        ),
        child: Text(
          '(empty)',
          style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textDim),
          textAlign: TextAlign.center,
        ),
      );
    }

    final displayItems = stack.reversed.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < displayItems.length; i++)
          _StackCell(
            symbol: displayItems[i],
            isTop: i == 0,
            isBottom: i == displayItems.length - 1,
          ),
      ],
    );
  }
}

class _StackCell extends StatelessWidget {
  final String symbol;
  final bool isTop;
  final bool isBottom;

  const _StackCell({
    required this.symbol,
    required this.isTop,
    required this.isBottom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final display = symbol.isEmpty ? '~' : symbol;
    final isBottomMarker = symbol == kStackBottom;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: isTop ? const Color(0xFF0A1929) : const Color(0xFF080D14),
        borderRadius: BorderRadius.vertical(
          top: isTop ? const Radius.circular(6) : Radius.zero,
          bottom: isBottom ? const Radius.circular(6) : Radius.zero,
        ),
        border: Border.all(
          color: isTop ? theme.accent : theme.borderMid,
          width: isTop ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (isTop) ...[
            Icon(Icons.arrow_right, size: 16, color: theme.accent),
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 20),
          Expanded(
            child: Text(
              display,
              style: GoogleFonts.courierPrime(
                fontSize: 15,
                fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                color: isTop ? theme.accent : theme.textMid,
              ),
            ),
          ),
          if (isTop)
            Text(
              'top',
              style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
            ),
          if (isBottom && isBottomMarker)
            Text(
              'btm',
              style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TM CONFIG PANEL
// ═════════════════════════════════════════════════════════════════════════════

/// Floating panel: NTM configurations (state, head position, tape) per step.
class TmConfigPanel extends StatelessWidget {
  final TmSimulator simulator;
  final Map<String, NodeData> nodes;

  /// Index of the tape (0-based) whose contents should be shown in each
  /// branch's config card. Meaningless (and hidden) when the machine has
  /// only one tape.
  ///
  /// This is deliberately the *same* index the caller feeds into
  /// [StringSimulatorPanel.activeTapeIndex] — sharing one piece of state
  /// means picking a tape tab in either panel keeps both in sync, rather
  /// than the config panel silently being stuck on tape 1.
  final int activeTapeIndex;

  /// Called when the user taps a tape tab in this panel to switch which
  /// tape is displayed.
  final ValueChanged<int>? onTapeSelected;

  const TmConfigPanel({
    super.key,
    required this.simulator,
    required this.nodes,
    this.activeTapeIndex = 0,
    this.onTapeSelected,
  });

  String _stateLabel(String nodeId) => displayNodeLabel(nodeId, nodes);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final configs = simulator.activeConfigs;
    final result  = simulator.result;
    final isDone  = result != TmResult.running;

    // Tape count read off the live configs when available (defensive:
    // stays correct even a frame before simulator.tapeCount and the
    // configs agree), falling back to the simulator's own count.
    final tapeCount = configs.isNotEmpty
        ? configs.first.tapes.length
        : (simulator.tapeCount < 1 ? 1 : simulator.tapeCount);
    final selectedTape = activeTapeIndex.clamp(0, tapeCount - 1);

    Color? headerColor;
    if (isDone) {
      headerColor = switch (result) {
        TmResult.accept  => const Color(0xFF1FD99A),
        TmResult.reject  => const Color(0xFFFF1744),
        TmResult.running => null,
      };
    }

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340, maxHeight: 520),
          child: Card(
            color: theme.surface,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.borderMid),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ───────────────────────────────────────────
                  Row(
                    children: [
                      Icon(Icons.memory, size: 18,
                          color: headerColor ?? theme.accent),
                      const SizedBox(width: 6),
                      Text(
                        'TM (NTM)',
                        style: GoogleFonts.courierPrime(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: headerColor ?? theme.textLight,
                        ),
                      ),
                      const Spacer(),
                      if (isDone)
                        Text(
                          switch (result) {
                            TmResult.accept  => 'ACCEPT',
                            TmResult.reject  => 'REJECT',
                            TmResult.running => '',
                          },
                          style: GoogleFonts.courierPrime(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: headerColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Step label ───────────────────────────────────────
                  Text(
                    'Step ${simulator.step < 0 ? 0 : simulator.step + 1} '
                    '/ ${simulator.steps.isEmpty ? 0 : simulator.steps.length - 1}',
                    style: GoogleFonts.courierPrime(fontSize: 11, color: theme.textDim),
                  ),

                  // ── Tape tab strip (only when there's more than one
                  //    tape to choose from) ───────────────────────────
                  if (tapeCount > 1) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 22,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: tapeCount,
                        separatorBuilder: (_, _) => const SizedBox(width: 4),
                        itemBuilder: (context, i) {
                          final isActive = i == selectedTape;
                          return GestureDetector(
                            onTap: () => onTapeSelected?.call(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? theme.accent.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isActive
                                      ? theme.accent.withValues(alpha: 0.7)
                                      : theme.borderMid,
                                  width: isActive ? 1.5 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Tape ${i + 1}',
                                  style: GoogleFonts.courierPrime(
                                    fontSize: 10,
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isActive
                                        ? theme.accent
                                        : theme.textDim,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  Divider(height: 16, color: theme.borderMid),

                  // ── Configs list ─────────────────────────────────────
                  if (configs.isEmpty)
                    Text(
                      'No active configuration',
                      style: GoogleFonts.courierPrime(
                          fontSize: 13, color: const Color(0xFFFF1744)),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < configs.length; i++) ...[
                              if (configs.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'Branch ${i + 1}',
                                    style: GoogleFonts.courierPrime(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: theme.textDim,
                                    ),
                                  ),
                                ),
                              _TmConfigCard(
                                stateLabel: _stateLabel(configs[i].nodeId),
                                tapes: configs[i].tapes,
                                headPositions: configs[i].readHeadPositions,
                                activeTapeIndex: selectedTape,
                                isAccepted: () {
                                  final node = nodes[configs[i].nodeId];
                                  return node != null && node.isHaltAccept;
                                }(),
                                isRejected: () {
                                  final node = nodes[configs[i].nodeId];
                                  return node != null && node.isHaltReject;
                                }(),
                              ),
                              if (i < configs.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single config card
// ─────────────────────────────────────────────────────────────────────────────

class _TmConfigCard extends StatelessWidget {
  final String stateLabel;

  /// One entry per tape this configuration carries (tapes[0] = tape 1, …).
  final List<TmTape> tapes;

  /// Head position for each tape, same order/length as [tapes].
  final List<int> headPositions;

  /// Which entry of [tapes] to actually render. Clamped internally so a
  /// stale index (e.g. right after removing a tape) never throws.
  final int activeTapeIndex;

  final bool isAccepted;
  final bool isRejected;

  const _TmConfigCard({
    required this.stateLabel,
    required this.tapes,
    required this.headPositions,
    required this.activeTapeIndex,
    required this.isAccepted,
    required this.isRejected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final idx = activeTapeIndex.clamp(0, tapes.length - 1);
    final tape = tapes[idx];
    final headPos = headPositions[idx];
    final borderColor = isAccepted
        ? theme.accentGreen
        : isRejected
            ? const Color(0xFFFF1744)
            : theme.borderMid;

    final bgColor = isAccepted
        ? theme.accentGreen.withValues(alpha: 0.08)
        : isRejected
            ? const Color(0xFF1A0005)
            : theme.bg;

    final stateTextColor = isAccepted
        ? theme.accentGreen
        : isRejected
            ? const Color(0xFFFF1744)
            : theme.textLight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // State row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  'state',
                  style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
                ),
              ),
              Expanded(
                child: Text(
                  stateLabel,
                  style: GoogleFonts.courierPrime(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: stateTextColor,
                  ),
                ),
              ),
              if (isAccepted)
                Text(
                  'ACCEPT',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: theme.accentGreen,
                  ),
                ),
              if (isRejected)
                Text(
                  'REJECT',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFF1744),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            tapes.length > 1 ? 'tape ${idx + 1}' : 'tape',
            style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
          ),
          const SizedBox(height: 4),

          _TapeStrip(tape: tape, headPos: headPos),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tape strip — horizontal scrollable row of cells
// ─────────────────────────────────────────────────────────────────────────────

class _TapeStrip extends StatelessWidget {
  final TmTape tape;
  final int headPos;

  const _TapeStrip({required this.tape, required this.headPos});

  @override
  Widget build(BuildContext context) {
    const pad = 3;
    final startAbs = -pad;
    final endAbs   = tape.cells.length - tape.headOffset + pad;

    final items = <({String symbol, bool isHead})>[];
    for (int rel = startAbs; rel < endAbs; rel++) {
      final abs = tape.absolutePos(rel);
      final sym = (abs >= 0 && abs < tape.cells.length) ? tape.cells[abs] : kBlank;
      items.add((symbol: sym.isEmpty ? kBlank : sym, isHead: abs == headPos));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items)
            _TapeCell(symbol: item.symbol, isHead: item.isHead),
        ],
      ),
    );
  }
}

class _TapeCell extends StatelessWidget {
  final String symbol;
  final bool isHead;

  const _TapeCell({required this.symbol, required this.isHead});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: isHead ? theme.surface : theme.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHead ? theme.accent : theme.borderMid,
          width: isHead ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              symbol,
              style: GoogleFonts.courierPrime(
                fontSize: 14,
                fontWeight: isHead ? FontWeight.bold : FontWeight.normal,
                color: isHead ? theme.accent : theme.textMid,
              ),
            ),
          ),
          if (isHead)
            Positioned(
              bottom: 1,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '▲',
                  style: TextStyle(fontSize: 7, color: theme.accent.withValues(alpha: 0.7)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  REGEX PANEL
// ═════════════════════════════════════════════════════════════════════════════
// ─────────────────────────────────────────────────────────────────────────────
//  regex_panel.dart
//
//  Floating panel shown when the automata mode is set to RegEx.
//  Lets the user type a simple regex and convert it to a DFA
//  that is displayed on the canvas.
//
//  Supported syntax:
//    *  = Kleene star (zero or more of the preceding atom)
//    +  = union / alternation (either side), equivalent to | in standard regex
//    () = grouping
//    All other characters are literals (single characters).
//
//  Examples:
//    (0 + 1(01*0)*1)*   — strings whose binary value is divisible by 3
//    a*b*               — any number of a followed by any number of b
//    (a + b)*abb        — strings ending in "abb" over {a,b}
// ─────────────────────────────────────────────────────────────────────────────

// ─── Public callback type ────────────────────────────────────────────────────

typedef RegexConvertCallback = void Function(RegexConversionResult result, bool isDfa);

// ─── Panel widget ─────────────────────────────────────────────────────────────

class RegexPanel extends StatefulWidget {
  /// Called when the user clicks "Convert to DFA".
  /// The parent screen is responsible for loading the resulting graph.
  final RegexConvertCallback onConvert;

  /// Called when the user closes the panel.
  final VoidCallback onClose;

  /// Optional text to pre-fill the expression field with (e.g. when the panel
  /// is opened from the NFA/DFA → Regex dialog).
  final String? initialText;

  /// Called once after [initialText] has been copied into the text field so
  /// the parent can clear it and avoid re-seeding on rebuilds.
  final VoidCallback? onInitialTextConsumed;

  const RegexPanel({
    super.key,
    required this.onConvert,
    required this.onClose,
    this.initialText,
    this.onInitialTextConsumed,
  });

  @override
  State<RegexPanel> createState() => _RegexPanelState();
}

class _RegexPanelState extends State<RegexPanel> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _ctrl.text = widget.initialText!;
      // Notify the parent that the seed has been consumed so it doesn't
      // re-apply it on the next rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onInitialTextConsumed?.call();
      });
    }
  }

  /// Picks up a new [initialText] when the panel is already mounted — this
  /// happens when the user loads a derived regex from the FA→Regex dialog
  /// while the Regex Panel is already visible.
  @override
  void didUpdateWidget(RegexPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.initialText;
    if (incoming != null &&
        incoming.isNotEmpty &&
        incoming != oldWidget.initialText) {
      setState(() {
        _ctrl.text = incoming;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onInitialTextConsumed?.call();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _convert() {
    // Use the raw text — the parser skips all whitespace internally,
    // so spaces around operators (e.g. "0 + 1") are handled correctly.
    final pattern = _ctrl.text;
    if (pattern.trim().isEmpty) {
      setState(() => _error = 'Please enter a regular expression.');
      return;
    }

    final result = regexToDfa(pattern);

    if (result.isError) {
      setState(() => _error = result.error);
      return;
    }

    setState(() => _error = null);
    widget.onConvert(result, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, bottom: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            color: theme.surface,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.borderMid),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Row(
                    children: [
                      Icon(Icons.text_fields, color: theme.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Regular Expression',
                        style: GoogleFonts.courierPrime(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: theme.textLight,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: theme.textMid, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Syntax reminder ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.borderMid),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Syntax',
                          style: GoogleFonts.courierPrime(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.textDim,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _SyntaxRow(symbol: '*', desc: 'zero or more (Kleene star)', theme: theme),
                        _SyntaxRow(symbol: '+', desc: 'or / union (alternation)', theme: theme),
                        _SyntaxRow(symbol: '()', desc: 'grouping', theme: theme),
                        _SyntaxRow(symbol: 'a–z, 0–9, …', desc: 'literal character', theme: theme),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Regex input ────────────────────────────────────────
                  Text(
                    'Expression',
                    style: GoogleFonts.courierPrime(
                      fontSize: 12,
                      color: theme.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.bg,
                      border: Border.all(
                        color: _error != null
                            ? const Color(0xFFFF1744)
                            : theme.accent.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      style: GoogleFonts.courierPrime(
                        fontSize: 18,
                        color: theme.textLight,
                        letterSpacing: 1.2,
                      ),
                      cursorColor: theme.accent,
                      onSubmitted: (_) => _convert(),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: InputBorder.none,
                        hintText: '(0 + 1(01*0)*1)*',
                        hintStyle: GoogleFonts.courierPrime(
                          fontSize: 16,
                          color: theme.textDim,
                        ),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: const Color(0xFFFF1744),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // ── Convert button ─────────────────────────────────────
                  FilledButton.icon(
                    onPressed: _convert,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.transform, size: 18),
                    label: Text(
                      'Convert to DFA',
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ── Examples ───────────────────────────────────────────
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      'Examples',
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: theme.textDim,
                      ),
                    ),
                    iconColor: theme.textDim,
                    collapsedIconColor: theme.textDim,
                    children: [
                      _ExampleTile(
                        pattern: '(0 + 1(01*0)*1)*',
                        desc: 'Divisible by 3 in binary',
                        onTap: () {
                          _ctrl.text = '(0 + 1(01*0)*1)*';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: 'a*b*',
                        desc: "Any a's then b's",
                        onTap: () {
                          _ctrl.text = 'a*b*';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: '(a + b)*abb',
                        desc: 'Strings ending in "abb"',
                        onTap: () {
                          _ctrl.text = '(a + b)*abb';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: '(0 + 1)*1(0 + 1)',
                        desc: 'Second-to-last bit is 1',
                        onTap: () {
                          _ctrl.text = '(0 + 1)*1(0 + 1)';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: '(0 + 1(001*0(101*0)*0 + 1(101*0)*0)*(001*0(101*0)*11 + 01 + 1(101*0)*11))*',
                        desc: 'Divisible by 5 in binary',
                        onTap: () {
                          _ctrl.text = '(0 + 1(001*0(101*0)*0 + 1(101*0)*0)*(001*0(101*0)*11 + 01 + 1(101*0)*11))*';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _SyntaxRow extends StatelessWidget {
  final String symbol;
  final String desc;
  final AppThemeNotifier theme;

  const _SyntaxRow({
    required this.symbol,
    required this.desc,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              symbol,
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.accent,
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                color: theme.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleTile extends StatelessWidget {
  final String pattern;
  final String desc;
  final VoidCallback onTap;
  final AppThemeNotifier theme;

  const _ExampleTile({
    required this.pattern,
    required this.desc,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern,
                    style: GoogleFonts.courierPrime(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.textLight,
                    ),
                  ),
                  Text(
                    desc,
                    style: GoogleFonts.courierPrime(
                      fontSize: 11,
                      color: theme.textDim,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 12, color: theme.textDim),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  STRING SIMULATOR PANEL
// ═════════════════════════════════════════════════════════════════════════════

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
    this.additionalTapeControllers = const [],
    this.onTapeInputChanged,
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

  /// Controllers for the input strings of tapes 2, 3, … (index 0 = tape 2).
  /// When non-empty, the active non-tape-1 tab shows an input field so the
  /// user can type a separate starting string for that tape.
  final List<TextEditingController> additionalTapeControllers;

  /// Called whenever a per-tape input field changes so the parent can
  /// rebuild the simulation with the new additional tape content.
  final VoidCallback? onTapeInputChanged;

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

  /// The real stopping point for the shared step cursor (`widget.simulator.step`),
  /// whichever mode is active.
  ///
  /// `widget.simulator` (the base [AutomataSimulator]) is used as the generic
  /// token/step tracker in every mode, but the authoritative simulation — and
  /// therefore the authoritative halting point — comes from whichever
  /// mode-specific simulator is active: [TmSimulator] in TM mode,
  /// [PdaSimulator] in PDA mode, or `widget.simulator` itself in FA/NFA mode.
  /// Each of those exposes its own `maxStep` that reflects where its
  /// computation actually stopped (halt-accept reached, every branch died,
  /// etc.) — never padded out to `tokens.length`. See [AutomataSimulator.maxStep].
  int get _effectiveMaxStep {
    final tm = widget.tmSimulator as TmSimulator?;
    if (tm != null) return tm.maxStep;
    final pda = widget.pdaSimulator;
    if (pda != null) return pda.maxStep;
    return widget.simulator.maxStep;
  }

  void _syncTmStep() {
    final tm = widget.tmSimulator as TmSimulator?;
    if (tm != null) {
      tm.step = widget.simulator.step.clamp(-1, tm.maxStep);
    }
  }

  void _startPlayback() {
    if (_playing) return;
    final maxStep = _effectiveMaxStep;
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

    final maxStep = _effectiveMaxStep;
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

    final maxStep = _effectiveMaxStep;
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

    final maxStep = _effectiveMaxStep;
    setState(() => widget.simulator.step = maxStep);
    widget.onStepChanged();
    _scrollToChip(maxStep - 1);
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

    final maxStep = _effectiveMaxStep;

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

    // For multi-tape TM mode, show the tape selected by the tab strip.
    // For single-tape TM mode, always show tape 1 (backward-compatible).
    final tapeView = isTmMode
        ? tm.tapeViewForTape(widget.activeTapeIndex + 1)
        : null;

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
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: theme.accent.withValues(alpha: 0.04),
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
                      // ── Tape tab strip (TM mode, always shown so user
                      //    can add tapes even when only 1 exists) ─────────
                      if (isTmMode) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 24,
                          child: Row(
                            children: [
                              // Scrollable tab list
                              Expanded(
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: widget.tapeNames.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 4),
                                  itemBuilder: (context, i) {
                                    final isActive = i == widget.activeTapeIndex;
                                    final canRemove = widget.tapeNames.length > 1 &&
                                        widget.onTapeRemoved != null;
                                    return GestureDetector(
                                      onTap: () =>
                                          widget.onTapeSelected?.call(i),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 140),
                                        padding: const EdgeInsets.only(
                                            left: 8, right: 4, top: 2, bottom: 2),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? theme.accent.withValues(alpha: 0.15)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: isActive
                                                ? theme.accent.withValues(alpha: 0.7)
                                                : theme.borderMid,
                                            width: isActive ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              widget.tapeNames[i],
                                              style: GoogleFonts.courierPrime(
                                                fontSize: 10,
                                                fontWeight: isActive
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isActive
                                                    ? theme.accent
                                                    : theme.textDim,
                                              ),
                                            ),
                                            // × remove button — only on active tab
                                            // when more than 1 tape exists
                                            if (isActive && canRemove) ...[
                                              const SizedBox(width: 4),
                                              GestureDetector(
                                                onTap: () => widget
                                                    .onTapeRemoved?.call(i),
                                                child: Icon(
                                                  Icons.close,
                                                  size: 10,
                                                  color: theme.textDim,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // + add-tape button
                              if (widget.onTapeAdded != null) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Add tape',
                                  child: GestureDetector(
                                    onTap: widget.onTapeAdded,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                            color: theme.borderMid),
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        size: 13,
                                        color: theme.textMid,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      // ── Per-tape input field (tapes 2+) ─────────────
                      // Shown when the selected tab is a non-tape-1 tape
                      // and we have a controller for it.
                      if (widget.activeTapeIndex > 0 &&
                          widget.activeTapeIndex - 1 <
                              widget.additionalTapeControllers.length) ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: widget.additionalTapeControllers[
                              widget.activeTapeIndex - 1],
                          onChanged: (_) {
                            widget.onTapeInputChanged?.call();
                          },
                          style: GoogleFonts.courierPrime(
                              fontSize: 13, color: theme.textLight),
                          cursorColor: theme.accent,
                          decoration: InputDecoration(
                            hintText: widget.activeTapeIndex < widget.tapeNames.length
                                ? '${widget.tapeNames[widget.activeTapeIndex]} input…'
                                : 'Tape input…',
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
                              borderSide:
                                  BorderSide(color: theme.accent, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          controller: _tapeScroll,
                          scrollDirection: Axis.horizontal,
                          itemCount: tapeView.cells.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 2),
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
                          separatorBuilder: (_, _) => const SizedBox(width: 3),
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
                          color: _resultColor(result).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _resultColor(result).withValues(alpha: 0.5),
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
              color: enabled ? theme.borderMid : theme.borderMid.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? theme.textMid : theme.textDim.withValues(alpha: 0.35),
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
          border: theme.panelHighlight.withValues(alpha: 0.75),
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
              color: theme.panelHighlight.withValues(alpha: 0.75),
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
