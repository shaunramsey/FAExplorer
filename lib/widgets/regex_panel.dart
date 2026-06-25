// ─────────────────────────────────────────────────────────────────────────────
//  regex_panel.dart
//
//  Floating panel shown when the automata mode is set to RegEx.
//  Lets the user type a simple regex and convert it to a DFA
//  that is displayed on the canvas.
//
//  Supported syntax:
//    *  = Kleene star (zero or more of the preceding atom)
//    +  = union / alternation (either side), equivalent to | in standard regex
//    () = grouping
//    All other characters are literals (single characters).
//
//  Examples:
//    (0 + 1(01*0)*1)*   — strings whose binary value is divisible by 3
//    a*b*               — any number of a followed by any number of b
//    (a + b)*abb        — strings ending in "abb" over {a,b}
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../regex_engine.dart';
import '../models.dart';
import '../widgets/app_theme.dart';

// ─── Public callback type ────────────────────────────────────────────────────

typedef RegexConvertCallback = void Function(RegexConversionResult result, bool isDfa);

// ─── Panel widget ─────────────────────────────────────────────────────────────

class RegexPanel extends StatefulWidget {
  /// Called when the user clicks "Convert to DFA".
  /// The parent screen is responsible for loading the resulting graph.
  final RegexConvertCallback onConvert;

  /// Called when the user closes the panel.
  final VoidCallback onClose;

  /// Optional text to pre-fill the expression field with (e.g. when the panel
  /// is opened from the NFA/DFA → Regex dialog).
  final String? initialText;

  /// Called once after [initialText] has been copied into the text field so
  /// the parent can clear it and avoid re-seeding on rebuilds.
  final VoidCallback? onInitialTextConsumed;

  const RegexPanel({
    super.key,
    required this.onConvert,
    required this.onClose,
    this.initialText,
    this.onInitialTextConsumed,
  });

  @override
  State<RegexPanel> createState() => _RegexPanelState();
}

class _RegexPanelState extends State<RegexPanel> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _ctrl.text = widget.initialText!;
      // Notify the parent that the seed has been consumed so it doesn't
      // re-apply it on the next rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onInitialTextConsumed?.call();
      });
    }
  }

  /// Picks up a new [initialText] when the panel is already mounted — this
  /// happens when the user loads a derived regex from the FA→Regex dialog
  /// while the Regex Panel is already visible.
  @override
  void didUpdateWidget(RegexPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.initialText;
    if (incoming != null &&
        incoming.isNotEmpty &&
        incoming != oldWidget.initialText) {
      setState(() {
        _ctrl.text = incoming;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onInitialTextConsumed?.call();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _convert() {
    // Use the raw text — the parser skips all whitespace internally,
    // so spaces around operators (e.g. "0 + 1") are handled correctly.
    final pattern = _ctrl.text;
    if (pattern.trim().isEmpty) {
      setState(() => _error = 'Please enter a regular expression.');
      return;
    }

    final result = regexToDfa(pattern);

    if (result.isError) {
      setState(() => _error = result.error);
      return;
    }

    setState(() => _error = null);
    widget.onConvert(result, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, bottom: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            color: theme.surface,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.borderMid),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Row(
                    children: [
                      Icon(Icons.text_fields, color: theme.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Regular Expression',
                        style: GoogleFonts.courierPrime(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: theme.textLight,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: theme.textMid, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Syntax reminder ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.borderMid),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Syntax',
                          style: GoogleFonts.courierPrime(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.textDim,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _SyntaxRow(symbol: '*', desc: 'zero or more (Kleene star)', theme: theme),
                        _SyntaxRow(symbol: '+', desc: 'or / union (alternation)', theme: theme),
                        _SyntaxRow(symbol: '()', desc: 'grouping', theme: theme),
                        _SyntaxRow(symbol: 'a–z, 0–9, …', desc: 'literal character', theme: theme),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Regex input ────────────────────────────────────────
                  Text(
                    'Expression',
                    style: GoogleFonts.courierPrime(
                      fontSize: 12,
                      color: theme.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.bg,
                      border: Border.all(
                        color: _error != null
                            ? const Color(0xFFFF1744)
                            : theme.accent.withOpacity(0.6),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      style: GoogleFonts.courierPrime(
                        fontSize: 18,
                        color: theme.textLight,
                        letterSpacing: 1.2,
                      ),
                      cursorColor: theme.accent,
                      onSubmitted: (_) => _convert(),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: InputBorder.none,
                        hintText: '(0 + 1(01*0)*1)*',
                        hintStyle: GoogleFonts.courierPrime(
                          fontSize: 16,
                          color: theme.textDim,
                        ),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: const Color(0xFFFF1744),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // ── Convert button ─────────────────────────────────────
                  FilledButton.icon(
                    onPressed: _convert,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.transform, size: 18),
                    label: Text(
                      'Convert to DFA',
                      style: GoogleFonts.courierPrime(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ── Examples ───────────────────────────────────────────
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      'Examples',
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: theme.textDim,
                      ),
                    ),
                    iconColor: theme.textDim,
                    collapsedIconColor: theme.textDim,
                    children: [
                      _ExampleTile(
                        pattern: '(0 + 1(01*0)*1)*',
                        desc: 'Divisible by 3 in binary',
                        onTap: () {
                          _ctrl.text = '(0 + 1(01*0)*1)*';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: 'a*b*',
                        desc: "Any a's then b's",
                        onTap: () {
                          _ctrl.text = 'a*b*';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: '(a + b)*abb',
                        desc: 'Strings ending in "abb"',
                        onTap: () {
                          _ctrl.text = '(a + b)*abb';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: '(0 + 1)*1(0 + 1)',
                        desc: 'Second-to-last bit is 1',
                        onTap: () {
                          _ctrl.text = '(0 + 1)*1(0 + 1)';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                      _ExampleTile(
                        pattern: '(0 + 1(001*0(101*0)*0 + 1(101*0)*0)*(001*0(101*0)*11 + 01 + 1(101*0)*11))*',
                        desc: 'Divisible by 5 in binary',
                        onTap: () {
                          _ctrl.text = '(0 + 1(001*0(101*0)*0 + 1(101*0)*0)*(001*0(101*0)*11 + 01 + 1(101*0)*11))*';
                          setState(() => _error = null);
                        },
                        theme: theme,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _SyntaxRow extends StatelessWidget {
  final String symbol;
  final String desc;
  final AppThemeNotifier theme;

  const _SyntaxRow({
    required this.symbol,
    required this.desc,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              symbol,
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.accent,
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                color: theme.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleTile extends StatelessWidget {
  final String pattern;
  final String desc;
  final VoidCallback onTap;
  final AppThemeNotifier theme;

  const _ExampleTile({
    required this.pattern,
    required this.desc,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern,
                    style: GoogleFonts.courierPrime(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.textLight,
                    ),
                  ),
                  Text(
                    desc,
                    style: GoogleFonts.courierPrime(
                      fontSize: 11,
                      color: theme.textDim,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 12, color: theme.textDim),
          ],
        ),
      ),
    );
  }
}