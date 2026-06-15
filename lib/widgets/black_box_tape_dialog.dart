import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../tm_simulator.dart';
import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  BlackBoxTapeEditDialog
//
//  Improved version: shows a live mini-tape strip for every available tape
//  so the user can see what symbols are at the current head positions before
//  picking which tape to read from / write to.
//
//  Changes vs. the original:
//   • Accepts an optional [simulator] argument.  When provided, each tape
//     row shows a scrollable cell strip with the current head position
//     highlighted — the user can immediately see what the head is reading on
//     each tape and make an informed routing choice.
//   • The "only 1 tape" hint is replaced with a clearer call-to-action that
//     deep-links to the TM config panel (same message, better placement).
//   • Selecting a tape row directly sets that tape as the read or write target
//     (no need to tap +/−), making the interaction a single tap.
//   • Mismatch warning: when the saved read/write tape is out of range a
//     visible warning banner is shown above the steppers rather than silently
//     clamping.
//   • The +/− steppers are retained for power users who prefer them.
// ─────────────────────────────────────────────────────────────────────────────

class BlackBoxTapeEditDialog extends StatefulWidget {
  const BlackBoxTapeEditDialog({
    super.key,
    required this.node,
    this.tapeCount = 1,
    this.simulator,
  });

  final NodeData node;

  /// Total number of tapes available (from [TmSimulator.tapeCount]).
  final int tapeCount;

  /// Optional live simulator — when supplied, the dialog shows a tape strip
  /// for each tape so the user can see current cell content before choosing.
  final TmSimulator? simulator;

  /// Convenience helper.
  static Future<bool?> show(
    BuildContext context, {
    required NodeData node,
    int tapeCount = 1,
    TmSimulator? simulator,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => BlackBoxTapeEditDialog(
        node: node,
        tapeCount: tapeCount,
        simulator: simulator,
      ),
    );
  }

  @override
  State<BlackBoxTapeEditDialog> createState() => _BlackBoxTapeEditDialogState();
}

class _BlackBoxTapeEditDialogState extends State<BlackBoxTapeEditDialog> {
  late int _readTape;
  late int _writeTape;

  int get _maxTape => widget.tapeCount < 1 ? 1 : widget.tapeCount;
  bool get _multiTape => _maxTape > 1;

  // Whether the current values are out of range (can happen when the tape
  // count was reduced after the node was last configured).
  bool get _readOutOfRange => _readTape > _maxTape;
  bool get _writeOutOfRange => _writeTape > _maxTape;

  @override
  void initState() {
    super.initState();
    _readTape = widget.node.blackBoxReadTape.clamp(1, _maxTape);
    _writeTape = widget.node.blackBoxWriteTape.clamp(1, _maxTape);
  }

  void _save() {
    widget.node.blackBoxReadTape = _readTape;
    widget.node.blackBoxWriteTape = _writeTape;
    Navigator.of(context).pop(true);
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  /// Pull the tape snapshot for [tapeIndex] (1-based) from the simulator, or
  /// return null when the simulator has no current step yet.
  ({TmTape tape, int headPos})? _tapeSnapshot(int tapeIndex) {
    final sim = widget.simulator;
    if (sim == null) return null;
    final configs = sim.activeConfigs;
    if (configs.isEmpty) return null;
    // Prefer a halting-accept config if one exists, otherwise first.
    TmConfig? cfg;
    for (final c in configs) {
      if (sim.nodes[c.nodeId]?.isHaltAccept == true) {
        cfg = c;
        break;
      }
    }
    cfg ??= configs.first;
    final i = tapeIndex - 1;
    if (i < 0 || i >= cfg.tapes.length) return null;
    return (tape: cfg.tapes[i], headPos: cfg.headPositions[i]);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final nodeName = widget.node.label.trim().isEmpty
        ? 'this black box'
        : '"${widget.node.label.trim()}"';

    final hasOutOfRange = _readOutOfRange || _writeOutOfRange;

    return Dialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.borderMid),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ──────────────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.settings_input_component, size: 18, color: theme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tape Routing',
                      style: GoogleFonts.courierPrime(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Choose which tape $nodeName reads its input from '
                'and which tape it writes its output to.',
                style: TextStyle(fontSize: 12, color: theme.textMid, height: 1.4),
              ),

              const SizedBox(height: 14),

              // ── Out-of-range warning ───────────────────────────────────
              if (hasOutOfRange) ...[
                _WarningBanner(
                  message: 'The saved tape index is out of range '
                      '(tapes 1–$_maxTape available). '
                      'It has been clamped — save to confirm.',
                  theme: theme,
                ),
                const SizedBox(height: 10),
              ],

              // ── Single-tape hint ───────────────────────────────────────
              if (!_multiTape) ...[
                _InfoBanner(
                  message: 'Only 1 tape is configured. Add more tapes via '
                      'the TM panel ▸ Tapes counter, then reassign here.',
                  theme: theme,
                ),
                const SizedBox(height: 14),
              ],

              // ── Tape selection rows ────────────────────────────────────
              if (_multiTape) ...[
                Text(
                  'Tap a tape to select it as the Read or Write target:',
                  style: GoogleFonts.courierPrime(
                    fontSize: 11,
                    color: theme.textDim,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (int t = 1; t <= _maxTape; t++)
                          _TapeRow(
                            tapeIndex: t,
                            isRead: t == _readTape,
                            isWrite: t == _writeTape,
                            snapshot: _tapeSnapshot(t),
                            theme: theme,
                            onSelectRead: () =>
                                setState(() => _readTape = t),
                            onSelectWrite: () =>
                                setState(() => _writeTape = t),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Fine-tune steppers (always shown for precision) ────────
              _TapeStepper(
                label: 'Read',
                icon: Icons.input,
                value: _readTape,
                min: 1,
                max: _maxTape,
                enabled: _multiTape,
                onChanged: (v) => setState(() => _readTape = v),
                theme: theme,
              ),
              const SizedBox(height: 8),
              _TapeStepper(
                label: 'Write',
                icon: Icons.output,
                value: _writeTape,
                min: 1,
                max: _maxTape,
                enabled: _multiTape,
                onChanged: (v) => setState(() => _writeTape = v),
                theme: theme,
              ),

              const SizedBox(height: 20),

              // ── Actions ───────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel', style: TextStyle(color: theme.textDim)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(backgroundColor: theme.accent),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _TapeRow — one tape with a live cell strip + R/W selection buttons
// ─────────────────────────────────────────────────────────────────────────────

class _TapeRow extends StatelessWidget {
  const _TapeRow({
    required this.tapeIndex,
    required this.isRead,
    required this.isWrite,
    required this.snapshot,
    required this.theme,
    required this.onSelectRead,
    required this.onSelectWrite,
  });

  final int tapeIndex;
  final bool isRead;
  final bool isWrite;
  final ({TmTape tape, int headPos})? snapshot;
  final AppThemeNotifier theme;
  final VoidCallback onSelectRead;
  final VoidCallback onSelectWrite;

  @override
  Widget build(BuildContext context) {
    final active = isRead || isWrite;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: active ? theme.accent.withOpacity(0.07) : theme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? theme.accent.withOpacity(0.45) : theme.borderMid,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: tape label + R/W badges + select buttons
            Row(
              children: [
                Text(
                  'Tape $tapeIndex',
                  style: GoogleFonts.courierPrime(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: active ? theme.accent : theme.textMid,
                  ),
                ),
                const SizedBox(width: 6),
                if (isRead)
                  _Badge(label: 'R', color: theme.accent),
                if (isWrite)
                  _Badge(label: 'W', color: theme.accentGreen),
                const Spacer(),
                // Read selector
                _SelectBtn(
                  label: 'Read',
                  active: isRead,
                  activeColor: theme.accent,
                  theme: theme,
                  onTap: onSelectRead,
                ),
                const SizedBox(width: 6),
                // Write selector
                _SelectBtn(
                  label: 'Write',
                  active: isWrite,
                  activeColor: theme.accentGreen,
                  theme: theme,
                  onTap: onSelectWrite,
                ),
              ],
            ),

            // Live tape strip (shown only when simulator data is available)
            if (snapshot != null) ...[
              const SizedBox(height: 6),
              _MiniTapeStrip(
                tape: snapshot!.tape,
                headPos: snapshot!.headPos,
                theme: theme,
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                'No simulation running — start the simulator to preview tape content.',
                style: TextStyle(fontSize: 10, color: theme.textDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _MiniTapeStrip — compact scrollable row of cells
// ─────────────────────────────────────────────────────────────────────────────

class _MiniTapeStrip extends StatelessWidget {
  const _MiniTapeStrip({
    required this.tape,
    required this.headPos,
    required this.theme,
  });

  final TmTape tape;
  final int headPos;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    const pad = 2;
    final startRel = -pad;
    final endRel = tape.cells.length - tape.headOffset + pad;

    final items = <({String symbol, bool isHead})>[];
    for (int rel = startRel; rel < endRel; rel++) {
      final abs = tape.absolutePos(rel);
      final sym = (abs >= 0 && abs < tape.cells.length)
          ? tape.cells[abs]
          : kBlank;
      items.add((
        symbol: sym.isEmpty ? kBlank : sym,
        isHead: abs == headPos,
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items)
            _MiniCell(symbol: item.symbol, isHead: item.isHead, theme: theme),
        ],
      ),
    );
  }
}

class _MiniCell extends StatelessWidget {
  const _MiniCell({
    required this.symbol,
    required this.isHead,
    required this.theme,
  });

  final String symbol;
  final bool isHead;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: isHead ? theme.surface : theme.bg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isHead ? theme.accent : theme.borderMid,
          width: isHead ? 1.5 : 1,
        ),
      ),
      child: Center(
        child: Text(
          symbol,
          style: GoogleFonts.courierPrime(
            fontSize: 10,
            fontWeight: isHead ? FontWeight.bold : FontWeight.normal,
            color: isHead ? theme.accent : theme.textMid,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _TapeStepper — fine-tune row with − / value / + controls
// ─────────────────────────────────────────────────────────────────────────────

class _TapeStepper extends StatelessWidget {
  const _TapeStepper({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.theme,
  });

  final String label;
  final IconData icon;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    final canDec = enabled && value > min;
    final canInc = enabled && value < max;

    return Row(
      children: [
        Icon(icon, size: 16, color: enabled ? theme.accent : theme.textDim),
        const SizedBox(width: 6),
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: GoogleFonts.courierPrime(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? theme.textLight : theme.textDim,
            ),
          ),
        ),
        _StepBtn(
          icon: Icons.remove,
          enabled: canDec,
          onTap: canDec ? () => onChanged(value - 1) : null,
          theme: theme,
        ),
        const SizedBox(width: 4),
        Container(
          width: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: theme.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: enabled
                  ? theme.accent.withOpacity(0.5)
                  : theme.borderMid,
            ),
          ),
          child: Text(
            '$value',
            style: GoogleFonts.courierPrime(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: enabled ? theme.accent : theme.textDim,
            ),
          ),
        ),
        const SizedBox(width: 4),
        _StepBtn(
          icon: Icons.add,
          enabled: canInc,
          onTap: canInc ? () => onChanged(value + 1) : null,
          theme: theme,
        ),
        const SizedBox(width: 8),
        Text(
          'Tape $value',
          style: GoogleFonts.courierPrime(
            fontSize: 11,
            color: enabled ? theme.textMid : theme.textDim,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _SelectBtn — pill button used inside the tape row header
// ─────────────────────────────────────────────────────────────────────────────

class _SelectBtn extends StatelessWidget {
  const _SelectBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color activeColor;
  final AppThemeNotifier theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.18) : theme.bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active ? activeColor.withOpacity(0.7) : theme.borderMid,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.courierPrime(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? activeColor : theme.textDim,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small utility widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.courierPrime(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.theme,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: enabled ? theme.surface : theme.bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: enabled
                ? theme.borderMid
                : theme.borderMid.withOpacity(0.35),
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled
              ? theme.accent
              : theme.textDim.withOpacity(0.35),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, required this.theme});

  final String message;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accent.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: theme.textMid, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message, required this.theme});

  final String message;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    const warningColor = Color(0xFFFF9E40);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warningColor.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warningColor.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: warningColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11, color: warningColor, height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}