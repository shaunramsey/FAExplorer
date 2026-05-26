import 'package:flutter/material.dart';

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
        color: Colors.black.withValues(alpha: 0.9),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          child: const DefaultTextStyle(
            style: TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Quick Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text('• Double click empty space → Create node'),
                Text('• Drag node → Move node'),
                Text('• Double click node → Toggle accept state'),
                Text('• Shift or link button → Line mode'),
                Text('• Drag line → Curve line'),
                Text('• Long press screen → Reset graph'),
                Text('• Delete button → Delete mode'),
                SizedBox(height: 16),
                Text('Textbox Commands', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('[[DELTA_CAP]] → Δ'),
                Text('[[DELTA]] → δ'),
                Text('[[EPSILON]] → ε'),
                Text('[[SIGMA_CAP]] → Σ'),
                Text('[[SIGMA]] → σ'),
                Text('[[LAMBDA]] → λ'),
                Text('[[PHI]] → φ'),
                Text('[[/0]] → ∅'),
                Text('[[INFINITY]] → ∞'),
                Text('[[/abc]] → ã̸b̸c̸  (slashed letters)'),
                SizedBox(height: 12),
                Text(
                  'Tip: Commands can be typed directly inside node and line labels.',
                  style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
