import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

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
  bool _advancedOpen = false;
  double _bgDepth = 0;
  double _textContrast = 0;
  bool _linkHighlights = false;

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
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                      widget.notifier.applyBackgroundDepth(v);
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
                      widget.notifier.applyTextContrast(v);
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
                    activeColor: accent,
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
                                color: accent.withOpacity(0.65),
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
        color: accent.withOpacity(0.85),
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
        '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

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

  Color get _current =>
      Color.fromARGB(_a.round(), _r.round(), _g.round(), _b.round());

  String _toHex() =>
      _current.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

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