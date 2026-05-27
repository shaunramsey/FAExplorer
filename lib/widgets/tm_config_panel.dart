import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import '../tm_simulator.dart';

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
        TmResult.accept  => Colors.green.shade700,
        TmResult.reject  => Colors.red.shade700,
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
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ───────────────────────────────────────────
                  Row(
                    children: [
                      Icon(Icons.memory, size: 18, color: headerColor ?? Colors.blueGrey),
                      const SizedBox(width: 6),
                      Text(
                        'TM (NTM)',
                        style: GoogleFonts.courierPrime(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: headerColor,
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
                    style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black54),
                  ),
                  const Divider(height: 16),

                  // ── Loop warning ─────────────────────────────────────
                  if (simulator.loopDetected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Stopped: step limit reached (possible infinite loop).',
                        style: GoogleFonts.courierPrime(
                          fontSize: 12,
                          color: Colors.deepOrange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  // ── Configs list ─────────────────────────────────────
                  if (configs.isEmpty)
                    Text(
                      simulator.loopDetected ? 'Simulation aborted' : 'No active configuration',
                      style: GoogleFonts.courierPrime(fontSize: 13, color: Colors.red),
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
                                      color: Colors.black45,
                                    ),
                                  ),
                                ),
                              _TmConfigCard(
                                stateLabel: _stateLabel(configs[i].nodeId),
                                headPos: configs[i].readHeadPos,
                                tape: configs[i].tape,
                                isAccepted: () {
                                  final node = nodes[configs[i].nodeId];
                                  return node != null && (node.isHaltAccept || node.isAccept);
                                }(),
                                isRejected: () {
                                  final node = nodes[configs[i].nodeId];
                                  return node != null && node.isHaltReject;
                                }(),
                              ),
                              if (i < configs.length - 1) const SizedBox(height: 12),
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
        ? Colors.green.shade300
        : isRejected
            ? Colors.red.shade300
            : Colors.grey.shade300;

    final bgColor = isAccepted
        ? Colors.green.shade50
        : isRejected
            ? Colors.red.shade50
            : Colors.grey.shade50;

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
                  style: GoogleFonts.courierPrime(fontSize: 10, color: Colors.black45),
                ),
              ),
              Expanded(
                child: Text(
                  stateLabel,
                  style: GoogleFonts.courierPrime(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isAccepted
                        ? Colors.green.shade800
                        : isRejected
                            ? Colors.red.shade800
                            : Colors.black87,
                  ),
                ),
              ),
              if (isAccepted)
                Text(
                  'ACCEPT',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              if (isRejected)
                Text(
                  'REJECT',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Tape row label
          Text(
            'tape',
            style: GoogleFonts.courierPrime(fontSize: 10, color: Colors.black45),
          ),
          const SizedBox(height: 4),

          // Tape strip
          _TapeStrip(tape: tape, headPos: headPos),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tape strip  — horizontal scrollable row of cells
// ─────────────────────────────────────────────────────────────────────────────

class _TapeStrip extends StatelessWidget {
  final TmTape tape;
  final int headPos; // absolute

  const _TapeStrip({required this.tape, required this.headPos});

  @override
  Widget build(BuildContext context) {
    // Build a window: 3 blanks before first cell, the cells, 3 blanks after.
    const pad = 3;
    final startAbs = -pad;                              // relative to origin (headOffset=0)
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
        color: isHead ? const Color(0xFFE3F2FD) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHead ? Colors.blue.shade400 : Colors.grey.shade300,
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
                color: isHead ? Colors.blue.shade800 : Colors.black87,
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
                  style: TextStyle(fontSize: 7, color: Colors.blue.shade400),
                ),
              ),
            ),
        ],
      ),
    );
  }
}