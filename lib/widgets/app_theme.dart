// ─────────────────────────────────────────────────────────────────────────────
//  app_theme.dart
//
//  Holds the live color palette for the app and persists it via
//  SharedPreferences.  Import this wherever you currently import the
//  hard-coded constants from main.dart.
//
//  Usage (in main.dart):
//    final themeNotifier = await AppThemeNotifier.load();
//    runApp(
//      ChangeNotifierProvider(
//        create: (_) => themeNotifier,
//        child: const MyApp(),
//      ),
//    );
//
//  Usage (anywhere in the widget tree):
//    final theme = context.watch<AppThemeNotifier>();
//    theme.accent   // live accent Color — widget rebuilds when it changes
//
//    // Or without listening (e.g. in callbacks):
//    context.read<AppThemeNotifier>().setColor('accent', Colors.cyan);
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Default palette (identical to the original constants in main.dart)
// ─────────────────────────────────────────────────────────────────────────────

const _kDefaults = {
  'bg':           0xFF05080F,
  'gridLine':     0xFF0D1620,
  'accent':       0xFF00E5FF,
  'accentGreen':  0xFF1FD99A,
  'textDim':      0xFF8A9BB0,
  'textMid':      0xFFB0BDCC,
  'textLight':    0xFFE8ECF0,
  'surface':      0xFF0A0F18,
  'border':       0xFF141E2A,
  'borderMid':    0xFF1A2535,
};

// ─────────────────────────────────────────────────────────────────────────────
//  AppThemeData — immutable snapshot of every color slot
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
  });

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

  // ── Default factory ───────────────────────────────────────────────────────

  factory AppThemeData.defaults() => AppThemeData(
    bg:           Color(_kDefaults['bg']!),
    gridLine:     Color(_kDefaults['gridLine']!),
    accent:       Color(_kDefaults['accent']!),
    accentGreen:  Color(_kDefaults['accentGreen']!),
    textDim:      Color(_kDefaults['textDim']!),
    textMid:      Color(_kDefaults['textMid']!),
    textLight:    Color(_kDefaults['textLight']!),
    surface:      Color(_kDefaults['surface']!),
    border:       Color(_kDefaults['border']!),
    borderMid:    Color(_kDefaults['borderMid']!),
  );

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'bg':          bg.value,
    'gridLine':    gridLine.value,
    'accent':      accent.value,
    'accentGreen': accentGreen.value,
    'textDim':     textDim.value,
    'textMid':     textMid.value,
    'textLight':   textLight.value,
    'surface':     surface.value,
    'border':      border.value,
    'borderMid':   borderMid.value,
  };

  factory AppThemeData.fromJson(Map<String, dynamic> json) {
    int v(String key) => (json[key] as int?) ?? _kDefaults[key]!;
    return AppThemeData(
      bg:          Color(v('bg')),
      gridLine:    Color(v('gridLine')),
      accent:      Color(v('accent')),
      accentGreen: Color(v('accentGreen')),
      textDim:     Color(v('textDim')),
      textMid:     Color(v('textMid')),
      textLight:   Color(v('textLight')),
      surface:     Color(v('surface')),
      border:      Color(v('border')),
      borderMid:   Color(v('borderMid')),
    );
  }

  // ── CopyWith ──────────────────────────────────────────────────────────────

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
  }) => AppThemeData(
    bg:          bg          ?? this.bg,
    gridLine:    gridLine    ?? this.gridLine,
    accent:      accent      ?? this.accent,
    accentGreen: accentGreen ?? this.accentGreen,
    textDim:     textDim     ?? this.textDim,
    textMid:     textMid     ?? this.textMid,
    textLight:   textLight   ?? this.textLight,
    surface:     surface     ?? this.surface,
    border:      border      ?? this.border,
    borderMid:   borderMid   ?? this.borderMid,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  AppThemeNotifier — ChangeNotifier wrapper; call setColor() to update
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeNotifier extends ChangeNotifier {
  AppThemeNotifier._(this._data, this._prefs);

  AppThemeData _data;
  final SharedPreferences _prefs;

  static const _prefsKey = 'app_theme_v1';

  // ── Load from SharedPreferences (call once at startup) ────────────────────

  static Future<AppThemeNotifier> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    AppThemeData data;
    if (raw != null && raw.isNotEmpty) {
      try {
        data = AppThemeData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        data = AppThemeData.defaults();
      }
    } else {
      data = AppThemeData.defaults();
    }
    return AppThemeNotifier._(data, prefs);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  AppThemeData get data => _data;

  /// Convenience: read individual slots from the notifier directly.
  Color get bg          => _data.bg;
  Color get gridLine    => _data.gridLine;
  Color get accent      => _data.accent;
  Color get accentGreen => _data.accentGreen;
  Color get textDim     => _data.textDim;
  Color get textMid     => _data.textMid;
  Color get textLight   => _data.textLight;
  Color get surface     => _data.surface;
  Color get border      => _data.border;
  Color get borderMid   => _data.borderMid;

  /// Update a single color slot (identified by its key string, see [colorKeys]).
  Future<void> setColor(String key, Color color) async {
    _data = _applyKey(_data, key, color);
    notifyListeners();
    await _persist();
  }

  /// Reset everything to the original defaults.
  Future<void> resetToDefaults() async {
    _data = AppThemeData.defaults();
    notifyListeners();
    await _prefs.remove(_prefsKey);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    await _prefs.setString(_prefsKey, jsonEncode(_data.toJson()));
  }

  static AppThemeData _applyKey(AppThemeData d, String key, Color c) {
    switch (key) {
      case 'bg':          return d.copyWith(bg: c);
      case 'gridLine':    return d.copyWith(gridLine: c);
      case 'accent':      return d.copyWith(accent: c);
      case 'accentGreen': return d.copyWith(accentGreen: c);
      case 'textDim':     return d.copyWith(textDim: c);
      case 'textMid':     return d.copyWith(textMid: c);
      case 'textLight':   return d.copyWith(textLight: c);
      case 'surface':     return d.copyWith(surface: c);
      case 'border':      return d.copyWith(border: c);
      case 'borderMid':   return d.copyWith(borderMid: c);
      default:            return d;
    }
  }

  // ── Provider bridge ───────────────────────────────────────────────────────

  /// Listen for theme changes and rebuild (same as [context.watch]).
  static AppThemeNotifier of(BuildContext context) =>
      context.watch<AppThemeNotifier>();

  /// Read without subscribing — use in callbacks after the widget has built.
  static AppThemeNotifier read(BuildContext context) =>
      context.read<AppThemeNotifier>();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Metadata for the Settings UI
// ─────────────────────────────────────────────────────────────────────────────

/// Every color slot with a user-facing label, grouped by category.
const List<({String key, String label, String group})> kColorSlots = [
  // Background
  (key: 'bg',          label: 'Background',       group: 'Canvas'),
  (key: 'gridLine',    label: 'Grid Lines',        group: 'Canvas'),
  (key: 'surface',     label: 'Surface / Panels',  group: 'Canvas'),
  // Borders
  (key: 'border',      label: 'Border (dark)',     group: 'Borders'),
  (key: 'borderMid',   label: 'Border (mid)',      group: 'Borders'),
  // Accent
  (key: 'accent',      label: 'Accent (cyan)',     group: 'Accent'),
  (key: 'accentGreen', label: 'Accent (green)',    group: 'Accent'),
  // Text
  (key: 'textLight',   label: 'Text (bright)',     group: 'Text'),
  (key: 'textMid',     label: 'Text (mid)',        group: 'Text'),
  (key: 'textDim',     label: 'Text (dim)',        group: 'Text'),
];