import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_theme.dart';
import '../models.dart';
import '../dsl_code.dart';
import '../latex_export.dart';
import '../pda_simulator.dart';
import '../saved_export.dart';
import '../simulator.dart';
import '../svg_export.dart';
import '../tm_simulator.dart';
import '../widgets/automata_drawer.dart' show AutomataMode;

void showExportDialog(
  BuildContext context, {
  required String dsl,
  required int savedExportCount,
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? startArrow,
  required GraphState graphState,
  required void Function(String name, String dsl) onSave,
}) {
  final theme = AppThemeNotifier.read(context);
  final nameController = TextEditingController(text: 'Export ${savedExportCount + 1}');

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.borderMid),
      ),
      title: Text(
        'Export',
        style: GoogleFonts.courierPrime(
          fontWeight: FontWeight.bold,
          color: theme.textLight,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              style: GoogleFonts.courierPrime(color: theme.textLight, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Save Name',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Copied to clipboard.',
              style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textMid),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.borderMid),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    dsl.isEmpty ? '(empty graph)' : dsl,
                    style: GoogleFonts.courierPrime(
                        fontSize: 13, color: theme.textMid),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final svg = SvgExporter.export(
                nodes: nodes, lines: lines, startArrow: startArrow);
            await Clipboard.setData(ClipboardData(text: svg));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('SVG copied to clipboard',
                    style: GoogleFonts.courierPrime()),
              ),
            );
            Navigator.pop(ctx);
          },
          child: const Text('Export SVG'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            showLatexExportDialog(context, graphState: graphState);
          },
          child: const Text('Export LaTeX'),
        ),
        TextButton(
          onPressed: () {
            onSave(
              nameController.text.trim().isEmpty
                  ? 'Untitled'
                  : nameController.text.trim(),
              dsl,
            );
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export saved')));
          },
          child: const Text('Save'),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: dsl));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')));
          },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

void showImportDialog(
  BuildContext context, {
  required String? Function(String text, {required bool isSvg}) onImport,
}) {
  final theme = AppThemeNotifier.read(context);
  final controller = TextEditingController();
  String? errorText;

  const hint =
      'n0 = hello world\n'
      'n1 = yes and no\n'
      'hello world to yes and no = pears\n'
      'pears curve = 30\n'
      'apples\n'
      'apples to yes and no\n'
      'to apples\n'
      'apples to apples = 1\n'
      'apples = (0, 0)\n'
      'to apples length = 150\n'
      'apples is accepted';

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.borderMid),
        ),
        title: Text(
          'Import',
          style: GoogleFonts.courierPrime(
              fontWeight: FontWeight.bold, color: theme.textLight),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  style: GoogleFonts.courierPrime(
                      fontSize: 13, color: theme.textLight),
                  cursorColor: theme.accent,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: hint,
                    hintStyle: GoogleFonts.courierPrime(
                        fontSize: 11, color: theme.textDim),
                    errorText: errorText,
                    errorMaxLines: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final clip = await Clipboard.getData(Clipboard.kTextPlain);
              if (clip?.text != null) controller.text = clip!.text!;
            },
            child: const Text('Paste'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              final lower = text.toLowerCase();
              final isSvg =
                  lower.contains('<svg') && lower.contains('</svg>');
              final err = onImport(text, isSvg: isSvg);
              if (err == null) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Import successful')));
              } else {
                setDialogState(() => errorText = err);
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    ),
  );
}

void showExportHistoryDialog(
  BuildContext context, {
  required List<SavedExport> savedExports,
  required String? Function(String dsl) onImportDsl,
  required void Function(SavedExport export) onInsertBlackBox,
  required void Function() onListChanged,
}) {
  final theme = AppThemeNotifier.read(context);

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: theme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.borderMid),
            ),
            title: Text(
              'Saved Exports',
              style: GoogleFonts.courierPrime(
                  fontWeight: FontWeight.bold, color: theme.textLight),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: savedExports.isEmpty
                  ? Center(
                      child: Text(
                        'No saved exports',
                        style: GoogleFonts.courierPrime(color: theme.textDim),
                      ),
                    )
                  : ListView.builder(
                      itemCount: savedExports.length,
                      itemBuilder: (context, index) {
                        if (index >= savedExports.length) {
                          return const SizedBox.shrink();
                        }
                        final save = savedExports[index];
                        return ListTile(
                          title: Text(save.name,
                              style: TextStyle(color: theme.textLight)),
                          leading: save.isBlackBox
                              ? Icon(Icons.inbox_rounded,
                                  color: theme.textMid)
                              : Icon(Icons.account_tree_outlined,
                                  color: theme.textMid),
                          subtitle: Text(
                            save.isBlackBox
                                ? 'Black box machine'
                                : (save.dsl.trim().isEmpty
                                    ? '(empty export)'
                                    : save.dsl.split('\n').first),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: theme.textDim),
                          ),
                          onTap: () {
                            if (save.isBlackBox) {
                              showBlackBoxRunnerDialog(context, save: save);
                              return;
                            }
                            Navigator.of(ctx).pop();
                            final err = onImportDsl(save.dsl);
                            if (err != null) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('Import error: $err'),
                              ));
                            }
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Available for all exports: inserts a black box
                              // node onto the canvas backed by this saved DSL.
                              IconButton(
                                icon: Icon(Icons.add_box_outlined,
                                    color: theme.textMid),
                                tooltip: 'Insert as black box node',
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  onInsertBlackBox(save);
                                },
                              ),
                              if (!save.isBlackBox) ...[
                                IconButton(
                                  icon: Icon(
                                      Icons.input_rounded,
                                      color: theme.textMid),
                                  tooltip: 'Load',
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        backgroundColor: theme.surface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          side:
                                              BorderSide(color: theme.borderMid),
                                        ),
                                        title: Text(
                                          'Load "${save.name}"?',
                                          style: TextStyle(
                                              color: theme.textLight),
                                        ),
                                        content: Text(
                                          'This will replace the current graph.',
                                          style: TextStyle(
                                              color: theme.textMid),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              Navigator.of(ctx).pop();
                                              final err =
                                                  onImportDsl(save.dsl);
                                              if (err != null) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Import error: $err'),
                                                ));
                                              }
                                            },
                                            child: const Text('Import'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.code,
                                      color: theme.textMid),
                                  tooltip: 'Export as LaTeX',
                                  onPressed: () {
                                    try {
                                      final gs = DslCodec.importFromDsl(save.dsl);
                                      showLatexExportDialog(context, graphState: gs);
                                    } catch (e) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text('LaTeX export error: $e'),
                                      ));
                                    }
                                  },
                                ),
                              ],
                              IconButton(
                                icon: Icon(Icons.edit, color: theme.textMid),
                                onPressed: () {
                                  final controller =
                                      TextEditingController(text: save.name);
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      backgroundColor: theme.surface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        side:
                                            BorderSide(color: theme.borderMid),
                                      ),
                                      title: Text('Rename Export',
                                          style:
                                              TextStyle(color: theme.textLight)),
                                      content: TextField(
                                        controller: controller,
                                        style: TextStyle(color: theme.textLight),
                                        cursorColor: theme.accent,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () {
                                            save.name =
                                                controller.text.trim();
                                            onListChanged();
                                            setDialogState(() {});
                                            Navigator.pop(context);
                                          },
                                          child: const Text('Save'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Color(0xFFFF1744)),
                                onPressed: () {
                                  savedExports.removeAt(index);
                                  onListChanged();
                                  setDialogState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}

void showBlackBoxRunnerDialog(
  BuildContext context, {
  required SavedExport save,
}) {
  final theme = AppThemeNotifier.read(context);
  final inputController = TextEditingController();
  String output = '';
  String? errorText;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.borderMid),
        ),
        title: Text(
          save.name,
          style: GoogleFonts.courierPrime(
              fontWeight: FontWeight.bold, color: theme.textLight),
        ),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Black box machine',
                style: TextStyle(color: theme.textMid),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: inputController,
                maxLines: 8,
                style: GoogleFonts.courierPrime(
                    fontSize: 13, color: theme.textLight),
                cursorColor: theme.accent,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'One input string per line',
                  hintStyle: TextStyle(color: theme.textDim),
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.borderMid),
                  borderRadius: BorderRadius.circular(6),
                  color: theme.bg,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    output.isEmpty
                        ? 'Output will list only accepted strings and changes.'
                        : output,
                    style: GoogleFonts.courierPrime(
                        fontSize: 13, color: theme.textMid),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              final results = _runBlackBox(save, inputController.text);
              if (results.error != null) {
                setDialogState(() => errorText = results.error);
                return;
              }
              setDialogState(() {
                errorText = null;
                output = results.lines.isEmpty
                    ? '(no accepted strings)'
                    : results.lines.join('\n');
              });
            },
            child: const Text('Run'),
          ),
        ],
      ),
    ),
  );
}

({List<String> lines, String? error}) _runBlackBox(
  SavedExport save,
  String rawInput,
) {
  GraphState state;
  try {
    state = DslCodec.importFromDsl(save.dsl);
  } catch (e) {
    return (lines: const [], error: 'Black box parse error: $e');
  }

  final rows = rawInput
      .split('\n')
      .map((line) => line.replaceAll('\r', ''))
      .where((line) => line.isNotEmpty)
      .toList();

  if (rows.isEmpty) return (lines: const [], error: null);

  final output = <String>[];
  switch (state.automataMode) {
    case AutomataMode.ndfa:
    case AutomataMode.regex:
      final sim = AutomataSimulator(nodes: state.nodes, lines: state.lines);
      for (final row in rows) {
        sim.rebuild(row, startArrow: state.startArrow);
        if (sim.finalResult() == SimResult.accept) output.add(row);
      }
      break;
    case AutomataMode.pda:
      final sim = PdaSimulator(nodes: state.nodes, lines: state.lines);
      for (final row in rows) {
        sim.rebuild(row, startArrow: state.startArrow);
        if (sim.finalResult() == PdaSimResult.accept) output.add(row);
      }
      break;
    case AutomataMode.tm:
      final sim = TmSimulator(nodes: state.nodes, lines: state.lines);
      for (final row in rows) {
        sim.rebuild(row, startArrow: state.startArrow);
        while (sim.computeNext()) {}
        if (sim.result != TmResult.accept) continue;
        final transformed = _tmOutputString(sim);
        if (transformed == row) {
          output.add(row);
        } else {
          output.add('$row -> $transformed');
        }
      }
      break;
  }

  return (lines: output, error: null);
}

String _tmOutputString(TmSimulator sim) {
  final tape = sim.currentTape;
  if (tape == null) return '';
  final cells = tape.cells.map((c) => c == kBlank ? '' : c).toList();
  int start = 0;
  int end = cells.length;
  while (start < end && cells[start].isEmpty) start++;
  while (end > start && cells[end - 1].isEmpty) end--;
  if (start >= end) return '';
  return cells.sublist(start, end).join();
}