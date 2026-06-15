import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import 'app_theme.dart';

/// Dialog for editing which tape a black-box node reads from and writes to.
///
/// Returns `true` via [showDialog] if the values were changed, so the caller
/// can `setState`/persist as needed. The [node]'s `blackBoxReadTape` and
/// `blackBoxWriteTape` fields are mutated in place on save.
///
/// When [tapeCount] is 1 the steppers are disabled and a hint is shown
/// explaining how to add more tapes via the TM config panel.
class BlackBoxTapeEditDialog extends StatefulWidget {
  final NodeData node;

  /// Total number of tapes available (from [TmSimulator.tapeCount]).
  /// Read/write values are clamped to the range 1..[tapeCount].
  final int tapeCount;

  const BlackBoxTapeEditDialog({
    super.key,
    required this.node,
    this.tapeCount = 1,
  });

  /// Convenience helper: shows the dialog and returns `true` if the user
  /// saved changes.
  static Future<bool?> show(
    BuildContext context, {
    required NodeData node,
    int tapeCount = 1,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => BlackBoxTapeEditDialog(node: node, tapeCount: tapeCount),
    );
  }

  @override
  State<BlackBoxTapeEditDialog> createState() => _BlackBoxTapeEditDialogState();
}

class _BlackBoxTapeEditDialogState extends State<BlackBoxTapeEditDialog> {
  late int _readTape;
  late int _writeTape;

  int get _maxTape => widget.tapeCount < 1 ? 1 : widget.tapeCount;
  bool get _multiTape => _maxTape > 1;

  @override
  void initState() {
    super.initState();
    _readTape  = widget.node.blackBoxReadTape.clamp(1, _maxTape);
    _writeTape = widget.node.blackBoxWriteTape.clamp(1, _maxTape);
  }

  void _save() {
    widget.node.blackBoxReadTape  = _readTape;
    widget.node.blackBoxWriteTape = _writeTape;
    Navigator.of(context).pop(true);
  }

  // ── individual stepper row ────────────────────────────────────────────────

  Widget _tapeStepper({
    required String label,
    required IconData icon,
    required int value,
    required ValueChanged<int> onChanged,
    required AppThemeNotifier theme,
  }) {
    final canDec = _multiTape && value > 1;
    final canInc = _multiTape && value < _maxTape;

    return Row(
      children: [
        // Icon + label
        Icon(icon, size: 16, color: _multiTape ? theme.accent : theme.textDim),
        const SizedBox(width: 6),
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: GoogleFonts.courierPrime(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _multiTape ? theme.textLight : theme.textDim,
            ),
          ),
        ),

        // − button
        _StepBtn(
          icon: Icons.remove,
          enabled: canDec,
          onTap: canDec ? () => setState(() => onChanged(value - 1)) : null,
          theme: theme,
        ),
        const SizedBox(width: 4),

        // value display
        Container(
          width: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: theme.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _multiTape ? theme.accent.withOpacity(0.5) : theme.borderMid,
            ),
          ),
          child: Text(
            '$value',
            style: GoogleFonts.courierPrime(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _multiTape ? theme.accent : theme.textDim,
            ),
          ),
        ),
        const SizedBox(width: 4),

        // + button
        _StepBtn(
          icon: Icons.add,
          enabled: canInc,
          onTap: canInc ? () => setState(() => onChanged(value + 1)) : null,
          theme: theme,
        ),

        // tape label badge
        const SizedBox(width: 8),
        Text(
          'Tape $value',
          style: GoogleFonts.courierPrime(
            fontSize: 11,
            color: _multiTape ? theme.textMid : theme.textDim,
          ),
        ),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

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
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ────────────────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.settings_input_component,
                      size: 18, color: theme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tape Routing',
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
                'Configure which tape $nodeName reads its input from '
                'and which tape it writes its output to.',
                style: TextStyle(
                    fontSize: 12, color: theme.textMid, height: 1.4),
              ),

              const SizedBox(height: 16),

              // ── Tape availability hint ────────────────────────────────────
              if (!_multiTape) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.accent.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: theme.accent.withOpacity(0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: theme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only 1 tape is configured. Use the Tapes '
                          'counter in the TM panel to add more tapes, '
                          'then reassign black boxes here.',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.textMid,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Available tape count badge ─────────────────────────────────
              if (_multiTape) ...[
                Row(
                  children: [
                    Text(
                      'Available tapes: ',
                      style: GoogleFonts.courierPrime(
                          fontSize: 11, color: theme.textDim),
                    ),
                    ...[
                      for (int t = 1; t <= _maxTape; t++)
                        Padding(
                          padding:
                              const EdgeInsets.only(right: 4),
                          child: _TapePill(
                            number: t,
                            isRead: t == _readTape,
                            isWrite: t == _writeTape,
                            theme: theme,
                          ),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // ── Steppers ─────────────────────────────────────────────────
              _tapeStepper(
                label: 'Read',
                icon: Icons.input,
                value: _readTape,
                onChanged: (v) => _readTape = v,
                theme: theme,
              ),
              const SizedBox(height: 10),
              _tapeStepper(
                label: 'Write',
                icon: Icons.output,
                value: _writeTape,
                onChanged: (v) => _writeTape = v,
                theme: theme,
              ),

              const SizedBox(height: 20),

              // ── Actions ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel',
                        style: TextStyle(color: theme.textDim)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: theme.accent),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Small +/− button
// ─────────────────────────────────────────────────────────────────────────────

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.theme,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? theme.surface : theme.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled
                ? theme.borderMid
                : theme.borderMid.withOpacity(0.35),
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: enabled
              ? theme.accent
              : theme.textDim.withOpacity(0.35),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small tape pill showing R / W badges
// ─────────────────────────────────────────────────────────────────────────────

class _TapePill extends StatelessWidget {
  const _TapePill({
    required this.number,
    required this.isRead,
    required this.isWrite,
    required this.theme,
  });

  final int number;
  final bool isRead;
  final bool isWrite;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    final active = isRead || isWrite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? theme.accent.withOpacity(0.12)
            : theme.bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: active
              ? theme.accent.withOpacity(0.5)
              : theme.borderMid,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$number',
            style: GoogleFonts.courierPrime(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: active ? theme.accent : theme.textDim,
            ),
          ),
          if (isRead) ...[
            const SizedBox(width: 3),
            Text('R',
                style: GoogleFonts.courierPrime(
                    fontSize: 9,
                    color: theme.accent,
                    fontWeight: FontWeight.bold)),
          ],
          if (isWrite) ...[
            const SizedBox(width: 3),
            Text('W',
                style: GoogleFonts.courierPrime(
                    fontSize: 9,
                    color: theme.accentGreen,
                    fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }
}