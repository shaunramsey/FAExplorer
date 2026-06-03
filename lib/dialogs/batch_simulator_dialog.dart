import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../batch_highlight_controller.dart';
import '../models.dart';
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

Future<void> showBatchSimulatorDialog(
  BuildContext context, {
  required AutomataSimulator simulator,
  TmSimulator? tmSimulator,
  required StartArrowData? startArrow,
}) async {
  final accepted = <int>{};
  final rejected = <int>{};
  late BatchHighlightController controller;

  void rebuildResults() {
    accepted.clear();
    rejected.clear();

    final lines = controller.text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final str = lines[i].replaceAll('\r', '');
      final isComplete = i < lines.length - 1 || controller.text.endsWith('\n');
      if (!isComplete || str.isEmpty) continue;

      if (tmSimulator != null) {
        final oldStep  = tmSimulator.step;
        final oldSteps = List<TmStepSnapshot>.from(tmSimulator.steps);

        tmSimulator.rebuild(str, startArrow: startArrow);
        final result = tmSimulator.result;

        if (result == TmResult.accept) {
          accepted.add(i);
        } else if (result == TmResult.reject) {
          rejected.add(i);
        }

        tmSimulator.steps
          ..clear()
          ..addAll(oldSteps);
        tmSimulator.step = oldStep;
      } else {
        final oldTokens = List<String>.from(simulator.tokens);
        final oldStates = simulator.states.map(Set<String>.from).toList();
        final oldLines  = simulator.usedLines.map(Set<String>.from).toList();
        final oldStep   = simulator.step;

        simulator.rebuild(str, startArrow: startArrow);
        final result = simulator.finalResult();

        if (result == SimResult.accept) {
          accepted.add(i);
        } else {
          rejected.add(i);
        }

        simulator.tokens = oldTokens;
        simulator.step   = oldStep;
        simulator.states
          ..clear()
          ..addAll(oldStates);
        simulator.usedLines
          ..clear()
          ..addAll(oldLines);
      }
    }
  }

  controller = BatchHighlightController(
    isAccepted: (i) => accepted.contains(i),
    isRejected: (i) => rejected.contains(i),
  );
  controller.addListener(rebuildResults);
  rebuildResults();

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          final acceptCount = accepted.length;
          final rejectCount = rejected.length;
          final totalRun    = acceptCount + rejectCount;

          return AlertDialog(
            backgroundColor: _kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _kBorderMid),
            ),
            title: Text(
              'Batch String Simulator${tmSimulator != null ? ' (TM)' : ''}',
              style: GoogleFonts.courierPrime(
                color: _kTextLight,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              width: 700,
              height: 500,
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      cursorColor: _kAccent,
                      style: GoogleFonts.courierPrime(
                          color: _kTextLight, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'One string per line...\nPress enter to simulate.',
                        hintStyle: GoogleFonts.courierPrime(color: _kTextDim),
                        filled: true,
                        fillColor: const Color(0xFF080D14),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: _kBorderMid),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _kBorderMid),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _kAccent, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (_) => setLocalState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Summary row ──────────────────────────────────────────
                  if (totalRun > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          _SummaryChip(
                            label: '$acceptCount accepted',
                            color: const Color(0xFF1FD99A),
                          ),
                          const SizedBox(width: 8),
                          _SummaryChip(
                            label: '$rejectCount rejected',
                            color: const Color(0xFFFF1744),
                          ),
                        ],
                      ),
                    ),

                  // ── Import button ────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D1620),
                            foregroundColor: _kTextMid,
                            side: BorderSide(color: _kBorderMid),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['txt'],
                            );
                            if (result == null ||
                                result.files.single.bytes == null) return;
                            final text = String.fromCharCodes(
                                result.files.single.bytes!);
                            setLocalState(() {
                              controller.text = text;
                              rebuildResults();
                            });
                          },
                          child: Text('Import .txt',
                              style: GoogleFonts.courierPrime()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  controller.dispose();
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