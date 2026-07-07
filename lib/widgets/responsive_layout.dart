import 'package:flutter/material.dart';

/// Width breakpoint below which compact (mobile) layouts are used.
const double kCompactLayoutBreakpoint = 600;

/// True when the viewport is narrow enough for a stacked / compact layout.
bool isCompactLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kCompactLayoutBreakpoint;

/// Horizontal padding that scales down on compact screens.
double responsiveHorizontalPadding(BuildContext context) =>
    isCompactLayout(context) ? 12.0 : 20.0;

/// Scale factor for level-map canvas geometry on narrow viewports.
double levelMapLayoutScale(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 900) return 1.0;
  return (w / 900).clamp(0.6, 1.0);
}
