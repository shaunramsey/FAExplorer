import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme_presets.dart';

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
    'bg': bg.value,
    'gridLine': gridLine.value,
    'accent': accent.value,
    'accentGreen': accentGreen.value,
    'textDim': textDim.value,
    'textMid': textMid.value,
    'textLight': textLight.value,
    'surface': surface.value,
    'border': border.value,
    'borderMid': borderMid.value,
    'nodeBorder': nodeBorder.value,
    'nodeBorderSelected': nodeBorderSelected.value,
    'nodeBorderHighlight': nodeBorderHighlight.value,
    'nodeBorderDuplicate': nodeBorderDuplicate.value,
    'nodeBorderDelete': nodeBorderDelete.value,
    'lineColor': lineColor.value,
    'lineHighlight': lineHighlight.value,
    'acceptState': acceptState.value,
    'rejectState': rejectState.value,
    'edgeDim': edgeDim.value,
    'edgeActive': edgeActive.value,
    'edgeBright': edgeBright.value,
    'edgeAlmost': edgeAlmost.value,
    'edgeBlocking': edgeBlocking.value,
    'tagIntro': tagIntro.value,
    'tagDfa': tagDfa.value,
    'tagNfa': tagNfa.value,
    'tagPda': tagPda.value,
    'tagTm': tagTm.value,
    'tagBoss': tagBoss.value,
    'tagDefault': tagDefault.value,
    'error': error.value,
    'warning': warning.value,
    'panelHighlight': panelHighlight.value,
  };

  factory AppThemeData.fromJson(Map<String, dynamic> json) {
    final base = AppThemeData.defaults();
    Color c(String key, Color fallback) =>
        Color((json[key] as int?) ?? fallback.value);
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
  AppThemeData withBackgroundDepth(double amount) {
    Color shift(Color c, double amt) {
      final hsl = HSLColor.fromColor(c);
      final l = (hsl.lightness + amt).clamp(0.02, 0.98);
      return hsl.withLightness(l).toColor();
    }
    return copyWith(
      bg: shift(bg, amount * 0.08),
      surface: shift(surface, amount * 0.07),
      gridLine: shift(gridLine, amount * 0.06),
      border: shift(border, amount * 0.05),
      borderMid: shift(borderMid, amount * 0.05),
    );
  }

  /// Adjust text readability together.
  AppThemeData withTextContrast(double amount) {
    Color shift(Color c, double amt) {
      final hsl = HSLColor.fromColor(c);
      final l = (hsl.lightness + amt).clamp(0.05, 0.95);
      return hsl.withLightness(l).toColor();
    }
    final delta = amount * 0.12;
    return copyWith(
      textDim: shift(textDim, -delta),
      textMid: shift(textMid, delta * 0.5),
      textLight: shift(textLight, delta),
    );
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

  Future<void> applyBackgroundDepth(double amount) async {
    _data = _data.withBackgroundDepth(amount);
    _presetId = null;
    notifyListeners();
    await _persist();
  }

  Future<void> applyTextContrast(double amount) async {
    _data = _data.withTextContrast(amount);
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

/// @deprecated Use [AppThemeNotifier.tagColor] or [AppThemeData.tagColor].
Color levelTagColor(String? tag, AppThemeData theme) => theme.tagColor(tag);
