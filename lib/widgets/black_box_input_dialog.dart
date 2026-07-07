import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../import_export.dart';
import '../widgets/automata_drawer.dart' show AutomataMode;
import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  BlackBoxEditDialog  (improved)
//
//  Changes vs. the original:
//
//  1. Live DSL validation — as the user types, the dialog attempts to parse
//     the DSL and shows a green ✓ / red ✗ badge next to the "Machine DSL"
//     label, plus a one-line error message when parsing fails.  This catches
//     copy-paste mistakes before the user taps Save.
//
//  2. Automaton type badge — when the DSL is valid the detected type (NFA,
//     PDA, TM) is shown as a small pill, so the user can confirm they pasted
//     the right kind of machine.
//
//  3. Quick-insert bar — a row of small chips for common TM label tokens
//     (∅, ~, R, L, S, ε) inserted at the cursor position.  Saves typing
//     special characters on mobile.
//
//  4. Tap-to-open-tape-routing shortcut — a "Tape routing →" link at the
//     bottom opens the tape dialog inline without closing the current dialog,
//     via the [onOpenTapeRouting] callback supplied by the parent screen.
//
//  5. Cleaner layout — description and DSL fields are visually separated with
//     a divider rather than just spacing, making the two purposes unambiguous.
//
//  The public API is backward-compatible: the existing [show] helper still
//  works unchanged.  The [onOpenTapeRouting] callback is optional; when omitted
//  the tape-routing shortcut is simply not shown.
// ─────────────────────────────────────────────────────────────────────────────

class BlackBoxEditDialog extends StatefulWidget {
  const BlackBoxEditDialog({
    super.key,
    required this.node,
    this.onOpenTapeRouting,
  });

  final NodeData node;

  /// Optional callback invoked when the user taps the "Tape routing →" link.
  /// The parent screen can use this to open [BlackBoxTapeEditDialog] and then
  /// call [setState] to reflect any changes without closing this dialog.
  final VoidCallback? onOpenTapeRouting;

  /// Convenience helper — backward-compatible with the original signature.
  static Future<bool?> show(
    BuildContext context, {
    required NodeData node,
    VoidCallback? onOpenTapeRouting,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => BlackBoxEditDialog(
        node: node,
        onOpenTapeRouting: onOpenTapeRouting,
      ),
    );
  }

  @override
  State<BlackBoxEditDialog> createState() => _BlackBoxEditDialogState();
}

// ── Validation result ─────────────────────────────────────────────────────────

enum _DslStatus { empty, valid, invalid }

class _DslValidation {
  const _DslValidation(this.status, {this.type, this.error});

  final _DslStatus status;
  final String? type;   // e.g. 'NFA', 'PDA', 'TM'
  final String? error;
}

_DslValidation _validate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const _DslValidation(_DslStatus.empty);
  try {
    final graph = DslCodec.importFromDsl(trimmed);
    // Map the detected mode to a human-readable label.
    const modeLabel = {
      AutomataMode.ndfa: 'NFA / DFA',
      AutomataMode.pda:  'PDA',
      AutomataMode.tm:   'TM',
    };
    final typeLabel = modeLabel[graph.automataMode] ?? graph.automataMode.name.toUpperCase();
    return _DslValidation(_DslStatus.valid, type: typeLabel);
  } catch (e) {
    // Surface only the most useful part of a parse error.
    final msg = e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
    return _DslValidation(_DslStatus.invalid, error: msg.length > 120 ? '${msg.substring(0, 120)}…' : msg);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BlackBoxEditDialogState extends State<BlackBoxEditDialog> {
  late final TextEditingController _dslController;
  late final TextEditingController _descController;
  late final TextEditingController _tapesController;
  late _DslValidation _validation;

  // Focus node for the DSL field, so we can insert text at the cursor.
  final FocusNode _dslFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _dslController = TextEditingController(text: widget.node.blackBoxDsl);
    _descController = TextEditingController(text: widget.node.blackBoxDescription);
    _tapesController = TextEditingController(
      text: widget.node.blackBoxActiveTapes.join(','),
    );
    _validation = _validate(_dslController.text);
    _dslController.addListener(_onDslChanged);
  }

  @override
  void dispose() {
    _dslController.removeListener(_onDslChanged);
    _dslController.dispose();
    _descController.dispose();
    _tapesController.dispose();
    _dslFocus.dispose();
    super.dispose();
  }

  void _onDslChanged() {
    final v = _validate(_dslController.text);
    if (v.status != _validation.status ||
        v.type != _validation.type ||
        v.error != _validation.error) {
      setState(() => _validation = v);
    }
  }

  void _save() {
    widget.node.blackBoxDsl = _dslController.text.trim();
    widget.node.blackBoxDescription = _descController.text.trim();
    widget.node.blackBoxActiveTapes = _parseActiveTapes(_tapesController.text);
    Navigator.of(context).pop(true);
  }

  void _clear() {
    setState(() {
      _dslController.clear();
      _descController.clear();
      _tapesController.clear();
    });
  }

  /// Parses the comma-separated "Active tapes" field (e.g. `3` or `2,3`)
  /// into a list of 1-based tape indices, dropping anything malformed.
  /// A blank field yields an empty list, which preserves the default
  /// positional triple → tape mapping (see [NodeData.blackBoxActiveTapes]).
  static List<int> _parseActiveTapes(String raw) {
    if (raw.trim().isEmpty) return <int>[];
    return raw
        .split(',')
        .map((t) => int.tryParse(t.trim()))
        .whereType<int>()
        .where((t) => t >= 1)
        .toList();
  }

  /// Insert [text] at the current cursor position in the DSL field.
  void _insertToken(String text) {
    _dslFocus.requestFocus();
    final ctrl = _dslController;
    final sel = ctrl.selection;
    final current = ctrl.text;
    final start = sel.start < 0 ? current.length : sel.start;
    final end = sel.end < 0 ? current.length : sel.end;
    final newText = current.replaceRange(start, end, text);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ────────────────────────────────────────────────
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
                  // Tape routing shortcut
                  if (widget.onOpenTapeRouting != null)
                    TextButton.icon(
                      onPressed: widget.onOpenTapeRouting,
                      icon: Icon(Icons.settings_input_component,
                          size: 13, color: theme.textDim),
                      label: Text(
                        'Tape routing',
                        style: GoogleFonts.courierPrime(
                            fontSize: 11, color: theme.textDim),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Edit the inner machine $nodeName runs against the tape it '
                'reads and writes.',
                style: TextStyle(fontSize: 12, color: theme.textMid, height: 1.4),
              ),

              const SizedBox(height: 16),

              // ── Description ──────────────────────────────────────────
              _FieldLabel(text: 'Description', theme: theme),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
                maxLines: 2,
                minLines: 1,
                decoration: _inputDecoration(
                  theme: theme,
                  hint: 'e.g. "Increments a binary number by 1"',
                ),
              ),

              const SizedBox(height: 12),

              // ── Active tapes ─────────────────────────────────────────
              _FieldLabel(text: 'Active tapes (optional)', theme: theme),
              const SizedBox(height: 6),
              TextField(
                controller: _tapesController,
                style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
                decoration: _inputDecoration(
                  theme: theme,
                  hint: 'e.g. 3  or  2,3 — leave blank for default',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Which tapes the outgoing-line RWD triples address, in order. '
                'Leave blank for the default (triple 1 → tape 1, triple 2 → '
                'tape 2, …); tapes not listed are left untouched.',
                style: TextStyle(fontSize: 11, color: theme.textDim, height: 1.3),
              ),

              const SizedBox(height: 14),
              Divider(height: 1, color: theme.borderMid),
              const SizedBox(height: 14),

              // ── DSL field header ─────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _FieldLabel(text: 'Machine DSL', theme: theme),
                  const SizedBox(width: 8),
                  _ValidationBadge(validation: _validation, theme: theme),
                  const Spacer(),
                  if (_dslController.text.trim().isNotEmpty ||
                      _descController.text.trim().isNotEmpty ||
                      _tapesController.text.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: _clear,
                      icon: Icon(Icons.delete_outline, size: 13, color: theme.textDim),
                      label: Text(
                        'Clear',
                        style: GoogleFonts.courierPrime(
                            fontSize: 11, color: theme.textDim),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                ],
              ),

              // Validation error message
              if (_validation.status == _DslStatus.invalid &&
                  _validation.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _validation.error!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFF5252),
                    height: 1.3,
                  ),
                ),
              ],

              const SizedBox(height: 6),

              // DSL text area
              Container(
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _validation.status == _DslStatus.invalid
                        ? const Color(0xFFFF5252).withValues(alpha: 0.6)
                        : _validation.status == _DslStatus.valid
                            ? theme.accentGreen.withValues(alpha: 0.4)
                            : theme.borderMid,
                  ),
                ),
                child: TextField(
                  controller: _dslController,
                  focusNode: _dslFocus,
                  style: GoogleFonts.courierPrime(
                      fontSize: 12, color: theme.textLight),
                  maxLines: 8,
                  minLines: 6,
                  decoration: InputDecoration(
                    isCollapsed: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText:
                        'No machine assigned — paste a DSL definition exported\n'
                        'from another graph, or write one directly.',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: theme.textDim.withValues(alpha: 0.6),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Quick-insert bar ─────────────────────────────────────
              _QuickInsertBar(onInsert: _insertToken, theme: theme),

              const SizedBox(height: 10),

              // ── Info box ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: theme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tape routing is encoded in the outgoing line labels '
                        'as RWD triples per tape — e.g. aXRa1R means '
                        '"tape 1: read a, write X, Right; tape 2: read a, '
                        'write 1, Right". With "Active tapes" set (e.g. 3), a '
                        'label of just 10R addresses tape 3 alone — no '
                        'padding for the other tapes needed. No separate '
                        'tape-routing dialog needed.',
                        style: TextStyle(
                            fontSize: 11, color: theme.textMid, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Actions ──────────────────────────────────────────────
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
                    // Disable Save when the DSL is non-empty but invalid.
                    onPressed: _validation.status == _DslStatus.invalid
                        ? null
                        : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      disabledBackgroundColor:
                          theme.accent.withValues(alpha: 0.35),
                    ),
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

  InputDecoration _inputDecoration({
    required AppThemeNotifier theme,
    required String hint,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(color: theme.textDim.withValues(alpha: 0.6)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ValidationBadge — green ✓ / red ✗ / grey (empty) chip
// ─────────────────────────────────────────────────────────────────────────────

class _ValidationBadge extends StatelessWidget {
  const _ValidationBadge({required this.validation, required this.theme});

  final _DslValidation validation;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    switch (validation.status) {
      case _DslStatus.empty:
        return const SizedBox.shrink();
      case _DslStatus.valid:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 13, color: Color(0xFF1FD99A)),
            const SizedBox(width: 4),
            if (validation.type != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF1FD99A).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: const Color(0xFF1FD99A).withValues(alpha: 0.4)),
                ),
                child: Text(
                  validation.type!,
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1FD99A),
                  ),
                ),
              ),
          ],
        );
      case _DslStatus.invalid:
        return const Icon(Icons.error_outline,
            size: 13, color: Color(0xFFFF5252));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _QuickInsertBar — one-tap insertion of common TM symbols
// ─────────────────────────────────────────────────────────────────────────────

class _QuickInsertBar extends StatelessWidget {
  const _QuickInsertBar({
    required this.onInsert,
    required this.theme,
  });

  final ValueChanged<String> onInsert;
  final AppThemeNotifier theme;

  static const _tokens = [
    ('∅', 'blank'),
    ('~',  'ε-jump'),
    ('R',  'right'),
    ('L',  'left'),
    ('S',  'stay'),
    ('ε',  'epsilon'),
    ('1:', 'tape 1'),
    ('2:', 'tape 2'),
    ('b1', 'cross-write'),
    ('b2', 'parallel'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        Text(
          'Insert:',
          style: GoogleFonts.courierPrime(
              fontSize: 10, color: theme.textDim),
        ),
        for (final (token, label) in _tokens)
          Tooltip(
            message: label,
            child: GestureDetector(
              onTap: () => onInsert(token),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: theme.borderMid),
                ),
                child: Text(
                  token,
                  style: GoogleFonts.courierPrime(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.textLight,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small helpers
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, required this.theme});

  final String text;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.courierPrime(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: theme.textDim,
      ),
    );
  }
}