import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme palette (mirrors main.dart)
// ─────────────────────────────────────────────────────────────────────────────
const _kSurface   = Color(0xFF0A0F18);
const _kBorderMid = Color(0xFF1A2535);
const _kAccent    = Color(0xFF00E5FF);
const _kTextLight = Color(0xFFCDD5E0);
const _kTextMid   = Color(0xFF6B7E96);

class HelpOverlay extends StatelessWidget {
  const HelpOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        color: _kSurface,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorderMid, width: 1),
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: _kTextLight, fontSize: 14, height: 1.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Quick Controls',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kAccent,
                  ),
                ),
                const SizedBox(height: 12),
                _HelpLine('Double click empty space', 'Create node'),
                _HelpLine('Drag node', 'Move node'),
                _HelpLine('Double click node', 'Toggle accept state'),
                _HelpLine('Shift or link button', 'Line mode'),
                _HelpLine('Drag line', 'Curve line'),
                _HelpLine('Long press screen', 'Reset graph'),
                _HelpLine('Delete button', 'Delete mode'),
                const SizedBox(height: 16),
                Text(
                  'Textbox Commands',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _kAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text('[[DELTA_CAP]] → Δ', style: TextStyle(color: _kTextLight)),
                Text('[[DELTA]] → δ', style: TextStyle(color: _kTextLight)),
                Text('[[EPSILON]] → ε', style: TextStyle(color: _kTextLight)),
                Text('[[SIGMA_CAP]] → Σ', style: TextStyle(color: _kTextLight)),
                Text('[[SIGMA]] → σ', style: TextStyle(color: _kTextLight)),
                Text('[[LAMBDA]] → λ', style: TextStyle(color: _kTextLight)),
                Text('[[PHI]] → φ', style: TextStyle(color: _kTextLight)),
                Text('[[/0]] → ∅', style: TextStyle(color: _kTextLight)),
                Text('[[INFINITY]] → ∞', style: TextStyle(color: _kTextLight)),
                Text('[[/abc]] → ã̸b̸c̸  (slashed letters)', style: TextStyle(color: _kTextLight)),
                const SizedBox(height: 12),
                Text(
                  'Tip: Commands can be typed directly inside node and line labels.',
                  style: TextStyle(
                    color: _kTextMid,
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
  final String key_;
  final String value;

  const _HelpLine(this.key_, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '• $key_',
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            TextSpan(
              text: ' → $value',
              style: const TextStyle(
                color: Color(0xFFCDD5E0),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}