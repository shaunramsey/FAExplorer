import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import '../tm_simulator.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme palette (mirrors main.dart)
// ─────────────────────────────────────────────────────────────────────────────
const _kSurface   = Color(0xFF0A0F18);
const _kBorderMid = Color(0xFF1A2535);
const _kAccent    = Color(0xFF00E5FF);
const _kTextLight = Color(0xFFCDD5E0);
const _kTextMid   = Color(0xFF6B7E96);
const _kTextDim   = Color(0xFF3A4A5E);

/// Floating panel: NTM configurations (state, head position, tape) per step.
class TmConfigPanel extends StatelessWidget {
  final TmSimulator simulator;
  final Map<String, NodeData> nodes;

  const TmConfigPanel({
    super.key,
    required this.simulator,
    required this.nodes,
  });

  String _stateLabel(String nodeId) => displayNodeLabel(nodeId, nodes);

  @override
  Widget build(BuildContext context) {
    final configs = simulator.activeConfigs;
    final result  = simulator.result;
    final isDone  = result != TmResult.running;

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
            color: _kSurface,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _kBorderMid),
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
                          color: headerColor ?? _kAccent),
                      const SizedBox(width: 6),
                      Text(
                        'TM (NTM)',
                        style: GoogleFonts.courierPrime(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: headerColor ?? _kTextLight,
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
                    style: GoogleFonts.courierPrime(fontSize: 11, color: _kTextDim),
                  ),
                  Divider(height: 16, color: _kBorderMid),

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
                                      color: _kTextDim,
                                    ),
                                  ),
                                ),
                              _TmConfigCard(
                                stateLabel: _stateLabel(configs[i].nodeId),
                                headPos: configs[i].readHeadPos,
                                tape: configs[i].tape,
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
  final int headPos;
  final TmTape tape;
  final bool isAccepted;
  final bool isRejected;

  const _TmConfigCard({
    required this.stateLabel,
    required this.headPos,
    required this.tape,
    required this.isAccepted,
    required this.isRejected,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isAccepted
        ? const Color(0xFF1FD99A)
        : isRejected
            ? const Color(0xFFFF1744)
            : _kBorderMid;

    final bgColor = isAccepted
        ? const Color(0xFF051A10)
        : isRejected
            ? const Color(0xFF1A0005)
            : const Color(0xFF080D14);

    final stateTextColor = isAccepted
        ? const Color(0xFF1FD99A)
        : isRejected
            ? const Color(0xFFFF1744)
            : _kTextLight;

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
                  style: GoogleFonts.courierPrime(fontSize: 10, color: _kTextDim),
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
                    color: const Color(0xFF1FD99A),
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
            'tape',
            style: GoogleFonts.courierPrime(fontSize: 10, color: _kTextDim),
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
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: isHead ? const Color(0xFF0A1929) : const Color(0xFF080D14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHead ? _kAccent : _kBorderMid,
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
                color: isHead ? _kAccent : _kTextMid,
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
                  style: TextStyle(fontSize: 7, color: _kAccent.withOpacity(0.7)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}