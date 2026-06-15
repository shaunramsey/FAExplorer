import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import 'app_theme.dart';

/// Dialog for editing the inner machine (DSL) and description of a black-box
/// node — i.e. *what* the black box actually does to the tape/string it
/// reads and writes.
///
/// Returns `true` via [showDialog] if the values were changed, so the caller
/// can `setState`/persist as needed. The [node]'s `blackBoxDsl` and
/// `blackBoxDescription` fields are mutated in place on save.
class BlackBoxEditDialog extends StatefulWidget {
  final NodeData node;

  const BlackBoxEditDialog({super.key, required this.node});

  /// Convenience helper: shows the dialog and returns `true` if the user
  /// saved changes.
  static Future<bool?> show(BuildContext context, {required NodeData node}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => BlackBoxEditDialog(node: node),
    );
  }

  @override
  State<BlackBoxEditDialog> createState() => _BlackBoxEditDialogState();
}

class _BlackBoxEditDialogState extends State<BlackBoxEditDialog> {
  late final TextEditingController _dslController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _dslController = TextEditingController(text: widget.node.blackBoxDsl);
    _descController = TextEditingController(text: widget.node.blackBoxDescription);
  }

  @override
  void dispose() {
    _dslController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _save() {
    widget.node.blackBoxDsl = _dslController.text.trim();
    widget.node.blackBoxDescription = _descController.text.trim();
    Navigator.of(context).pop(true);
  }

  void _clear() {
    setState(() {
      _dslController.clear();
      _descController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final nodeName = widget.node.label.trim().isEmpty
        ? 'this black box'
        : '"${widget.node.label.trim()}"';

    return Dialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.borderMid),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ────────────────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.memory, size: 18, color: theme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Black Box Program',
                      style: GoogleFonts.courierPrime(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Edit the inner machine $nodeName runs against the tape it '
                'reads and writes. Paste a DSL definition exported from '
                'another graph, or write one directly.',
                style: TextStyle(fontSize: 12, color: theme.textMid, height: 1.4),
              ),

              const SizedBox(height: 16),

              // ── Description field ───────────────────────────────────────
              Text(
                'Description',
                style: GoogleFonts.courierPrime(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.textDim,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. "Increments a binary number by 1"',
                  hintStyle: TextStyle(color: theme.textDim.withOpacity(0.6)),
                  filled: true,
                  fillColor: theme.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.borderMid),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.borderMid),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.accent),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),

              const SizedBox(height: 14),

              // ── DSL field ────────────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Machine DSL',
                    style: GoogleFonts.courierPrime(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.textDim,
                    ),
                  ),
                  const Spacer(),
                  if (_dslController.text.trim().isNotEmpty ||
                      _descController.text.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: _clear,
                      icon: Icon(Icons.delete_outline, size: 14, color: theme.textDim),
                      label: Text(
                        'Clear',
                        style: GoogleFonts.courierPrime(fontSize: 11, color: theme.textDim),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.borderMid),
                ),
                child: TextField(
                  controller: _dslController,
                  style: GoogleFonts.courierPrime(fontSize: 12, color: theme.textLight),
                  maxLines: 8,
                  minLines: 6,
                  decoration: InputDecoration(
                    isCollapsed: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'No machine assigned — this black box will reject '
                        'until a DSL definition is provided.',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: theme.textDim.withOpacity(0.6),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.accent.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.accent.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: theme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The inner machine reads the tape starting at this '
                        'black box\'s read tape position and writes its '
                        'result back to the write tape. Configure tape '
                        'routing separately via the Tapes button.',
                        style: TextStyle(fontSize: 11, color: theme.textMid, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Actions ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel', style: TextStyle(color: theme.textDim)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(backgroundColor: theme.accent),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}