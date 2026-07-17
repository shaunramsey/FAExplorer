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

// Timer, used to drive automatic step-by-step playback of a simulation.
import 'dart:async';

import 'package:flutter/material.dart';
// Monospace font used consistently across all the panels in this file.
import 'package:google_fonts/google_fonts.dart';
// `context.watch<AppThemeNotifier>()` — rebuilds these widgets on theme change.
import 'package:provider/provider.dart';

// NodeData / TmTape and other shared data models.
import '../models.dart';
// The three simulators (AutomataSimulator, PdaSimulator, TmSimulator) plus
// their result enums and constants (kBlank, kStackBottom).
import '../simulator.dart';
// AppThemeNotifier itself, plus displayNodeLabel() for rendering node ids
// using whatever label the user gave that node instead of its raw id.
import 'app_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  PDA STACK PANEL
// ═════════════════════════════════════════════════════════════════════════════

/// Floating panel: NPDA configurations (state, remaining input, stack) per step.
class PdaStackPanel extends StatelessWidget {
  // The live PDA simulator instance whose current step this panel renders.
  final PdaSimulator simulator;
  // Node id -> NodeData lookup, needed to resolve friendly state labels.
  final Map<String, NodeData> nodes;

  const PdaStackPanel({
    super.key,
    required this.simulator,
    required this.nodes,
  });

  // Resolves a raw node id to its user-facing display label.
  String _stateLabel(String nodeId) => displayNodeLabel(nodeId, nodes);

  @override
  Widget build(BuildContext context) {
    // `watch` (not `read`) so this panel repaints automatically if the app
    // theme changes while a simulation is running.
    final theme = context.watch<AppThemeNotifier>();
    // All configurations (branches) currently alive at this simulation step
    // — an NPDA can be in multiple configurations at once due to nondeterminism.
    final configs = simulator.activeConfigs;
    // Overall accept/reject verdict once the input has been fully consumed.
    final result = simulator.finalResult();
    // Whether the scrubber is parked on the very last step.
    final atEnd = simulator.step == simulator.maxStep;

    // Header icon/text color: neutral (null -> theme.accent) unless we're at
    // the end of a non-empty run, in which case it reflects accept/reject.
    Color? headerColor;
    if (atEnd && simulator.tokens.isNotEmpty) {
      headerColor = switch (result) {
        PdaSimResult.accept => const Color(0xFF1FD99A),
        PdaSimResult.reject => const Color(0xFFFF1744),
      };
    }

    return Align(
      // Panel anchors to the bottom-left corner of the canvas.
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 16),
        child: ConstrainedBox(
          // Cap the panel's size so a long stack/many branches scrolls
          // internally instead of growing the whole floating card offscreen.
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
                  // ── Header row: icon, title, ACCEPT/REJECT badge ──────
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
                      // Pushes the verdict badge (if any) to the far right.
                      const Spacer(),
                      // Only show a verdict badge once input has been
                      // consumed and we're parked at the final step.
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
                  // ── Step counter label ─────────────────────────────────
                  Text(
                    simulator.tokens.isEmpty
                        ? 'No input'
                        : simulator.step < 0
                            ? 'Before input'
                            : 'After token ${simulator.step} / ${simulator.tokens.length}',
                    style: GoogleFonts.courierPrime(fontSize: 11, color: theme.textDim),
                  ),
                  Divider(height: 16, color: theme.borderMid),
                  // ── Optional warning banner: the simulator gave up
                  //    because free (ε-only) pushes caused the stack to
                  //    grow without bound (an infinite loop in the PDA's
                  //    own rules, not a bug in the simulator). ───────────
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
                  // ── Configuration list, or an empty-state message ──────
                  if (configs.isEmpty)
                    Text(
                      // Distinguish "the machine legitimately has no valid
                      // configuration left" from "we bailed out due to
                      // runaway stack growth" — same visual slot, different
                      // wording.
                      simulator.stackGrowthLoopDetected
                          ? 'Simulation aborted'
                          : 'No active configuration',
                      style: GoogleFonts.courierPrime(
                          fontSize: 13, color: const Color(0xFFFF1744)),
                    )
                  else
                    // Flexible + SingleChildScrollView: lets this section
                    // shrink to fit within the Card's maxHeight and scroll
                    // internally rather than overflowing the layout.
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // One card per active configuration (branch).
                            for (int i = 0; i < configs.length; i++) ...[
                              // Only label branches when there's more than
                              // one — a single branch doesn't need a
                              // "Configuration 1" header cluttering the view.
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
                              // Gap between consecutive branch cards, but
                              // not after the very last one.
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
//  Single PDA configuration card: state + remaining input + stack.
// ─────────────────────────────────────────────────────────────────────────────
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
          // Current state label.
          _RowLabel(label: 'state', value: stateLabel),
          const SizedBox(height: 4),
          // Remaining (unconsumed) input; shown muted with a tilde placeholder
          // when there's nothing left to read.
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
          // The visual stack itself (bottom to top, rendered top-down).
          _StackView(stack: stack),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small "label: value" row used for state/input display.
// ─────────────────────────────────────────────────────────────────────────────
class _RowLabel extends StatelessWidget {
  final String label;
  final String value;
  // When true, renders the value in a dimmer color (used for "no input left").
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
        // Fixed-width label column so values line up across rows.
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
          ),
        ),
        // Value takes the remaining width and wraps/truncates as needed.
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

// ─────────────────────────────────────────────────────────────────────────────
//  Stack visualization: top-to-bottom column of cells.
// ─────────────────────────────────────────────────────────────────────────────
class _StackView extends StatelessWidget {
  final List<String> stack;

  const _StackView({required this.stack});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    // Empty-stack placeholder card.
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

    // `stack` is stored bottom-first internally; reverse it so index 0 is
    // the top of the stack, matching how a stack is normally drawn (top at
    // the visual top of the column).
    final displayItems = stack.reversed.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      // Stretch each cell to the full available width.
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

// ─────────────────────────────────────────────────────────────────────────────
//  A single stack cell — highlighted specially when it's the top of stack,
//  and labeled when it's the bottom-of-stack sentinel symbol.
// ─────────────────────────────────────────────────────────────────────────────
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
    // Show a tilde placeholder for an empty-string symbol so the cell isn't
    // rendered as visually blank.
    final display = symbol.isEmpty ? '~' : symbol;
    // Whether this cell is specifically the reserved stack-bottom marker
    // (as opposed to just happening to be the lowest cell currently present).
    final isBottomMarker = symbol == kStackBottom;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        // Tint the top cell with a faint accent wash so it stands out.
        color: isTop
            ? Color.alphaBlend(theme.accent.withValues(alpha: 0.14), theme.bg)
            : theme.bg,
        // Round only the outer corners of the whole stack column: top
        // corners on the top cell, bottom corners on the bottom cell.
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
          // Little arrow marker + gap for the top cell; otherwise just an
          // equivalent-width blank spacer so all cells' text stays aligned.
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
          // "top" tag on the top cell.
          if (isTop)
            Text(
              'top',
              style: GoogleFonts.courierPrime(fontSize: 10, color: theme.textDim),
            ),
          // "btm" tag only when the bottom cell is actually the reserved
          // bottom-of-stack marker (not just whatever happens to be lowest).
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
    // All currently-alive branches (an NTM can be nondeterministic too).
    final configs = simulator.activeConfigs;
    // Overall halted/running status for the whole machine.
    final result  = simulator.result;
    final isDone  = result != TmResult.running;

    // Tape count read off the live configs when available (defensive:
    // stays correct even a frame before simulator.tapeCount and the
    // configs agree), falling back to the simulator's own count.
    final tapeCount = configs.isNotEmpty
        ? configs.first.tapes.length
        : (simulator.tapeCount < 1 ? 1 : simulator.tapeCount);
    // Clamp the externally-provided tape index in case it's briefly stale
    // (e.g. a tape was just removed elsewhere in the UI).
    final selectedTape = activeTapeIndex.clamp(0, tapeCount - 1);

    // Header color reflects the final verdict once the machine has halted;
    // stays neutral (null) while still running.
    Color? headerColor;
    if (isDone) {
      headerColor = switch (result) {
        TmResult.accept  => const Color(0xFF1FD99A),
        TmResult.reject  => const Color(0xFFFF1744),
        TmResult.running => null,
      };
    }

    return Align(
      // Same bottom-left anchor as the PDA panel (they're mutually
      // exclusive — only one automata mode's panel is shown at a time).
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 16),
        child: ConstrainedBox(
          // Slightly larger cap than the PDA panel to accommodate the tape
          // tab strip and wider tape cells.
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
                      // Verdict badge once halted (blank string while
                      // running, so no badge text is rendered).
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
                    // step is stored 0-based internally but displayed
                    // 1-based; clamp the "before any step" case (-1) down
                    // to 0 for display, and guard the total against an
                    // empty steps list.
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
                              // Smoothly animates highlight/border changes
                              // when the active tab switches.
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
                              // Label branches only when there's more than
                              // one active configuration.
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
                                headPositions: configs[i].headPositions,
                                activeTapeIndex: selectedTape,
                                // Immediately-invoked closures used purely
                                // to keep this call site readable — each
                                // just looks up whether this branch's
                                // current node is a halt-accept / halt-
                                // reject node, defaulting to false if the
                                // node id can't be resolved.
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
    // Defensive clamp: guards against activeTapeIndex momentarily pointing
    // past the end of `tapes` (e.g. one frame after a tape removal).
    final idx = activeTapeIndex.clamp(0, tapes.length - 1);
    final tape = tapes[idx];
    final headPos = headPositions[idx];
    // Card border reflects this branch's own halt status (not the whole
    // machine's), so an accepted branch can be visually distinct from a
    // still-running sibling branch.
    final borderColor = isAccepted
        ? theme.accentGreen
        : isRejected
            ? const Color(0xFFFF1744)
            : theme.borderMid;

    final bgColor = isAccepted
        ? theme.accentGreen.withValues(alpha: 0.08)
        : isRejected
            ? const Color(0xFFFF1744).withValues(alpha: 0.08)
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
              // ACCEPT / REJECT tag inline with the state row, mutually
              // exclusive (a node can't be both halt-accept and halt-reject).
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

          // Tape label — shows the tape number only in multi-tape machines,
          // otherwise just the generic word "tape".
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
    // Extra blank cells of padding shown on either side of the tape's
    // actual content, so the head never looks like it's jammed against the
    // edge of the visible strip.
    const pad = 3;
    final startAbs = -pad;
    final endAbs   = tape.cells.length - tape.headOffset + pad;

    // Build the list of (symbol, isHead) pairs to render, one per absolute
    // tape position from startAbs to endAbs (relative to the tape's own
    // internal offset bookkeeping).
    final items = <({String symbol, bool isHead})>[];
    for (int rel = startAbs; rel < endAbs; rel++) {
      final abs = tape.absolutePos(rel);
      // Positions outside the tape's actually-allocated cell range read as
      // blank, since the tape is conceptually infinite in both directions.
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

// ─────────────────────────────────────────────────────────────────────────────
//  A single fixed-size tape cell, highlighted when the head sits on it.
// ─────────────────────────────────────────────────────────────────────────────
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
          // Small upward-pointing triangle glyph under the head's cell,
          // acting as a "head is here" pointer marker.
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

// Fired when the user successfully converts a regex; `isDfa` is always true
// here (kept as a parameter for interface flexibility / future NFA output).
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
  // Controller for the single-line regex input field.
  final TextEditingController _ctrl = TextEditingController();
  // Current parse/validation error, shown under the input field.
  String? _error;

  @override
  void initState() {
    super.initState();
    // Seed the field with any initialText supplied at construction time
    // (e.g. panel opened directly with a regex derived from an existing DFA).
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
    // Only react when there's genuinely new non-empty text different from
    // what this widget was last built with — avoids clobbering whatever the
    // user has since typed themselves on every unrelated rebuild.
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

  // Attempts to parse the current field text as a regex and convert it to a
  // DFA, surfacing either a validation error or the successful result.
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
    // `true` = the result is a DFA (see RegexConvertCallback typedef note).
    widget.onConvert(result, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Align(
      // Anchored to the bottom-right, as opposed to the PDA/TM panels which
      // anchor bottom-left — they don't coexist with this panel since only
      // one automata mode is active at a time, but bottom-right also leaves
      // room on the left for the (always-present) StringSimulatorPanel.
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
                // Stretch children to the card's full width (unlike the
                // PDA/TM panels, which left-align instead).
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
                      // Explicit close button — this panel isn't tied to
                      // whether a simulation is active, so it needs its own
                      // dismiss control.
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
                        // Quick legend for each supported operator/token.
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
                      // Border turns red when there's a validation error,
                      // otherwise a semi-transparent accent tint.
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
                      // Pressing Enter/Done in the field also triggers convert.
                      onSubmitted: (_) => _convert(),
                      // Clear any stale error as soon as the user starts
                      // editing again, so the red border disappears
                      // immediately rather than waiting for another convert
                      // attempt.
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        // Border is drawn manually via the wrapping
                        // Container above, so the TextField itself has none.
                        border: InputBorder.none,
                        hintText: '(0 + 1(01*0)*1)*',
                        hintStyle: GoogleFonts.courierPrime(
                          fontSize: 16,
                          color: theme.textDim,
                        ),
                      ),
                    ),
                  ),

                  // Inline error message, only rendered while an error exists.
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
                  // Collapsible list of example patterns the user can tap to
                  // load directly into the field (a quick-start / teaching aid).
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
                      // Each _ExampleTile: tapping it overwrites the field
                      // with `pattern` and clears any existing error.
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

// One row of the syntax legend: a fixed-width symbol column plus its
// description, e.g. "*" -> "zero or more (Kleene star)".
class _SyntaxRow extends StatelessWidget {
  final String symbol;
  final String desc;
  // Theme is passed in explicitly here (rather than re-read via
  // context.watch) since the parent already has it and this avoids an
  // extra Provider lookup for such a small leaf widget.
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

// A tappable example-pattern row inside the "Examples" ExpansionTile.
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
                  // The pattern text itself, in monospace/bold so it reads
                  // clearly as code.
                  Text(
                    pattern,
                    style: GoogleFonts.courierPrime(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.textLight,
                    ),
                  ),
                  // Plain-English description underneath.
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
            // Small chevron affordance hinting the row is tappable.
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
// Labels shown on the speed SegmentedButton, paired index-for-index with the
// millisecond delays in _kSpeedMs below (e.g. '2×' -> 350ms per step).
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

  // Key attached to a RepaintBoundary wrapping this panel — lets the caller
  // capture the panel as an image (e.g. for screenshot/export features)
  // independent of the rest of the canvas.
  final GlobalKey boundaryKey;
  // Always present: the generic token/step tracker shared across all modes
  // (see _effectiveMaxStep's doc comment below for how the three simulators
  // relate to one another).
  final AutomataSimulator simulator;
  // Present only in PDA mode.
  final PdaSimulator? pdaSimulator;
  // Present only in TM mode. Typed `dynamic` here and cast to `TmSimulator?`
  // at each use site (see e.g. `_effectiveMaxStep`) rather than typed
  // directly, presumably to avoid importing TmSimulator's full type surface
  // into the constructor signature.
  final dynamic tmSimulator;
  // Shared text field controller for the "current input string" field.
  final TextEditingController controller;
  final Map<String, NodeData> nodes;
  final VoidCallback onClose;
  // Fired whenever the input string field changes (any mode).
  final VoidCallback onTextChanged;
  // Fired whenever the step cursor moves (playback, scrubbing, etc).
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
    // Needed because this State owns an AnimationController (_pulseCtrl)
    // and must supply a TickerProvider for it.
    with SingleTickerProviderStateMixin {
  // Whether auto-playback is currently running.
  bool _playing = false;
  // Index into _kSpeedLabels / _kSpeedMs for the current playback speed.
  int _speedIndex = 1;
  // The pending single-shot timer that advances playback by one step; null
  // when playback is stopped.
  Timer? _playTimer;

  // Drives the pulsing scale animation on the "current" token/tape chip.
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Scroll controller for the horizontal token/tape strip, used to
  // auto-scroll the current chip into view as playback advances.
  final ScrollController _tapeScroll = ScrollController();
  // One GlobalKey per token chip, used with Scrollable.ensureVisible to
  // scroll a specific chip into view by index.
  final List<GlobalKey> _chipKeys = [];

  // ── string history ────────────────────────────────────────────────────────
  // A simple "browser history"-style list of input strings the user has
  // typed during this session, so Prev/Next arrows can step through them.
  // Always starts with one empty entry.
  final List<String> _strings = [''];
  int _stringIndex = 0;

  @override
  void initState() {
    super.initState();
    // Pulse animation: continuously reverses between 0.85x and 1.0x scale
    // (see _pulseAnim below) to give the "current" chip a breathing/pulsing
    // highlight effect.
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

  // Keeps the TM simulator's own step cursor mirrored to the shared
  // `widget.simulator.step` value, clamped to a valid range for the TM.
  // Needed because TM playback/stepping logic reads/writes `tm.step`
  // directly (via tm.currentSnapshot etc.) in addition to the shared cursor.
  void _syncTmStep() {
    final tm = widget.tmSimulator as TmSimulator?;
    if (tm != null) {
      tm.step = widget.simulator.step.clamp(-1, tm.maxStep);
    }
  }

  // Begins auto-playback from the current step, or restarts from the
  // beginning if already sitting at the end.
  void _startPlayback() {
    if (_playing) return;
    final maxStep = _effectiveMaxStep;
    // If the scrubber is parked at (or past) the end, restart from before
    // the first token rather than doing nothing when Play is pressed again.
    if (widget.simulator.step >= maxStep) {
      setState(() => widget.simulator.step = -1);
      _syncTmStep();
      widget.onStepChanged();
    }
    setState(() => _playing = true);
    _scheduleNextStep();
  }

  // Halts auto-playback and cancels any pending scheduled step. Safe to
  // call even when playback isn't currently running.
  void _stopPlayback() {
    _playing = false;
    _playTimer?.cancel();
    _playTimer = null;
  }

  // Schedules `_tick` to run after the current speed's delay, replacing any
  // previously-scheduled tick (used both for normal playback cadence and
  // for immediately rescheduling after a mid-playback speed change).
  void _scheduleNextStep() {
    _playTimer?.cancel();
    _playTimer = Timer(Duration(milliseconds: _kSpeedMs[_speedIndex]), _tick);
  }

  // The recurring playback "frame": advances one step and, if still
  // playing and not yet finished, schedules the next tick.
  void _tick() {
    // Guard against firing after this State has been disposed (e.g. the
    // panel was closed mid-playback).
    if (!mounted) return;
    final sim = widget.simulator;
    final tm = widget.tmSimulator as TmSimulator?;
    if (tm != null) {
      // TM mode computes lazily: each tick asks the TM to compute one more
      // step of its (possibly still-unfolding) branch tree, rather than
      // stepping through an already-fully-known sequence like the other
      // modes do.
      final appended = tm.computeNext();
      if (appended) {
        setState(() => sim.step = tm.maxStep);
        _syncTmStep();
        widget.onStepChanged();
        if (_playing) _scheduleNextStep();
      } else {
        // Nothing more to compute — the machine has halted; stop playback.
        if (_playing) setState(_stopPlayback);
      }
      return;
    }

    // Non-TM modes: the full step sequence is already known ahead of time,
    // so playback is just incrementing the shared step cursor.
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
      // Just advanced onto the final step — stop here rather than
      // scheduling one more (now pointless) tick.
      setState(_stopPlayback);
    } else {
      _scheduleNextStep();
    }
  }

  // Play/Pause button handler.
  void _togglePlayback() {
    if (_playing) {
      setState(_stopPlayback);
    } else {
      _startPlayback();
    }
  }

  // Step-back button handler: moves the cursor one step earlier (down to
  // -1, "before any input"), stopping any active playback first.
  void _stepBack() {
    _stopPlayback();
    if (widget.simulator.step > -1) {
      setState(() => widget.simulator.step--);
      _syncTmStep();
      widget.onStepChanged();
      _scrollToCurrentChip();
    }
  }

  // Step-forward button handler: moves the cursor one step later,
  // computing a new TM step on demand if needed.
  void _stepForward() {
    _stopPlayback();
    final tm = widget.tmSimulator as TmSimulator?;
    if (tm != null) {
      // If we already have a computed step ahead of the cursor, just move
      // onto it without recomputing anything.
      if (widget.simulator.step < tm.maxStep) {
        setState(() => widget.simulator.step++);
        _syncTmStep();
        widget.onStepChanged();
        return;
      }
      // Otherwise we're at the frontier of what's been computed — ask the
      // TM to compute one more step lazily.
      final appended = tm.computeNext();
      if (appended) {
        setState(() => widget.simulator.step = tm.maxStep);
        _syncTmStep();
        widget.onStepChanged();
      } else {
        // Machine has halted; nothing new to step onto, but still sync/notify
        // in case halting itself changed derived state (e.g. result banner).
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

  // Rewind button handler: jumps straight back to "before any input" (-1).
  void _rewind() {
    _stopPlayback();
    setState(() => widget.simulator.step = -1);
    _syncTmStep();
    widget.onStepChanged();
    _scrollToChip(0);
  }

  // Skip-to-end / fast-forward button handler. For TM mode this actively
  // drives computation forward for up to 5 real-world seconds (since a TM
  // may run arbitrarily long, or even forever); for the other modes the
  // end step is already known so this just jumps straight there.
  void _skipToEnd() {
    _stopPlayback();
    final tm = widget.tmSimulator as TmSimulator?;
    if (tm != null) {
      // Hard wall-clock deadline protects the UI from hanging forever on a
      // non-halting (or extremely long-running) Turing machine.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      bool progressed = false;
      while (DateTime.now().isBefore(deadline)) {
        final beforeLen = tm.steps.length;
        final appended = tm.computeNext();
        if (!appended) break;
        progressed = true;
        // If the deadline expired *during* this last computeNext() call and
        // it actually produced a new step, undo that partial step so we
        // don't leave the simulator holding a step that took longer than
        // the allotted budget to produce — keeps behavior consistent with
        // "we stopped because of the deadline", not a half-committed state.
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

  // Scrolls the token strip so the chip at the current step is visible,
  // no-op if the current step doesn't correspond to a valid token index
  // (e.g. step is -1, "before any input").
  void _scrollToCurrentChip() {
    final idx = widget.simulator.step;
    if (idx >= 0 && idx < widget.simulator.tokens.length) {
      _scrollToChip(idx);
    }
  }

  // Scrolls the token strip to bring the chip at `idx` into view, centered
  // (alignment: 0.5) with a short easing animation. Deferred to the next
  // frame via addPostFrameCallback because the target chip's GlobalKey
  // context may not be laid out yet within the same build that changed the
  // step (e.g. right after setState).
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

  // Persists whatever's currently in the text field back into `_strings` at
  // the current history index, so it isn't lost when navigating away.
  void _saveCurrentString() {
    _strings[_stringIndex] = widget.controller.text;
  }

  // Switches the active history entry to `newIndex`, saving the current
  // entry first, updating the text field to match, and stopping any
  // playback (since the input string changed out from under it).
  void _applyString(int newIndex) {
    _saveCurrentString();
    setState(() => _stringIndex = newIndex);
    widget.controller.text = _strings[_stringIndex];
    _stopPlayback();
    widget.onTextChanged();
  }

  // "Previous string" arrow: only active when not already at the first entry.
  void _prevString() {
    if (_stringIndex > 0) _applyString(_stringIndex - 1);
  }

  // "Next string" arrow: steps forward through existing history entries,
  // but once at the end of the history, instead creates and switches to a
  // brand-new blank entry — effectively doubling as an "add new string"
  // action.
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

  // Deletes the currently-active history entry (but never lets the list
  // shrink below one entry), and shifts the active index back if it would
  // otherwise point past the new end of the list.
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

  // Computes the current accept/reject verdict (if any) across whichever
  // mode is active, normalizing all three simulators' distinct result enums
  // down to the shared `SimResult` type used for the result banner.
  SimResult? get _currentResult {
    final sim = widget.simulator;
    final pda = widget.pdaSimulator;
    final tm  = widget.tmSimulator as TmSimulator?;

    if (tm != null) {
      // No steps computed yet — nothing to report.
      if (tm.steps.isEmpty) return null;
      final r = tm.result;
      // Still running — no verdict to show yet.
      if (r == TmResult.running) return null;
      return r == TmResult.accept ? SimResult.accept : SimResult.reject;
    }

    if (pda != null) {
      // No input has ever been simulated — nothing to report.
      if (pda.tokens.isEmpty && pda.steps.isEmpty) return null;
      final r = pda.finalResult();
      return r == PdaSimResult.accept ? SimResult.accept : SimResult.reject;
    }

    // Plain FA/NFA/regex-derived-DFA mode.
    if (sim.tokens.isEmpty && sim.states.isEmpty) return null;
    return sim.finalResult();
  }

  // Maps a verdict to its display color (green for accept, red for reject).
  Color _resultColor(SimResult r) {
    switch (r) {
      case SimResult.accept:
        return const Color(0xFF1FD99A);
      case SimResult.reject:
        return const Color(0xFFFF1744);
    }
  }

  // Maps a verdict to its display label text.
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

    // Keep _chipKeys in sync with the token count: rebuild the whole list
    // whenever the number of tokens changes (e.g. the user edited the input
    // string), so each chip has a stable, correctly-sized key for scrolling.
    if (_chipKeys.length != tokens.length) {
      _chipKeys
        ..clear()
        ..addAll(List.generate(tokens.length, (_) => GlobalKey()));
    }

    // Whether the cursor sits before the first token has been consumed.
    final atStart = step <= -1;
    // Whether there's any input/tape history to show controls for at all.
    final hasTokens = isTmMode ? tm.steps.isNotEmpty : tokens.isNotEmpty;

    // Determine whether we're "at the end" of the simulation — meaning
    // enabled by the following rules:
    bool atEnd;
    if (isTmMode) {
      // TM mode has no fixed token-count-based end; instead "at end" means
      // the current snapshot represents a halted (or dead) computation.
      final snap = tm.currentSnapshot;
      if (snap == null) {
        // No snapshot at all — nothing to compute further, treat as ended.
        atEnd = true;
      } else if (snap.configs.isEmpty) {
        // Every branch has died with no active configurations left.
        atEnd = true;
      } else {
        // Otherwise inspect each active branch's node to see whether the
        // whole machine should be considered finished: it's "at end" if
        // any branch has already reached halt-accept, OR if every branch
        // (accept or reject) has independently halted.
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
      // Other modes: simply compare the cursor to the known max step.
      atEnd = step >= maxStep;
    }
    final result     = _currentResult;
    // Only show the result banner once we've reached a natural end state
    // (or, in TM mode, whenever a result is available at all — TM halting
    // is detected independently of the atEnd token-count logic above).
    final showResult = result != null && (atEnd || isTmMode);

    // Index of the token chip that corresponds to the current step, or -1
    // if the step doesn't map onto a real token (e.g. before start or in
    // TM/tape mode where chips represent tape cells instead).
    final currentChipIndex = (step >= 0 && step < tokens.length) ? step : -1;

    // For multi-tape TM mode, show the tape selected by the tab strip.
    // For single-tape TM mode, always show tape 1 (backward-compatible).
    final tapeView = isTmMode
        ? tm.tapeViewForTape(widget.activeTapeIndex + 1)
        : null;

    return Align(
      // Anchored to the top-left, unlike the mode-specific config panels
      // (PDA/TM bottom-left, Regex bottom-right) — this panel is always
      // present regardless of mode, so it claims its own separate corner.
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        // Lets external code (e.g. a "copy panel as image" feature) render
        // just this subtree in isolation via widget.boundaryKey.
        key: widget.boundaryKey,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 0, 0),
          width: 250,
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.borderMid, width: 1),
            boxShadow: [
              // Soft drop shadow for depth against the canvas behind it.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              // Very faint accent-colored glow layered underneath the main
              // shadow, using a negative spreadRadius so it only shows at
              // the very edge.
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
                      // Compact density + tight padding/constraints keep
                      // this close button small, matching the panel's
                      // otherwise compact 250px-wide header.
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
                        // "Previous string" arrow — disabled at the start
                        // of history.
                        _StringNavArrow(
                          icon: Icons.arrow_left,
                          tooltip: 'Previous string',
                          enabled: _stringIndex > 0,
                          onPressed: _prevString,
                        ),
                        const SizedBox(width: 2),
                        // The main editable input-string field.
                        Expanded(
                          child: TextField(
                            controller: widget.controller,
                            onChanged: (v) {
                              // Keep the history entry in sync as the user
                              // types, so switching away and back preserves
                              // the in-progress edit.
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
                              fillColor: theme.bg,
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
                        // "Next string" arrow — always enabled; its tooltip
                        // changes to "Add new string" once at the end of
                        // history, reflecting _nextString's dual behavior.
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

                    // String counter + delete — only shown once there's
                    // more than one string in history (no point cluttering
                    // the UI with "1 / 1").
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
                                    // Only allow removing a tape when more
                                    // than one exists (never delete the
                                    // last remaining tape) and the parent
                                    // actually supports removal.
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
                              // + add-tape button — only rendered if the
                              // parent actually wired up an onTapeAdded
                              // handler.
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
                          // additionalTapeControllers is indexed starting
                          // from tape 2, so subtract 1 from the 0-based
                          // activeTapeIndex to find the right controller.
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
                            fillColor: theme.bg,
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
                      // The tape strip itself for TM mode: one chip per
                      // cell in the currently-selected tape's view window.
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
                      // Non-TM modes: render the consumed/current/upcoming
                      // token strip instead of a tape.
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
                            // A token counts as "consumed" if it's before
                            // the current chip (when one exists), or
                            // otherwise before the raw step index — this
                            // fallback matters right when playback moves
                            // past the last token (currentChipIndex becomes
                            // -1 because there's no token at that index,
                            // but everything up to `step` is still consumed).
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
                          // Disabled when there's no input or already at
                          // the very start.
                          onPressed: (hasTokens && !atStart) ? _rewind : null,
                        ),
                        _TransportBtn(
                          icon: Icons.chevron_left,
                          tooltip: 'Step back',
                          onPressed: (hasTokens && !atStart) ? _stepBack : null,
                        ),
                        // Play/pause — styled as a filled circular button
                        // rather than a plain IconButton, making it the
                        // visually primary transport control.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Material(
                            // Background reflects state: only lit up at all
                            // when there's something to play and it's not
                            // already finished; brighter highlight while
                            // actively playing versus a neutral border tone
                            // when paused-but-playable.
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
                          // TM mode's "skip to end" is really a bounded
                          // fast-forward (since the computation might not
                          // halt), so its tooltip is worded differently
                          // from the other modes' true "jump to the known
                          // end" behavior.
                          tooltip: isTmMode ? 'Fast forward (5s)' : 'Skip to end',
                          onPressed: (hasTokens && !atEnd) ? _skipToEnd : null,
                        ),
                      ],
                    ),

                    // Speed selector row — only relevant once there's
                    // something to play back.
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
                          // If playback is currently running, immediately
                          // reschedule the next tick using the new speed
                          // rather than waiting out the old (possibly much
                          // slower) delay first.
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

                    // Result banner — animates in with a color/border that
                    // reflects accept vs. reject.
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
        // Route taps through only when enabled — GestureDetector itself
        // doesn't have a built-in disabled state like IconButton does.
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
              // Dim the border further when disabled, on top of the
              // already-dimmer background, to reinforce the disabled look.
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

// ─────────────────────────────────────────────────────────────────────────────
//  Generic transport control button (rewind / step / skip icons)
// ─────────────────────────────────────────────────────────────────────────────
class _TransportBtn extends StatelessWidget {
  const _TransportBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  // Nullable: passing null disables the button (standard Flutter
  // IconButton convention) rather than using a separate `enabled` flag.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return IconButton(
      // Dim the icon automatically when disabled (onPressed == null).
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
  // Shared pulse animation instance from the parent State, driving the
  // "current" chip's breathing scale effect.
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    // The chip currently being read: pulses via a Transform.scale driven by
    // the shared animation, and uses the "highlight" color scheme.
    if (isCurrent) {
      return AnimatedBuilder(
        animation: pulseAnim,
        // Rebuilding just the Transform.scale on each animation tick (via
        // the `child` param) avoids rebuilding the whole chip's subtree —
        // `child` is built once and reused across animation frames.
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
    // Already-consumed tokens: muted/grayed-out styling.
    if (isConsumed) {
      return _chip(
        bg: theme.gridLine,
        fg: theme.textDim,
        border: theme.borderMid,
        bold: false,
      );
    }
    // Not-yet-reached tokens: neutral/transparent styling.
    return _chip(
      bg: Colors.transparent,
      fg: theme.textMid,
      border: theme.borderMid,
      bold: false,
    );
  }

  // Shared chip-shape builder used by all three visual states above, so
  // only the color scheme and boldness need to vary per call site.
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

    // The cell under the read/write head: pulses via the shared animation,
    // uses the "highlight" color, and always renders in solid white text
    // (rather than a theme-derived color) for maximum contrast against the
    // bright highlight background.
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
              // Render the blank-tape symbol as '∅' for readability instead
              // of whatever internal sentinel string kBlank actually is.
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
    // Non-head cells: neutral gridline-tinted styling.
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