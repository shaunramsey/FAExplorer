import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'automata_drawer.dart' show AutomataMode;

// ─────────────────────────────────────────────────────────────────────────────
//  help_overlay.dart
//
//  A small floating "cheat sheet" panel overlaid in the corner of the canvas
//  screen. Always shows the core mouse/gesture controls and the symbol
//  token shortcuts; conditionally appends a PDA or TM syntax section
//  depending on which editor mode is currently active, so users editing a
//  DFA/NFA/regex aren't shown irrelevant PDA/TM notation.
// ─────────────────────────────────────────────────────────────────────────────

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
  ///
  /// Nullable: some call sites (e.g. a context where the overlay is shown
  /// generically, without a specific automaton editor behind it) may not
  /// have a mode to pass, in which case neither the PDA nor TM section
  /// renders and only the always-shown core content is displayed.
  final AutomataMode? automataMode;

  /// Called when the user taps the close button. If null, no close button
  /// is shown.
  ///
  /// Making this nullable (rather than always showing a close button) lets
  /// a caller embed this overlay in a context where dismissal is handled
  /// some other way (e.g. tapping outside it), without an extra unused
  /// close icon cluttering the header.
  final VoidCallback? onClose;

  @override
  State<HelpOverlay> createState() => _HelpOverlayState();
}

class _HelpOverlayState extends State<HelpOverlay> {
  // Owned explicitly (rather than relying on the ambient
  // PrimaryScrollController) so the Scrollbar always has a ScrollPosition
  // to attach to — sharing/omitting a controller here is what causes the
  // "ScrollController not attached to any scroll views" exception.
  //
  // (Concretely: PrimaryScrollController is inherited from ancestors like
  // Scaffold, and if some ancestor further up already attached a *different*
  // scrollable to it, a Scrollbar here relying on the same inherited
  // controller would either attach to the wrong scroll view or find no
  // ScrollPosition of its own — hence the explicit, locally-owned controller
  // passed to *both* the Scrollbar and the SingleChildScrollView below.)
  final _scrollController = ScrollController();

  @override
  void dispose() {
    // Standard Flutter hygiene: any ScrollController (or other
    // Listenable/ChangeNotifier-based controller) created in State must be
    // disposed in State.dispose(), or it leaks its internal listeners /
    // resources for the lifetime of whatever's left holding a reference to
    // it (in a StatefulWidget's case, effectively forever once the widget
    // is removed from the tree, until the object itself gets GC'd — a slow,
    // hard-to-notice leak class in Flutter apps that create/destroy this
    // overlay repeatedly).
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final automataMode = widget.automataMode;
    final onClose = widget.onClose;
    // context.watch here means the whole overlay rebuilds if the app theme
    // changes at runtime (e.g. user toggles light/dark while this overlay
    // happens to be open) — desired, since every color reference below
    // comes from `theme`.
    final theme = context.watch<AppThemeNotifier>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Cap the panel to 60% of screen height, but never let it be so short
    // it's useless (floor 220) nor so tall it dominates a huge screen
    // (ceiling 460). On a very short screen (e.g. a landscape phone with
    // height < 367px), 60% would compute below 220 and the clamp forces it
    // back up to 220 — meaning on a sufficiently short screen this panel
    // could still overflow the visible viewport despite the "cap to a
    // fraction of screen height" intent. In practice the panel is wrapped
    // in a Positioned + Material with a Flexible/SingleChildScrollView
    // inside, so content would still scroll rather than visually overflow
    // — this is a minor edge case, not a crash risk.
    final maxHeight = (screenHeight * 0.6).clamp(220.0, 460.0);

    return Positioned(
      // Pins the panel to a fixed 12px inset from the top-right corner of
      // whatever Stack this is placed inside. Requires an ancestor Stack —
      // this widget will throw if used outside one (not guarded here; that
      // responsibility is left to callers, who presumably always render
      // this inside the canvas screen's Stack).
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
            // mainAxisSize.min lets the Column shrink to fit its content's
            // natural height (header + divider + scrollable body) rather
            // than expanding to fill maxHeight even when the content is
            // shorter than that — so a short DFA-only help panel (no
            // PDA/TM section) doesn't leave a big empty gap at the bottom.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row: title + optional close button ──────────────
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
                    // Close button only rendered when a callback was
                    // actually provided — see the field doc on
                    // widget.onClose above.
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
              // Flexible (not Expanded) around the scrollable body: since
              // the outer Column is mainAxisSize.min, Flexible lets the
              // scroll area take up only as much space as it needs up to
              // the Container's maxHeight constraint, rather than forcing
              // it to fill all remaining space the way Expanded would (which
              // would conflict with the Column trying to shrink-wrap).
              Flexible(
                child: Scrollbar(
                  controller: _scrollController,
                  // Always-visible scrollbar thumb (rather than only
                  // appearing during an active scroll gesture) — makes it
                  // obvious at a glance that there's more content below the
                  // fold in a small fixed-width panel like this.
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    // Same controller instance passed to both the Scrollbar
                    // and the scroll view it decorates — this pairing is
                    // exactly what the comment on _scrollController above
                    // is about.
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
                    child: DefaultTextStyle(
                      // Sets a baseline text style inherited by every Text
                      // widget below that doesn't specify its own style —
                      // several of the helper widgets further down (e.g.
                      // _HelpLine) still specify their own full TextStyle
                      // rather than relying on this, so this mainly benefits
                      // any bare Text widgets added here in the future.
                      style: TextStyle(color: theme.textLight, fontSize: 13.5, height: 1.4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Always-shown core canvas controls ──────────
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
                          // Wrap lays the symbol chips out in a flowing
                          // grid that wraps to a new line automatically as
                          // needed, rather than needing a fixed
                          // row/column count — appropriate since the fixed
                          // 290px panel width means the number of chips per
                          // row isn't known ahead of time.
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _SymbolChip('Δ', '[[DELTA_CAP]]', theme),
                              _SymbolChip('δ', '[[DELTA]]', theme),
                              _SymbolChip('ε', '[[EPSILON]]', theme),
                              _SymbolChip('Σ', '[[SIGMA_CAP]]', theme),
                              _SymbolChip('σ', '[[SIGMA]]', theme),
                              // NOTE (cross-file bug, see token_replacements.dart):
                              // this chip advertises `[[LAMBDA]]` as the
                              // shortcut for λ, but the actual lookup table in
                              // token_replacements.dart only defines the key
                              // 'LAMDA' (missing the 'B'). Typing exactly what
                              // this legend says (`[[LAMBDA]]`) will NOT
                              // produce λ — it silently passes through as the
                              // literal text "[[LAMBDA]]". Only the misspelled
                              // `[[LAMDA]]` currently works. Fix in
                              // token_replacements.dart (add/rename the key),
                              // not here — this chip's advertised spelling is
                              // the "correct" one from a user's perspective.
                              _SymbolChip('λ', '[[LAMBDA]]', theme),
                              _SymbolChip('φ', '[[PHI]]', theme),
                              // NOTE: this chip's displayed symbol is the
                              // true Unicode ∅ (U+2205 EMPTY SET) character,
                              // but typing `[[/0]]` does not actually
                              // produce that character. `/0` is parsed by
                              // parseTokenText's *strikethrough* branch (see
                              // token_replacements.dart), which instead
                              // outputs the digit "0" followed by a combining
                              // long-solidus overlay (U+0338) — visually a
                              // slashed zero, which happens to look similar
                              // to ∅ in most fonts but is a different
                              // character/code-point sequence. Not a crash or
                              // functional bug, but the legend's displayed
                              // glyph doesn't exactly match its own
                              // instruction's real output. If pixel-for-
                              // pixel/character-for-character accuracy
                              // matters here (e.g. downstream code ever
                              // compares label text against literal '∅'),
                              // this is worth reconciling — either document
                              // the distinction, or route this chip through
                              // the real `[[\0]]` token instead (see the
                              // `r'\0': '∅'` entry in token_replacements.dart).
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

/// One "gesture -> effect" row, e.g. "Drag node — move it". Renders as a
/// single RichText with the action in bold and " — result" in the normal
/// weight so it reads as one continuous sentence-like line rather than two
/// visually separate labels.
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
          // Base style applied to the whole span (used by the second child
          // TextSpan below, which doesn't override it); the first child
          // TextSpan (the bold `action` text) layers a font-weight override
          // on top of this same base style via TextSpan style-inheritance.
          style: TextStyle(color: theme.textLight, fontSize: 13.5, height: 1.4),
          children: [
            TextSpan(
              text: action,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            // Leading " — " em-dash-style separator baked directly into
            // this span's text rather than a separate SizedBox/spacer
            // widget, since RichText spans are plain text runs, not
            // widgets.
            TextSpan(text: ' — $result'),
          ],
        ),
      ),
    );
  }
}

/// Small bold, accent-colored section heading (e.g. "Symbol shortcuts",
/// "PDA transitions").
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

/// A single pill-shaped chip pairing a rendered symbol (e.g. 'δ') with the
/// typed token that produces it (e.g. '[[DELTA]]'), used in the "Symbol
/// shortcuts" Wrap above. Purely presentational — does not itself validate
/// that `token` actually round-trips through parseTokenText() to `symbol`
/// (see the ∅/[[/0]] and λ/[[LAMBDA]] notes above, both of which are cases
/// where that assumption doesn't quite hold).
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
              // Referenced by family name string rather than via
              // GoogleFonts.courierPrime() (as other files in this app do)
              // — implies 'CourierPrime' is registered as a local font
              // asset (pubspec fonts: entry) rather than fetched via
              // google_fonts here. Both approaches render the same
              // typeface; just a different plumbing mechanism from the
              // GoogleFonts.* calls seen elsewhere in this codebase (e.g.
              // batch_simulator_dialog.dart).
              fontFamily: 'CourierPrime',
            ),
          ),
        ],
      ),
    );
  }
}

/// A single line of monospace "code" text (e.g. `read,pop|push`), used for
/// PDA/TM syntax examples.
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

/// A small, dim, optionally-italic annotation line placed under a
/// _CodeLine or _SymbolChip group to explain it further.
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