// ─────────────────────────────────────────────────────────────────────────────
//  app_theme.dart
//
//  Everything related to app theming in one place. Merged from the
//  formerly-separate app_theme.dart, app_theme_settings.dart, and
//  palette_fab.dart, which all revolve around the same AppThemeData /
//  AppThemeNotifier:
//
//    • AppThemeData / AppThemeNotifier   — theme model, presets, persistence
//    • showAppThemeSettings / sheet UI   — the "Appearance" bottom sheet
//    • PaletteFab                        — themed icon button used in FAB
//                                           toolbars, styled from the notifier
// ─────────────────────────────────────────────────────────────────────────────
//
//  A note on how this annotated copy is commented: this file is large and
//  much of its bulk is genuinely repetitive data (8 near-identical theme
//  color tables; three ~33-field switch/copyWith/toJson blocks that all
//  enumerate the same field list). For those repetitive blocks, this copy
//  explains the *pattern* once rather than re-explaining the same thing on
//  every one of the ~30+ near-duplicate lines — that would add bulk, not
//  understanding. Every widget, method, and algorithm gets full treatment.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
// jsonEncode/jsonDecode — used by AppThemeNotifier to persist the current
// theme as a JSON string in SharedPreferences.
import 'dart:math' as math;
// math.pow/max/min — used only inside the WCAG-style contrast-ratio helpers
// further down (_relativeLuminance, _contrastRatio).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// SystemUiOverlayStyle — used once in buildMaterialTheme() to pick a
// light/dark status-bar icon style to match the theme.
import 'package:google_fonts/google_fonts.dart';
// GoogleFonts.orbitron() (headings/labels) and .sourceCodePro() (body/mono
// text) — the app's two-font system, applied both ad hoc in this file's own
// widgets and wholesale via buildMaterialTheme()'s textTheme.
import 'package:provider/provider.dart';
// context.watch/read<AppThemeNotifier>() throughout this file's widgets.
import 'package:shared_preferences/shared_preferences.dart';
// Local key-value persistence backing AppThemeNotifier's save/load.

// ═════════════════════════════════════════════════════════════════════════════
//  THEME MODEL & NOTIFIER
// ═════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
//  AppThemeData — every customizable color in the app
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeData {
  // Immutable value object: every field is `final`, and there's no way to
  // mutate an existing instance — changes go through copyWith() (below),
  // which returns a *new* AppThemeData. This is what makes ChangeNotifier-
  // style "replace _data wholesale and notifyListeners()" (see
  // AppThemeNotifier further down) safe and predictable.
  const AppThemeData({
    required this.bg,
    required this.gridLine,
    required this.accent,
    required this.accentGreen,
    required this.textDim,
    required this.textMid,
    required this.textLight,
    required this.surface,
    required this.border,
    required this.borderMid,
    required this.nodeBorder,
    required this.nodeBorderSelected,
    required this.nodeBorderHighlight,
    required this.nodeBorderDuplicate,
    required this.nodeBorderDelete,
    required this.lineColor,
    required this.lineHighlight,
    required this.acceptState,
    required this.rejectState,
    required this.edgeDim,
    required this.edgeActive,
    required this.edgeBright,
    required this.edgeAlmost,
    required this.edgeBlocking,
    required this.tagIntro,
    required this.tagDfa,
    required this.tagNfa,
    required this.tagPda,
    required this.tagTm,
    required this.tagBoss,
    required this.tagDefault,
    required this.error,
    required this.warning,
    required this.panelHighlight,
  });
  // Every one of the ~33 colors is `required` — there is no "partial" theme;
  // every factory constructor below (cyberDark, light, midnight, ...) must
  // specify all of them. This is also why copyWith() exists: it's the only
  // way to produce a *modified* theme without re-specifying every field.

  // ── Core UI ───────────────────────────────────────────────────────────────
  final Color bg;
  final Color gridLine;              // faint grid lines painted behind the canvas
  final Color accent;                // primary brand/interactive color
  final Color accentGreen;           // secondary "success/progress" color
  final Color textDim;               // lowest-emphasis text (hints, disabled)
  final Color textMid;               // secondary/body text
  final Color textLight;             // highest-emphasis text (titles, primary content)
  final Color surface;               // cards, sheets, dialogs, panels
  final Color border;                // darker/subtler border tone
  final Color borderMid;             // the border tone actually used almost everywhere in the UI

  // ── Automata canvas (nodes & lines) ─────────────────────────────────────
  final Color nodeBorder;            // default (unselected) state-node outline
  final Color nodeBorderSelected;    // outline while a node is selected/being dragged
  final Color nodeBorderHighlight;   // outline while a node is highlighted during simulation
  final Color nodeBorderDuplicate;   // outline when the typed label collides with another node's
  final Color nodeBorderDelete;      // outline shown while delete mode is active
  final Color lineColor;             // default transition-line/arrow color
  final Color lineHighlight;         // transition line color while highlighted during simulation
  final Color acceptState;           // fill/marker color for an accepting state
  final Color rejectState;           // fill/marker color for a rejecting/halt-reject state

  // ── Level-select map edges ──────────────────────────────────────────────
  final Color edgeDim;               // path to a still-locked level
  final Color edgeActive;            // path to a currently-unlocked/available level
  final Color edgeBright;            // path already completed
  final Color edgeAlmost;            // path to a level that's nearly unlockable
  final Color edgeBlocking;          // path representing an unmet prerequisite that's blocking progress

  // ── Level type tags ─────────────────────────────────────────────────────
  final Color tagIntro;
  final Color tagDfa;
  final Color tagNfa;
  final Color tagPda;
  final Color tagTm;
  final Color tagBoss;               // boss-level accent color
  final Color tagDefault;            // fallback for any level type not covered above

  // ── Semantic ──────────────────────────────────────────────────────────────
  final Color error;
  final Color warning;               // also reused for the start-arrow color, per kAdvancedColorSlots below
  final Color panelHighlight;        // simulator/token highlight color

  bool get isLightTheme => bg.computeLuminance() > 0.45;
  // Derives "is this a light or dark theme" purely from the background
  // color's relative luminance, rather than storing a separate isLight
  // flag on AppThemeData itself — so a custom/user-edited background
  // always classifies correctly even if the user didn't start from one of
  // the two ThemePresets flagged `isLight: true` below. 0.45 sits below the
  // typical 0.5 "midpoint" threshold, biasing slightly toward classifying
  // borderline-mid-luminance backgrounds as dark.

  Color tagColor(String? tag) {
    switch (tag) {
      case 'intro':
        return tagIntro;
      case 'dfa':
        return tagDfa;
      case 'nfa':
        return tagNfa;
      case 'boss':
        return tagBoss;
      case 'pda':
        return tagPda;
      case 'tm':
        return tagTm;
      default:
        return tagDefault;
      // Covers `null` (no tag) as well as any tag string that isn't one of
      // the six known level types — both fall through to the neutral
      // tagDefault color rather than throwing or returning a hardcoded
      // fallback Color.
    }
  }

  // ── Theme factory constructors ──────────────────────────────────────────
  // Each of the eight factories below is a flat 33-field color literal
  // table — the property *names* are identical across all eight (same
  // AppThemeData shape), only the hex values differ. The doc comments on
  // each (where present) describe what makes that theme's specific color
  // choices distinct from its siblings; the individual Color(0xFFrrggbb)
  // values themselves aren't separately annotated line-by-line below,
  // since they're plain data, not logic — the field-name comments above
  // already explain what role each slot plays in the UI regardless of
  // which theme is supplying its value.

  /// The default theme: cyan accent on a near-black charcoal background —
  /// this is what every other theme is compared against, and what
  /// `AppThemeData.defaults()` (below) resolves to.
  factory AppThemeData.cyberDark() => const AppThemeData(
    bg: Color(0xFF05080F),
    gridLine: Color(0xFF0D1620),
    accent: Color(0xFF00E5FF),
    accentGreen: Color(0xFF1FD99A),
    textDim: Color(0xFF8A9BB0),
    textMid: Color(0xFFB0BDCC),
    textLight: Color(0xFFE8ECF0),
    surface: Color(0xFF0A0F18),
    border: Color(0xFF141E2A),
    borderMid: Color(0xFF1A2535),
    nodeBorder: Color(0xFFFFFFFF),
    nodeBorderSelected: Color(0xFF40C4FF),
    nodeBorderHighlight: Color(0xFFD000FF),
    nodeBorderDuplicate: Color(0xFFFF9800),
    nodeBorderDelete: Color(0xFFFF1744),
    lineColor: Color(0xFFFFFFFF),
    lineHighlight: Color(0xFFD000FF),
    acceptState: Color(0xFF4CAF50),
    rejectState: Color(0xFFFF1744),
    edgeDim: Color(0xFF1A2E40),
    edgeActive: Color(0xFF1CBD8A),
    edgeBright: Color(0xFF1FD99A),
    edgeAlmost: Color(0xFFFFAA00),
    edgeBlocking: Color(0xFFFF6D00),
    tagIntro: Color(0xFF00E5FF),
    tagDfa: Color(0xFF69FF47),
    tagNfa: Color(0xFFFFD740),
    tagPda: Color(0xFFFF6D00),
    tagTm: Color(0xFFE040FB),
    tagBoss: Color(0xFFFF1744),
    tagDefault: Color(0xFF9E9E9E),
    error: Color(0xFFFF1744),
    warning: Color(0xFFFF6D00),
    panelHighlight: Color(0xFFD000FF),
  );

  /// The app's sole "bright/paper" light theme alternative to cyberDark —
  /// see also [parchment] below for a second, warmer-toned light option.
  factory AppThemeData.light() => const AppThemeData(
    bg: Color(0xFFF4F6FA),
    gridLine: Color(0xFFD8DEE8),
    accent: Color(0xFF0077B6),
    accentGreen: Color(0xFF2A9D8F),
    textDim: Color(0xFF6B7280),
    textMid: Color(0xFF374151),
    textLight: Color(0xFF111827),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7EB),
    borderMid: Color(0xFFD1D5DB),
    nodeBorder: Color(0xFF374151),
    nodeBorderSelected: Color(0xFF0077B6),
    nodeBorderHighlight: Color(0xFF7C3AED),
    nodeBorderDuplicate: Color(0xFFD97706),
    nodeBorderDelete: Color(0xFFDC2626),
    lineColor: Color(0xFF1F2937),
    lineHighlight: Color(0xFF7C3AED),
    acceptState: Color(0xFF16A34A),
    rejectState: Color(0xFFDC2626),
    edgeDim: Color(0xFFCBD5E1),
    edgeActive: Color(0xFF2A9D8F),
    edgeBright: Color(0xFF059669),
    edgeAlmost: Color(0xFFD97706),
    edgeBlocking: Color(0xFFEA580C),
    tagIntro: Color(0xFF0077B6),
    tagDfa: Color(0xFF16A34A),
    tagNfa: Color(0xFFD97706),
    tagPda: Color(0xFFEA580C),
    tagTm: Color(0xFF7C3AED),
    tagBoss: Color(0xFFDC2626),
    tagDefault: Color(0xFF9CA3AF),
    error: Color(0xFFDC2626),
    warning: Color(0xFFD97706),
    panelHighlight: Color(0xFF7C3AED),
  );

  /// Indigo-violet "aurora" night theme. Deliberately NOT derived from
  /// [cyberDark] — shares only the general dark-UI contrast rules, not the
  /// specific hues, so it reads as its own theme rather than a recolored
  /// accent on top of the default. Cool violet bg, lavender node/line
  /// strokes, pink-magenta highlight, rose reject/delete.
  factory AppThemeData.midnight() => const AppThemeData(
    bg: Color(0xFF0A0A1F),
    gridLine: Color(0xFF17153A),
    accent: Color(0xFF8B5CF6),
    accentGreen: Color(0xFF34D399),
    textDim: Color(0xFF8783A6),
    textMid: Color(0xFFB4AFCF),
    textLight: Color(0xFFEDEBF7),
    surface: Color(0xFF120F28),
    border: Color(0xFF1E1A3C),
    borderMid: Color(0xFF2C2652),
    nodeBorder: Color(0xFFE9E4FF),
    nodeBorderSelected: Color(0xFF60A5FA),
    nodeBorderHighlight: Color(0xFFF472B6),
    nodeBorderDuplicate: Color(0xFFFACC15),
    nodeBorderDelete: Color(0xFFF43F5E),
    lineColor: Color(0xFFE9E4FF),
    lineHighlight: Color(0xFFF472B6),
    acceptState: Color(0xFF34D399),
    rejectState: Color(0xFFF43F5E),
    edgeDim: Color(0xFF241F44),
    edgeActive: Color(0xFF8B5CF6),
    edgeBright: Color(0xFFC084FC),
    edgeAlmost: Color(0xFFF472B6),
    edgeBlocking: Color(0xFFF43F5E),
    tagIntro: Color(0xFF8B5CF6),
    tagDfa: Color(0xFF34D399),
    tagNfa: Color(0xFFFACC15),
    tagPda: Color(0xFF60A5FA),
    tagTm: Color(0xFFF472B6),
    tagBoss: Color(0xFFF43F5E),
    tagDefault: Color(0xFF8783A6),
    error: Color(0xFFF43F5E),
    warning: Color(0xFFFACC15),
    panelHighlight: Color(0xFFF472B6),
  );

  /// Deep-sea teal theme with warm gold/coral accents used *against* the
  /// cool background — the inverse relationship of [midnight]'s all-cool
  /// palette — so simulation highlights and warnings pop rather than
  /// blending into a same-hue-family backdrop.
  factory AppThemeData.ocean() => const AppThemeData(
    bg: Color(0xFF03141A),
    gridLine: Color(0xFF0A2530),
    accent: Color(0xFF14B8A6),
    accentGreen: Color(0xFF2DD4BF),
    textDim: Color(0xFF6B94A0),
    textMid: Color(0xFF9EC3CC),
    textLight: Color(0xFFE3F6F5),
    surface: Color(0xFF082027),
    border: Color(0xFF0F3038),
    borderMid: Color(0xFF1B4048),
    nodeBorder: Color(0xFFDFF8F0),
    nodeBorderSelected: Color(0xFF2DD4BF),
    nodeBorderHighlight: Color(0xFFFFB020),
    nodeBorderDuplicate: Color(0xFFFF8A65),
    nodeBorderDelete: Color(0xFFFF5252),
    lineColor: Color(0xFFDFF8F0),
    lineHighlight: Color(0xFFFFB020),
    acceptState: Color(0xFF2DD4BF),
    rejectState: Color(0xFFFF5252),
    edgeDim: Color(0xFF123840),
    edgeActive: Color(0xFF14B8A6),
    edgeBright: Color(0xFF5EEAD4),
    edgeAlmost: Color(0xFFFFB020),
    edgeBlocking: Color(0xFFFF7043),
    tagIntro: Color(0xFF14B8A6),
    tagDfa: Color(0xFF5EEAD4),
    tagNfa: Color(0xFFFFB020),
    tagPda: Color(0xFFFF7043),
    tagTm: Color(0xFF7DD3FC),
    tagBoss: Color(0xFFFF5252),
    tagDefault: Color(0xFF6B94A0),
    error: Color(0xFFFF5252),
    warning: Color(0xFFFFB020),
    panelHighlight: Color(0xFFFFB020),
  );

  /// Warm ember/firelight theme. Every color is tuned toward amber/rust/red
  /// rather than reusing [cyberDark]'s cool grays and white strokes, so it
  /// doesn't just look like "dark theme with an orange accent."
  factory AppThemeData.ember() => const AppThemeData(
    bg: Color(0xFF120A06),
    gridLine: Color(0xFF241610),
    accent: Color(0xFFFFB020),
    accentGreen: Color(0xFF84CC16),
    textDim: Color(0xFFB0937A),
    textMid: Color(0xFFD3B79A),
    textLight: Color(0xFFF5E6D3),
    surface: Color(0xFF1C120B),
    border: Color(0xFF2A1B12),
    borderMid: Color(0xFF3D2718),
    nodeBorder: Color(0xFFFCEEDD),
    nodeBorderSelected: Color(0xFFFFB020),
    nodeBorderHighlight: Color(0xFFFF5A36),
    nodeBorderDuplicate: Color(0xFFFFD166),
    nodeBorderDelete: Color(0xFFE53935),
    lineColor: Color(0xFFFCEEDD),
    lineHighlight: Color(0xFFFF5A36),
    acceptState: Color(0xFF84CC16),
    rejectState: Color(0xFFE53935),
    edgeDim: Color(0xFF2A1810),
    edgeActive: Color(0xFFD97706),
    edgeBright: Color(0xFFFFD166),
    edgeAlmost: Color(0xFFFF8C42),
    edgeBlocking: Color(0xFFB91C1C),
    tagIntro: Color(0xFFFFB020),
    tagDfa: Color(0xFF84CC16),
    tagNfa: Color(0xFFFFD166),
    tagPda: Color(0xFFFF6B35),
    tagTm: Color(0xFFC2410C),
    tagBoss: Color(0xFFE53935),
    tagDefault: Color(0xFFB0937A),
    error: Color(0xFFE53935),
    warning: Color(0xFFFF8C42),
    panelHighlight: Color(0xFFFF5A36),
  );

  /// Desaturated, low-glow "quiet" theme. Where cyberDark/midnight/ocean/ember
  /// all share the same recipe (near-black bg + one saturated neon accent +
  /// white strokes + neon pink/orange highlight), Slate deliberately drops
  /// saturation across the board: warm charcoal instead of blue-black, a
  /// dusty steel-blue accent instead of neon, and earth-toned semantic colors
  /// (sage, ochre, clay, brick) instead of primary-color coding. Nothing here
  /// glows — it's the professional/subdued option next to the louder themes.
  factory AppThemeData.slate() => const AppThemeData(
    bg: Color(0xFF1A1917),
    gridLine: Color(0xFF242320),
    accent: Color(0xFF7C8B99),
    accentGreen: Color(0xFF8FA680),
    textDim: Color(0xFF8C8880),
    textMid: Color(0xFFB8B3A9),
    textLight: Color(0xFFEDEAE3),
    surface: Color(0xFF211F1C),
    border: Color(0xFF2E2C27),
    borderMid: Color(0xFF3A3730),
    nodeBorder: Color(0xFFD8D4CA),
    nodeBorderSelected: Color(0xFF7C8B99),
    nodeBorderHighlight: Color(0xFFB08968),
    nodeBorderDuplicate: Color(0xFFC9A227),
    nodeBorderDelete: Color(0xFFA65D57),
    lineColor: Color(0xFFD8D4CA),
    lineHighlight: Color(0xFFB08968),
    acceptState: Color(0xFF8FA680),
    rejectState: Color(0xFFA65D57),
    edgeDim: Color(0xFF33312B),
    edgeActive: Color(0xFF7C8B99),
    edgeBright: Color(0xFFA8B8C4),
    edgeAlmost: Color(0xFFC9A227),
    edgeBlocking: Color(0xFFA65D57),
    tagIntro: Color(0xFF7C8B99),
    tagDfa: Color(0xFF8FA680),
    tagNfa: Color(0xFFC9A227),
    tagPda: Color(0xFFB08968),
    tagTm: Color(0xFF9B8AA6),
    tagBoss: Color(0xFFA65D57),
    tagDefault: Color(0xFF8C8880),
    error: Color(0xFFA65D57),
    warning: Color(0xFFC9A227),
    panelHighlight: Color(0xFFB08968),
  );

  /// Monochrome CRT-terminal theme. Instead of hue-coding categories like the
  /// other dark themes, almost every color here is a brightness step of one
  /// green — the identity comes from being single-hue, not from which hue.
  /// Red and amber are held back as the only two breaks from green, reserved
  /// for genuine alarm states (delete/reject, duplicate/warning), so they
  /// read as alerts rather than as two more colors in a rainbow.
  factory AppThemeData.phosphor() => const AppThemeData(
    bg: Color(0xFF030503),
    gridLine: Color(0xFF0A130A),
    accent: Color(0xFF33FF66),
    accentGreen: Color(0xFF33FF66),
    // Note: `accent` and `accentGreen` are literally the same hex value in
    // this theme — consistent with the "single-hue identity" design note
    // above; there's no separate "success green" distinct from the main
    // accent since the whole palette is built from one green.
    textDim: Color(0xFF2C7A3E),
    textMid: Color(0xFF4FCB6C),
    textLight: Color(0xFFB9FFC9),
    surface: Color(0xFF071A0B),
    border: Color(0xFF0F2814),
    borderMid: Color(0xFF16351C),
    nodeBorder: Color(0xFFB9FFC9),
    nodeBorderSelected: Color(0xFF33FF66),
    nodeBorderHighlight: Color(0xFFE8FFEC),
    nodeBorderDuplicate: Color(0xFFFFC53D),
    nodeBorderDelete: Color(0xFFFF4B4B),
    lineColor: Color(0xFF4FCB6C),
    lineHighlight: Color(0xFFE8FFEC),
    acceptState: Color(0xFF33FF66),
    rejectState: Color(0xFFFF4B4B),
    edgeDim: Color(0xFF123018),
    edgeActive: Color(0xFF2C7A3E),
    edgeBright: Color(0xFF33FF66),
    edgeAlmost: Color(0xFFFFC53D),
    edgeBlocking: Color(0xFFFF4B4B),
    tagIntro: Color(0xFF33FF66),
    tagDfa: Color(0xFF4FCB6C),
    tagNfa: Color(0xFFFFC53D),
    tagPda: Color(0xFF2C7A3E),
    tagTm: Color(0xFFB9FFC9),
    tagBoss: Color(0xFFFF4B4B),
    tagDefault: Color(0xFF2C7A3E),
    error: Color(0xFFFF4B4B),
    warning: Color(0xFFFFC53D),
    panelHighlight: Color(0xFFE8FFEC),
  );

  /// Warm "old technical manual" light theme — a second light option that's
  /// deliberately not a reskin of [light]. Cream parchment instead of
  /// cool gray-blue paper, ink-brown text instead of slate gray, and muted
  /// denim/forest/rust/plum inks instead of clinical saturated primaries.
  factory AppThemeData.parchment() => const AppThemeData(
    bg: Color(0xFFF2EBDA),
    gridLine: Color(0xFFE4D9C0),
    accent: Color(0xFF3A5A7A),
    accentGreen: Color(0xFF4C7A52),
    textDim: Color(0xFF8A7A63),
    textMid: Color(0xFF5C4E3D),
    textLight: Color(0xFF2B2013),
    surface: Color(0xFFFBF6EA),
    border: Color(0xFFE0D3B8),
    borderMid: Color(0xFFD0C09E),
    nodeBorder: Color(0xFF2B2013),
    nodeBorderSelected: Color(0xFF3A5A7A),
    nodeBorderHighlight: Color(0xFF7A4A8A),
    nodeBorderDuplicate: Color(0xFFB8791E),
    nodeBorderDelete: Color(0xFFA13A2E),
    lineColor: Color(0xFF2B2013),
    lineHighlight: Color(0xFF7A4A8A),
    acceptState: Color(0xFF4C7A52),
    rejectState: Color(0xFFA13A2E),
    edgeDim: Color(0xFFD0C09E),
    edgeActive: Color(0xFF4C7A52),
    edgeBright: Color(0xFF6FA377),
    edgeAlmost: Color(0xFFB8791E),
    edgeBlocking: Color(0xFF9C4A20),
    tagIntro: Color(0xFF3A5A7A),
    tagDfa: Color(0xFF4C7A52),
    tagNfa: Color(0xFFB8791E),
    tagPda: Color(0xFF9C4A20),
    tagTm: Color(0xFF7A4A8A),
    tagBoss: Color(0xFFA13A2E),
    tagDefault: Color(0xFF8A7A63),
    error: Color(0xFFA13A2E),
    warning: Color(0xFFB8791E),
    panelHighlight: Color(0xFF7A4A8A),
  );

  factory AppThemeData.defaults() => AppThemeData.cyberDark();
  // The one canonical "reset" target — everything that resets a theme
  // (AppThemeNotifier.resetToDefaults, fromJson's fallback below, etc.)
  // routes through this single factory rather than hardcoding cyberDark()
  // in multiple places, so changing the app-wide default is a one-line edit.

  // ── Serialization ────────────────────────────────────────────────────────
  // toJson/fromJson/copyWith below all enumerate the same ~33 fields in the
  // same order as the constructor above. Each is explained once; the
  // remaining fields in each block follow the identical pattern shown by
  // the first couple of entries.

  Map<String, dynamic> toJson() => {
    'bg': bg.toARGB32(),
    // Each Color is serialized as its packed 32-bit ARGB integer (not a hex
    // string) — compact and directly round-trippable through Color(value)
    // in fromJson below.
    'gridLine': gridLine.toARGB32(),
    'accent': accent.toARGB32(),
    'accentGreen': accentGreen.toARGB32(),
    'textDim': textDim.toARGB32(),
    'textMid': textMid.toARGB32(),
    'textLight': textLight.toARGB32(),
    'surface': surface.toARGB32(),
    'border': border.toARGB32(),
    'borderMid': borderMid.toARGB32(),
    'nodeBorder': nodeBorder.toARGB32(),
    'nodeBorderSelected': nodeBorderSelected.toARGB32(),
    'nodeBorderHighlight': nodeBorderHighlight.toARGB32(),
    'nodeBorderDuplicate': nodeBorderDuplicate.toARGB32(),
    'nodeBorderDelete': nodeBorderDelete.toARGB32(),
    'lineColor': lineColor.toARGB32(),
    'lineHighlight': lineHighlight.toARGB32(),
    'acceptState': acceptState.toARGB32(),
    'rejectState': rejectState.toARGB32(),
    'edgeDim': edgeDim.toARGB32(),
    'edgeActive': edgeActive.toARGB32(),
    'edgeBright': edgeBright.toARGB32(),
    'edgeAlmost': edgeAlmost.toARGB32(),
    'edgeBlocking': edgeBlocking.toARGB32(),
    'tagIntro': tagIntro.toARGB32(),
    'tagDfa': tagDfa.toARGB32(),
    'tagNfa': tagNfa.toARGB32(),
    'tagPda': tagPda.toARGB32(),
    'tagTm': tagTm.toARGB32(),
    'tagBoss': tagBoss.toARGB32(),
    'tagDefault': tagDefault.toARGB32(),
    'error': error.toARGB32(),
    'warning': warning.toARGB32(),
    'panelHighlight': panelHighlight.toARGB32(),
  };
  // Used by AppThemeNotifier._persist() to serialize the *entire* current
  // theme (not just the fields that differ from a preset) into
  // SharedPreferences — so a fully custom, hand-edited theme survives app
  // restarts even with no associated preset id.

  factory AppThemeData.fromJson(Map<String, dynamic> json) {
    final base = AppThemeData.defaults();
    // Starts from the default theme as a fallback source, not from a blank/
    // zeroed AppThemeData — so if `json` is missing a key entirely (e.g. an
    // older save written before a new field like `panelHighlight` existed),
    // that field silently falls back to cyberDark's value rather than
    // becoming transparent/black or throwing.
    Color c(String key, Color fallback) =>
        Color((json[key] as int?) ?? fallback.toARGB32());
    // Local helper closure: looks up `key` in the JSON map, casts to int?
    // (safe — `as int?` returns null rather than throwing if the value is
    // missing or of the wrong type... actually `as` does throw on a type
    // mismatch, just not on a *missing* key, where json[key] is already
    // null), and falls back to `fallback`'s own packed value if absent.
    return base.copyWith(
      bg: c('bg', base.bg),
      gridLine: c('gridLine', base.gridLine),
      accent: c('accent', base.accent),
      accentGreen: c('accentGreen', base.accentGreen),
      textDim: c('textDim', base.textDim),
      textMid: c('textMid', base.textMid),
      textLight: c('textLight', base.textLight),
      surface: c('surface', base.surface),
      border: c('border', base.border),
      borderMid: c('borderMid', base.borderMid),
      nodeBorder: c('nodeBorder', base.nodeBorder),
      nodeBorderSelected: c('nodeBorderSelected', base.nodeBorderSelected),
      nodeBorderHighlight: c('nodeBorderHighlight', base.nodeBorderHighlight),
      nodeBorderDuplicate: c('nodeBorderDuplicate', base.nodeBorderDuplicate),
      nodeBorderDelete: c('nodeBorderDelete', base.nodeBorderDelete),
      lineColor: c('lineColor', base.lineColor),
      lineHighlight: c('lineHighlight', base.lineHighlight),
      acceptState: c('acceptState', base.acceptState),
      rejectState: c('rejectState', base.rejectState),
      edgeDim: c('edgeDim', base.edgeDim),
      edgeActive: c('edgeActive', base.edgeActive),
      edgeBright: c('edgeBright', base.edgeBright),
      edgeAlmost: c('edgeAlmost', base.edgeAlmost),
      edgeBlocking: c('edgeBlocking', base.edgeBlocking),
      tagIntro: c('tagIntro', base.tagIntro),
      tagDfa: c('tagDfa', base.tagDfa),
      tagNfa: c('tagNfa', base.tagNfa),
      tagPda: c('tagPda', base.tagPda),
      tagTm: c('tagTm', base.tagTm),
      tagBoss: c('tagBoss', base.tagBoss),
      tagDefault: c('tagDefault', base.tagDefault),
      error: c('error', base.error),
      warning: c('warning', base.warning),
      panelHighlight: c('panelHighlight', base.panelHighlight),
    );
    // `base.copyWith(...)` (rather than a bare `AppThemeData(...)`
    // constructor call) is actually redundant here since every field is
    // explicitly supplied — but it does mean this stays correct for free
    // if a *new* AppThemeData field is ever added without also updating
    // this factory, since copyWith's `??` fallback (see below) would use
    // `base`'s value for the missing key instead of failing to compile.
  }

  AppThemeData copyWith({
    Color? bg,
    Color? gridLine,
    Color? accent,
    Color? accentGreen,
    Color? textDim,
    Color? textMid,
    Color? textLight,
    Color? surface,
    Color? border,
    Color? borderMid,
    Color? nodeBorder,
    Color? nodeBorderSelected,
    Color? nodeBorderHighlight,
    Color? nodeBorderDuplicate,
    Color? nodeBorderDelete,
    Color? lineColor,
    Color? lineHighlight,
    Color? acceptState,
    Color? rejectState,
    Color? edgeDim,
    Color? edgeActive,
    Color? edgeBright,
    Color? edgeAlmost,
    Color? edgeBlocking,
    Color? tagIntro,
    Color? tagDfa,
    Color? tagNfa,
    Color? tagPda,
    Color? tagTm,
    Color? tagBoss,
    Color? tagDefault,
    Color? error,
    Color? warning,
    Color? panelHighlight,
  }) =>
      // Standard immutable-value-object copyWith pattern: every param is
      // nullable and optional; omitted params fall back to `this`'s
      // current value via `??`, so callers only need to specify the fields
      // they're actually changing (see e.g. applyQuickAccent below, which
      // only overrides `accent` and `tagIntro`).
      AppThemeData(
        bg: bg ?? this.bg,
        gridLine: gridLine ?? this.gridLine,
        accent: accent ?? this.accent,
        accentGreen: accentGreen ?? this.accentGreen,
        textDim: textDim ?? this.textDim,
        textMid: textMid ?? this.textMid,
        textLight: textLight ?? this.textLight,
        surface: surface ?? this.surface,
        border: border ?? this.border,
        borderMid: borderMid ?? this.borderMid,
        nodeBorder: nodeBorder ?? this.nodeBorder,
        nodeBorderSelected: nodeBorderSelected ?? this.nodeBorderSelected,
        nodeBorderHighlight: nodeBorderHighlight ?? this.nodeBorderHighlight,
        nodeBorderDuplicate: nodeBorderDuplicate ?? this.nodeBorderDuplicate,
        nodeBorderDelete: nodeBorderDelete ?? this.nodeBorderDelete,
        lineColor: lineColor ?? this.lineColor,
        lineHighlight: lineHighlight ?? this.lineHighlight,
        acceptState: acceptState ?? this.acceptState,
        rejectState: rejectState ?? this.rejectState,
        edgeDim: edgeDim ?? this.edgeDim,
        edgeActive: edgeActive ?? this.edgeActive,
        edgeBright: edgeBright ?? this.edgeBright,
        edgeAlmost: edgeAlmost ?? this.edgeAlmost,
        edgeBlocking: edgeBlocking ?? this.edgeBlocking,
        tagIntro: tagIntro ?? this.tagIntro,
        tagDfa: tagDfa ?? this.tagDfa,
        tagNfa: tagNfa ?? this.tagNfa,
        tagPda: tagPda ?? this.tagPda,
        tagTm: tagTm ?? this.tagTm,
        tagBoss: tagBoss ?? this.tagBoss,
        tagDefault: tagDefault ?? this.tagDefault,
        error: error ?? this.error,
        warning: warning ?? this.warning,
        panelHighlight: panelHighlight ?? this.panelHighlight,
      );
  // Caveat inherent to the `??` pattern: there's no way to explicitly set a
  // field *to* its already-current value via a literal null through
  // copyWith — but since `?? this.x` treats "omitted" and "passed null"
  // identically, that distinction is moot; both just mean "keep current".

  // ── Derived/bulk adjustments ─────────────────────────────────────────────

  /// Shifts backgrounds darker/lighter together (amount -1..1).
  AppThemeData withBackgroundDepth(double amount, {AppThemeData? baseTheme}) {
    final base = baseTheme ?? this;
    // `baseTheme` lets the caller re-derive from a fixed starting point
    // (e.g. the theme as it was when the settings sheet first opened)
    // rather than compounding the shift onto whatever the *current* colors
    // already are — this is what makes the "Background depth" slider in
    // the settings sheet behave like an absolute -1..1 dial instead of a
    // relative nudge that drifts further with every onChanged tick.
    Color shift(Color c, Color baselineColor, double amt) {
      final hsl = HSLColor.fromColor(baselineColor);
      // Converts to HSL specifically so lightness can be adjusted in
      // isolation, leaving hue and saturation untouched — a naive RGB
      // blend toward white/black would also desaturate the color.
      final l = (hsl.lightness + amt).clamp(0.02, 0.98);
      // Never lets lightness hit the true extremes (0 or 1), which would
      // collapse the color to pure black/white regardless of its hue.
      return hsl.withLightness(l).toColor();
    }
    return copyWith(
      bg: shift(bg, base.bg, amount * 0.08),
      surface: shift(surface, base.surface, amount * 0.07),
      gridLine: shift(gridLine, base.gridLine, amount * 0.06),
      border: shift(border, base.border, amount * 0.05),
      borderMid: shift(borderMid, base.borderMid, amount * 0.05),
      // Each of the five "structural" colors gets its own slightly
      // different multiplier (0.08 down to 0.05) — bg shifts the most,
      // borderMid/border the least — so the slider doesn't just uniformly
      // darken everything by the same amount (which would compress the
      // existing contrast between these layers); the *relative* spacing
      // between bg/surface/borders is preserved, just all shifted together.
    );
  }

  /// Adjust text readability together while keeping contrast readable.
  AppThemeData withTextContrast(double amount, {AppThemeData? baseTheme}) {
    final base = baseTheme ?? this;
    final bg = base.bg;
    // Contrast is always measured against the *baseline* background, not
    // whatever the live (possibly already-shifted-by-withBackgroundDepth)
    // background currently is — keeping the two sliders (background depth,
    // text contrast) independent of each other's current position.

    Color shift(Color color, Color baselineColor, double amt, {required double minRatio}) {
      final hsl = HSLColor.fromColor(baselineColor);
      final targetLightness = (hsl.lightness + amt).clamp(0.02, 0.98);
      final adjusted = hsl.withLightness(targetLightness).toColor();
      return _ensureReadableContrast(adjusted, bg, minRatio: minRatio);
      // After nudging lightness by the slider amount, the result is passed
      // through a WCAG-style contrast-ratio safety net (see below) — the
      // slider can push text lighter/darker, but never past the point
      // where it becomes illegible against the background.
    }

    final delta = amount * 0.08;
    return copyWith(
      textDim: shift(textDim, base.textDim, -delta * 0.8, minRatio: 2.4),
      textMid: shift(textMid, base.textMid, delta * 0.5, minRatio: 3.2),
      textLight: shift(textLight, base.textLight, delta, minRatio: 4.4),
      // Three different treatments for the three text tiers: textDim moves
      // in the *opposite* direction from the slider (`-delta`, at 0.8x
      // strength) — increasing "contrast" pushes dim text further away
      // from mid/light rather than all three converging together; textMid
      // moves the same direction at half strength; textLight moves the
      // full amount. Minimum contrast ratios also step up with emphasis
      // tier (2.4 / 3.2 / 4.4) — roughly mirroring WCAG's own graduated
      // requirements for large vs. normal vs. high-emphasis text.
    );
  }

  static Color _ensureReadableContrast(Color color, Color background, {required double minRatio}) {
    final source = HSLColor.fromColor(color);
    final bgLum = background.computeLuminance();
    final targetIsDarker = bgLum > 0.5;
    // If the background is itself light, the safety net pushes the
    // candidate text color *darker* to gain contrast (and vice versa for a
    // dark background pushing text lighter) — this is what keeps the same
    // withTextContrast() logic correct for both light and dark themes
    // without a separate code path.

    double lightness = source.lightness;
    for (var i = 0; i < 80; i++) {
      // Iteratively steps lightness by 1% up to 80 times (i.e. up to a
      // full 0.0-1.0 sweep) rather than solving for the exact lightness
      // analytically — simple and robust, at the cost of doing up to 80
      // Color conversions/luminance calculations per color per theme
      // adjustment; acceptable here since this only runs on user-driven
      // slider changes, not every frame.
      final candidate = HSLColor.fromAHSL(
        source.alpha,
        source.hue,
        source.saturation,
        lightness,
      ).toColor();
      if (_contrastRatio(candidate, background) >= minRatio) {
        return candidate;
        // Returns as soon as the *first* (smallest step from the original)
        // lightness value that clears the minimum ratio is found — so the
        // result stays as close as possible to the caller's originally
        // requested color, only pushed as far as strictly necessary.
      }
      lightness = (lightness + (targetIsDarker ? -0.01 : 0.01)).clamp(0.02, 0.98);
    }

    // If no lightness value in [0.02, 0.98] achieves minRatio within 80
    // steps (i.e. this color's hue/saturation simply can't reach the
    // required contrast against this background at any lightness), fall
    // back to the most extreme allowed lightness in the needed direction —
    // the best available approximation rather than an infinite loop or a
    // color that silently fails to meet the requirement.
    return HSLColor.fromAHSL(
      source.alpha,
      source.hue,
      source.saturation,
      targetIsDarker ? 0.02 : 0.98,
    ).toColor();
  }

  static double _contrastRatio(Color foreground, Color background) {
    final fgLum = _relativeLuminance(foreground);
    final bgLum = _relativeLuminance(background);
    final lighter = math.max(fgLum, bgLum);
    final darker = math.min(fgLum, bgLum);
    return (lighter + 0.05) / (darker + 0.05);
    // Standard WCAG 2.x contrast-ratio formula: (L1 + 0.05) / (L2 + 0.05)
    // where L1 is the lighter of the two relative luminances — the +0.05
    // offset avoids a divide-by-zero when either color is pure black
    // (luminance 0) and keeps the ratio well-behaved at the extremes.
    // max/min (rather than assuming foreground is always lighter) makes
    // this symmetric — it doesn't matter which of the two args is
    // literally "the text" vs "the background" for the ratio's value.
  }

  static double _relativeLuminance(Color color) {
    final r = color.r <= 0.03928 ? color.r / 12.92 : math.pow((color.r + 0.055) / 1.055, 2.4).toDouble();
    final g = color.g <= 0.03928 ? color.g / 12.92 : math.pow((color.g + 0.055) / 1.055, 2.4).toDouble();
    final b = color.b <= 0.03928 ? color.b / 12.92 : math.pow((color.b + 0.055) / 1.055, 2.4).toDouble();
    // The WCAG "linearization" (gamma-decoding) step applied to each
    // channel independently before combining: sRGB channel values (here
    // Color's .r/.g/.b, which in this Flutter version are already
    // normalized floats in [0, 1] rather than 0-255 ints) don't combine
    // linearly with perceived brightness, so each is either divided by
    // 12.92 (for very dark values, where the power curve would be
    // numerically unstable) or raised to a 2.4 gamma exponent, per the
    // official WCAG formula.
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    // Weighted sum reflecting human eyes' greater sensitivity to green
    // than red, and red more than blue — again, exact WCAG-specified
    // coefficients, not app-specific tuning.
  }

  AppThemeData withLinkedHighlights() => copyWith(
        panelHighlight: accent,
        nodeBorderHighlight: accent,
        lineHighlight: accent,
        tagIntro: accent,
      );
  // "Link highlights to accent": collapses four independently-colorable
  // highlight slots down to all match the current accent color — used by
  // the "Use accent for simulation highlights" toggle in the settings
  // sheet. Note `tagIntro` is included here too — the intro level tag is
  // treated as another "highlight" slot for this purpose, not just the
  // three canvas/simulator highlights the toggle's own label mentions.
}

// ─────────────────────────────────────────────────────────────────────────────
//  Settings UI metadata
// ─────────────────────────────────────────────────────────────────────────────

const kCoreColorSlots = [
  (key: 'accent', label: 'Main accent', group: 'Quick'),
  (key: 'accentGreen', label: 'Success / progress', group: 'Quick'),
  (key: 'bg', label: 'Background', group: 'Quick'),
  (key: 'surface', label: 'Panels & cards', group: 'Quick'),
  (key: 'textLight', label: 'Primary text', group: 'Quick'),
];
// Dart 3 named-record list — each entry pairs an AppThemeData field name
// (`key`, used with the string-keyed _applyKey/_colorForKey switches below)
// with a human label and a UI grouping. `kCoreColorSlots` is the five most
// commonly-adjusted colors, shown unconditionally as "Quick customize"
// tiles in the settings sheet.

const kAdvancedColorSlots = [
  (key: 'gridLine', label: 'Grid lines', group: 'Canvas'),
  (key: 'border', label: 'Border (dark)', group: 'Canvas'),
  (key: 'borderMid', label: 'Border (mid)', group: 'Canvas'),
  (key: 'textMid', label: 'Text (mid)', group: 'Text'),
  (key: 'textDim', label: 'Text (dim)', group: 'Text'),
  (key: 'nodeBorder', label: 'Node border (default)', group: 'Nodes & lines'),
  (key: 'nodeBorderSelected', label: 'Node border (selected)', group: 'Nodes & lines'),
  (key: 'nodeBorderHighlight', label: 'Node border (simulation)', group: 'Nodes & lines'),
  (key: 'nodeBorderDuplicate', label: 'Node border (duplicate label)', group: 'Nodes & lines'),
  (key: 'nodeBorderDelete', label: 'Node border (delete mode)', group: 'Nodes & lines'),
  (key: 'lineColor', label: 'Line / arrow (default)', group: 'Nodes & lines'),
  (key: 'lineHighlight', label: 'Line / arrow (simulation)', group: 'Nodes & lines'),
  (key: 'acceptState', label: 'Accept state (halt)', group: 'Nodes & lines'),
  (key: 'rejectState', label: 'Reject state (halt)', group: 'Nodes & lines'),
  (key: 'panelHighlight', label: 'Simulator / token highlight', group: 'Nodes & lines'),
  (key: 'edgeDim', label: 'Path (locked)', group: 'Level map'),
  (key: 'edgeActive', label: 'Path (available)', group: 'Level map'),
  (key: 'edgeBright', label: 'Path (completed)', group: 'Level map'),
  (key: 'edgeAlmost', label: 'Path (almost unlocked)', group: 'Level map'),
  (key: 'edgeBlocking', label: 'Path (blocking prereq)', group: 'Level map'),
  (key: 'tagIntro', label: 'Intro levels', group: 'Level types'),
  (key: 'tagDfa', label: 'DFA levels', group: 'Level types'),
  (key: 'tagNfa', label: 'NFA levels', group: 'Level types'),
  (key: 'tagPda', label: 'PDA levels', group: 'Level types'),
  (key: 'tagTm', label: 'TM levels', group: 'Level types'),
  (key: 'tagBoss', label: 'Boss levels', group: 'Level types'),
  (key: 'tagDefault', label: 'Other levels', group: 'Level types'),
  (key: 'error', label: 'Error / delete', group: 'Other'),
  (key: 'warning', label: 'Warning / start arrow', group: 'Other'),
];
// The remaining 28 fields (everything not in kCoreColorSlots). Grouped
// into six named `group`s ('Canvas', 'Text', 'Nodes & lines', 'Level map',
// 'Level types', 'Other') that the settings sheet's Advanced section
// (further down, via `advancedGroups`) uses to build its collapsible
// sub-headings — the group strings here are exactly what gets
// `.toUpperCase()`'d into that UI's section labels.

List<({String key, String label, String group})> get kAllColorSlots => [
      ...kCoreColorSlots,
      ...kAdvancedColorSlots,
    ];
// Simple concatenation of both lists — declared as a top-level getter
// (recomputed on every access, since list literals with spread operators
// aren't `const`-representable here) rather than a `final` — cheap enough
// that this doesn't matter, and not currently referenced elsewhere in this
// file's visible code (kCoreColorSlots and kAdvancedColorSlots are used
// separately instead), so this likely exists for external callers.

// ─────────────────────────────────────────────────────────────────────────────
//  AppThemeNotifier
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeNotifier extends ChangeNotifier {
  // The `provider`-package ChangeNotifier that every `context.watch/read
  // <AppThemeNotifier>()` call throughout the app subscribes to. Wraps an
  // immutable AppThemeData (`_data`) — every mutating method below follows
  // the same three-step pattern: replace `_data` wholesale, call
  // notifyListeners(), then persist asynchronously.
  AppThemeNotifier._(this._data, this._prefs, this._presetId, this._flashHighlights);
  // Private named constructor (`._`) — the only way to construct this
  // class from outside is the async `load()` factory below, since
  // constructing one synchronously would require already having a loaded
  // SharedPreferences instance and its persisted values in hand.

  AppThemeData _data;
  final SharedPreferences _prefs;
  String? _presetId;
  // Tracks which named preset (if any) the current `_data` matches exactly
  // — null means "a custom/hand-edited theme with no exact preset match".
  // Sliders and per-color edits below all explicitly null this out, since
  // a manual edit means the current colors no longer represent a clean
  // preset selection.
  bool _flashHighlights;

  static const _prefsKeyV2 = 'app_theme_v2';
  static const _prefsKeyPreset = 'app_theme_preset_id';
  // The "V2" suffix on the color-data key (vs. a bare 'app_theme_v1' key
  // referenced directly-by-string in load() below, not as a constant)
  // implies a prior schema migration — see load()'s v1/v2 fallback chain.

  /// Accessibility: pulse (fade in/out) highlighted colors instead of relying
  /// on a static color swap, so highlight/duplicate/error states stay
  /// noticeable for colorblind players or anyone who might just miss a
  /// static color change. On by default.
  static const _prefsKeyFlashHighlights = 'app_theme_flash_highlights';

  static Future<AppThemeNotifier> load() async {
    final prefs = await SharedPreferences.getInstance();
    final presetId = prefs.getString(_prefsKeyPreset);
    final flashHighlights = prefs.getBool(_prefsKeyFlashHighlights) ?? true;
    // Defaults to `true` (per the doc comment above) when the key has
    // never been written — an accessibility feature that ships opt-out,
    // not opt-in.
    AppThemeData data;

    final rawV2 = prefs.getString(_prefsKeyV2);
    if (rawV2 != null && rawV2.isNotEmpty) {
      try {
        data = AppThemeData.fromJson(jsonDecode(rawV2) as Map<String, dynamic>);
      } catch (_) {
        // Malformed/corrupted saved JSON (or a decode that doesn't produce
        // the expected Map shape) falls back to the hardcoded default
        // rather than crashing app startup — theming is not worth a boot
        // failure over.
        data = AppThemeData.defaults();
      }
    } else {
      // No "v2" data at all — check for a legacy "v1" save before falling
      // back further, so users upgrading from an old app version don't
      // lose their customized theme.
      final rawV1 = prefs.getString('app_theme_v1');
      // Note: 'app_theme_v1' is a bare string literal here, not a named
      // static const like `_prefsKeyV2`/`_prefsKeyPreset` above — since
      // it's only ever read once, during this one-time migration path,
      // and never written again once v2 data exists, it wasn't promoted
      // to a shared constant.
      if (rawV1 != null && rawV1.isNotEmpty) {
        try {
          data = AppThemeData.fromJson(jsonDecode(rawV1) as Map<String, dynamic>);
          // Reuses the *same* fromJson parser for both v1 and v2 data —
          // implying the v1→v2 "migration" was purely a storage-key rename
          // with an unchanged JSON shape, not an actual field-format
          // change (fromJson's per-field `?? fallback` already handles any
          // fields v1 might be missing that v2 later added).
        } catch (_) {
          data = AppThemeData.defaults();
        }
      } else {
        // No saved color data under either key: fall back to whatever
        // preset the (separately-persisted) presetId points to, or the
        // hardcoded default if there's no presetId either (e.g. truly
        // first launch).
        data = presetById(presetId)?.data ?? AppThemeData.defaults();
      }
    }

    return AppThemeNotifier._(data, prefs, presetId, flashHighlights);
  }

  AppThemeData get data => _data;
  String? get activePresetId => _presetId;

  /// Whether highlighted/duplicate/error states on the canvas should pulse
  /// their opacity rather than stay a static color. Persisted independently
  /// of the color theme itself since it's a behavior toggle, not a color.
  bool get flashHighlights => _flashHighlights;

  Future<void> setFlashHighlights(bool enabled) async {
    _flashHighlights = enabled;
    notifyListeners();
    await _prefs.setBool(_prefsKeyFlashHighlights, enabled);
    // Unlike every color-mutating method below, this doesn't go through
    // `_persist()` — it's a standalone bool key, entirely separate from
    // the `_data`/`_presetId` persistence pair, consistent with the doc
    // comment above calling it out as independent of the color theme.
  }

  // Core getters (backward compatible)
  // Thin `Color get x => _data.x;` forwarding for every field on
  // AppThemeData — lets call sites throughout the rest of the app write
  // `theme.accent`, `theme.textDim`, etc. directly off the *notifier*
  // (which is what `context.watch<AppThemeNotifier>()` returns) rather
  // than needing `theme.data.accent` everywhere. "(backward compatible)"
  // suggests this mirrors an older API shape from before `AppThemeData`
  // existed as a separate model class.
  Color get bg => _data.bg;
  Color get gridLine => _data.gridLine;
  Color get accent => _data.accent;
  Color get accentGreen => _data.accentGreen;
  Color get textDim => _data.textDim;
  Color get textMid => _data.textMid;
  Color get textLight => _data.textLight;
  Color get surface => _data.surface;
  Color get border => _data.border;
  Color get borderMid => _data.borderMid;

  Color get nodeBorder => _data.nodeBorder;
  Color get nodeBorderSelected => _data.nodeBorderSelected;
  Color get nodeBorderHighlight => _data.nodeBorderHighlight;
  Color get nodeBorderDuplicate => _data.nodeBorderDuplicate;
  Color get nodeBorderDelete => _data.nodeBorderDelete;
  Color get lineColor => _data.lineColor;
  Color get lineHighlight => _data.lineHighlight;
  Color get acceptState => _data.acceptState;
  Color get rejectState => _data.rejectState;
  Color get edgeDim => _data.edgeDim;
  Color get edgeActive => _data.edgeActive;
  Color get edgeBright => _data.edgeBright;
  Color get edgeAlmost => _data.edgeAlmost;
  Color get edgeBlocking => _data.edgeBlocking;
  Color get panelHighlight => _data.panelHighlight;
  Color get error => _data.error;
  Color get warning => _data.warning;
  // Note: `nodeBorder` itself has a getter but `tagIntro`/`tagDfa`/etc. do
  // not — tag colors are only reachable via the `tagColor(String?)` method
  // below (delegating to AppThemeData.tagColor), not individual getters,
  // since callers look them up dynamically by tag string rather than by a
  // known-in-advance field name.

  Color tagColor(String? tag) => _data.tagColor(tag);

  Future<void> applyPreset(String presetId) async {
    final preset = presetById(presetId);
    if (preset == null) return;
    // Silently no-ops on an unrecognized id rather than throwing — callers
    // (the preset-carousel UI below) only ever pass ids that exist in
    // kThemePresets, but this guards against a stale/invalid persisted id
    // too.
    _data = preset.data;
    _presetId = presetId;
    notifyListeners();
    await _persist();
  }

  Future<void> setColor(String key, Color color) async {
    _data = _applyKey(_data, key, color);
    _presetId = null;
    // Any single-color edit immediately breaks the "matches a preset
    // exactly" invariant, so _presetId is cleared unconditionally — even
    // if, coincidentally, the new color happens to match what the preset
    // already had.
    notifyListeners();
    await _persist();
  }

  Future<void> applyQuickAccent(Color accent) async {
    _data = _data.copyWith(accent: accent, tagIntro: accent);
    // Setting the "Main accent" quick-customize color also updates
    // `tagIntro` to match — consistent with withLinkedHighlights() above
    // treating tagIntro as an accent-following slot, though note this
    // method updates *only* tagIntro (not panelHighlight/nodeBorderHighlight
    // /lineHighlight too) unless setLinkHighlightsToAccent has separately
    // linked those.
    _presetId = null;
    notifyListeners();
    await _persist();
  }

  Future<void> setLinkHighlightsToAccent(bool linked) async {
    if (linked) {
      _data = _data.withLinkedHighlights();
    } else {
      // Un-linking doesn't just leave the highlight colors as whatever
      // they currently are (still equal to accent) — it actively restores
      // them to what the *preset* (or default, if no preset is active)
      // originally specified, so toggling link on-then-off round-trips
      // back to the theme's original highlight colors rather than leaving
      // them stuck matching the accent.
      final base = presetById(_presetId)?.data ?? AppThemeData.defaults();
      _data = _data.copyWith(
        panelHighlight: base.panelHighlight,
        nodeBorderHighlight: base.nodeBorderHighlight,
        lineHighlight: base.lineHighlight,
        // Notably does NOT restore `tagIntro` here, unlike
        // withLinkedHighlights() which sets all four (including tagIntro)
        // when linking — so un-linking is asymmetric with linking: tagIntro
        // stays wherever it was left (e.g. still equal to accent from
        // applyQuickAccent, or from having been linked a moment ago).
      );
    }
    _presetId = null;
    notifyListeners();
    await _persist();
  }

  Future<void> applyBackgroundDepth(double amount, {AppThemeData? baseTheme}) async {
    _data = _data.withBackgroundDepth(amount, baseTheme: baseTheme);
    _presetId = null;
    notifyListeners();
    await _persist();
  }

  Future<void> applyTextContrast(double amount, {AppThemeData? baseTheme}) async {
    _data = _data.withTextContrast(amount, baseTheme: baseTheme);
    _presetId = null;
    notifyListeners();
    await _persist();
  }
  // These last two methods are thin wrappers that just add the standard
  // "clear preset id, notify, persist" bookkeeping around the pure
  // AppThemeData.withBackgroundDepth/withTextContrast computations —
  // consistent with every other mutator in this class.

  Future<void> resetToDefaults() async {
    _data = AppThemeData.defaults();
    _presetId = 'dark';
    // Unlike every other mutator, this sets _presetId to the *specific*
    // 'dark' preset id rather than null — because AppThemeData.defaults()
    // is defined as literally AppThemeData.cyberDark(), which is exactly
    // what the 'dark' ThemePreset's `.data` is too, so this genuinely does
    // match a real preset, not a custom/unmatched theme.
    notifyListeners();
    await _prefs.remove(_prefsKeyV2);
    // Deletes the persisted custom-color-JSON key entirely (rather than
    // writing AppThemeData.defaults().toJson() over it) — combined with
    // writing the 'dark' preset id below, this means a fresh load() call
    // later will skip both the v2-JSON and v1-JSON branches and land on
    // `presetById(presetId)?.data`, i.e. it resolves via the preset system
    // rather than via a redundant stored color blob.
    await _prefs.setString(_prefsKeyPreset, 'dark');
  }

  Future<void> _persist() async {
    await _prefs.setString(_prefsKeyV2, jsonEncode(_data.toJson()));
    // Every mutator (other than resetToDefaults, which manages persistence
    // itself, and setFlashHighlights, which is independent) always writes
    // the full color JSON blob — even applyPreset(), where in principle
    // just persisting the preset id and re-deriving colors from it on next
    // load would suffice. Storing the full data means a later change to a
    // ThemePreset's own color values (a code update) won't silently alter
    // what a user who previously picked that preset sees, since their
    // exact colors were snapshotted at selection time.
    if (_presetId != null) {
      await _prefs.setString(_prefsKeyPreset, _presetId!);
    } else {
      await _prefs.remove(_prefsKeyPreset);
      // No lingering stale preset id once the theme has been customized
      // away from any preset — important because load()'s final fallback
      // branch (`presetById(presetId)?.data`) is only reached when there's
      // no v2/v1 JSON at all; leaving a stale preset id wouldn't actually
      // cause a bug given _persist always writes v2 JSON too, but removing
      // it keeps `activePresetId` correctly reporting `null` after reload.
    }
  }

  static AppThemeData _applyKey(AppThemeData d, String key, Color c) {
    // String-keyed setter — translates the dynamic `key` string (as used
    // throughout kCoreColorSlots/kAdvancedColorSlots and the settings UI)
    // into a specific copyWith(...) call. Every case follows the identical
    // one-line pattern `case 'x': return d.copyWith(x: c);` — shown here in
    // full since it's the actual dispatch logic, not decorative.
    switch (key) {
      case 'bg':
        return d.copyWith(bg: c);
      case 'gridLine':
        return d.copyWith(gridLine: c);
      case 'accent':
        return d.copyWith(accent: c);
      case 'accentGreen':
        return d.copyWith(accentGreen: c);
      case 'textDim':
        return d.copyWith(textDim: c);
      case 'textMid':
        return d.copyWith(textMid: c);
      case 'textLight':
        return d.copyWith(textLight: c);
      case 'surface':
        return d.copyWith(surface: c);
      case 'border':
        return d.copyWith(border: c);
      case 'borderMid':
        return d.copyWith(borderMid: c);
      case 'nodeBorder':
        return d.copyWith(nodeBorder: c);
      case 'nodeBorderSelected':
        return d.copyWith(nodeBorderSelected: c);
      case 'nodeBorderHighlight':
        return d.copyWith(nodeBorderHighlight: c);
      case 'nodeBorderDuplicate':
        return d.copyWith(nodeBorderDuplicate: c);
      case 'nodeBorderDelete':
        return d.copyWith(nodeBorderDelete: c);
      case 'lineColor':
        return d.copyWith(lineColor: c);
      case 'lineHighlight':
        return d.copyWith(lineHighlight: c);
      case 'acceptState':
        return d.copyWith(acceptState: c);
      case 'rejectState':
        return d.copyWith(rejectState: c);
      case 'edgeDim':
        return d.copyWith(edgeDim: c);
      case 'edgeActive':
        return d.copyWith(edgeActive: c);
      case 'edgeBright':
        return d.copyWith(edgeBright: c);
      case 'edgeAlmost':
        return d.copyWith(edgeAlmost: c);
      case 'edgeBlocking':
        return d.copyWith(edgeBlocking: c);
      case 'tagIntro':
        return d.copyWith(tagIntro: c);
      case 'tagDfa':
        return d.copyWith(tagDfa: c);
      case 'tagNfa':
        return d.copyWith(tagNfa: c);
      case 'tagPda':
        return d.copyWith(tagPda: c);
      case 'tagTm':
        return d.copyWith(tagTm: c);
      case 'tagBoss':
        return d.copyWith(tagBoss: c);
      case 'tagDefault':
        return d.copyWith(tagDefault: c);
      case 'error':
        return d.copyWith(error: c);
      case 'warning':
        return d.copyWith(warning: c);
      case 'panelHighlight':
        return d.copyWith(panelHighlight: c);
      default:
        return d;
        // An unrecognized key (e.g. a typo, or a stale key string from a
        // renamed field) is a silent no-op — returns the theme unchanged
        // rather than throwing, which would otherwise crash the settings
        // sheet on a single bad color-slot definition.
    }
  }

  static AppThemeNotifier of(BuildContext context) =>
      context.watch<AppThemeNotifier>();

  static AppThemeNotifier read(BuildContext context) =>
      context.read<AppThemeNotifier>();
  // Static convenience wrappers around the two standard `provider` access
  // patterns — `of` subscribes to rebuilds (like every `context.watch<...>`
  // call used ad hoc elsewhere in this codebase), `read` doesn't. Neither
  // is actually called anywhere in *this* file's own visible code (which
  // consistently uses `context.watch<AppThemeNotifier>()` / `.read<...>()`
  // directly) — these exist for external callers who'd rather write
  // `AppThemeNotifier.of(context)` than spell out the generic themselves.
}

// ── Theme presets ───────────────────────────────────────────────────────────

class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.data,
    this.isLight = false,
    // Defaults to false — most presets are dark themes in this app, so
    // light ones (`light`, `parchment`) are the explicit opt-in below.
  });

  final String id;
  // The stable string key persisted to SharedPreferences (_prefsKeyPreset)
  // and used throughout AppThemeNotifier — must stay unique and, in
  // practice, stable across app versions once shipped, or existing users'
  // persisted preset id would silently fail to resolve via presetById().
  final String name;
  final String description;
  final AppThemeData data;
  final bool isLight;
  // Not actually load-bearing for AppThemeData.isLightTheme (which derives
  // light/dark purely from `bg`'s computed luminance) — this flag is
  // presumably UI metadata only, e.g. for filtering/grouping presets in
  // some other screen not shown in this file, or historical from before
  // `isLightTheme` existed as a computed getter.
}

final List<ThemePreset> kThemePresets = [
  ThemePreset(
    id: 'dark',
    name: 'Dark',
    description: 'Default cyan-on-charcoal look',
    data: AppThemeData.cyberDark(),
  ),
  ThemePreset(
    id: 'light',
    name: 'Light',
    description: 'Bright paper-style workspace',
    isLight: true,
    data: AppThemeData.light(),
  ),
  ThemePreset(
    id: 'midnight',
    name: 'Midnight',
    description: 'Indigo night with pink aurora highlights',
    data: AppThemeData.midnight(),
  ),
  ThemePreset(
    id: 'ocean',
    name: 'Ocean',
    description: 'Deep teal sea with warm gold & coral pops',
    data: AppThemeData.ocean(),
  ),
  ThemePreset(
    id: 'ember',
    name: 'Ember',
    description: 'Firelight amber, rust, and cream on charcoal-brown',
    data: AppThemeData.ember(),
  ),
  ThemePreset(
    id: 'slate',
    name: 'Slate',
    description: 'Muted charcoal with dusty steel-blue, no neon',
    data: AppThemeData.slate(),
  ),
  ThemePreset(
    id: 'phosphor',
    name: 'Phosphor',
    description: 'Monochrome green CRT terminal, amber/red alarms only',
    data: AppThemeData.phosphor(),
  ),
  ThemePreset(
    id: 'parchment',
    name: 'Parchment',
    description: 'Warm cream paper with ink-brown text and muted inks',
    isLight: true,
    data: AppThemeData.parchment(),
  ),
];
// The single canonical list every preset-related lookup (presetById,
// applyPreset, the settings sheet's horizontal preset carousel) iterates
// or searches over — order here is also *display* order in that carousel,
// since the UI just maps over kThemePresets by index.

ThemePreset? presetById(String? id) {
  if (id == null) return null;
  for (final p in kThemePresets) {
    if (p.id == id) return p;
  }
  return null;
  // A linear scan over an 8-element list — a Map<String, ThemePreset>
  // would be O(1), but at this size the difference is immaterial, and a
  // plain List keeps kThemePresets simple to read/edit/reorder as a
  // literal above.
}

ThemeData buildMaterialTheme(AppThemeData c) {
  // Translates this app's own ~33-color AppThemeData into a full Flutter
  // `ThemeData`, so standard Material widgets used elsewhere in the app
  // (AppBar, TextField, buttons, Chip, SnackBar, ...) automatically pick
  // up the current custom theme without every screen needing to
  // hand-style each widget individually.
  final base = c.isLightTheme ? ThemeData.light() : ThemeData.dark();
  // Starts from Flutter's own light/dark baseline ThemeData (for whatever
  // this doesn't explicitly override below — e.g. default Material
  // component behaviors/animations) rather than ThemeData() alone, so the
  // "brightness family" of defaults matches this theme's own light/dark
  // classification.

  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    cardColor: c.surface,
    colorScheme: (c.isLightTheme ? ColorScheme.light : ColorScheme.dark)(
      // Calls whichever of ColorScheme.light(...) / ColorScheme.dark(...)
      // matches this theme's brightness — both are constructors with the
      // same named-parameter shape, so this ternary-selecting-a-constructor
      // pattern lets the same argument list below populate either one.
      primary: c.accent,
      onPrimary: c.bg,
      secondary: c.accentGreen,
      onSecondary: c.bg,
      surface: c.surface,
      onSurface: c.textLight,
      error: c.error,
      onError: c.bg,
      outline: c.borderMid,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.textLight,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      // elevation: 0 + explicit transparent surfaceTintColor together
      // disable Material 3's default "elevation overlay" tinting, which
      // would otherwise subtly shift the app bar's color away from
      // `c.surface` based on scroll elevation — keeping the app bar a
      // flat, exact match to the theme's surface color.
      titleTextStyle: GoogleFonts.orbitron(
        color: c.accent,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
        // Wide letter-spacing (3) on bold condensed-feeling Orbitron is
        // the recurring "sci-fi terminal heading" treatment reused for
        // several labels throughout this file (APPEARANCE title below,
        // _SectionTitle, etc.).
      ),
      iconTheme: IconThemeData(color: c.textMid),
      systemOverlayStyle:
          c.isLightTheme ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      // Status-bar icon color follows the theme's brightness — dark icons
      // on a light theme's app bar, light icons on a dark theme's,
      // otherwise the OS status bar icons could end up low-contrast
      // against a custom-colored app bar.
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: c.borderMid, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.borderMid),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.borderMid),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      // Same three-border pattern (border/enabledBorder/focusedBorder, 8px
      // radius, focus swaps to accent) seen hand-rolled per-field in
      // black_box_input_dialog.dart's `_inputDecoration` helper — here it's
      // set globally via the Material theme instead, so any *other* plain
      // TextField in the app that doesn't build its own custom decoration
      // gets this look for free.
      labelStyle: GoogleFonts.orbitron(color: c.textMid, fontSize: 12, letterSpacing: 1),
      hintStyle: GoogleFonts.sourceCodePro(color: c.textDim, fontSize: 13),
      errorStyle: GoogleFonts.sourceCodePro(color: c.error, fontSize: 11),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent.withValues(alpha: 0.12),
        // A low-alpha tinted fill rather than a solid accent-colored
        // button — matches the "tinted badge" visual language used
        // throughout the drawer/canvas UI elsewhere in this app rather
        // than Material's default fully-opaque FilledButton look.
        foregroundColor: c.accent,
        side: BorderSide(color: c.accent, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        textStyle: GoogleFonts.orbitron(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textMid,
        side: BorderSide(color: c.borderMid),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        textStyle: GoogleFonts.orbitron(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.textMid,
        textStyle: GoogleFonts.orbitron(fontSize: 10, letterSpacing: 1.5),
      ),
    ),
    // The three button themes step down in visual weight (Filled: tinted
    // fill + border + largest text; Outlined: border only, no fill;
    // Text: no border, smallest/lightest text) — a consistent hierarchy of
    // "primary / secondary / tertiary" action emphasis across the app.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.surface,
      foregroundColor: c.textLight,
      elevation: 4,
      highlightElevation: 8,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      labelStyle: GoogleFonts.orbitron(color: c.textMid, fontSize: 9, letterSpacing: 1.5),
      side: BorderSide(color: c.borderMid),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.gridLine,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface,
      contentTextStyle: GoogleFonts.sourceCodePro(color: c.textLight, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.borderMid),
      ),
      behavior: SnackBarBehavior.floating,
      // Floating (not the Material default "fixed full-width bar stuck to
      // the bottom") — pairs naturally with the rounded-border shape just
      // above, which would look odd spanning edge-to-edge.
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // Transparent by design — every actual bottom sheet in this app
      // (e.g. AppThemeSettingsSheet below) paints its own themed Container
      // background/border/radius manually rather than relying on
      // BottomSheetThemeData's own background, so this just prevents
      // Material's default sheet chrome from showing through underneath.
    ),
    textTheme: GoogleFonts.orbitronTextTheme(base.textTheme).copyWith(
      // Starts from an Orbitron-ified copy of the *base* (light/dark
      // default) text theme, then selectively overrides the
      // body/label styles below — so any TextTheme slot not explicitly
      // listed here (e.g. displayLarge/headlineMedium/titleSmall) still
      // gets Orbitron applied, just with Flutter's own default sizing/
      // color for that slot rather than a custom one.
      bodyLarge: GoogleFonts.sourceCodePro(color: c.textLight, fontSize: 14),
      bodyMedium: GoogleFonts.sourceCodePro(color: c.textMid, fontSize: 13),
      bodySmall: GoogleFonts.sourceCodePro(color: c.textDim, fontSize: 11),
      // Body text overrides swap to sourceCodePro (monospace) rather than
      // keeping Orbitron — Orbitron is reserved for headings/labels/
      // branding, sourceCodePro for actual readable body content, matching
      // the two-font system described at this file's import section.
      labelLarge: GoogleFonts.orbitron(
        color: c.textLight,
        fontSize: 12,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: GoogleFonts.orbitron(color: c.textMid, fontSize: 10, letterSpacing: 1.2),
      labelSmall: GoogleFonts.orbitron(color: c.textDim, fontSize: 8, letterSpacing: 1.0),
      // Label styles (used by default for things like button text)
      // conversely stay on Orbitron, stepping down in size/weight/emphasis
      // from Large to Small alongside the text-tier color progression
      // (textLight -> textMid -> textDim).
    ),
    primaryTextTheme: GoogleFonts.orbitronTextTheme(base.primaryTextTheme),
    iconTheme: IconThemeData(color: c.textMid, size: 22),
    primaryIconTheme: IconThemeData(color: c.accent),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  THEME SETTINGS SHEET
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the appearance bottom sheet.
/// Set [popRoute] true when launching from the automata drawer (closes drawer first).
void showAppThemeSettings(BuildContext context, {bool popRoute = false}) {
  final notifier = AppThemeNotifier.read(context);
  // Reads (not watches) the notifier once, up front, before the sheet is
  // even shown — this is what's passed into AppThemeSettingsSheet's
  // `notifier` field below, which then manages its own subscription
  // lifecycle internally (see _AppThemeSettingsSheetState.initState/dispose
  // further down) rather than relying on this function's own BuildContext,
  // which won't be valid for the sheet's whole lifetime anyway.
  if (popRoute) Navigator.of(context).pop();
  // Called from automata_drawer.dart's "Color Settings" tile with
  // popRoute: true — this is what closes the drawer before the bottom
  // sheet opens, so the two don't visually stack.

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Lets the sheet's DraggableScrollableSheet child (below) control its
    // own height/sizing rather than being capped at Material's default
    // "about half the screen" modal-bottom-sheet height.
    backgroundColor: Colors.transparent,
    // Transparent so AppThemeSettingsSheet's own rounded/bordered Container
    // (below) is the only visible background, not a default white/dark
    // rectangle showing through behind/around it.
    builder: (_) => AppThemeSettingsSheet(notifier: notifier),
  );
}

class AppThemeSettingsSheet extends StatefulWidget {
  const AppThemeSettingsSheet({super.key, required this.notifier});

  final AppThemeNotifier notifier;

  @override
  State<AppThemeSettingsSheet> createState() => _AppThemeSettingsSheetState();
}

class _AppThemeSettingsSheetState extends State<AppThemeSettingsSheet> {
  late AppThemeData _live;
  // A local snapshot of the notifier's current data, kept in sync via a
  // manual listener (below) rather than via `context.watch` — necessary
  // because this State needs to read/write _live synchronously inside
  // build() and various callbacks without forcing a `context.watch`-driven
  // rebuild cycle for every single field read.
  late AppThemeData _baselineTheme;
  // Frozen at whatever the theme was when the sheet first opened — passed
  // as `baseTheme:` to applyBackgroundDepth/applyTextContrast so the two
  // sliders always compute their shift relative to this fixed starting
  // point, not the live (already-shifted) data.
  bool _advancedOpen = false;
  double _bgDepth = 0;
  double _textContrast = 0;
  bool _linkHighlights = false;
  // Local slider/switch positions — note these are NOT re-derived from
  // `_live`/the notifier's actual current colors on rebuild; they're purely
  // local UI state initialized to "neutral" (0 / 0 / false) whenever the
  // sheet opens, regardless of whatever background-depth/contrast/link
  // state the underlying theme is already in. So reopening the sheet after
  // a previous session's adjustments resets these three controls to
  // neutral even though the *colors* they produced persist.

  @override
  void initState() {
    super.initState();
    _live = widget.notifier.data;
    _baselineTheme = _live;
    widget.notifier.addListener(_onNotifierChanged);
    // Subscribes to the notifier manually (rather than via
    // context.watch, which isn't available/appropriate to call from
    // initState) so this State's `_live` field — and therefore its
    // build() output — stays in sync if the notifier changes for any
    // reason *other* than this sheet's own edits (unlikely in practice
    // since this sheet is the only UI that mutates theme colors while
    // open, but keeps the sheet correct regardless).
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() => setState(() => _live = widget.notifier.data);

  Color _colorForKey(String key) {
    // The read-side counterpart to AppThemeNotifier._applyKey's write-side
    // switch above — same string-key dispatch pattern, just returning
    // instead of setting. Used to resolve `slot.key` strings from
    // kCoreColorSlots/kAdvancedColorSlots into actual current Color values
    // for display (in _QuickColorTile/_ColorRow swatches) and for seeding
    // the color picker dialog's `initial` color.
    final d = _live;
    switch (key) {
      case 'bg':
        return d.bg;
      case 'gridLine':
        return d.gridLine;
      case 'accent':
        return d.accent;
      case 'accentGreen':
        return d.accentGreen;
      case 'textDim':
        return d.textDim;
      case 'textMid':
        return d.textMid;
      case 'textLight':
        return d.textLight;
      case 'surface':
        return d.surface;
      case 'border':
        return d.border;
      case 'borderMid':
        return d.borderMid;
      case 'nodeBorder':
        return d.nodeBorder;
      case 'nodeBorderSelected':
        return d.nodeBorderSelected;
      case 'nodeBorderHighlight':
        return d.nodeBorderHighlight;
      case 'nodeBorderDuplicate':
        return d.nodeBorderDuplicate;
      case 'nodeBorderDelete':
        return d.nodeBorderDelete;
      case 'lineColor':
        return d.lineColor;
      case 'lineHighlight':
        return d.lineHighlight;
      case 'acceptState':
        return d.acceptState;
      case 'rejectState':
        return d.rejectState;
      case 'edgeDim':
        return d.edgeDim;
      case 'edgeActive':
        return d.edgeActive;
      case 'edgeBright':
        return d.edgeBright;
      case 'edgeAlmost':
        return d.edgeAlmost;
      case 'edgeBlocking':
        return d.edgeBlocking;
      case 'tagIntro':
        return d.tagIntro;
      case 'tagDfa':
        return d.tagDfa;
      case 'tagNfa':
        return d.tagNfa;
      case 'tagPda':
        return d.tagPda;
      case 'tagTm':
        return d.tagTm;
      case 'tagBoss':
        return d.tagBoss;
      case 'tagDefault':
        return d.tagDefault;
      case 'error':
        return d.error;
      case 'warning':
        return d.warning;
      case 'panelHighlight':
        return d.panelHighlight;
      default:
        return Colors.transparent;
        // Differs from _applyKey's `default: return d` (no-op) above — here
        // an unrecognized key renders as fully transparent rather than
        // silently substituting some other color, making a bad/stale key
        // visually obvious (an invisible swatch) rather than silently
        // wrong.
    }
  }

  void _pickColor(String label, String key) {
    showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initial: _colorForKey(key),
        label: label,
        onChanged: (c) => widget.notifier.setColor(key, c),
        // The dialog's onChanged writes straight through to the notifier
        // (not to a local variable first) — every RGB/hex edit inside the
        // color picker immediately persists and notifies listeners, so
        // e.g. the canvas behind the settings sheet updates live as the
        // user drags a slider, not just after tapping "Apply".
        textLight: _live.textLight,
        textMid: _live.textMid,
        borderMid: _live.borderMid,
        bg: _live.bg,
        surface: _live.surface,
        // The dialog needs its *own* chrome colors (for its own text/
        // borders/background) to stay legible even while the user is
        // actively changing, say, the app's own `bg` or `surface` color —
        // these are snapshotted from `_live` at the moment the dialog
        // opens, not continuously updated as the dialog's own edits
        // change the underlying theme.
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _live.accent;
    final surface = _live.surface;
    final textLight = _live.textLight;
    final textMid = _live.textMid;
    final textDim = _live.textDim;
    final borderMid = _live.borderMid;
    final bg = _live.bg;
    // Destructures the handful of colors this sheet's own chrome needs
    // into locals up front, rather than repeating `_live.x` at every use
    // site below.

    final advancedGroups = <String, List<({String key, String label, String group})>>{};
    for (final slot in kAdvancedColorSlots) {
      advancedGroups.putIfAbsent(slot.group, () => []).add(slot);
    }
    // Buckets the flat kAdvancedColorSlots list into a Map keyed by each
    // slot's `group` string (e.g. all "Nodes & lines" slots together) —
    // `putIfAbsent` lazily creates each group's list only the first time
    // that group name is encountered, and because kAdvancedColorSlots is
    // already ordered with same-group entries adjacent, this also
    // preserves each group's internal ordering and (via Dart's
    // insertion-ordered LinkedHashMap-backed `{}` map literal) the order
    // groups first appear in the source list.

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      // Opens most of the way up the screen (82%) but lets the user drag
      // it down to 45% or up to nearly full-screen (95%) — rather than a
      // fixed-height sheet, since the color-list content can be long,
      // especially with Advanced expanded.
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: borderMid)),
          // Only a top border (matching only-rounding-the-top-corners above)
          // — the sheet's other three edges sit flush against the screen
          // edges, so a full border would be partially invisible/pointless.
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: borderMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // The small horizontal "grab handle" bar conventionally shown
              // at the top of a draggable sheet — purely decorative, the
              // actual drag gesture is handled by DraggableScrollableSheet
              // itself across the whole sheet, not just this handle.
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'APPEARANCE',
                      style: GoogleFonts.orbitron(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset to default dark theme',
                    icon: Icon(Icons.restart_alt, color: textMid),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: surface,
                          title: Text('Reset theme?',
                              style: GoogleFonts.orbitron(color: textLight, fontSize: 13)),
                          content: Text(
                            'Restore the default dark palette and clear custom colors.',
                            style: GoogleFonts.sourceCodePro(color: textMid, fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Reset')),
                          ],
                        ),
                      );
                      if (ok == true) await widget.notifier.resetToDefaults();
                      // Same `== true` (not just `if (ok)`) pattern seen in
                      // the drawer's own Reset Canvas flow — `ok` is
                      // `bool?`, and dismissing the AlertDialog without
                      // tapping either button must not trigger the reset.
                    },
                  ),
                ],
              ),
            ),
            Divider(color: borderMid, height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                // Wires the DraggableScrollableSheet's own scrollController
                // into this inner ListView — required so dragging the
                // sheet's content area both scrolls the list *and* resizes
                // the sheet itself as appropriate (DraggableScrollableSheet
                // coordinates the two based on scroll position/direction).
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _SectionTitle(label: 'Color palettes', accent: accent),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // A horizontally-scrolling row of preset cards nested
                      // inside the outer vertically-scrolling ListView —
                      // the fixed `height: 88` on the outer SizedBox is
                      // what lets a horizontal ListView live inside a
                      // vertical one without needing intrinsic-size passes.
                      itemCount: kThemePresets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final p = kThemePresets[i];
                        final selected = widget.notifier.activePresetId == p.id ||
                            (widget.notifier.activePresetId == null &&
                                p.id == 'dark' &&
                                _live.bg == p.data.bg);
                        // Two ways a preset card can show as "selected":
                        // (1) its id exactly matches activePresetId, or (2)
                        // there's no active preset at all (a from-scratch
                        // default/first-launch state) but this is the
                        // 'dark' card and the live background happens to
                        // match cyberDark's — a heuristic fallback so the
                        // Dark card still highlights on a truly fresh
                        // install where _presetId might be null despite the
                        // colors genuinely being the default theme.
                        return _PresetCard(
                          preset: p,
                          selected: selected,
                          onTap: () => widget.notifier.applyPreset(p.id),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),
                  _SectionTitle(label: 'Quick customize', accent: accent),
                  const SizedBox(height: 6),
                  Text(
                    'Change a few core colors at once. Open Advanced for every individual color.',
                    style: GoogleFonts.sourceCodePro(color: textMid, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),

                  _QuickColorTile(
                    label: 'Main accent',
                    color: _live.accent,
                    bg: bg,
                    borderMid: borderMid,
                    textLight: textLight,
                    onTap: () => _pickColor('Main accent', 'accent'),
                  ),
                  _QuickColorTile(
                    label: 'Background',
                    color: _live.bg,
                    bg: bg,
                    borderMid: borderMid,
                    textLight: textLight,
                    onTap: () => _pickColor('Background', 'bg'),
                  ),
                  _QuickColorTile(
                    label: 'Panels',
                    color: _live.surface,
                    bg: bg,
                    borderMid: borderMid,
                    textLight: textLight,
                    onTap: () => _pickColor('Panels', 'surface'),
                  ),
                  // Only 3 of the 5 kCoreColorSlots entries are surfaced as
                  // individual _QuickColorTile rows here (accent, bg,
                  // surface) — 'accentGreen' and 'textLight' are present in
                  // the kCoreColorSlots constant but not built into
                  // dedicated tiles in this build() method, so that data
                  // list is broader than what's actually rendered as quick
                  // tiles right now.

                  const SizedBox(height: 8),
                  Text('Background depth',
                      style: GoogleFonts.orbitron(color: textMid, fontSize: 9, letterSpacing: 1.5)),
                  Slider(
                    value: _bgDepth,
                    min: -1,
                    max: 1,
                    divisions: 8,
                    // 8 discrete steps across the -1..1 range (0.25 per
                    // step) rather than a continuous drag — makes it easier
                    // to land exactly back on 0 ("Default").
                    label: _bgDepth == 0 ? 'Default' : (_bgDepth > 0 ? 'Lighter' : 'Darker'),
                    // The floating value bubble shown while dragging reads
                    // as a word ("Lighter"/"Darker"/"Default"), not the raw
                    // numeric slider value.
                    onChanged: (v) {
                      setState(() => _bgDepth = v);
                      widget.notifier.applyBackgroundDepth(v, baseTheme: _baselineTheme);
                    },
                  ),

                  Text('Text contrast',
                      style: GoogleFonts.orbitron(color: textMid, fontSize: 9, letterSpacing: 1.5)),
                  Slider(
                    value: _textContrast,
                    min: -1,
                    max: 1,
                    divisions: 8,
                    label: _textContrast == 0 ? 'Balanced' : (_textContrast > 0 ? 'Sharper' : 'Softer'),
                    onChanged: (v) {
                      setState(() => _textContrast = v);
                      widget.notifier.applyTextContrast(v, baseTheme: _baselineTheme);
                    },
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Use accent for simulation highlights',
                        style: GoogleFonts.sourceCodePro(color: textLight, fontSize: 13)),
                    subtitle: Text('Nodes, lines, and simulator chips',
                        style: GoogleFonts.sourceCodePro(color: textDim, fontSize: 11)),
                    value: _linkHighlights ||
                        (_live.nodeBorderHighlight == _live.accent &&
                            _live.lineHighlight == _live.accent),
                    // The switch's displayed value isn't purely the local
                    // `_linkHighlights` flag — it's OR'd with a live check
                    // of whether the highlight colors *already happen to*
                    // equal the accent color, so the switch correctly shows
                    // "on" even if that equality arose some other way (e.g.
                    // a preset whose highlight colors coincidentally match
                    // its own accent) rather than only via this specific
                    // toggle having been flipped during this session.
                    activeThumbColor: accent,
                    activeTrackColor: accent.withValues(alpha: 0.35),
                    onChanged: (v) {
                      setState(() => _linkHighlights = v);
                      widget.notifier.setLinkHighlightsToAccent(v);
                    },
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Flash highlights',
                        style: GoogleFonts.sourceCodePro(color: textLight, fontSize: 13)),
                    subtitle: Text(
                      'Pulse highlighted, duplicate, and error states instead of a '
                      'static color — helps with color blindness or easy-to-miss cues',
                      style: GoogleFonts.sourceCodePro(color: textDim, fontSize: 11),
                    ),
                    value: widget.notifier.flashHighlights,
                    // Unlike the switch above, this one's value is read
                    // directly off the notifier with no local-state OR —
                    // flashHighlights is a simple independent bool with no
                    // equivalent "could also be true via some other
                    // combination of colors" ambiguity to account for.
                    activeThumbColor: accent,
                    activeTrackColor: accent.withValues(alpha: 0.35),
                    onChanged: (v) => widget.notifier.setFlashHighlights(v),
                  ),

                  const SizedBox(height: 8),
                  Material(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    // Material wrapper needed so ExpansionTile's own
                    // ink-splash/expand-collapse animations render
                    // correctly with this custom background/radius rather
                    // than Material's own default surface color.
                    child: ExpansionTile(
                      initiallyExpanded: _advancedOpen,
                      onExpansionChanged: (v) => setState(() => _advancedOpen = v),
                      // Mirrors the tile's own expanded/collapsed state back
                      // into `_advancedOpen` — necessary so that state
                      // survives this widget's own rebuilds (e.g. triggered
                      // by _onNotifierChanged firing while Advanced happens
                      // to be open), since ExpansionTile would otherwise
                      // reset to `initiallyExpanded`'s value on every fresh
                      // build if that state weren't fed back in.
                      iconColor: accent,
                      collapsedIconColor: textMid,
                      title: Text(
                        'Advanced colors',
                        style: GoogleFonts.orbitron(
                          color: textLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      subtitle: Text(
                        'Nodes, lines, level map, tags, and more',
                        style: GoogleFonts.sourceCodePro(color: textMid, fontSize: 11),
                      ),
                      children: [
                        for (final entry in advancedGroups.entries) ...[
                          // Iterates the grouped Map built earlier — each
                          // `entry.key` is a group name ('Canvas', 'Text',
                          // ...), `entry.value` the list of color slots in
                          // that group.
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: GoogleFonts.orbitron(
                                color: accent.withValues(alpha: 0.65),
                                fontSize: 8,
                                letterSpacing: 2,
                              ),
                            ),
                            // A miniature sub-heading for each group,
                            // smaller/dimmer than the outer _SectionTitle
                            // widgets — establishing a two-level heading
                            // hierarchy within the single "Advanced colors"
                            // expansion.
                          ),
                          for (final slot in entry.value)
                            _ColorRow(
                              label: slot.label,
                              color: _colorForKey(slot.key),
                              onColorChanged: (c) => widget.notifier.setColor(slot.key, c),
                              textLight: textLight,
                              textMid: textMid,
                              borderMid: borderMid,
                              bg: bg,
                              surface: surface,
                            ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.orbitron(
        color: accent.withValues(alpha: 0.85),
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.5,
      ),
    );
  }
  // Small reusable heading widget for this sheet's top-level sections
  // ('Color palettes', 'Quick customize') — parallel in spirit to
  // automata_drawer.dart's `_SectionLabel`, though styled independently
  // (Orbitron + accent-tinted here, vs. courierPrime + textDim there)
  // since this sheet uses its own distinct visual language.
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = preset.data;
    // Every color used inside this card comes from the *preset's own*
    // AppThemeData (`preset.data`), not from the ambient/live theme — so
    // each card in the horizontal carousel renders using its own colors
    // (a self-contained preview), including while some *other* theme is
    // currently active.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 108,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? d.accent : d.borderMid,
            width: selected ? 2 : 1,
          ),
          // Selection is indicated purely via this preset's *own* accent-
          // colored border getting thicker — no external "selected" tint
          // color from the currently-active theme is used, keeping the
          // whole card visually self-consistent with the theme it's
          // previewing.
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Swatch(d.bg),
                const SizedBox(width: 3),
                _Swatch(d.accent),
                const SizedBox(width: 3),
                _Swatch(d.accentGreen),
                // Three small color swatches (bg / accent / accentGreen)
                // as a quick visual fingerprint of the theme, rather than
                // trying to preview the full 33-color palette in this
                // small card.
              ],
            ),
            const Spacer(),
            // Pushes the name/description text down to the bottom of the
            // fixed-width card, below the swatches, regardless of how many
            // description lines there end up being (bounded by maxLines
            // below anyway).
            Text(
              preset.name,
              style: GoogleFonts.orbitron(
                color: d.textLight,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            Text(
              preset.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.sourceCodePro(
                color: d.textDim,
                fontSize: 9,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
        // Hardcoded translucent white border (not theme-driven) — a
        // pragmatic choice so the swatch's own outline stays visible
        // regardless of which preset's colors it's displaying (a
        // preset-driven border color risks near-invisible outlines for
        // colors close to that same preset's own borderMid).
      ),
    );
  }
}

class _QuickColorTile extends StatelessWidget {
  const _QuickColorTile({
    required this.label,
    required this.color,
    required this.bg,
    required this.borderMid,
    required this.textLight,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color bg;
  final Color borderMid;
  final Color textLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderMid),
        ),
        // The tile's leading swatch is the *only* visual preview of the
        // current color — no hex text shown here, unlike _ColorRow below
        // which does display the hex value; Quick tiles favor a simpler,
        // larger swatch over textual precision.
      ),
      title: Text(label, style: GoogleFonts.sourceCodePro(color: textLight, fontSize: 14)),
      trailing: Icon(Icons.chevron_right, color: borderMid),
      // Chevron affordance signaling "tapping opens something further" —
      // consistent with this being a full ListTile (which Material
      // typically pairs with drill-down navigation), even though it
      // actually opens a dialog, not a new screen.
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onColorChanged,
    required this.textLight,
    required this.textMid,
    required this.borderMid,
    required this.bg,
    required this.surface,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final Color textLight;
  final Color textMid;
  final Color borderMid;
  final Color bg;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    // toARGB32() -> 32-bit int -> hex string, left-padded to 8 digits (in
    // case leading zero bytes would otherwise be dropped by
    // toRadixString), then `.substring(2)` strips the leading 2-digit
    // alpha channel so only the 6-digit RGB portion is displayed —
    // alpha isn't shown in this compact advanced-color-list row (contrast
    // with _ColorPickerDialog's own hex field below, which does include
    // alpha).

    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => _ColorPickerDialog(
            initial: color,
            label: label,
            onChanged: onColorChanged,
            textLight: textLight,
            textMid: textMid,
            borderMid: borderMid,
            bg: bg,
            surface: surface,
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderMid),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderMid),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.sourceCodePro(color: textLight, fontSize: 12),
              ),
            ),
            Text(hex,
                style: GoogleFonts.sourceCodePro(color: textMid, fontSize: 10)),
            // Hex value shown as trailing text, unlike _QuickColorTile's
            // chevron — these advanced rows are denser/more information-
            // rich per row, appropriate given there can be ~28 of them
            // versus only 3 quick tiles.
          ],
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initial,
    required this.label,
    required this.onChanged,
    required this.textLight,
    required this.textMid,
    required this.borderMid,
    required this.bg,
    required this.surface,
  });

  final Color initial;
  final String label;
  final ValueChanged<Color> onChanged;
  final Color textLight;
  final Color textMid;
  final Color borderMid;
  final Color bg;
  final Color surface;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _r, _g, _b, _a;
  // Each RGBA channel tracked as its own separate double (0-255 range,
  // matching Slider's native double value type) rather than storing a
  // single Color and deriving channel values on demand — makes each
  // channel's Slider a simple direct two-way binding.
  late TextEditingController _hexController;
  bool _hexError = false;

  @override
  void initState() {
    super.initState();
    _r = (widget.initial.r * 255.0).round().clamp(0, 255).toDouble();
    _g = (widget.initial.g * 255.0).round().clamp(0, 255).toDouble();
    _b = (widget.initial.b * 255.0).round().clamp(0, 255).toDouble();
    _a = (widget.initial.a * 255.0).round().clamp(0, 255).toDouble();
    // `.r`/`.g`/`.b`/`.a` on Color in this Flutter version are normalized
    // floats in [0.0, 1.0], not legacy 0-255 ints — so each is scaled back
    // up to 0-255, rounded to the nearest int, clamped (defensively, in
    // case of any floating-point rounding pushing slightly outside range),
    // and converted back to a double for Slider compatibility.
    _hexController = TextEditingController(text: _toHex());
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _current => Color.fromARGB(
        _a.round().clamp(0, 255),
        _r.round().clamp(0, 255),
        _g.round().clamp(0, 255),
        _b.round().clamp(0, 255),
      );
  // The single source of truth this whole dialog converges toward — every
  // slider/hex-field change ultimately updates _r/_g/_b/_a, and `_current`
  // recomputes the resulting Color fresh on every access (a getter, not a
  // cached field) from whatever those four doubles currently hold.

  String _toHex() =>
      _current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  // Same ARGB-int -> hex-string -> strip-alpha-prefix technique as
  // _ColorRow's `hex` computation above, reused here for the picker's own
  // hex text field (though note: unlike _ColorRow, this dialog's actual
  // color model *does* track alpha via `_a` — only the *displayed* hex
  // string omits it, matching the 6-digit RGB-only format the hex
  // TextField accepts via _applyHex below).

  void _syncHexField() {
    final hex = _toHex();
    if (_hexController.text.toUpperCase() != hex) {
      // Only rewrites the text field if the computed hex actually differs
      // from what's currently displayed (case-insensitively) — avoids an
      // unnecessary TextEditingController.text assignment (which would
      // otherwise reset cursor position / potentially trigger extra
      // rebuilds) when a slider drag hasn't actually changed the resulting
      // hex value. More importantly, this guard is what prevents fighting
      // with the user's own typing in the hex field itself, see _applyHex
      // below.
      _hexController.text = hex;
      _hexController.selection = TextSelection.collapsed(offset: hex.length);
      // Explicitly re-positions the cursor to the end after programmatically
      // rewriting `.text` — without this, Flutter would otherwise reset the
      // cursor to position 0, which would be jarring if the user is
      // actively looking at/editing this field while a slider elsewhere
      // updates it.
    }
  }

  void _applyHex(String raw) {
    final cleaned = raw.replaceAll('#', '').trim();
    if (cleaned.length == 6 || cleaned.length == 8) {
      // Accepts either a 6-digit RGB-only hex or an 8-digit ARGB hex —
      // matching what the TextField's own maxLength: 8 and its `#` prefix
      // display (see build() below) allow the user to type.
      final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
      // A bare 6-digit RGB hex is assumed fully opaque (`FF` alpha
      // prefix) — consistent with _toHex()/the hex field display never
      // showing an alpha prefix by default, so a 6-digit paste round-trips
      // as "same RGB, full opacity" rather than inheriting whatever alpha
      // happened to be set before.
      final value = int.tryParse(full, radix: 16);
      if (value != null) {
        final c = Color(value);
        setState(() {
          _r = (c.r * 255.0).round().clamp(0, 255).toDouble();
          _g = (c.g * 255.0).round().clamp(0, 255).toDouble();
          _b = (c.b * 255.0).round().clamp(0, 255).toDouble();
          _a = (c.a * 255.0).round().clamp(0, 255).toDouble();
          // Same float-to-255-scale-and-round conversion as initState()
          // above, run again here to update the RGBA sliders from the
          // newly-parsed hex value.
          _hexError = false;
        });
        return;
      }
    }
    setState(() => _hexError = true);
    // Any failure path (wrong length, or a value int.tryParse couldn't
    // parse — e.g. non-hex characters, though the TextField's own
    // inputFormatters below should already prevent most of those) lands
    // here, flipping on the "Invalid hex" error text shown in build().
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: widget.borderMid),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label.toUpperCase(),
              style: GoogleFonts.orbitron(
                color: widget.textLight,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
              // Dialog title is whatever descriptive label the caller
              // passed in (e.g. "Node border (selected)") rather than a
              // generic "Choose color" — so the user always knows exactly
              // which of the ~33 theme slots they're currently editing.
            ),
            const SizedBox(height: 16),
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.borderMid),
                color: _current,
                // Live preview swatch — reflects `_current`, so it updates
                // in real time as either the sliders or the hex field
                // change the underlying RGBA values.
              ),
            ),
            const SizedBox(height: 16),
            _slider('R', Colors.red, _r, (v) => setState(() => _r = v)),
            _slider('G', Colors.green, _g, (v) => setState(() => _g = v)),
            _slider('B', Colors.blue, _b, (v) => setState(() => _b = v)),
            _slider('A', widget.textMid, _a, (v) => setState(() => _a = v)),
            // Three channel sliders each tracked with a distinct hardcoded
            // track color (red/green/blue) matching their letter — the
            // Alpha slider instead uses the dialog's own textMid theme
            // color, since "alpha" has no natural hue of its own to
            // represent.
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              maxLength: 8,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                // Restricts keystrokes to hex digits and '#' only — invalid
                // characters are rejected at the input-formatter level
                // before they even reach `.text`, rather than being
                // accepted and only caught later in _applyHex's parsing.
              ],
              style: GoogleFonts.sourceCodePro(
                  color: widget.textLight, fontSize: 14, letterSpacing: 2),
              decoration: InputDecoration(
                prefixText: '#',
                labelText: 'HEX',
                counterText: '',
                // Empty string (not null) suppresses Flutter's default
                // "x/8" character-counter text that maxLength would
                // otherwise show beneath the field.
                errorText: _hexError ? 'Invalid hex' : null,
                filled: true,
                fillColor: widget.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.borderMid)),
              ),
              onChanged: (v) {
                setState(() => _hexError = false);
                // Clears any stale error as soon as the user resumes
                // typing, even before knowing whether this new value is
                // valid — avoids the error message lingering visually
                // "stuck" while they're mid-edit toward a valid value.
                if (v.replaceAll('#', '').length >= 6) _applyHex(v);
                // Only attempts to parse/apply once at least 6 hex
                // characters have been entered (a complete RGB value) —
                // typing "3" through "33FF0" doesn't trigger a premature
                // "Invalid hex" error on every partial keystroke; only once
                // there's enough input to plausibly be a real value does
                // parsing (and therefore error-flagging) kick in.
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                  // Note: "Cancel" only closes the dialog — it does NOT
                  // revert widget.onChanged calls that already fired while
                  // dragging sliders (each slider's onChanged calls
                  // widget.onChanged(_current) — see _slider below —
                  // immediately, live). So despite the Cancel/Apply button
                  // pair suggesting a commit-or-discard model, any color
                  // actually applied via a slider drag has already taken
                  // effect on the real theme by the time Cancel is tapped;
                  // only edits made purely by typing in the hex field
                  // without ever touching a slider would be "cancelable"
                  // in the sense of never having called onChanged at all.
                ),
                FilledButton(
                  onPressed: () {
                    widget.onChanged(_current);
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    Color track,
    double value,
    ValueChanged<double> onChanged,
  ) {
    // Instance method (not a separate widget class) returning a Widget —
    // a lightweight way to share the R/G/B/A row layout without the
    // overhead of a whole separate StatelessWidget class, at the cost of
    // this method not being reusable outside _ColorPickerDialogState.
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(label,
              style: GoogleFonts.orbitron(
                  color: widget.textMid, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Slider(
            value: value,
            max: 255,
            // No explicit `min:` — Slider defaults min to 0, matching the
            // 0-255 range these channel values live in.
            onChanged: (v) {
              onChanged(v);
              // Updates this dialog's own _r/_g/_b/_a state via the passed-
              // in callback (each of which wraps its update in setState —
              // see the four _slider(...) call sites in build() above).
              _syncHexField();
              // Then immediately re-derives and re-displays the hex text
              // field from the *new* current color — this is what keeps
              // the hex field live-updating as sliders move, using the
              // "only rewrite if actually different" guard inside
              // _syncHexField to avoid disrupting the user if they're
              // simultaneously typing in that field (an edge case, but
              // handled).
            },
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PALETTE FAB
// ═════════════════════════════════════════════════════════════════════════════

/// Themed icon button used in both the sandbox and game-puzzle FAB toolbars.
///
/// Idle:   [AppThemeNotifier.surface] background, [AppThemeNotifier.textDim] icon.
/// Active: tinted background + border glow in [activeColor].
class PaletteFab extends StatelessWidget {
  // This is the widget consumed as `PaletteFab(...)` inside
  // automata_canvas_embed.dart's `_MiniToolbar` (start-arrow / line-mode /
  // delete-mode buttons) — its definition here fleshes out exactly how
  // `active`/`activeColor`/`small` drive its appearance.
  const PaletteFab({
    super.key,
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onPressed,
    this.small = false,
  });

  final Object heroTag;
  final String tooltip;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    final bg   = active ? activeColor.withValues(alpha: 0.14) : theme.surface;
    final fg   = active ? activeColor : theme.textDim;
    final borderColor = active
        ? activeColor.withValues(alpha: 0.7)
        : theme.borderMid;
    final borderWidth = active ? 1.5 : 1.0;
    // Four parallel "idle vs active" pairs computed up front — matches the
    // doc comment above exactly: idle uses theme.surface/theme.textDim/
    // theme.borderMid (fully theme-driven), active swaps every one of
    // those to some function of the caller-supplied `activeColor` instead
    // (14% alpha fill, full-color icon, 70% alpha border, thicker border).

    final size     = small ? 36.0 : 48.0;
    final iconSize = small ? 18.0 : 22.0;
    final radius   = small ?  8.0 : 12.0;
    // Two complete size presets (not a continuous scale) — `small` is a
    // simple boolean toggle between "compact FAB" (used in
    // AutomataCanvasEmbed's _MiniToolbar, which needs to stay unobtrusive
    // floating over canvas content) and "full-size FAB" (the default,
    // presumably for main-screen toolbars with more room).

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        // Smoothly animates between idle/active visual states over 180ms
        // whenever `active` flips — same duration used by _ModeRadioGroup's
        // segment AnimatedContainer in automata_drawer.dart, suggesting a
        // shared "quick toggle transition" timing convention across the app.
        width:  size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ]
              : null,
          // The "glow" mentioned in the class doc comment: a soft,
          // unoffset (no `offset:` specified, defaults to Offset.zero)
          // blurred shadow in activeColor, present only while `active` is
          // true — this is what gives active PaletteFabs their halo look
          // rather than just a plain color/border change.
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onPressed,
            child: Icon(icon, color: fg, size: iconSize),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MainMenuButton — small icon button back to the mode-select ("main menu")
//  screen. Every top-level screen (Sandbox, Game, Study) plants one of these
//  in a corner so switching between modes never requires signing out or
//  hunting through a drawer for a mode-specific link. Styled to match the
//  existing "Appearance" palette IconButton these screens already show, so it
//  drops in as a natural neighbor rather than a new visual element.
// ─────────────────────────────────────────────────────────────────────────────

class MainMenuButton extends StatelessWidget {
  const MainMenuButton({
    super.key,
    required this.onPressed,
    this.size = 20,
  });

  /// Navigates back to [ModeSelectScreen]. The button renders disabled
  /// (rather than disappearing) when null, so layouts stay stable even if a
  /// caller hasn't wired it up yet.
  final VoidCallback? onPressed;
  // Nullable, and per the doc comment, deliberately left in the widget
  // tree (as a disabled IconButton) rather than the caller conditionally
  // omitting this widget entirely when there's nothing to navigate to —
  // this keeps whatever fixed-position row of corner buttons a screen
  // builds from reflowing/shifting if this one button happens to have no
  // handler in some context.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return IconButton(
      tooltip: 'Main menu',
      icon: Icon(Icons.home_rounded, color: theme.textMid, size: size),
      onPressed: onPressed,
      // Passing `onPressed` straight through, including when it's null —
      // Flutter's IconButton natively renders as visually disabled
      // (dimmed, non-interactive) when its onPressed is null, which is
      // exactly the "renders disabled... when null" behavior the doc
      // comment describes; no extra logic needed here to achieve that.
    );
  }
}