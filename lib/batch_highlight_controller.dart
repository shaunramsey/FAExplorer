import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BatchHighlightController extends TextEditingController {
  final bool Function(int lineIndex) isAccepted;
  final bool Function(int lineIndex) isRejected;

  BatchHighlightController({required this.isAccepted, required this.isRejected});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final lines = text.split('\n');
    final children = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      Color color = Colors.white;
      if (isAccepted(i)) {
        color = Colors.green;
      } else if (isRejected(i)) {
        color = Colors.red;
      }

      children.add(
        TextSpan(
          text: lines[i],
          style: GoogleFonts.courierPrime(color: color, fontSize: 16),
        ),
      );

      if (i != lines.length - 1) {
        children.add(
          TextSpan(
            text: '\n',
            style: GoogleFonts.courierPrime(color: Colors.white, fontSize: 16),
          ),
        );
      }
    }

    return TextSpan(children: children);
  }
}
