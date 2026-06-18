// ─────────────────────────────────────────────────────────────────────────────
//  fa_to_regex_dialog.dart
//
//  A bottom sheet / dialog that:
//    1. Runs the state-elimination algorithm on the current automaton.
//    2. Displays the resulting regular expression with a copy button.
//    3. Offers a "Load into Regex Panel" shortcut that switches the canvas to
//       Regex mode and pre-fills the panel with the derived expression.
//
//  Import this file and call [showFaToRegexDialog] from the automata screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../fa_to_regex.dart';
import '../widgets/app_theme.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

/// Shows the NFA/DFA → Regex dialog.
///
/// [onLoadIntoRegexPanel] is called with the derived regex string when the
/// user taps "Load into Regex Panel".  The caller should switch to regex mode
/// and pre-fill the regex panel text field with this value.
Future<void> showFaToRegexDialog(
  BuildContext context, {
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? startArrow,
  required void Function(String regex) onLoadIntoRegexPanel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FaToRegexDialog(
      nodes: nodes,
      lines: lines,
      startArrow: startArrow,
      onLoadIntoRegexPanel: onLoadIntoRegexPanel,
    ),
  );
}

// ─── Dialog widget ────────────────────────────────────────────────────────────

class _FaToRegexDialog extends StatefulWidget {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;
  final void Function(String regex) onLoadIntoRegexPanel;

  const _FaToRegexDialog({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.onLoadIntoRegexPanel,
  });

  @override
  State<_FaToRegexDialog> createState() => _FaToRegexDialogState();
}

class _FaToRegexDialogState extends State<_FaToRegexDialog> {
  late final FaToRegexResult _result;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _result = faToRegex(
      nodes: widget.nodes,
      lines: widget.lines,
      startArrow: widget.startArrow,
    );
  }

  Future<void> _copyToClipboard() async {
    if (_result.regex == null) return;
    await Clipboard.setData(ClipboardData(text: _result.regex!));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Dialog(
      backgroundColor: theme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.transform, color: theme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'NFA / DFA  →  Regex',
                    style: GoogleFonts.courierPrime(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: theme.textLight,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.textMid, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Divider(height: 16, color: theme.borderMid),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Info blurb ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF080D14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.borderMid),
                    ),
                    child: Text(
                      'Uses the state-elimination (GNFA) algorithm to derive '
                      'an equivalent regular expression from the current automaton. '
                      'The output uses the same syntax as the Regex Panel '
                      '(* = Kleene star,  + = union,  ~ = ε).',
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: theme.textMid,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_result.isError) ...[
                    // ── Error banner ─────────────────────────────────────
                    _ErrorBanner(message: _result.error!),
                  ] else ...[
                    // ── Result box ────────────────────────────────────────
                    Text(
                      'Derived regular expression',
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: theme.textDim,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.accent.withOpacity(0.5),
                          width: 1.5,
                        ),
                      ),
                      child: SelectableText(
                        _result.regex!,
                        style: GoogleFonts.courierPrime(
                          fontSize: 17,
                          color: theme.textLight,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Copy button ──────────────────────────────────────
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copyToClipboard,
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                _copied ? const Color(0xFF1FD99A) : theme.textMid,
                            side: BorderSide(
                              color: _copied
                                  ? const Color(0xFF1FD99A)
                                  : theme.borderMid,
                            ),
                          ),
                          icon: Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 16,
                          ),
                          label: Text(
                            _copied ? 'Copied!' : 'Copy',
                            style: GoogleFonts.courierPrime(fontSize: 13),
                          ),
                        ),
                        const Spacer(),
                        // ── Load into Regex Panel ────────────────────────
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onLoadIntoRegexPanel(_result.regex!);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.accent,
                            foregroundColor: Colors.black,
                          ),
                          icon: const Icon(Icons.text_fields, size: 16),
                          label: Text(
                            'Load into Regex Panel',
                            style: GoogleFonts.courierPrime(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0005),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF1744), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined,
              color: Color(0xFFFF1744), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.courierPrime(
                fontSize: 13,
                color: const Color(0xFFFF6666),
              ),
            ),
          ),
        ],
      ),
    );
  }
}