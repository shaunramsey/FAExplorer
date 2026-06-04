import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Built-in palette the user can switch to in one tap.
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

/// Preset palettes (dark cyberpunk default + alternates).
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
