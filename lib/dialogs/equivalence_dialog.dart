// A dialog that lets the user paste or type two DSL strings and checks whether
// the two finite automata they describe accept exactly the same language.
//
// Usage (from AutomataScreen or anywhere you have a BuildContext):
//
//   await showEquivalenceDialog(
//     context,
//     initialDsl: DslCodec.exportToDsl(_graphState), // pre-fill slot A
//   );

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../dsl_code.dart';
import '../fa_equivalence.dart';
import '../widgets/automata_drawer.dart' show AutomataMode;

Future<void> showEquivalenceDialog(
  BuildContext context, {
  String? initialDsl,
}) {
  return showDialog(
    context: context,
    builder: (_) => _EquivalenceDialog(initialDsl: initialDsl),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _EquivalenceDialog extends StatefulWidget {
  final String? initialDsl;
  const _EquivalenceDialog({this.initialDsl});

  @override
  State<_EquivalenceDialog> createState() => _EquivalenceDialogState();
}

class _EquivalenceDialogState extends State<_EquivalenceDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _ctrlA;
  late final TextEditingController _ctrlB;
  late final TabController _tabController;

  EquivalenceResult? _result;
  String? _errorA;
  String? _errorB;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _ctrlA = TextEditingController(text: widget.initialDsl ?? '');
    _ctrlB = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _ctrlA.dispose();
    _ctrlB.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Check ─────────────────────────────────────────────────────────────────

  void _check() {
    setState(() {
      _errorA = null;
      _errorB = null;
      _result = null;
      _checking = true;
    });

    // Parse both DSLs.
    GraphState? g1, g2;
    try {
      g1 = DslCodec.importFromDsl(_ctrlA.text);
    } catch (e) {
      setState(() {
        _errorA = 'Parse error: $e';
        _checking = false;
      });
      return;
    }
    try {
      g2 = DslCodec.importFromDsl(_ctrlB.text);
    } catch (e) {
      setState(() {
        _errorB = 'Parse error: $e';
        _checking = false;
      });
      return;
    }

    // Only NFA mode is decidable with this algorithm.
    if (g1.automataMode != AutomataMode.ndfa) {
      setState(() {
        _errorA = 'Automaton A is in ${g1!.automataMode.name.toUpperCase()} mode. '
            'Equivalence checking is only supported for NFA/DFA (ndfa mode).';
        _checking = false;
      });
      return;
    }
    if (g2.automataMode != AutomataMode.ndfa) {
      setState(() {
        _errorB = 'Automaton B is in ${g2!.automataMode.name.toUpperCase()} mode. '
            'Equivalence checking is only supported for NFA/DFA (ndfa mode).';
        _checking = false;
      });
      return;
    }

    final result = checkEquivalence(
      nodes1: g1.nodes,
      lines1: g1.lines,
      startArrow1: g1.startArrow,
      nodes2: g2.nodes,
      lines2: g2.lines,
      startArrow2: g2.startArrow,
    );

    setState(() {
      _result = result;
      _checking = false;
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Widget _dslEditor(
    TextEditingController ctrl,
    String label,
    String? error,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(
              color: error != null ? Colors.red : Colors.grey.shade400,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: 14,
            style: GoogleFonts.courierPrime(fontSize: 13),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(10),
              border: InputBorder.none,
              hintText: 'Paste DSL here…',
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _resultBanner() {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final r = _result;
    if (r == null) return const SizedBox.shrink();

    switch (r.status) {
      case EquivalenceStatus.equivalent:
        return _Banner(
          color: Colors.green.shade50,
          borderColor: Colors.green.shade600,
          icon: Icons.check_circle_outline,
          iconColor: Colors.green.shade700,
          title: 'Equivalent',
          body: 'Both automata accept exactly the same language.',
        );

      case EquivalenceStatus.notEquivalent:
        final w = r.witness!;
        final wDisplay = w.isEmpty ? 'ε (the empty string)' : '"$w"';
        final other = r.acceptedByMachine == 1 ? 'B' : 'A';
        final accepted = r.acceptedByMachine == 1 ? 'A' : 'B';
        return _Banner(
          color: Colors.orange.shade50,
          borderColor: Colors.orange.shade600,
          icon: Icons.highlight_off,
          iconColor: Colors.orange.shade800,
          title: 'Not Equivalent',
          body: 'Distinguishing witness: $wDisplay\n'
              'Automaton $accepted accepts this string, automaton $other does not.',
        );

      case EquivalenceStatus.unknownCapReached:
        return _Banner(
          color: Colors.blue.shade50,
          borderColor: Colors.blue.shade400,
          icon: Icons.help_outline,
          iconColor: Colors.blue.shade700,
          title: 'Unknown (state cap reached)',
          body: 'The state-space exceeded the search limit (8 000 product states). '
              'No distinguishing string was found within this bound, but equivalence '
              'could not be proven. Try simplifying the automata.',
        );

      case EquivalenceStatus.noStartState:
        return _Banner(
          color: Colors.red.shade50,
          borderColor: Colors.red.shade400,
          icon: Icons.warning_amber_outlined,
          iconColor: Colors.red.shade700,
          title: 'Missing start state',
          body: 'One or both automata have no start state defined. '
              'Add a start arrow (▶) and try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.compare_arrows),
                  const SizedBox(width: 8),
                  Text(
                    'Compare Automata',
                    style: GoogleFonts.courierPrime(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Instruction blurb
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Paste the DSL for two finite automata (NFA/DFA only). '
                        'The checker will determine whether they accept the same language '
                        'and, if not, show you a short string that one accepts and the other rejects.',
                        style: GoogleFonts.courierPrime(fontSize: 12, color: Colors.black87),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Two-column layout on wide screens, stacked on narrow ──
                    LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth > 500;
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _dslEditor(_ctrlA, 'Automaton A', _errorA),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _dslEditor(_ctrlB, 'Automaton B', _errorB),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _dslEditor(_ctrlA, 'Automaton A', _errorA),
                          const SizedBox(height: 16),
                          _dslEditor(_ctrlB, 'Automaton B', _errorB),
                        ],
                      );
                    }),

                    const SizedBox(height: 20),

                    // ── Result ───────────────────────────────────────────────
                    _resultBanner(),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // ── Actions ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _checking ? null : _check,
                    icon: const Icon(Icons.compare),
                    label: const Text('Check equivalence'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small reusable banner widget
// ─────────────────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _Banner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.courierPrime(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.courierPrime(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}