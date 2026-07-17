import 'package:flutter/material.dart';
// Core Material widgets: Drawer, ListView, Container, InkWell, etc.

import 'package:flutter/services.dart';
// Only used for HapticFeedback.selectionClick() — the little tactile
// "tick" fired on toggles, mode switches, and section-expand taps below.

import 'package:google_fonts/google_fonts.dart';
// GoogleFonts.courierPrime() — the monospace font used for every label
// in the drawer, matching the app's "terminal" visual identity.

import 'package:provider/provider.dart';
// Supplies `context.watch<AppThemeNotifier>()`, used in nearly every
// build() method below to read live theme colors/fonts.

import 'app_theme.dart';
// Defines AppThemeNotifier and showAppThemeSettings(), both used later
// in this file (the latter from the "Color Settings" row).

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataMode  — the three simulation modes
// ─────────────────────────────────────────────────────────────────────────────

enum AutomataMode { ndfa, pda, tm, regex }
// Despite the section comment above saying "the three simulation modes",
// there are actually four values here (ndfa/pda/tm/regex) — the comment
// predates `regex` being added and wasn't updated. `regex` is treated
// specially in _ModeRadioGroup below (see its tooltip) as a one-shot
// "convert to NFA/DFA" action rather than a persistent simulation mode
// like the other three.

// ─────────────────────────────────────────────────────────────────────────────
//  Small building blocks shared by the drawer below.
//
//  Visual language: every actionable row gets a tinted "badge" icon so the
//  eye can scan the drawer by colour/shape instead of reading every label,
//  rows are grouped under small-caps section labels instead of one long
//  undifferentiated list cut up by plain dividers, and colours/fonts come
//  from the app's own AppThemeNotifier so the drawer matches the canvas and
//  panels instead of falling back to generic Material defaults.
// ─────────────────────────────────────────────────────────────────────────────

/// Small-caps section header, e.g. "TOOLS", "DANGER ZONE".
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  // Positional (unnamed) constructor param — call sites read as
  // `_SectionLabel('Tools')` rather than `_SectionLabel(label: 'Tools')`,
  // deliberately terse since this widget is used ~8 times below.

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      // Asymmetric padding: more space above (18) than below (6) — visually
      // groups the label with the section content that follows it rather
      // than centering it between the previous section and this one.
      child: Text(
        label.toUpperCase(),
        // Caller passes normal-case text ('Tools', 'Data', ...); the
        // small-caps look is achieved here via .toUpperCase() + letterSpacing,
        // not a real small-caps font feature.
        style: GoogleFonts.courierPrime(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          // Extra letter-spacing is what sells the "section label" look at
          // this small size/weight — without it the bold caps would look
          // cramped rather than like a deliberate heading style.
          color: theme.textDim,
        ),
      ),
    );
  }
}

/// Small tinted rounded-square icon badge used as the leading element of
/// every drawer row, so related actions share a recognisable colour.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge({required this.icon, required this.color});
  // Both params required — there's no sensible default icon/color, so
  // every call site must supply both explicitly.

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      // Fixed 34x34 square — every badge across the drawer is identically
      // sized regardless of which icon it holds, so rows line up evenly.
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        // Low-alpha tint of the badge's own color as its background, not
        // a separate neutral fill — this is what makes each badge read as
        // "this icon, softly colored" rather than "icon on a grey chip".
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: color),
      // Icon rendered at full color/opacity on top of its own 14%-alpha
      // tinted background.
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _HoverTile — icon-badged row with tooltip description on hover/long-press,
//  rounded ink feedback, and an optional colour override for danger items.
// ─────────────────────────────────────────────────────────────────────────────

class _HoverTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  // `subtitle` is never rendered as visible text in this widget — it's
  // only surfaced via the Tooltip's `message` below, i.e. on hover
  // (desktop/web) or long-press (touch). The name "subtitle" is a bit
  // misleading since there's no always-visible subtitle text anywhere.
  final Color? tint;
  // Nullable — falls back to theme.accent below when omitted, so most
  // rows can skip specifying a color and still get a sensible default.
  final Color? titleColor;
  // Separate from `tint`: `tint` colors the icon badge, `titleColor`
  // colors the title text — independently overridable (used together
  // only for the red "Reset Canvas" row, where both need to be theme.error).
  final VoidCallback? onTap;
  // Nullable, though in practice every call site in this file supplies one
  // — a tile with no onTap would just render as an inert row.

  const _HoverTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tint,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final color = tint ?? theme.accent;
    // Resolved once and reused for the icon badge — `tint` itself stays
    // nullable on the widget so callers aren't forced to know theme.accent.
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 400),
      // Shorter than Flutter's default Tooltip wait (~ longer) so the
      // description appears fairly promptly on hover without needing a
      // deliberate hold.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        // Small vertical padding here (2) is separate from — and much
        // smaller than — the InkWell's own internal padding (10) below;
        // this outer padding just adds a hairline gap between adjacent
        // tiles so their ink-splash bounds don't visually touch.
        child: Material(
          color: Colors.transparent,
          // Material wrapper exists purely to host InkWell's ink-splash
          // painting — transparent so it doesn't add its own background
          // on top of whatever container this tile is nested inside.
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            // Matches the Material's borderRadius above so the ink splash
            // is clipped to the same rounded shape as the tap target.
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  _IconBadge(icon: icon, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.courierPrime(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? theme.textLight,
                      ),
                    ),
                  ),
                  // No trailing chevron/icon — unlike a typical ListTile,
                  // this row gives no visual affordance that it's tappable
                  // beyond the ink splash itself; the whole row is the
                  // "instruction", nothing indicates "this leads somewhere".
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _HoverSwitch — switch row with tooltip description, icon reflects state.
// ─────────────────────────────────────────────────────────────────────────────

class _HoverSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  // All required, no nullable/optional fields — unlike _HoverTile, every
  // _HoverSwitch instance must fully specify its state and callback since
  // a switch with no value/onChanged wouldn't make sense.

  const _HoverSwitch({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
          // Tapping *anywhere* in the row (not just the Switch itself)
          // toggles the value — the Switch below has its own separate
          // onChanged too, so both the row-tap and a direct thumb-drag/tap
          // on the Switch achieve the same toggle.
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: value ? theme.accent : theme.textDim),
              // The leading icon itself changes color based on `value` —
              // this is the "icon reflects state" behavior promised in the
              // section-header comment (note: unlike _HoverTile, there's no
              // _IconBadge here — just a bare Icon, no tinted background box).
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.courierPrime(fontSize: 13.5, color: theme.textLight),
                ),
              ),
              Switch(
                value: value,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                  // Duplicates the haptic-then-callback pattern from the
                  // outer InkWell's onTap above — necessary because the
                  // Switch handles its own gestures independently and
                  // isn't otherwise reachable from the row-level onTap.
                },
                activeThumbColor: theme.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _DropdownSection — collapsible boxed group used for the "Docs" and
//  "Settings" sections. Keeps rarely-used rows out of the way by default
//  while still living in the same visual language as the rest of the drawer
//  (tinted icon badge, rounded bordered box, courier heading).
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownSection extends StatefulWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final List<Widget> children;
  // `children` are the rows revealed when expanded — passed in fully
  // built by the caller (see the 'Docs' and 'Settings' usages further
  // down), so this widget doesn't need to know anything about their
  // content, just how to show/hide them.

  const _DropdownSection({
    required this.icon,
    required this.tint,
    required this.title,
    required this.children,
  });

  @override
  State<_DropdownSection> createState() => _DropdownSectionState();
  // Needs to be Stateful (unlike _HoverTile/_HoverSwitch) because it owns
  // its own `_expanded` toggle state internally — the caller doesn't
  // control or observe whether a given section is open.
}

class _DropdownSectionState extends State<_DropdownSection> {
  bool _expanded = false;
  // Starts collapsed — matches the "Collapsed by default" comments at
  // both call sites below (Docs and Settings).

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.borderMid),
      ),
      clipBehavior: Clip.antiAlias,
      // Clips the InkWell's ink splash and the AnimatedCrossFade's content
      // to the container's rounded corners — without this, a splash near
      // an edge or the cross-fade's box would visually poke past the
      // rounded border.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              // Header row itself is the toggle — tapping "Docs" or
              // "Settings" expands/collapses; there's no separate chevron
              // button, just the whole header being tappable (the chevron
              // icon below is purely decorative/indicative, not its own
              // tap target).
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    _IconBadge(icon: widget.icon, color: widget.tint),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: GoogleFonts.courierPrime(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.textLight,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      // 0.5 turns = 180° — flips the chevron from
                      // pointing down to pointing up (visually "down" vs
                      // "up" since it's a `keyboard_arrow_down` glyph
                      // rotated in place, not swapped for a different icon).
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down, size: 20, color: theme.textDim),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            // "Collapsed" state — a zero-height full-width box, not
            // `SizedBox.shrink()`; using full width (rather than 0x0)
            // avoids a horizontal layout jump during the cross-fade since
            // both children then share the same width.
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                ...widget.children,
                // Spread operator — inserts each caller-supplied child
                // widget directly into this Column, rather than nesting
                // them inside another wrapper.
                const SizedBox(height: 4),
                // Small trailing gap so the last child row doesn't sit
                // flush against the container's bottom rounded corner.
              ],
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            // Same 200ms as the chevron's AnimatedRotation above, so the
            // arrow flip and the content reveal/hide are visually in sync.
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ModeRadioGroup  — compact 4-way segmented control for NDFA / PDA / TM / RegEx
// ─────────────────────────────────────────────────────────────────────────────

class _ModeRadioGroup extends StatelessWidget {
  final AutomataMode value;
  final ValueChanged<AutomataMode> onChanged;

  const _ModeRadioGroup({required this.value, required this.onChanged});

  static const _modes = [
    (
      mode: AutomataMode.ndfa,
      label: 'NDFA',
      icon: Icons.hub_outlined,
      tooltip: 'Non-deterministic Finite Automaton',
    ),
    (
      mode: AutomataMode.pda,
      label: 'PDA',
      icon: Icons.layers_outlined,
      tooltip: 'Pushdown Automaton — labels use read,pop|push format',
    ),
    (
      mode: AutomataMode.tm,
      label: 'TM',
      icon: Icons.memory_outlined,
      tooltip: 'Turing Machine — labels use read,write,direction format',
    ),
    (
      mode: AutomataMode.regex,
      label: 'RegEx',
      icon: Icons.functions,
      tooltip: 'Regular Expression — convert a regex to NFA or DFA on the canvas',
      // This tooltip's phrasing ("convert a regex to...") is the tell that
      // `regex` isn't really a persistent simulation mode like the other
      // three — selecting it is expected to trigger a one-shot conversion
      // action rather than switch the canvas into an ongoing "regex mode".
    ),
  ];
  // Dart 3 *named*-record list (each entry has named fields: mode, label,
  // icon, tooltip) — unlike _QuickInsertBar's positional-record tokens in
  // black_box_input_dialog.dart, these are accessed as `entry.mode` etc.
  // below rather than by destructuring.

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: _modes.map((entry) {
          final selected = value == entry.mode;
          return Expanded(
            // Each of the 4 segments gets equal width via Expanded inside
            // the Row — a true segmented control rather than left-aligned
            // chips that only take up as much space as their label needs.
            child: Tooltip(
              message: entry.tooltip,
              waitDuration: const Duration(milliseconds: 400),
              child: GestureDetector(
                // GestureDetector (not InkWell/Material) — no ripple
                // feedback here; the selected/unselected visual state
                // itself (via AnimatedContainer below) is the feedback.
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(entry.mode);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? theme.accent.withValues(alpha: 0.16) : theme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? theme.accent : theme.borderMid,
                      width: selected ? 1.4 : 1,
                      // Selected segment gets a very slightly thicker
                      // border (1.4 vs 1) in addition to the color change
                      // — a subtle extra emphasis beyond just color.
                    ),
                  ),
                  // AnimatedContainer (not a bare Container) — background
                  // color and border smoothly tween over 150ms whenever
                  // `selected` flips, rather than snapping instantly.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.icon,
                        size: 16,
                        color: selected ? theme.accent : theme.textDim,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        // Needed because Expanded gives each segment more
                        // width than its label needs, so the text must be
                        // explicitly centered rather than left-defaulting.
                        style: GoogleFonts.courierPrime(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: selected ? theme.accent : theme.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
        // .map(...).toList() — Row.children needs a concrete List<Widget>,
        // so the lazy Iterable from .map() is materialized here.
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _DrawerHeader — app branding + account row. Replaces the old bare
//  "Signed in / email" ListTile with something that actually identifies the
//  app and gives Guest/Signed-in state a clear visual chip.
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final bool isGuest;
  final String? accountLabel;
  // Nullable — when null, the entire account Row (icon + label + chip)
  // is omitted below, leaving just the app-branding Row. Used for contexts
  // where there's no account concept at all (vs. `isGuest: true`, which
  // still shows a "GUEST" chip alongside a label).

  const _DrawerHeader({required this.isGuest, required this.accountLabel});
  // `accountLabel` is `required` despite being nullable — the caller must
  // explicitly pass `null` rather than getting an implicit default,
  // making the "no account info" case a deliberate choice at the call site.

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.borderMid)),
        // Only a bottom border (not all four sides) — visually separates
        // the header from the scrollable ListView below it, without
        // boxing the header in on its other three edges (which already
        // sit flush against the Drawer's own edges).
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.account_tree_rounded, color: theme.accent, size: 22),
                // A one-off larger version of the _IconBadge pattern
                // (42x42 vs 34x34, plus a visible border which _IconBadge
                // doesn't have) — used only here for the app logo, not
                // reusing the _IconBadge class itself.
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Automata Designer',
                  // App name is hardcoded directly in this widget rather
                  // than passed in as a parameter — this header assumes
                  // there's exactly one app name, never parameterized.
                  style: GoogleFonts.courierPrime(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.textLight,
                  ),
                ),
              ),
            ],
          ),
          if (accountLabel != null) ...[
            // The entire account-info block below is conditionally
            // included in the Column's children via a spread — when
            // accountLabel is null, this whole bracketed list contributes
            // zero widgets, and only the branding Row above renders.
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  isGuest ? Icons.person_outline : Icons.account_circle,
                  // Different icon glyph for guest vs signed-in, on top of
                  // the "GUEST"/"SIGNED IN" chip further along the row —
                  // two separate visual signals for the same boolean.
                  size: 16,
                  color: theme.textDim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    accountLabel!,
                    // Safe `!` here — this whole block only exists inside
                    // the `if (accountLabel != null)` branch above.
                    overflow: TextOverflow.ellipsis,
                    // Truncates a long email/username with "…" rather than
                    // wrapping or overflowing the drawer's fixed width.
                    style: GoogleFonts.courierPrime(fontSize: 12.5, color: theme.textMid),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isGuest ? theme.accentGreen : theme.accent).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    // 20px radius on a ~20px-tall chip effectively makes
                    // this a full pill/stadium shape, not just rounded
                    // corners.
                    border: Border.all(
                      color: (isGuest ? theme.accentGreen : theme.accent).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    isGuest ? 'GUEST' : 'SIGNED IN',
                    style: GoogleFonts.courierPrime(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: isGuest ? theme.accentGreen : theme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataDrawer
// ─────────────────────────────────────────────────────────────────────────────

class AutomataDrawer extends StatelessWidget {
  final bool showHelpOverlay;
  final bool showSimulator;

  /// Current simulation mode (NDFA / PDA / TM).
  final AutomataMode automataMode;
  // Doc comment lists only 3 of the 4 AutomataMode values (omits `regex`,
  // consistent with `regex` being a one-shot action rather than a mode
  // this drawer expects to sit in persistently — see _ModeRadioGroup above).

  final bool isGuest;
  final String? accountLabel;
  final ValueChanged<bool> onShowHelpChanged;
  final ValueChanged<bool> onShowSimulatorChanged;

  /// Called when the user picks a new simulation mode.
  final ValueChanged<AutomataMode> onModeChanged;

  final VoidCallback onBatchSimulator;
  final VoidCallback onEquivalenceChecker;

  /// Called when the user taps "NFA/DFA → Regex" in the drawer.
  /// Optional — callers that haven't wired this up yet simply won't show the
  /// menu item (see [build]).
  final VoidCallback? onFaToRegex;
  // The only nullable/optional callback among the "Tools"/"Data" actions —
  // a soft-rollout mechanism: older screens that embed AutomataDrawer
  // without wiring this up just don't get the row, rather than crashing
  // or showing a dead button.

  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onExportHistory;
  final VoidCallback onReset;
  final Future<void> Function()? onSignOut;
  // Async and nullable — nullable because not every context has a sign-out
  // concept (see the `if (onSignOut != null)` guard around the whole
  // "Account" section in build()); async because signing out presumably
  // involves a network/auth call the drawer awaits before finishing.

  const AutomataDrawer({
    super.key,
    required this.showHelpOverlay,
    required this.showSimulator,
    required this.automataMode,
    this.isGuest = false,
    // Defaults to false — most callers presumably don't need to think
    // about guest status unless they actually have an auth system.
    this.accountLabel,
    required this.onShowHelpChanged,
    required this.onShowSimulatorChanged,
    required this.onModeChanged,
    required this.onBatchSimulator,
    required this.onEquivalenceChecker,
    this.onFaToRegex,
    required this.onExport,
    required this.onImport,
    required this.onExportHistory,
    required this.onReset,
    this.onSignOut,

    // ── Legacy compat: old callers may still pass showPdaMode / onShowPdaModeChanged.
    //    We accept and silently ignore them so existing call-sites compile.
    @Deprecated('Use automataMode / onModeChanged instead') bool showPdaMode = false,
    @Deprecated('Use automataMode / onModeChanged instead') ValueChanged<bool>? onShowPdaModeChanged,
    // Both params are accepted into the constructor but never assigned to
    // any field or referenced anywhere else in this class — they exist
    // purely so old call sites (from before the mode was generalized from
    // a single PDA on/off boolean to the 4-way `automataMode` enum) keep
    // compiling without modification, with the @Deprecated annotation
    // nudging callers to migrate. Since neither has a `this.` prefix, Dart
    // doesn't even wire them to a field — passing them genuinely does
    // nothing.
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Drawer(
      backgroundColor: theme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          // Only the two right-hand corners are rounded — the left edge
          // sits flush against the screen edge (this is a left-side
          // Drawer, opened by swiping/tapping from the left), so rounding
          // the left corners would be invisible/pointless anyway.
        ),
      ),
      child: SafeArea(
        // Keeps drawer content clear of notches/status bars/home
        // indicators on all four edges by default.
        child: Column(
          children: [
            _DrawerHeader(isGuest: isGuest, accountLabel: accountLabel),
            // Fixed, non-scrolling header — sits outside the Expanded
            // ListView below, so it stays pinned while the rest scrolls.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                children: [
                  // ── Display toggles ───────────────────────────────────────
                  const _SectionLabel('Display'),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.borderMid),
                    ),
                    // This bordered/rounded Container wraps a *group* of
                    // related _HoverSwitch rows — the same "boxed group"
                    // visual pattern used for _DropdownSection and the
                    // "Reset Canvas" tile further down, just without the
                    // collapse behavior.
                    child: Column(
                      children: [
                        _HoverSwitch(
                          title: 'Show Help',
                          subtitle: 'Displays controls and textbox commands.',
                          icon: Icons.help_outline,
                          value: showHelpOverlay,
                          onChanged: onShowHelpChanged,
                        ),
                        Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                        // `indent`/`endIndent: 14` keeps the divider from
                        // spanning the container's full width, so it
                        // doesn't touch the rounded corners on either side.
                        _HoverSwitch(
                          title: 'String Simulator',
                          subtitle: 'Show/hide the simulator panel.',
                          icon: Icons.science_outlined,
                          value: showSimulator,
                          onChanged: onShowSimulatorChanged,
                        ),
                      ],
                    ),
                  ),

                  // ── Simulation mode ───────────────────────────────────────
                  const _SectionLabel('Simulation Mode'),
                  _ModeRadioGroup(
                    value: automataMode,
                    onChanged: (mode) {
                      Navigator.pop(context);
                      // Drawer closes *before* the mode actually changes
                      // (onModeChanged is called after pop) — same
                      // close-then-act pattern repeated for every other
                      // action row in this drawer (Tools, Data, Reset, etc.).
                      onModeChanged(mode);
                    },
                  ),

                  // ── Tools ─────────────────────────────────────────────────
                  const _SectionLabel('Tools'),
                  _HoverTile(
                    icon: Icons.science_outlined,
                    tint: theme.accent,
                    title: 'Batch Simulator',
                    subtitle: 'Test multiple strings at once.',
                    onTap: () {
                      Navigator.pop(context);
                      onBatchSimulator();
                    },
                  ),
                  _HoverTile(
                    icon: Icons.compare_arrows,
                    tint: theme.accent,
                    title: 'Equivalence Checker',
                    subtitle:
                        'Compare two automata and determine whether they accept the same language.',
                    onTap: () {
                      Navigator.pop(context);
                      onEquivalenceChecker();
                    },
                  ),
                  if (onFaToRegex != null)
                    // Only rendered when the parent screen actually wired
                    // up the callback — see the field doc-comment above.
                    _HoverTile(
                      icon: Icons.functions,
                      tint: theme.accent,
                      title: 'NFA / DFA  →  Regex',
                      subtitle:
                          'Derive a regular expression from the current automaton using state elimination.',
                      onTap: () {
                        Navigator.pop(context);
                        onFaToRegex!();
                        // Safe `!` — guarded by the enclosing `if
                        // (onFaToRegex != null)` above.
                      },
                    ),

                  // ── Data ──────────────────────────────────────────────────
                  const _SectionLabel('Data'),
                  _HoverTile(
                    icon: Icons.upload_file,
                    tint: theme.accentGreen,
                    // Tools section uses theme.accent; Data section uses
                    // theme.accentGreen — a deliberate color grouping so
                    // the eye can distinguish "action/tool" rows from
                    // "import/export data" rows at a glance, per the file
                    // header's "scan by colour" design intent.
                    title: 'Export',
                    subtitle: 'Copy graph DSL to clipboard.',
                    onTap: () {
                      Navigator.pop(context);
                      onExport();
                    },
                  ),
                  _HoverTile(
                    icon: Icons.download,
                    tint: theme.accentGreen,
                    title: 'Import',
                    subtitle: 'Load graph from clipboard or text input.',
                    onTap: () {
                      Navigator.pop(context);
                      onImport();
                    },
                  ),
                  _HoverTile(
                    icon: Icons.history,
                    tint: theme.textDim,
                    // Export History uses the neutral textDim tint rather
                    // than accentGreen — it's grouped under "Data" but
                    // treated as a lower-emphasis/secondary action than
                    // Export/Import themselves.
                    title: 'Export History',
                    subtitle: 'View and restore saved exports.',
                    onTap: () {
                      Navigator.pop(context);
                      onExportHistory();
                    },
                  ),

                  // ── Docs ──────────────────────────────────────────────────
                  // Collapsed by default — reference material, not something
                  // reached for mid-session.
                  _DropdownSection(
                    icon: Icons.menu_book_outlined,
                    tint: theme.textDim,
                    title: 'Docs',
                    children: [
                      _HoverTile(
                        icon: Icons.info_outline,
                        tint: theme.textDim,
                        title: 'About',
                        subtitle: 'App info and credits.',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MarkdownFileScreen(
                                  title: 'About', assetPath: 'assets/About.md'),
                            ),
                          );
                          // Note: unlike every other _HoverTile onTap in
                          // this file, these three Docs rows do NOT call
                          // `Navigator.pop(context)` first — the drawer is
                          // left open underneath the pushed MarkdownFileScreen
                          // route rather than being closed. Popping back
                          // from the doc screen would presumably reveal the
                          // drawer still open.
                        },
                      ),
                      Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                      _HoverTile(
                        icon: Icons.update,
                        tint: theme.textDim,
                        title: 'Changelog',
                        subtitle: "What's new in each version.",
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MarkdownFileScreen(
                                  title: 'Changelog', assetPath: 'assets/Changelog.md'),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                      _HoverTile(
                        icon: Icons.tag,
                        tint: theme.textDim,
                        title: 'Version',
                        subtitle: 'Current build version.',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MarkdownFileScreen(
                                  title: 'Version', assetPath: 'assets/Version.md'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // ── Settings ──────────────────────────────────────────────
                  // Collapsed by default; more prefs can be added here later
                  // without cluttering the always-visible part of the drawer.
                  _DropdownSection(
                    icon: Icons.settings_outlined,
                    tint: theme.accent,
                    title: 'Settings',
                    children: [
                      _HoverTile(
                        icon: Icons.palette_outlined,
                        tint: theme.accent,
                        title: 'Color Settings',
                        subtitle: 'Customize the accent, background, text, and border colors.',
                        onTap: () => showAppThemeSettings(context, popRoute: true),
                        // Delegates entirely to app_theme.dart's own helper
                        // rather than pushing a route or calling a
                        // drawer-owned callback — `popRoute: true` presumably
                        // tells that helper to close this drawer itself as
                        // part of opening the settings UI.
                      ),
                    ],
                  ),

                  // ── Account ───────────────────────────────────────────────
                  if (onSignOut != null) ...[
                    // Whole section — label plus tile — only exists when a
                    // sign-out handler was supplied, consistent with
                    // onFaToRegex's optional-row pattern above.
                    const _SectionLabel('Account'),
                    _HoverTile(
                      icon: Icons.logout,
                      tint: theme.textMid,
                      title: 'Sign out',
                      subtitle: 'Return to the login screen.',
                      onTap: () async {
                        Navigator.pop(context);
                        await onSignOut!();
                        // Closes the drawer immediately, then awaits the
                        // (presumably async/network) sign-out call — the
                        // drawer doesn't wait for sign-out to finish before
                        // dismissing itself, unlike the Reset flow below
                        // which confirms first, then closes.
                      },
                    ),
                  ],

                  // ── Reset ─────────────────────────────────────────────────
                  // Renamed from "Danger Zone" — it's one button, not a
                  // warning label; the red styling already signals caution.
                  const _SectionLabel('Reset'),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.error.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.error.withValues(alpha: 0.35)),
                      // Same "tinted box" pattern as the Display group
                      // above, but using theme.error instead of
                      // theme.surface/theme.borderMid — the box itself
                      // carries the "this is destructive" signal, on top
                      // of the tile's own titleColor/tint overrides below.
                    ),
                    child: _HoverTile(
                      icon: Icons.delete_sweep_outlined,
                      tint: theme.error,
                      titleColor: theme.error,
                      // Both the icon badge and the title text are
                      // colored theme.error here — the only _HoverTile
                      // usage in this file that sets titleColor at all.
                      title: 'Reset Canvas',
                      subtitle: 'Clear all nodes, transitions, and the start arrow.',
                      onTap: () {
                        Navigator.pop(context);
                        // Drawer closes immediately on tap — the
                        // confirmation dialog below is shown against the
                        // screen behind the drawer, not on top of the
                        // still-open drawer.
                        showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: theme.surface,
                            title: Text(
                              'Reset canvas?',
                              style: GoogleFonts.courierPrime(
                                fontWeight: FontWeight.bold,
                                color: theme.textLight,
                              ),
                            ),
                            content: Text(
                              'This will clear all nodes, transitions, and the start arrow.',
                              style: GoogleFonts.courierPrime(color: theme.textMid),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: theme.error),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Reset'),
                              ),
                            ],
                          ),
                        ).then((confirmed) {
                          if (confirmed == true) onReset();
                          // Explicit `== true` (not just `if (confirmed)`)
                          // because `confirmed` is `bool?` — dismissing the
                          // AlertDialog by tapping outside it (rather than
                          // hitting Cancel or Reset) resolves to `null`,
                          // which must NOT trigger onReset(); only an
                          // explicit "Reset" tap (-> true) does.
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                  // Trailing gap so "Reset Canvas" doesn't sit flush
                  // against the bottom of the scrollable ListView/screen.
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
//  MarkdownFileScreen — plain-text viewer for bundled .md docs (About,
//  Changelog, Version). Only ever opened from the drawer above, so it lives
//  here rather than as a standalone file.
// ─────────────────────────────────────────────────────────────────────────────

class MarkdownFileScreen extends StatefulWidget {
  final String title;
  final String assetPath;
  // Despite the class name and section-header comment referencing
  // "Markdown", this screen never actually parses/renders Markdown syntax
  // — it just displays the raw file contents as plain SelectableText (see
  // build() below). ".md" files are shown, but not rendered as Markdown.

  const MarkdownFileScreen({super.key, required this.title, required this.assetPath});

  @override
  State<MarkdownFileScreen> createState() => _MarkdownFileScreenState();
}

class _MarkdownFileScreenState extends State<MarkdownFileScreen> {
  String? _content;
  // null = still loading; non-null = loaded successfully. Combined with
  // `_failed` below, this gives three effective states even though
  // there's no single enum modeling them (loading / loaded / failed).
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadFile();
    // Fire-and-forget: initState() itself stays synchronous; _loadFile()'s
    // Future isn't awaited here, it just runs and calls setState() later
    // when it resolves.
  }

  Future<void> _loadFile() async {
    try {
      final text = await rootBundle.loadString(widget.assetPath);
      // Reads the bundled asset (e.g. 'assets/About.md') as a raw string
      // — this is what requires assetPath to be declared as a Flutter
      // asset in pubspec.yaml for this to succeed.
      if (!mounted) return;
      // Guards against calling setState() after this State object has
      // been disposed (e.g. user navigated away before the asset finished
      // loading) — a common async-gap safety check in Flutter.
      setState(() => _content = text);
    } catch (e) {
      // Broad catch — any failure (missing asset, read error, etc.) is
      // treated identically; `e` itself is caught but never inspected,
      // logged, or surfaced to the user beyond the generic message below.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(
        backgroundColor: theme.surface,
        title: Text(
          widget.title,
          style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold, color: theme.textLight),
        ),
      ),
      body: _failed
          ? Center(
              child: Text(
                'Failed to load ${widget.assetPath}',
                style: GoogleFonts.courierPrime(color: theme.error),
              ),
            )
          : _content == null
              ? Center(child: CircularProgressIndicator(color: theme.accent))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    _content!,
                    // Safe `!` — only reached once `_content == null` has
                    // already been ruled out by the ternary chain above.
                    // SelectableText (not just Text) lets the user
                    // copy/select passages from the About/Changelog/Version
                    // docs.
                    style: GoogleFonts.courierPrime(
                      fontSize: 15,
                      height: 1.5,
                      color: theme.textLight,
                    ),
                  ),
                ),
      // Three-way ternary chain models the _failed / loading / loaded
      // states directly in the widget tree rather than via a switch or
      // separate builder method — reads bottom-up as "loaded content, else
      // spinner if still null, else (outermost) the failure message".
    );
  }
}