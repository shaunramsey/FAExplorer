// study_mode_layout.dart
//
// Shared study-mode solution-graph layout post-processor.
//
// Originally lived as a private helper inside study_mode_pda.dart. Extracted
// here so both study_mode_pda.dart (PDA solutions) and study_mode_tm.dart (TM
// solutions) can call the same, fuller-featured post-processor — the one in
// study_mode_screen.dart (used for the regex/DFA solution preview) is a
// separate, simpler variant that does not need self-loop or node-node
// distance handling and is intentionally left alone.

import 'dart:math';
// sqrt, cos, sin, pi — every distance/angle computation below is built out
// of these five primitives; there's no vector-math library involved, just
// Offset arithmetic plus these.

import 'package:flutter/material.dart';
// Only used for the `Offset` type (dx/dy pairs) — nothing else from
// Flutter's widget system is needed in a pure layout algorithm like this.

import 'models.dart';
// NodeData, LineData, and the shared geometry constants referenced below
// (kLabelBoxWidth, kLabelLineHeight, kSelfLoopRadius,
// kSelfLoopCenterDistance, kSelfLoopTextDistance) — kept in models.dart so
// this file's constants can't drift out of sync with whatever LineWidget/
// StartArrowWidget actually render on screen (see the inline comments
// next to each constant below).

// ─────────────────────────────────────────────────────────────────────────────
//  Study-mode layout post-processor
//
//  Applied to the solution graph after it is built from a PDA spec, before
//  rendering it read-only.  Three passes:
//
//  1. Set a default perpendicularPart of 30 on every non-self-loop line.
//
//  2+3. For every node N and every line L that does not touch N, run two
//     sub-checks inside a single convergence loop so both can react to each
//     other rather than fighting across two separate loops:
//
//     2. CHORD CLEARANCE — closest point on the straight chord through the two
//        endpoint centres.  If within clearance, push N perpendicularly away.
//
//     3. TEXTBOX CLEARANCE — axis-aligned bounding rect of the line's label
//        (computed by LineData.getTextBoxLocation).  If the node circle
//        overlaps the rect, push N away from the nearest edge.
//
//     Repeat until stable (max iterations).
// ─────────────────────────────────────────────────────────────────────────────

void applyStudyModeLayout(
  Map<String, NodeData> nodes,
  Map<String, LineData> lines,
) {
  // Mutates `nodes`/`lines` in place (NodeData.position, LineData
  // fields) — there is no return value; the caller passes in the maps it
  // wants adjusted and reads them back afterward. This mirrors the
  // in-place-mutation style seen elsewhere in this codebase (e.g.
  // AutomataCanvasEmbed's own node/line maps), not a pure functional
  // "returns a new layout" design.

  // ── Pass 1: default perpendicularPart on all non-self-loop lines ───────────
  for (final line in lines.values) {
    if (line.nodeAId != line.nodeBId) {
      line.perpendicularPart = 30.0;
      // Every straight A→B transition line is force-curved outward by a
      // fixed 30px, rather than left perfectly straight — this is what
      // gives the auto-generated solution graphs their characteristic
      // "gently bowed" line look and, practically, leaves room for two
      // opposite-direction transitions between the same pair of nodes
      // (A→B and B→A) to visually separate instead of drawing directly on
      // top of each other. Self-loops are skipped here since
      // perpendicularPart has no meaning for a line whose two endpoints
      // are the same node (self-loops use selfLoopAngle instead, handled
      // entirely separately below).
    }
  }

  // ── Shared constants ───────────────────────────────────────────────────────
  const double nodeRadius     = 50.0;               // visual radius of a state circle
  const double nodeDiameter   = nodeRadius * 2;
  const double minNodeGap     = nodeDiameter + 40.0; // minimum centre-to-centre distance
  // 140px total: two full node diameters' worth of clearance would be
  // 200 (2 * 2*50)... actually minNodeGap is just one diameter (100) plus
  // a flat 40px buffer — i.e. "leave at least 40px of empty space between
  // two node circles' edges," not "leave two full node-widths."
  const double clearance      = nodeRadius + 30.0;   // min dist: node centre ↔ chord
  // A *third* node's centre must stay at least 80px (radius 50 + 30px
  // buffer) from the straight line connecting two *other* nodes' centres
  // — this is what stops a transition line from visually slicing through
  // an uninvolved state's circle.
  const double textBuffer     = 14.0;                // extra padding around textbox rect
  const double boxWidth       = kLabelBoxWidth;       // must match LineWidget — see models.dart
  const double lineHeight     = kLabelLineHeight;      // single-line height in LineWidget — see models.dart
  const double selfLoopRadius = kSelfLoopRadius;       // loop circle radius — see models.dart
  const double selfLoopCenterDist = kSelfLoopCenterDistance; // centre offset for loop — see models.dart
  const int    iterations     = 30;                  // convergence passes
  // 30 passes of the full node×line double loop below is the "max
  // iterations" mentioned in the file-header doc comment — the loop can
  // (and usually does) exit early via the `if (!anyMoved) break;` at the
  // very bottom once a stable layout is reached, so 30 is just a safety
  // ceiling against pathological inputs that never fully converge.

  // Helper: push node away from an axis-aligned rect.
  // Returns true if a push was applied.
  bool pushNodeFromRect(
    NodeData node,
    double rLeft,
    double rTop,
    double rRight,
    double rBottom,
  ) {
    // A local closure (captures `nodeRadius` from the enclosing scope)
    // rather than a top-level function — kept private to
    // applyStudyModeLayout since it's only ever meaningful in the context
    // of this specific layout pass, and closing over `nodeRadius` avoids
    // having to pass it as a fifth parameter at every one of its three
    // call sites below.
    final nc = node.center;
    final closestX = nc.dx.clamp(rLeft, rRight);
    final closestY = nc.dy.clamp(rTop, rBottom);
    // Standard "closest point on an axis-aligned rectangle to an external
    // point" technique: clamping the point's own coordinates into the
    // rect's [left,right]/[top,bottom] ranges. If the point is already
    // inside the rect on a given axis, clamp is a no-op for that axis; if
    // it's outside, clamp snaps it to the nearest edge on that axis. The
    // result (closestX, closestY) is the nearest point *on or inside* the
    // rectangle to the node's centre.
    final dxFromBox = nc.dx - closestX;
    final dyFromBox = nc.dy - closestY;
    final distFromBox = sqrt(dxFromBox * dxFromBox + dyFromBox * dyFromBox);
    // Standard Euclidean distance from the node centre to that closest
    // point. Note: this is 0 whenever the node's centre is literally
    // inside the rect (both clamps were no-ops) — handled specially just
    // below via the `distFromBox < 0.5` branch, since a zero-length
    // vector has no defined direction to push in.

    if (distFromBox < nodeRadius) {
      // The node's circle (radius nodeRadius) overlaps the rectangle —
      // "overlap" here means the node's centre is closer to the rect than
      // its own radius, which is the standard circle-vs-rect overlap test
      // once you already have the closest-point distance.
      final push = nodeRadius - distFromBox + 2.0; // +2 px safety margin
      // How far to move the node so its circle just clears the rect, plus
      // a small constant safety margin so repeated floating-point passes
      // don't leave it sitting exactly tangent (and therefore still
      // triggering on the next iteration due to rounding).

      final Offset pushDir;
      if (distFromBox < 0.5) {
        // Degenerate case: the node's centre is at (or extremely near) the
        // closest point itself, meaning the centre is inside/on the
        // rectangle — (dxFromBox, dyFromBox) is too close to (0,0) to
        // normalize into a reliable direction. Instead, push away from the
        // *rectangle's own centre* rather than from the (undefined) box-edge
        // direction.
        final rcx = (rLeft + rRight) / 2;
        final rcy = (rTop + rBottom) / 2;
        final awayDx = nc.dx - rcx;
        final awayDy = nc.dy - rcy;
        final awayLen = sqrt(awayDx * awayDx + awayDy * awayDy);
        pushDir = awayLen < 0.5
            ? const Offset(0, 1)
            : Offset(awayDx / awayLen, awayDy / awayLen);
        // A second, even-more-degenerate fallback: if the node's centre is
        // also sitting almost exactly on the rectangle's own centre (both
        // distances near zero), there is truly no meaningful direction to
        // derive from geometry at all — arbitrarily push straight down
        // (Offset(0, 1)) rather than dividing by ~zero and producing NaN/
        // Infinity. This can't loop forever because a single push in *any*
        // consistent direction is enough to break the degenerate symmetry
        // for the next iteration.
      } else {
        pushDir = Offset(dxFromBox / distFromBox, dyFromBox / distFromBox);
        // Normal case: normalize (dxFromBox, dyFromBox) into a unit vector
        // — push the node directly away from the nearest point on the
        // rect's boundary.
      }

      node.position = Offset(
        node.position.dx + pushDir.dx * push,
        node.position.dy + pushDir.dy * push,
      );
      // NodeData.position (top-left, presumably) is nudged by the push
      // vector — note this adds to `.position`, not `.center`; the two are
      // presumably related by a fixed offset (position + (radius, radius)
      // or similar), so adding the same delta to position produces the
      // same delta in center.
      return true;
    }
    return false;
    // No overlap: nothing to do, and the caller (see call sites below)
    // uses this `false` to decide whether `anyMoved` should flip to true
    // for this iteration.
  }

  // ── Convergence loop ───────────────────────────────────────────────────────
  for (int iter = 0; iter < iterations; iter++) {
    bool anyMoved = false;
    // Reset every iteration — this flag only tracks whether *this specific
    // pass* moved anything; the loop exits once a full pass produces no
    // movement at all (see the `break` at the very end), meaning the
    // layout has reached a local equilibrium.
    final nodeList = nodes.values.toList();
    // Snapshotted once per iteration (not per node-node/node-line check) —
    // safe here since nothing in this loop adds/removes map entries, only
    // mutates existing NodeData/LineData objects' fields in place, so a
    // stale List of references stays valid and up-to-date throughout the
    // iteration (each NodeData's `.center` getter presumably re-derives
    // from its live, possibly-just-mutated `.position`).

    // ── Check A: node-node minimum distance ─────────────────────────────────
    for (int i = 0; i < nodeList.length; i++) {
      final na = nodeList[i];
      if (na.isBlackBox) continue;
      // Black-box nodes are exempt from this spacing pass entirely —
      // presumably because they're allowed/expected to render differently
      // (e.g. a different shape/size) and forcing the same 50px-radius-
      // based minNodeGap onto them wouldn't reflect their actual on-screen
      // footprint.
      for (int j = i + 1; j < nodeList.length; j++) {
        // `j = i + 1` — classic "every unordered pair exactly once"
        // double-loop pattern, so node pair (A, B) is checked once, not
        // twice as (A,B) and again as (B,A).
        final nb = nodeList[j];
        if (nb.isBlackBox) continue;

        final cA = na.center;
        final cB = nb.center;
        final dx = cB.dx - cA.dx;
        final dy = cB.dy - cA.dy;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < minNodeGap && dist > 0.1) {
          // `dist > 0.1` guards against two nodes sitting exactly (or
          // almost exactly) on top of each other, where (dx, dy) would be
          // too close to (0,0) to derive a meaningful push direction —
          // unlike pushNodeFromRect's degenerate-case handling above, this
          // check simply skips the push entirely rather than falling back
          // to an arbitrary direction; two coincident nodes stay stuck
          // together rather than being pushed apart in some arbitrary
          // direction (an edge case the algorithm doesn't fully solve).
          final overlap = (minNodeGap - dist) / 2.0 + 2.0;
          // How far apart they're short of minNodeGap, split evenly
          // between the two nodes (each moves half the shortfall) plus the
          // same +2px safety margin pattern used elsewhere in this file.
          final ux = dx / dist;
          final uy = dy / dist;
          // Push both nodes apart equally.
          na.position = Offset(na.position.dx - ux * overlap, na.position.dy - uy * overlap);
          nb.position = Offset(nb.position.dx + ux * overlap, nb.position.dy + uy * overlap);
          // `na` moves backward along the unit vector from A to B (away
          // from B), `nb` moves forward along it (away from A) — the two
          // nodes symmetrically separate along their connecting axis.
          anyMoved = true;
        }
      }
    }

    // ── Checks B+C+D: per-line clearance for every node ─────────────────────
    for (final node in nodeList) {
      if (node.isBlackBox) continue;
      // Same black-box exemption as Check A above — a black-box node
      // never gets pushed away from other lines/textboxes in this pass
      // either (though note: it can still, per Check D below, have OTHER
      // regular nodes pushed away from a self-loop that happens to belong
      // to *it*, since Check D's exemption is only for the node being
      // tested against the loop, not for the loop's owner).

      for (final line in lines.values) {
        final isSelfLoop = line.nodeAId == line.nodeBId;

        if (isSelfLoop) {
          // ── Check D: self-loop textbox must not overlap OTHER nodes ─────
          // The loop belongs to its own node; we only care if it overlaps a
          // *different* node's circle.
          if (line.nodeAId == node.id) continue;
          // Skip testing a self-loop against the very node it's attached
          // to — a node's own loop is expected to sit right next to (and
          // partially "around") it; this check only guards against a
          // self-loop's label/circle intruding on some *other*, unrelated
          // node elsewhere in the layout.

          final ownerNode = nodes[line.nodeAId];
          if (ownerNode == null) continue;
          // Defensive: skip if the self-loop's owning node has somehow
          // been removed from `nodes` (shouldn't happen mid-layout, but
          // avoids a null-lookup crash if it does).

          // Compute self-loop textbox centre (mirrors LineData.getTextBoxLocation).
          final oc = ownerNode.center;
          final angle = line.selfLoopAngle; // default: -π/2 (straight up)
          final outward = Offset(cos(angle), sin(angle));
          // Standard unit-vector-from-angle: (cos θ, sin θ). At the
          // default angle of -π/2, cos(-π/2) ≈ 0 and sin(-π/2) = -1, so
          // `outward` points straight up (negative dy, matching screen
          // coordinates where -y is "up") — matching the "-π/2 (straight
          // up)" comment.
          final loopCenter = Offset(
            oc.dx + outward.dx * selfLoopCenterDist,
            oc.dy + outward.dy * selfLoopCenterDist,
          );
          // The self-loop's own drawn circle is centred not on the node
          // itself but offset outward from it by selfLoopCenterDist along
          // whatever direction `selfLoopAngle` currently points — this is
          // a plain-language re-derivation of whatever LineData's own
          // rendering code computes for where the loop circle actually
          // gets painted, kept independently here (per the "mirrors
          // LineData.getTextBoxLocation" comment above) so this pure-Dart
          // layout pass doesn't need to depend on any widget/painting code.
          const textDistance = kSelfLoopTextDistance;
          final textCenter = Offset(
            loopCenter.dx + outward.dx * (selfLoopRadius + textDistance),
            loopCenter.dy + outward.dy * (selfLoopRadius + textDistance),
          );
          // The loop's label text sits further out still, beyond the edge
          // of the loop circle itself (loopCenter + one more step outward
          // by the loop's own radius plus a fixed text-gap distance) —
          // same outward direction as the loop circle, just projected
          // further from the owning node.

          if (line.label.isNotEmpty) {
            final lineCount = '\n'.allMatches(line.label).length + 1;
            // Counts embedded newlines to determine how many visual text
            // lines the label spans — `+1` because N newlines divide text
            // into N+1 lines (e.g. zero newlines = 1 line).
            final boxHeight = lineHeight * lineCount;
            final tLeft   = textCenter.dx - boxWidth / 2 - textBuffer;
            final tTop    = textCenter.dy - boxHeight / 2 - textBuffer;
            final tRight  = textCenter.dx + boxWidth / 2 + textBuffer;
            final tBottom = textCenter.dy + boxHeight / 2 + textBuffer;
            // Builds an axis-aligned rectangle centred on textCenter, sized
            // boxWidth × (lineHeight * lineCount), expanded on all four
            // sides by textBuffer — the same "centre point + fixed
            // width/height + surrounding buffer" pattern used again just
            // below for Check C's non-self-loop textbox.

            if (pushNodeFromRect(node, tLeft, tTop, tRight, tBottom)) {
              anyMoved = true;
            }
          }

          // Also keep OTHER nodes away from the loop circle itself.
          final nc = node.center;
          final dxLoop = nc.dx - loopCenter.dx;
          final dyLoop = nc.dy - loopCenter.dy;
          final distLoop = sqrt(dxLoop * dxLoop + dyLoop * dyLoop);
          final minDist = nodeRadius + selfLoopRadius + 10.0;
          // A simpler circle-vs-circle check than pushNodeFromRect's
          // circle-vs-rect logic (appropriate since the loop's *circle*,
          // unlike its textbox, genuinely is circular) — minimum allowed
          // centre-to-centre distance is just the sum of both radii plus a
          // flat 10px buffer.
          if (distLoop < minDist && distLoop > 0.1) {
            final push = minDist - distLoop + 2.0;
            final ux = dxLoop / distLoop;
            final uy = dyLoop / distLoop;
            node.position = Offset(
              node.position.dx + ux * push,
              node.position.dy + uy * push,
            );
            anyMoved = true;
          }
          continue;
          // Self-loop lines never fall through to the non-self-loop chord/
          // textbox checks below (Checks B/C) — a self-loop has no
          // meaningful "chord between two distinct endpoints," so this
          // `continue` skips straight to the next line in the inner loop.
        }

        // Non-self-loop: skip if this line directly touches the node.
        if (line.nodeAId == node.id || line.nodeBId == node.id) continue;
        // Mirrors Check D's "skip a loop against its own owner" exemption
        // — a transition line is expected to touch its own two endpoint
        // nodes; this check only cares about *other*, uninvolved nodes
        // potentially overlapping the line/its label.

        final nodeA = nodes[line.nodeAId];
        final nodeB = nodes[line.nodeBId];
        if (nodeA == null || nodeB == null) continue;
        // Same defensive dangling-reference guard as `ownerNode` above.

        final cA = nodeA.center;
        final cB = nodeB.center;

        // ── Check B: chord clearance ────────────────────────────────────
        {
          // Bare block (not a loop or conditional) purely for local-variable
          // scoping — keeps `t`, `closestX/Y`, `dxFromChord`, etc. from
          // leaking into (or colliding with) Check C's own local variables
          // just below, without needing to extract this into a separate
          // named helper function.
          final nc = node.center;
          final abx = cB.dx - cA.dx;
          final aby = cB.dy - cA.dy;
          final abLen = sqrt(abx * abx + aby * aby);
          // Vector from A to B ("ab") and its length — the "chord" being
          // tested is the straight line segment between the two endpoint
          // centres (not the actual curved/bowed rendered line, which per
          // Pass 1 above bows outward by perpendicularPart — this check
          // deliberately tests against the simpler straight chord as an
          // approximation, presumably close enough given the curve is
          // modest).

          if (abLen >= 1) {
            // Guards against A and B being coincident (or extremely close),
            // where abLen would be near-zero and the projection math below
            // would divide by ~zero.
            final t = ((nc.dx - cA.dx) * abx + (nc.dy - cA.dy) * aby) /
                (abLen * abLen);
            // Standard "project point onto line" formula: `t` is the
            // scalar position along the A→B vector where the perpendicular
            // projection of `nc` lands, expressed as a fraction of abLen
            // (t=0 is exactly at A, t=1 is exactly at B, t=0.5 is the
            // midpoint, values outside [0,1] project beyond either
            // endpoint).
            if (t >= -0.05 && t <= 1.05) {
              // Only proceeds if the projection lands (approximately)
              // between the two endpoints — the small -0.05/1.05 slack
              // (rather than a strict [0,1]) lets the clearance check also
              // catch a node sitting just barely past either endpoint,
              // not only strictly "between" them.
              final closestX = cA.dx + t * abx;
              final closestY = cA.dy + t * aby;
              // The actual (x,y) position of that projected closest point
              // on the chord, computed by walking `t` fraction of the way
              // from A along the AB vector.
              final dxFromChord = nc.dx - closestX;
              final dyFromChord = nc.dy - closestY;
              final distFromChord =
                  sqrt(dxFromChord * dxFromChord + dyFromChord * dyFromChord);

              if (distFromChord < clearance) {
                final push = clearance - distFromChord + 2.0;
                final Offset perp;
                if (distFromChord < 0.5) {
                  perp = Offset(aby / abLen, -abx / abLen);
                  // Same "degenerate distance" fallback pattern as
                  // pushNodeFromRect above: if the node's centre sits
                  // (almost) exactly on the chord itself, (dxFromChord,
                  // dyFromChord) can't be normalized reliably, so instead
                  // derive a push direction directly from the chord's own
                  // direction vector, rotated 90° — (aby, -abx) is the
                  // standard "rotate a 2D vector by -90°" formula, giving
                  // a vector perpendicular to AB to push along.
                } else {
                  perp = Offset(
                      dxFromChord / distFromChord, dyFromChord / distFromChord);
                  // Normal case: push directly away from the closest point
                  // on the chord, i.e. along the already-known
                  // (dxFromChord, dyFromChord) direction, normalized.
                }
                node.position = Offset(
                  node.position.dx + perp.dx * push,
                  node.position.dy + perp.dy * push,
                );
                anyMoved = true;
              }
            }
          }
        }

        // ── Check C: non-self-loop textbox clearance ────────────────────
        if (line.label.isNotEmpty) {
          // re-read after chord push
          final lineCount = '\n'.allMatches(line.label).length + 1;
          final double boxHeight = lineHeight * lineCount;

          final Offset topLeft = line.getTextBoxLocation(
              cA, cB, boxWidth, boxHeight, line.label);
          // Unlike the self-loop textbox above (whose centre this file
          // computes itself, mirroring LineData's own logic), the
          // non-self-loop label position is instead obtained by calling
          // LineData.getTextBoxLocation directly — presumably because a
          // curved (perpendicularPart-bowed) line's label position depends
          // on rendering details (the bow amount, direction, etc.) that
          // are simpler to delegate to the same method LineWidget itself
          // calls, rather than re-deriving the curve math independently
          // here too. Note this is called fresh on every iteration
          // ("re-read after chord push" — since `cA`/`cB` themselves don't
          // change here, but the node being tested (`node.position`) may
          // have just moved via Check B immediately above, in case
          // getTextBoxLocation's result depends on more than just cA/cB).

          final rLeft   = topLeft.dx - textBuffer;
          final rTop    = topLeft.dy - textBuffer;
          final rRight  = topLeft.dx + boxWidth  + textBuffer;
          final rBottom = topLeft.dy + boxHeight + textBuffer;
          // Unlike the self-loop textbox rect above (built from a *centre*
          // point ± half-width/height), this one is built from `topLeft` —
          // getTextBoxLocation apparently already returns the box's
          // top-left corner directly, not its centre, so the buffer is
          // simply subtracted from the top-left corner and added past the
          // bottom-right corner (topLeft + full width/height) instead of
          // the centre-based ± half-size math used above.

          if (pushNodeFromRect(node, rLeft, rTop, rRight, rBottom)) {
            anyMoved = true;
          }
        }
      }
    }

    // ── Check E: self-loop textbox spacing between nodes on same node ────────
    // When a node has multiple self-loops (shouldn't happen after merge, but
    // guard anyway) or its own self-loop label would overlap itself, adjust
    // selfLoopAngle to spread them out.
    final selfLoopsByNode = <String, List<LineData>>{};
    for (final line in lines.values) {
      if (line.nodeAId == line.nodeBId) {
        selfLoopsByNode.putIfAbsent(line.nodeAId, () => []).add(line);
      }
    }
    // Groups every self-loop line by which node it's attached to — same
    // "bucket by key, build lists lazily via putIfAbsent" pattern seen
    // elsewhere in this codebase (e.g. app_theme.dart's advancedGroups).
    for (final entry in selfLoopsByNode.entries) {
      final loopsOnNode = entry.value;
      if (loopsOnNode.length <= 1) continue;
      // Only nodes with two or more self-loops need any adjustment here —
      // per the comment above, this "shouldn't happen after merge" (some
      // upstream step is expected to combine multiple self-loop
      // transitions on the same node into a single multi-label loop line),
      // but this pass guards against it anyway rather than assuming that
      // invariant always holds.
      // Spread multiple self-loops evenly around the node.
      final angleStep = (2 * pi) / loopsOnNode.length;
      for (int i = 0; i < loopsOnNode.length; i++) {
        loopsOnNode[i].selfLoopAngle = -pi / 2 + angleStep * i;
        // Distributes N self-loops evenly around the full circle (2π),
        // starting from the default "straight up" angle (-π/2, matching
        // the default noted in Check D above) and stepping by 2π/N for
        // each subsequent loop — e.g. two loops end up at -π/2 and
        // -π/2 + π (i.e. straight up and straight down), three loops at
        // 120° apart, etc.
      }
    }
    // Note: unlike Checks A-D, Check E does NOT set `anyMoved = true` even
    // though it does mutate line data (selfLoopAngle) — this reassignment
    // happens unconditionally on every iteration where a node has >1
    // self-loop (not just when something actually changed), and doesn't
    // factor into the convergence/early-exit decision below. In practice
    // this is likely harmless since the angles it computes are a pure,
    // stable function of `loopsOnNode.length` (which doesn't change across
    // iterations) — it will reassign the *same* angles every pass without
    // actually altering the layout after the first time, so it doesn't
    // prevent convergence; it's just redundant recomputation on every
    // remaining iteration.

    if (!anyMoved) break;
    // Exits as soon as a full pass produces zero node movement from Checks
    // A-D — Check E's own (possibly redundant but harmless) work doesn't
    // gate this decision either way.
  }
}