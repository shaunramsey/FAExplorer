// ─────────────────────────────────────────────────────────────────────────────
//  app_theme_settings.dart
//
//  A bottom-sheet settings panel for live-editing every color in the palette.
//  Open it with:
//
//    showAppThemeSettings(context);
//
//  The panel reads/writes via AppThemeNotifier.of(context).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Public entry point
// ─────────────────────────────────────────────────────────────────────────────

void showAppThemeSettings(BuildContext context) {
  // Grab the notifier before closing the drawer (which pops context).
  final notifier = AppThemeNotifier.of(context);

  // Close the drawer first so the sheet slides up cleanly.
  Navigator.of(context).pop();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AppThemeSettingsSheet(notifier: notifier),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  AppThemeSettingsSheet
// ─────────────────────────────────────────────────────────────────────────────

class AppThemeSettingsSheet extends StatefulWidget {
  const AppThemeSettingsSheet({super.key, required this.notifier});

  final AppThemeNotifier notifier;

  @override
  State<AppThemeSettingsSheet> createState() => _AppThemeSettingsSheetState();
}

class _AppThemeSettingsSheetState extends State<AppThemeSettingsSheet> {
  late AppThemeData _live;

  @override
  void initState() {
    super.initState();
    _live = widget.notifier.data;
    widget.notifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() => setState(() => _live = widget.notifier.data);

  Color _colorForKey(String key) {
    switch (key) {
      case 'bg':          return _live.bg;
      case 'gridLine':    return _live.gridLine;
      case 'accent':      return _live.accent;
      case 'accentGreen': return _live.accentGreen;
      case 'textDim':     return _live.textDim;
      case 'textMid':     return _live.textMid;
      case 'textLight':   return _live.textLight;
      case 'surface':     return _live.surface;
      case 'border':      return _live.border;
      case 'borderMid':   return _live.borderMid;
      default:            return Colors.transparent;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bg      = _live.bg;
    final surface = _live.surface;
    final accent  = _live.accent;
    final textLight = _live.textLight;
    final textMid   = _live.textMid;
    final borderMid = _live.borderMid;

    // Group the slots by category for visual structure.
    final groups = <String, List<({String key, String label, String group})>>{};
    for (final slot in kColorSlots) {
      groups.putIfAbsent(slot.group, () => []).add(slot);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: borderMid, width: 1)),
        ),
        child: Column(
          children: [
            // ── Handle ────────────────────────────────────────────────────
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
            const SizedBox(height: 12),

            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, color: accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'COLOR SETTINGS',
                      style: GoogleFonts.orbitron(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  // Reset to defaults
                  Tooltip(
                    message: 'Reset all colors to defaults',
                    child: IconButton(
                      icon: Icon(Icons.restart_alt, color: textMid, size: 20),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: surface,
                            title: Text(
                              'Reset colors?',
                              style: GoogleFonts.orbitron(color: textLight, fontSize: 13, letterSpacing: 1),
                            ),
                            content: Text(
                              'All color settings will return to the original defaults.',
                              style: GoogleFonts.sourceCodePro(color: textMid, fontSize: 13),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Reset'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await widget.notifier.resetToDefaults();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: borderMid, height: 1),
            const SizedBox(height: 4),

            // ── Scrollable content ────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  for (final groupEntry in groups.entries) ...[
                    _GroupHeader(label: groupEntry.key, accent: accent),
                    const SizedBox(height: 4),
                    for (final slot in groupEntry.value)
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
                    const SizedBox(height: 8),
                  ],
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
//  _GroupHeader
// ─────────────────────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.orbitron(
          color: accent.withOpacity(0.7),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ColorRow — a single color slot row with swatch + hex picker
// ─────────────────────────────────────────────────────────────────────────────

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

  void _openPicker(BuildContext context) {
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
  }

  @override
  Widget build(BuildContext context) {
    final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    return InkWell(
      onTap: () => _openPicker(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderMid),
        ),
        child: Row(
          children: [
            // Color swatch
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderMid, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),

            // Label
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.sourceCodePro(
                  color: textLight,
                  fontSize: 13,
                ),
              ),
            ),

            // Hex value
            Text(
              hex,
              style: GoogleFonts.sourceCodePro(
                color: textMid,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: textMid, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ColorPickerDialog
//
//  Sliders (R, G, B, A) + live hex input.  No third-party package needed.
// ─────────────────────────────────────────────────────────────────────────────

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
    _r = widget.initial.red.toDouble();
    _g = widget.initial.green.toDouble();
    _b = widget.initial.blue.toDouble();
    _a = widget.initial.alpha.toDouble();
    _hexController = TextEditingController(text: _toHex());
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _current => Color.fromARGB(_a.round(), _r.round(), _g.round(), _b.round());

  String _toHex() {
    final c = _current;
    return c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  }

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
          _r = c.red.toDouble();
          _g = c.green.toDouble();
          _b = c.blue.toDouble();
          _a = c.alpha.toDouble();
          _hexError = false;
        });
        return;
      }
    }
    setState(() => _hexError = true);
  }

  Widget _slider({
    required String label,
    required Color trackColor,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: GoogleFonts.orbitron(color: widget.textMid, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: trackColor,
              inactiveTrackColor: trackColor.withOpacity(0.2),
              thumbColor: trackColor,
              overlayColor: trackColor.withOpacity(0.15),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => onChanged(v));
                _syncHexField();
              },
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: GoogleFonts.sourceCodePro(color: widget.textMid, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.surface;
    final textLight = widget.textLight;
    final textMid = widget.textMid;
    final borderMid = widget.borderMid;

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderMid),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              widget.label.toUpperCase(),
              style: GoogleFonts.orbitron(
                color: textLight,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),

            // Preview swatch (full width, gradient to show alpha)
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderMid),
                // Checkerboard-ish dark pattern for alpha transparency cue
                gradient: LinearGradient(
                  colors: [_current, _current.withOpacity(0)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Expanded(child: Container(color: _current)),
                    Container(
                      width: 40,
                      color: widget.bg,
                      alignment: Alignment.center,
                      child: Text('α', style: GoogleFonts.orbitron(color: textMid, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // RGBA sliders
            _slider(label: 'R', trackColor: Colors.red,   value: _r, onChanged: (v) => _r = v),
            _slider(label: 'G', trackColor: Colors.green, value: _g, onChanged: (v) => _g = v),
            _slider(label: 'B', trackColor: Colors.blue,  value: _b, onChanged: (v) => _b = v),
            _slider(label: 'A', trackColor: textMid,      value: _a, onChanged: (v) => _a = v),

            const SizedBox(height: 12),

            // Hex input
            TextField(
              controller: _hexController,
              maxLength: 8,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              ],
              style: GoogleFonts.sourceCodePro(color: textLight, fontSize: 14, letterSpacing: 2),
              decoration: InputDecoration(
                prefixText: '#',
                prefixStyle: GoogleFonts.sourceCodePro(color: textMid, fontSize: 14),
                labelText: 'HEX',
                counterText: '',
                errorText: _hexError ? 'Invalid hex value' : null,
                filled: true,
                fillColor: widget.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderMid),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderMid),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _current, width: 1.5),
                ),
              ),
              onSubmitted: _applyHex,
              onChanged: (v) {
                setState(() => _hexError = false);
                if (v.replaceAll('#', '').length >= 6) _applyHex(v);
              },
            ),

            const SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.orbitron(fontSize: 10, color: textMid, letterSpacing: 1.5)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _current,
                    foregroundColor: ThemeData.estimateBrightnessForColor(_current) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  onPressed: () {
                    widget.onChanged(_current);
                    Navigator.pop(context);
                  },
                  child: Text('Apply', style: GoogleFonts.orbitron(fontSize: 10, letterSpacing: 1.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}