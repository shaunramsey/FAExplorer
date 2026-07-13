import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  responsive_layout.dart
//
//  Tiny, dependency-free set of helpers used throughout the app to decide
//  between "compact" (phone-width) and "regular" (tablet/desktop-width)
//  layouts, and to scale a couple of pixel-based geometry values down on
//  narrow screens. Nothing here holds state — every function derives its
//  answer fresh from the current BuildContext's MediaQuery on every call,
//  so callers naturally react to window resizes / orientation changes as
//  long as they're inside a widget that rebuilds on MediaQuery changes
//  (which is any widget under a MaterialApp).
// ─────────────────────────────────────────────────────────────────────────────

/// Width breakpoint below which compact (mobile) layouts are used.
///
/// 600 logical pixels is the conventional Material breakpoint between
/// "phone" and "small tablet". Anything narrower than this is treated as
/// compact everywhere in this app — there is no separate "tablet" tier.
const double kCompactLayoutBreakpoint = 600;

/// True when the viewport is narrow enough for a stacked / compact layout.
///
/// `MediaQuery.sizeOf(context)` (rather than `MediaQuery.of(context).size`)
/// is used deliberately: `sizeOf` subscribes this widget to *only* the size
/// portion of MediaQuery, so the widget rebuilds when the window is resized
/// but NOT when unrelated MediaQuery fields change (e.g. keyboard insets
/// appearing, text scale factor changing). That avoids extra rebuilds on
/// every call site that uses this helper.
bool isCompactLayout(BuildContext context) =>
    // Strictly-less-than: a width exactly equal to the breakpoint (600.0)
    // is treated as the *regular* (non-compact) layout, not compact.
    MediaQuery.sizeOf(context).width < kCompactLayoutBreakpoint;

/// Horizontal padding that scales down on compact screens.
///
/// Two fixed values only (12px compact / 20px regular) — this is a step
/// function, not a continuous scale, unlike [levelMapLayoutScale] below.
/// Kept intentionally simple since padding differences below ~600px don't
/// need finer granularity to look right.
double responsiveHorizontalPadding(BuildContext context) =>
    isCompactLayout(context) ? 12.0 : 20.0;

/// Scale factor for level-map canvas geometry on narrow viewports.
///
/// Unlike [responsiveHorizontalPadding], this is a *continuous* scale
/// (not just two fixed values) because the level-map canvas draws
/// absolutely-positioned nodes/edges whose coordinates need to shrink
/// smoothly as the viewport narrows, rather than jumping between two
/// discrete layouts. Callers are expected to multiply their canvas
/// geometry (node radii, edge coordinates, font sizes, etc.) by this
/// factor.
double levelMapLayoutScale(BuildContext context) {
  // Read the current viewport width once into a local so both branches
  // below refer to the same MediaQuery snapshot (matters if MediaQuery
  // could theoretically change mid-computation, but mainly just avoids a
  // second MediaQuery.sizeOf lookup).
  final w = MediaQuery.sizeOf(context).width;

  // At or above 900px, the map renders at full/native scale (1.0). 900 is
  // a *different*, larger breakpoint than kCompactLayoutBreakpoint (600) —
  // deliberately so: the map can still be usefully full-size on tablets
  // that are wider than the "compact" cutoff but narrower than a desktop.
  if (w >= 900) return 1.0;

  // Below 900px, scale linearly down to a floor of 0.6x at width 0, i.e.
  // scale = w / 900, clamped into [0.6, 1.0].
  //   - At w = 900:  900/900 = 1.0            -> clamps to 1.0 (matches the branch above at the seam)
  //   - At w = 540:  540/900 = 0.6            -> exactly the floor
  //   - At w = 320 (a small phone): 320/900 ≈ 0.356 -> clamped up to the 0.6 floor,
  //     so the map never shrinks below 60% no matter how narrow the phone is
  //     (prevents nodes/labels from becoming illegibly small).
  return (w / 900).clamp(0.6, 1.0);
}