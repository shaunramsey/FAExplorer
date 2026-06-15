import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';

class HelpOverlay extends StatelessWidget {
  const HelpOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        color: theme.surface,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.borderMid, width: 1),
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: theme.textLight, fontSize: 14, height: 1.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Quick Controls',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.accent,
                  ),
                ),
                const SizedBox(height: 12),
                _HelpLine('Double click empty space', 'Create node', theme: theme),
                _HelpLine('Drag node', 'Move node', theme: theme),
                _HelpLine('Double click node', 'Toggle accept state', theme: theme),
                _HelpLine('Shift or link button', 'Line mode', theme: theme),
                _HelpLine('Drag line', 'Curve line', theme: theme),
                _HelpLine('Long press screen', 'Reset graph', theme: theme),
                _HelpLine('Delete button', 'Delete mode', theme: theme),
                const SizedBox(height: 16),
                Text(
                  'Textbox Commands',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text('[[DELTA_CAP]] → Δ', style: TextStyle(color: theme.textLight)),
                Text('[[DELTA]] → δ', style: TextStyle(color: theme.textLight)),
                Text('[[EPSILON]] → ε', style: TextStyle(color: theme.textLight)),
                Text('[[SIGMA_CAP]] → Σ', style: TextStyle(color: theme.textLight)),
                Text('[[SIGMA]] → σ', style: TextStyle(color: theme.textLight)),
                Text('[[LAMBDA]] → λ', style: TextStyle(color: theme.textLight)),
                Text('[[PHI]] → φ', style: TextStyle(color: theme.textLight)),
                Text('[[/0]] → ∅', style: TextStyle(color: theme.textLight)),
                Text('[[INFINITY]] → ∞', style: TextStyle(color: theme.textLight)),
                Text('[[/abc]] → ã̸b̸c̸  (slashed letters)', style: TextStyle(color: theme.textLight)),
                const SizedBox(height: 12),
                Text(
                  'TM Multi-tape (conjunctive)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '1:aXR,b1,3:01S',
                  style: TextStyle(color: theme.textLight, fontFamily: 'CourierPrime'),
                ),
                Text(
                  '  b1 — tape 1 read fires → also writes tape 3\n'
                  '  (secondary read not checked)',
                  style: TextStyle(
                    color: theme.textMid,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '1:aXR,b2,2:01S',
                  style: TextStyle(color: theme.textLight, fontFamily: 'CourierPrime'),
                ),
                Text(
                  '  b2 — both tapes must match simultaneously\n'
                  '  (classic parallel multi-tape step)',
                  style: TextStyle(
                    color: theme.textMid,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Defaults: single tape, independent NTM branches per line.',
                  style: TextStyle(
                    color: theme.textDim,
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tip: Commands can be typed directly inside node and line labels.',
                  style: TextStyle(
                    color: theme.textMid,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpLine extends StatelessWidget {
  const _HelpLine(this.action, this.result, {required this.theme});

  final String action;
  final String result;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: theme.textLight, fontSize: 14, height: 1.45),
          children: [
            TextSpan(
              text: action,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: ' — $result'),
          ],
        ),
      ),
    );
  }
}