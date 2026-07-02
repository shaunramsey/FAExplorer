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
  TmSimulator? tmSimulator,
  required StartArrowData? startArrow,
}) async {
  final accepted = <int>{};
  final rejected = <int>{};
  late _BatchHighlightController controller;

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
              'Batch String Simulator${tmSimulator != null ? ' (TM)' : ''}',
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