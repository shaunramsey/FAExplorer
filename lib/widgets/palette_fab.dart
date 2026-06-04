import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';

/// Themed icon button used in both the sandbox and game-puzzle FAB toolbars.
///
/// Idle:   [AppThemeNotifier.surface] background, [AppThemeNotifier.textDim] icon.
/// Active: tinted background + border glow in [activeColor].
class PaletteFab extends StatelessWidget {
  const PaletteFab({
    super.key,
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onPressed,
    this.small = false,
  });

  final Object heroTag;
  final String tooltip;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    final bg   = active ? activeColor.withOpacity(0.14) : theme.surface;
    final fg   = active ? activeColor : theme.textDim;
    final borderColor = active
        ? activeColor.withOpacity(0.7)
        : theme.borderMid;
    final borderWidth = active ? 1.5 : 1.0;

    final size     = small ? 36.0 : 48.0;
    final iconSize = small ? 18.0 : 22.0;
    final radius   = small ?  8.0 : 12.0;

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width:  size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.3),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onPressed,
            child: Icon(icon, color: fg, size: iconSize),
          ),
        ),
      ),
    );
  }
}