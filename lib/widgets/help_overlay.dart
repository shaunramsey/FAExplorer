import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'automata_drawer.dart' show AutomataMode;

/// Compact, scrollable help panel.
///
/// Shows the core canvas controls and symbol shortcuts always; PDA and TM
/// syntax notes only appear when [automataMode] is the relevant mode, so the
/// common case (DFA/NFA/regex) stays short. Content is capped to a fraction
/// of the screen height and scrolls internally past that.
class HelpOverlay extends StatefulWidget {
  const HelpOverlay({
    super.key,
    this.automataMode,
    this.onClose,
  });

  /// Current editor mode. When provided, mode-specific sections (PDA/TM
  /// syntax) only render for the matching mode.
  final AutomataMode? automataMode;

  /// Called when the user taps the close button. If null, no close button
  /// is shown.
  final VoidCallback? onClose;

  @override
  State<HelpOverlay> createState() => _HelpOverlayState();
}

class _HelpOverlayState extends State<HelpOverlay> {
  // Owned explicitly (rather than relying on the ambient
  // PrimaryScrollController) so the Scrollbar always has a ScrollPosition
  // to attach to — sharing/omitting a controller here is what causes the
  // "ScrollController not attached to any scroll views" exception.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final automataMode = widget.automataMode;
    final onClose = widget.onClose;
    final theme = context.watch<AppThemeNotifier>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = (screenHeight * 0.6).clamp(220.0, 460.0);

    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        color: theme.surface,
        child: Container(
          width: 290,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.borderMid, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quick Help',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.accent,
                        ),
                      ),
                    ),
                    if (onClose != null)
                      InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 18, color: theme.textMid),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
                    child: DefaultTextStyle(
                      style: TextStyle(color: theme.textLight, fontSize: 13.5, height: 1.4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HelpLine('Double click empty space', 'create node', theme: theme),
                          _HelpLine('Drag node', 'move it', theme: theme),
                          _HelpLine('Double click node', 'toggle accept', theme: theme),
                          _HelpLine('Shift / link button', 'line mode', theme: theme),
                          _HelpLine('Drag a line', 'curve it', theme: theme),
                          _HelpLine('Delete button', 'delete mode', theme: theme),
                          _HelpLine('Long press canvas', 'reset graph', theme: theme),

                          const SizedBox(height: 12),
                          _SectionLabel('Symbol shortcuts', theme: theme),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _SymbolChip('Δ', '[[DELTA_CAP]]', theme),
                              _SymbolChip('δ', '[[DELTA]]', theme),
                              _SymbolChip('ε', '[[EPSILON]]', theme),
                              _SymbolChip('Σ', '[[SIGMA_CAP]]', theme),
                              _SymbolChip('σ', '[[SIGMA]]', theme),
                              _SymbolChip('λ', '[[LAMBDA]]', theme),
                              _SymbolChip('φ', '[[PHI]]', theme),
                              _SymbolChip('∅', '[[/0]]', theme),
                              _SymbolChip('∞', '[[INFINITY]]', theme),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _NoteLine(
                            '[[/text]] strikes each letter, e.g. [[/abc]] → '
                            'a\u0338b\u0338c\u0338',
                            theme: theme,
                          ),

                          // Only shown while working in PDA mode.
                          if (automataMode == AutomataMode.pda) ...[
                            const SizedBox(height: 14),
                            _SectionLabel('PDA transitions', theme: theme),
                            const SizedBox(height: 6),
                            _CodeLine('read,pop|push', theme: theme),
                            _NoteLine(
                              '~ or blank = none/tilda · push multiple '
                              'space-separated, left-most ends on top',
                              theme: theme,
                            ),
                            const SizedBox(height: 8),
                            _CodeLine('a,y|x\nb,x|y', theme: theme),
                            _NoteLine(
                              'on a — pop y, push x · on b — pop x, push y '
                              '(each line is its own independent rule)',
                              theme: theme,
                            ),
                          ],

                          // Only shown while working in TM mode.
                          if (automataMode == AutomataMode.tm) ...[
                            const SizedBox(height: 14),
                            _SectionLabel('Multi-tape syntax (conjunctive)', theme: theme),
                            const SizedBox(height: 6),
                            _CodeLine('1:aXR,b1,3:01S', theme: theme),
                            _NoteLine(
                              'b1 → tape 1 fires, tape 3 writes along with it',
                              theme: theme,
                            ),
                            const SizedBox(height: 8),
                            _CodeLine('1:aXR,b2,2:01S', theme: theme),
                            _NoteLine(
                              'b2 → both tapes must match to fire (parallel step)',
                              theme: theme,
                            ),
                            const SizedBox(height: 4),
                            _NoteLine(
                              'Default: single tape, independent branches per line.',
                              theme: theme,
                              italic: true,
                            ),
                          ],

                          const SizedBox(height: 12),
                          Text(
                            'Tip: symbol codes work directly inside node & line labels.',
                            style: TextStyle(
                              color: theme.textMid,
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpLine extends StatelessWidget {
  const _HelpLine(this.action, this.result, {required this.theme});

  final String action;
  final String result;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: theme.textLight, fontSize: 13.5, height: 1.4),
          children: [
            TextSpan(
              text: action,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: ' — $result'),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});

  final String text;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.2,
        color: theme.accent,
      ),
    );
  }
}

class _SymbolChip extends StatelessWidget {
  const _SymbolChip(this.symbol, this.token, this.theme);

  final String symbol;
  final String token;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: theme.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderMid, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: TextStyle(
              color: theme.accent,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            token,
            style: TextStyle(
              color: theme.textMid,
              fontSize: 10.5,
              fontFamily: 'CourierPrime',
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine(this.text, {required this.theme});

  final String text;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: theme.textLight, fontFamily: 'CourierPrime', fontSize: 13),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine(this.text, {required this.theme, this.italic = false});

  final String text;
  final AppThemeNotifier theme;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: TextStyle(
          color: theme.textDim,
          fontSize: 11.5,
          height: 1.35,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}
