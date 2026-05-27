import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import '../simulator.dart';
import '../tm_simulator.dart';
import '../batch_highlight_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Public entry-point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showBatchSimulatorDialog(
  BuildContext context, {
  required AutomataSimulator simulator,
  TmSimulator? tmSimulator,
  required StartArrowData? startArrow,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BatchSimulatorDialog(
      simulator: simulator,
      tmSimulator: tmSimulator,
      startArrow: startArrow,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dialog widget
// ─────────────────────────────────────────────────────────────────────────────

class _BatchSimulatorDialog extends StatefulWidget {
  const _BatchSimulatorDialog({
    required this.simulator,
    required this.tmSimulator,
    required this.startArrow,
  });

  final AutomataSimulator simulator;
  final TmSimulator? tmSimulator;
  final StartArrowData? startArrow;

  @override
  State<_BatchSimulatorDialog> createState() => _BatchSimulatorDialogState();
}

class _BatchSimulatorDialogState extends State<_BatchSimulatorDialog> {
  late final BatchHighlightController _controller;

  /// Per-line results: true = accept, false = reject, null = not yet run.
  List<bool?> _results = [];

  bool _hasRun = false;

  bool get _isTmMode => widget.tmSimulator != null;

  @override
  void initState() {
    super.initState();
    _controller = BatchHighlightController(
      isAccepted: (i) => i < _results.length && _results[i] == true,
      isRejected: (i) => i < _results.length && _results[i] == false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Run all lines ──────────────────────────────────────────────────────────

  void _runAll() {
    final lines = _controller.text.split('\n');
    final results = <bool?>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        results.add(null);
        continue;
      }

      if (_isTmMode) {
        // Run through the TM simulator.
        final tm = widget.tmSimulator!;
        tm.rebuild(line, startArrow: widget.startArrow);
        final r = tm.result;
        results.add(r == TmResult.accept ? true : r == TmResult.reject ? false : null);
      } else {
        // Run through the FA simulator.
        widget.simulator.rebuild(line, startArrow: widget.startArrow);
        final r = widget.simulator.finalResult();
        results.add(r == SimResult.accept);
      }
    }

    setState(() {
      _results = results;
      _hasRun = true;
    });
  }

  // ── Summary counts ─────────────────────────────────────────────────────────

  int get _acceptCount => _results.where((r) => r == true).length;
  int get _rejectCount => _results.where((r) => r == false).length;
  int get _totalRun    => _results.where((r) => r != null).length;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.science, size: 18, color: Colors.purple),
          const SizedBox(width: 8),
          Text(
            'Batch Simulator${_isTmMode ? ' (TM)' : ''}',
            style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter one input string per line. Press Run to test all.',
              style: GoogleFonts.courierPrime(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),

            // ── Input area ───────────────────────────────────────────────
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black54),
              ),
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style: GoogleFonts.courierPrime(fontSize: 16, color: Colors.white),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onChanged: (_) {
                  // Clear results when text changes so stale highlights don't linger.
                  if (_hasRun) {
                    setState(() {
                      _results = [];
                      _hasRun = false;
                    });
                  }
                },
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'ab\naab\nb\n...',
                  hintStyle: GoogleFonts.courierPrime(
                    color: Colors.white30,
                    fontSize: 16,
                  ),
                  isDense: true,
                ),
              ),
            ),

            // ── Summary ─────────────────────────────────────────────────
            if (_hasRun && _totalRun > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _SummaryChip(
                    label: '$_acceptCount accepted',
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: '$_rejectCount rejected',
                    color: Colors.red.shade700,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: GoogleFonts.courierPrime()),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow, size: 16),
          label: Text('Run', style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          onPressed: _runAll,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small summary chip
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.courierPrime(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}