import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../pda_simulator.dart';
import 'app_theme.dart';

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
    final atEnd = simulator.step == simulator.tokens.length;

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
                        'Stopped: ε-closure stack became too large '
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
            value: remaining.isEmpty ? 'ε' : remaining,
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
    final display = symbol.isEmpty ? 'ε' : symbol;
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