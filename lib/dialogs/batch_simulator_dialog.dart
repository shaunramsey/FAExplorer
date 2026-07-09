import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../widgets/app_theme.dart';
import '../models.dart';
import '../simulator.dart';

class _BatchHighlightController extends TextEditingController {
  _BatchHighlightController({required this.isAccepted, required this.isRejected});

  final bool Function(int lineIndex) isAccepted;
  final bool Function(int lineIndex) isRejected;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final lines = text.split('\n');
    final children = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final color = isAccepted(i)
          ? Colors.green
          : isRejected(i)
              ? Colors.red
              : Colors.white;
      children.add(TextSpan(
        text: lines[i],
        style: GoogleFonts.courierPrime(color: color, fontSize: 16),
      ));
      if (i != lines.length - 1) {
        children.add(TextSpan(
          text: '\n',
          style: GoogleFonts.courierPrime(color: Colors.white, fontSize: 16),
        ));
      }
    }

    return TextSpan(children: children);
  }
}

Future<void> showBatchSimulatorDialog(
  BuildContext context, {
  required AutomataSimulator simulator,
  PdaSimulator? pdaSimulator,
  TmSimulator? tmSimulator,
  required StartArrowData? startArrow,
  // The string currently loaded in the main string-simulator panel, plus any
  // extra-tape inputs (TM only). Needed to restore each simulator to its
  // pre-batch state once every candidate line has been tested — see the
  // comment above `rebuildResults()` for why this must be a full rebuild()
  // rather than a manual field-by-field restore.
  required String currentInput,
  List<String> additionalTapeInputs = const [],
}) async {
  final accepted = <int>{};
  final rejected = <int>{};
  late _BatchHighlightController controller;

  // Each iteration below drives a simulator through rebuild(candidateString)
  // purely to read off its accept/reject verdict, then must put that
  // simulator back exactly how it was so the main screen keeps showing the
  // *original* string's state once this dialog closes.
  //
  // That restoration used to be done by hand-copying a few public fields
  // (tokens, steps, step, states, usedLines). That was never enough:
  //   - AutomataSimulator additionally tracks acceptance via a *private*
  //     field (_configsByStep) that the dialog has no way to reach and copy
  //     back, so finalResult() kept reflecting the last batch line tested.
  //   - PdaSimulator/TmSimulator also carry loop/halt flags
  //     (stackGrowthLoopDetected / noMovesTerminal) and their own `tokens`
  //     list that weren't part of the manual restore, risking a stale
  //     "loop detected" result and a RangeError in remainingInputAt() if a
  //     later string were shorter than the last batch line tested.
  //
  // Rebuilding each simulator against `currentInput` after the test is the
  // one operation guaranteed to reset *all* of that state at once, public
  // or private, because it's the same code path the main screen itself uses
  // to build a simulator's state from a string. The extra rebuild per line
  // is negligible for the string lengths this dialog is used with.
  void rebuildResults() {
    accepted.clear();
    rejected.clear();

    final lines = controller.text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final str = lines[i].replaceAll('\r', '');
      final isComplete = i < lines.length - 1 || controller.text.endsWith('\n');
      if (!isComplete || str.isEmpty) continue;

      if (tmSimulator != null) {
        final oldStep = tmSimulator.step;

        tmSimulator.rebuild(str, startArrow: startArrow);
        final result = tmSimulator.result;

        if (result == TmResult.accept) {
          accepted.add(i);
        } else if (result == TmResult.reject) {
          rejected.add(i);
        }

        tmSimulator.rebuild(
          currentInput,
          startArrow: startArrow,
          additionalTapeInputs: additionalTapeInputs,
        );
        tmSimulator.step = oldStep.clamp(-1, tmSimulator.maxStep);
      } else if (pdaSimulator != null) {
        final oldStep = pdaSimulator.step;

        pdaSimulator.rebuild(str, startArrow: startArrow);
        final result = pdaSimulator.finalResult();

        if (result == PdaSimResult.accept) {
          accepted.add(i);
        } else {
          rejected.add(i);
        }

        pdaSimulator.rebuild(currentInput, startArrow: startArrow);
        pdaSimulator.step = oldStep.clamp(-1, pdaSimulator.maxStep);
      } else {
        final oldStep = simulator.step;

        simulator.rebuild(str, startArrow: startArrow);
        final result = simulator.finalResult();

        if (result == SimResult.accept) {
          accepted.add(i);
        } else {
          rejected.add(i);
        }

        simulator.rebuild(currentInput, startArrow: startArrow);
        simulator.step = oldStep.clamp(-1, simulator.maxStep);
      }
    }
  }

  controller = _BatchHighlightController(
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
          final theme = context.watch<AppThemeNotifier>();
          final acceptCount = accepted.length;
          final rejectCount = rejected.length;
          final totalRun    = acceptCount + rejectCount;

          return AlertDialog(
            backgroundColor: theme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.borderMid),
            ),
            title: Text(
              'Batch String Simulator${tmSimulator != null ? ' (TM)' : pdaSimulator != null ? ' (PDA)' : ''}',
              style: GoogleFonts.courierPrime(
                color: theme.textLight,
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
                      cursorColor: theme.accent,
                      style: GoogleFonts.courierPrime(
                          color: theme.textLight, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'One string per line...\nPress enter to simulate.',
                        hintStyle: GoogleFonts.courierPrime(color: theme.textDim),
                        filled: true,
                        fillColor: const Color(0xFF080D14),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.borderMid),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.borderMid),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.accent, width: 1.5),
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
                            foregroundColor: theme.textMid,
                            side: BorderSide(color: theme.borderMid),
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
                                result.files.single.bytes == null) {
                              return;
                            }
                            final text = utf8.decode(
                                result.files.single.bytes!,
                                allowMalformed: true);
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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