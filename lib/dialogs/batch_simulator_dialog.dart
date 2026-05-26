import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../batch_highlight_controller.dart';
import '../models.dart';
import '../simulator.dart';

Future<void> showBatchSimulatorDialog(
  BuildContext context, {
  required AutomataSimulator simulator,
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

      final oldTokens = List<String>.from(simulator.tokens);
      final oldStates = simulator.states.map(Set<String>.from).toList();
      final oldLines = simulator.usedLines.map(Set<String>.from).toList();
      final oldStep = simulator.step;

      simulator.rebuild(str, startArrow: startArrow);
      final result = simulator.finalResult();

      if (result == SimResult.accept) {
        accepted.add(i);
      } else {
        rejected.add(i);
      }

      simulator.tokens = oldTokens;
      simulator.step = oldStep;
      simulator.states
        ..clear()
        ..addAll(oldStates);
      simulator.usedLines
        ..clear()
        ..addAll(oldLines);
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
          return AlertDialog(
            backgroundColor: Colors.black,
            title: Text('Batch String Simulator', style: GoogleFonts.courierPrime(color: Colors.white)),
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
                      cursorColor: Colors.white,
                      style: GoogleFonts.courierPrime(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'One string per line...\nPress enter to simulate.',
                        hintStyle: GoogleFonts.courierPrime(color: Colors.grey),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocalState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['txt'],
                            );
                            if (result == null || result.files.single.bytes == null) return;
                            final text = String.fromCharCodes(result.files.single.bytes!);
                            setLocalState(() {
                              controller.text = text;
                              rebuildResults();
                            });
                          },
                          child: Text('Import .txt', style: GoogleFonts.courierPrime()),
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
}
