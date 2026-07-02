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

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  THEME MODEL & NOTIFIER
// ═════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
//  AppThemeData — every customizable color in the app
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeData {
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

  // ── Core UI ───────────────────────────────────────────────────────────────
  final Color bg;
  final Color gridLine;
  final Color accent;
  final Color accentGreen;
  final Color textDim;
  final Color textMid;
  final Color textLight;
  final Color surface;
  final Color border;
  final Color borderMid;

  // ── Automata canvas (nodes & lines) ─────────────────────────────────────
  final Color nodeBorder;
  final Color nodeBorderSelected;
  final Color nodeBorderHighlight;
  final Color nodeBorderDuplicate;
  final Color nodeBorderDelete;
  final Color lineColor;
  final Color lineHighlight;
  final Color acceptState;
  final Color rejectState;

  // ── Level-select map edges ──────────────────────────────────────────────
  final Color edgeDim;
  final Color edgeActive;
  final Color edgeBright;
  final Color edgeAlmost;
  final Color edgeBlocking;

  // ── Level type tags ─────────────────────────────────────────────────────
  final Color tagIntro;
  final Color tagDfa;
  final Color tagNfa;
  final Color tagPda;
  final Color tagTm;
  final Color tagBoss;
  final Color tagDefault;

  // ── Semantic ──────────────────────────────────────────────────────────────
  final Color error;
  final Color warning;
  final Color panelHighlight;

  bool get isLightTheme => bg.computeLuminance() > 0.45;

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
    }
  }

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

  factory AppThemeData.midnight() => AppThemeData.cyberDark().copyWith(
    bg: const Color(0xFF030510),
    surface: const Color(0xFF080C16),
    accent: const Color(0xFF8B5CF6),
    accentGreen: const Color(0xFF34D399),
    panelHighlight: const Color(0xFFA78BFA),
    nodeBorderHighlight: const Color(0xFFA78BFA),
    lineHighlight: const Color(0xFFA78BFA),
    tagIntro: const Color(0xFF8B5CF6),
    tagTm: const Color(0xFFC084FC),
  );

  factory AppThemeData.ocean() => AppThemeData.cyberDark().copyWith(
    bg: const Color(0xFF041018),
    accent: const Color(0xFF22D3EE),
    accentGreen: const Color(0xFF2DD4BF),
    edgeActive: const Color(0xFF14B8A6),
    edgeBright: const Color(0xFF2DD4BF),
    tagIntro: const Color(0xFF22D3EE),
    tagDfa: const Color(0xFF34D399),
    panelHighlight: const Color(0xFF06B6D4),
    nodeBorderHighlight: const Color(0xFF06B6D4),
    lineHighlight: const Color(0xFF06B6D4),
  );

  factory AppThemeData.ember() => AppThemeData.cyberDark().copyWith(
    bg: const Color(0xFF0C0806),
    surface: const Color(0xFF14100C),
    accent: const Color(0xFFFFB020),
    accentGreen: const Color(0xFF84CC16),
    edgeBlocking: const Color(0xFFFF6B35),
    edgeAlmost: const Color(0xFFFFB020),
    tagIntro: const Color(0xFFFFB020),
    tagNfa: const Color(0xFFFFD166),
    panelHighlight: const Color(0xFFFF8C42),
    nodeBorderHighlight: const Color(0xFFFF8C42),
    lineHighlight: const Color(0xFFFF8C42),
  );

  factory AppThemeData.defaults() => AppThemeData.cyberDark();

  Map<String, dynamic> toJson() => {
    'bg': bg.toARGB32(),
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

  factory AppThemeData.fromJson(Map<String, dynamic> json) {
    final base = AppThemeData.defaults();
    Color c(String key, Color fallback) =>
        Color((json[key] as int?) ?? fallback.toARGB32());
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

  /// Shifts backgrounds darker/lighter together (amount -1..1).
  AppThemeData withBackgroundDepth(double amount, {AppThemeData? baseTheme}) {
    final base = baseTheme ?? this;
    Color shift(Color c, Color baselineColor, double amt) {
      final hsl = HSLColor.fromColor(baselineColor);
      final l = (hsl.lightness + amt).clamp(0.02, 0.98);
      return hsl.withLightness(l).toColor();
    }
    return copyWith(
      bg: shift(bg, base.bg, amount * 0.08),
      surface: shift(surface, base.surface, amount * 0.07),
      gridLine: shift(gridLine, base.gridLine, amount * 0.06),
      border: shift(border, base.border, amount * 0.05),
      borderMid: shift(borderMid, base.borderMid, amount * 0.05),
    );
  }

  /// Adjust text readability together while keeping contrast readable.
  AppThemeData withTextContrast(double amount, {AppThemeData? baseTheme}) {
    final base = baseTheme ?? this;
    final bg = base.bg;

    Color shift(Color color, Color baselineColor, double amt, {required double minRatio}) {
      final hsl = HSLColor.fromColor(baselineColor);
      final targetLightness = (hsl.lightness + amt).clamp(0.02, 0.98);
      final adjusted = hsl.withLightness(targetLightness).toColor();
      return _ensureReadableContrast(adjusted, bg, minRatio: minRatio);
    }

    final delta = amount * 0.08;
    return copyWith(
      textDim: shift(textDim, base.textDim, -delta * 0.8, minRatio: 2.4),
      textMid: shift(textMid, base.textMid, delta * 0.5, minRatio: 3.2),
      textLight: shift(textLight, base.textLight, delta, minRatio: 4.4),
    );
  }

  static Color _ensureReadableContrast(Color color, Color background, {required double minRatio}) {
    final source = HSLColor.fromColor(color);
    final bgLum = background.computeLuminance();
    final targetIsDarker = bgLum > 0.5;

    double lightness = source.lightness;
    for (var i = 0; i < 80; i++) {
      final candidate = HSLColor.fromAHSL(
        source.alpha,
        source.hue,
        source.saturation,
        lightness,
      ).toColor();
      if (_contrastRatio(candidate, background) >= minRatio) {
        return candidate;
      }
      lightness = (lightness + (targetIsDarker ? -0.01 : 0.01)).clamp(0.02, 0.98);
    }

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
  }

  static double _relativeLuminance(Color color) {
    final r = color.r <= 0.03928 ? color.r / 12.92 : math.pow((color.r + 0.055) / 1.055, 2.4).toDouble();
    final g = color.g <= 0.03928 ? color.g / 12.92 : math.pow((color.g + 0.055) / 1.055, 2.4).toDouble();
    final b = color.b <= 0.03928 ? color.b / 12.92 : math.pow((color.b + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  AppThemeData withLinkedHighlights() => copyWith(
        panelHighlight: accent,
        nodeBorderHighlight: accent,
        lineHighlight: accent,
        tagIntro: accent,
      );
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

List<({String key, String label, String group})> get kAllColorSlots => [
      ...kCoreColorSlots,
      ...kAdvancedColorSlots,
    ];

// ─────────────────────────────────────────────────────────────────────────────
//  AppThemeNotifier
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeNotifier extends ChangeNotifier {
  AppThemeNotifier._(this._data, this._prefs, this._presetId);

  AppThemeData _data;
  final SharedPreferences _prefs;
  String? _presetId;

  static const _prefsKeyV2 = 'app_theme_v2';
  static const _prefsKeyPreset = 'app_theme_preset_id';

  static Future<AppThemeNotifier> load() async {
    final prefs = await SharedPreferences.getInstance();
    final presetId = prefs.getString(_prefsKeyPreset);
    AppThemeData data;

    final rawV2 = prefs.getString(_prefsKeyV2);
    if (rawV2 != null && rawV2.isNotEmpty) {
      try {
        data = AppThemeData.fromJson(jsonDecode(rawV2) as Map<String, dynamic>);
      } catch (_) {
        data = AppThemeData.defaults();
      }
    } else {
      final rawV1 = prefs.getString('app_theme_v1');
      if (rawV1 != null && rawV1.isNotEmpty) {
        try {
          data = AppThemeData.fromJson(jsonDecode(rawV1) as Map<String, dynamic>);
        } catch (_) {
          data = AppThemeData.defaults();
        }
      } else {
        data = presetById(presetId)?.data ?? AppThemeData.defaults();
      }
    }

    return AppThemeNotifier._(data, prefs, presetId);
  }

  AppThemeData get data => _data;
  String? get activePresetId => _presetId;

  // Core getters (backward compatible)
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

  Color tagColor(String? tag) => _data.tagColor(tag);

  Future<void> applyPreset(String presetId) async {
    final preset = presetById(presetId);
    if (preset == null) return;
    _data = preset.data;
    _presetId = presetId;
    notifyListeners();
    await _persist();
  }

  Future<void> setColor(String key, Color color) async {
    _data = _applyKey(_data, key, color);
    _presetId = null;
    notifyListeners();
    await _persist();
  }

  Future<void> applyQuickAccent(Color accent) async {
    _data = _data.copyWith(accent: accent, tagIntro: accent);
    _presetId = null;
    notifyListeners();
    await _persist();
  }

  Future<void> setLinkHighlightsToAccent(bool linked) async {
    if (linked) {
      _data = _data.withLinkedHighlights();
    } else {
      final base = presetById(_presetId)?.data ?? AppThemeData.defaults();
      _data = _data.copyWith(
        panelHighlight: base.panelHighlight,
        nodeBorderHighlight: base.nodeBorderHighlight,
        lineHighlight: base.lineHighlight,
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

  Future<void> resetToDefaults() async {
    _data = AppThemeData.defaults();
    _presetId = 'dark';
    notifyListeners();
    await _prefs.remove(_prefsKeyV2);
    await _prefs.setString(_prefsKeyPreset, 'dark');
  }

  Future<void> _persist() async {
    await _prefs.setString(_prefsKeyV2, jsonEncode(_data.toJson()));
    if (_presetId != null) {
      await _prefs.setString(_prefsKeyPreset, _presetId!);
    } else {
      await _prefs.remove(_prefsKeyPreset);
    }
  }

  static AppThemeData _applyKey(AppThemeData d, String key, Color c) {
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
    }
  }

  static AppThemeNotifier of(BuildContext context) =>
      context.watch<AppThemeNotifier>();

  static AppThemeNotifier read(BuildContext context) =>
      context.read<AppThemeNotifier>();
}

// ── Theme presets ───────────────────────────────────────────────────────────

class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.data,
    this.isLight = false,
  });

  final String id;
  final String name;
  final String description;
  final AppThemeData data;
  final bool isLight;
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
    description: 'Deep blues with violet highlights',
    data: AppThemeData.midnight(),
  ),
  ThemePreset(
    id: 'ocean',
    name: 'Ocean',
    description: 'Cool teal and sea-glass accents',
    data: AppThemeData.ocean(),
  ),
  ThemePreset(
    id: 'ember',
    name: 'Ember',
    description: 'Warm amber accents on dark brown',
    data: AppThemeData.ember(),
  ),
];

ThemePreset? presetById(String? id) {
  if (id == null) return null;
  for (final p in kThemePresets) {
    if (p.id == id) return p;
  }
  return null;
}

ThemeData buildMaterialTheme(AppThemeData c) {
  final base = c.isLightTheme ? ThemeData.light() : ThemeData.dark();

  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    cardColor: c.surface,
    colorScheme: (c.isLightTheme ? ColorScheme.light : ColorScheme.dark)(
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
      titleTextStyle: GoogleFonts.orbitron(
        color: c.accent,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
      ),
      iconTheme: IconThemeData(color: c.textMid),
      systemOverlayStyle:
          c.isLightTheme ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
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
      labelStyle: GoogleFonts.orbitron(color: c.textMid, fontSize: 12, letterSpacing: 1),
      hintStyle: GoogleFonts.sourceCodePro(color: c.textDim, fontSize: 13),
      errorStyle: GoogleFonts.sourceCodePro(color: c.error, fontSize: 11),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent.withValues(alpha: 0.12),
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
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    textTheme: GoogleFonts.orbitronTextTheme(base.textTheme).copyWith(
      bodyLarge: GoogleFonts.sourceCodePro(color: c.textLight, fontSize: 14),
      bodyMedium: GoogleFonts.sourceCodePro(color: c.textMid, fontSize: 13),
      bodySmall: GoogleFonts.sourceCodePro(color: c.textDim, fontSize: 11),
      labelLarge: GoogleFonts.orbitron(
        color: c.textLight,
        fontSize: 12,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: GoogleFonts.orbitron(color: c.textMid, fontSize: 10, letterSpacing: 1.2),
      labelSmall: GoogleFonts.orbitron(color: c.textDim, fontSize: 8, letterSpacing: 1.0),
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
  if (popRoute) Navigator.of(context).pop();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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
  late AppThemeData _baselineTheme;
  bool _advancedOpen = false;
  double _bgDepth = 0;
  double _textContrast = 0;
  bool _linkHighlights = false;

  @override
  void initState() {
    super.initState();
    _live = widget.notifier.data;
    _baselineTheme = _live;
    widget.notifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() => setState(() => _live = widget.notifier.data);

  Color _colorForKey(String key) {
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
    }
  }

  void _pickColor(String label, String key) {
    showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initial: _colorForKey(key),
        label: label,
        onChanged: (c) => widget.notifier.setColor(key, c),
        textLight: _live.textLight,
        textMid: _live.textMid,
        borderMid: _live.borderMid,
        bg: _live.bg,
        surface: _live.surface,
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

    final advancedGroups = <String, List<({String key, String label, String group})>>{};
    for (final slot in kAdvancedColorSlots) {
      advancedGroups.putIfAbsent(slot.group, () => []).add(slot);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: borderMid)),
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
                    },
                  ),
                ],
              ),
            ),
            Divider(color: borderMid, height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _SectionTitle(label: 'Color palettes', accent: accent),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: kThemePresets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final p = kThemePresets[i];
                        final selected = widget.notifier.activePresetId == p.id ||
                            (widget.notifier.activePresetId == null &&
                                p.id == 'dark' &&
                                _live.bg == p.data.bg);
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

                  const SizedBox(height: 8),
                  Text('Background depth',
                      style: GoogleFonts.orbitron(color: textMid, fontSize: 9, letterSpacing: 1.5)),
                  Slider(
                    value: _bgDepth,
                    min: -1,
                    max: 1,
                    divisions: 8,
                    label: _bgDepth == 0 ? 'Default' : (_bgDepth > 0 ? 'Lighter' : 'Darker'),
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
                    activeThumbColor: accent,
                    activeTrackColor: accent.withValues(alpha: 0.35),
                    onChanged: (v) {
                      setState(() => _linkHighlights = v);
                      widget.notifier.setLinkHighlightsToAccent(v);
                    },
                  ),

                  const SizedBox(height: 8),
                  Material(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    child: ExpansionTile(
                      initiallyExpanded: _advancedOpen,
                      onExpansionChanged: (v) => setState(() => _advancedOpen = v),
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
              ],
            ),
            const Spacer(),
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
      ),
      title: Text(label, style: GoogleFonts.sourceCodePro(color: textLight, fontSize: 14)),
      trailing: Icon(Icons.chevron_right, color: borderMid),
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
  late TextEditingController _hexController;
  bool _hexError = false;

  @override
  void initState() {
    super.initState();
    _r = (widget.initial.r * 255.0).round().clamp(0, 255).toDouble();
    _g = (widget.initial.g * 255.0).round().clamp(0, 255).toDouble();
    _b = (widget.initial.b * 255.0).round().clamp(0, 255).toDouble();
    _a = (widget.initial.a * 255.0).round().clamp(0, 255).toDouble();
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

  String _toHex() =>
      _current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  void _syncHexField() {
    final hex = _toHex();
    if (_hexController.text.toUpperCase() != hex) {
      _hexController.text = hex;
      _hexController.selection = TextSelection.collapsed(offset: hex.length);
    }
  }

  void _applyHex(String raw) {
    final cleaned = raw.replaceAll('#', '').trim();
    if (cleaned.length == 6 || cleaned.length == 8) {
      final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
      final value = int.tryParse(full, radix: 16);
      if (value != null) {
        final c = Color(value);
        setState(() {
          _r = (c.r * 255.0).round().clamp(0, 255).toDouble();
          _g = (c.g * 255.0).round().clamp(0, 255).toDouble();
          _b = (c.b * 255.0).round().clamp(0, 255).toDouble();
          _a = (c.a * 255.0).round().clamp(0, 255).toDouble();
          _hexError = false;
        });
        return;
      }
    }
    setState(() => _hexError = true);
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
            ),
            const SizedBox(height: 16),
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.borderMid),
                color: _current,
              ),
            ),
            const SizedBox(height: 16),
            _slider('R', Colors.red, _r, (v) => setState(() => _r = v)),
            _slider('G', Colors.green, _g, (v) => setState(() => _g = v)),
            _slider('B', Colors.blue, _b, (v) => setState(() => _b = v)),
            _slider('A', widget.textMid, _a, (v) => setState(() => _a = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              maxLength: 8,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              ],
              style: GoogleFonts.sourceCodePro(
                  color: widget.textLight, fontSize: 14, letterSpacing: 2),
              decoration: InputDecoration(
                prefixText: '#',
                labelText: 'HEX',
                counterText: '',
                errorText: _hexError ? 'Invalid hex' : null,
                filled: true,
                fillColor: widget.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.borderMid)),
              ),
              onChanged: (v) {
                setState(() => _hexError = false);
                if (v.replaceAll('#', '').length >= 6) _applyHex(v);
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
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
            onChanged: (v) {
              onChanged(v);
              _syncHexField();
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

    final size     = small ? 36.0 : 48.0;
    final iconSize = small ? 18.0 : 22.0;
    final radius   = small ?  8.0 : 12.0;

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
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