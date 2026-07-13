import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../widgets/app_theme.dart';
import '../models.dart';
import '../simulator.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  batch_simulator_dialog.dart
//
//  A dialog that lets the user paste/import a whole list of candidate
//  strings (one per line) and see, per line, whether the currently-loaded
//  automaton accepts or rejects it — colorizing each line green/red in
//  place inside the text field itself, rather than showing results in a
//  separate list. The tricky part of this file isn't the UI, it's safely
//  reusing the *live* simulator instance (shared with the rest of the
//  screen) to test each candidate line without permanently corrupting its
//  state for the string the main screen was actually showing — see the
//  large comment above rebuildResults() for why that's harder than it
//  sounds.
// ─────────────────────────────────────────────────────────────────────────────

/// A TextEditingController whose `buildTextSpan` override colorizes each
/// line green (accepted), red (rejected), or default white (not yet
/// tested / incomplete), instead of rendering the field as plain
/// single-colored text. This is what makes the batch simulator show
/// results *inline*, directly in the text the user typed, rather than in a
/// separate results panel.
class _BatchHighlightController extends TextEditingController {
  _BatchHighlightController({required this.isAccepted, required this.isRejected});

  /// Callback consulted per rendered line index to decide its color.
  /// Backed by the `accepted` Set captured in the enclosing
  /// showBatchSimulatorDialog closure (see below) — this controller has no
  /// simulation logic of its own, it's purely a rendering layer over
  /// externally-computed results.
  final bool Function(int lineIndex) isAccepted;
  final bool Function(int lineIndex) isRejected;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    // Re-split the full text into lines every time this is called (i.e. on
    // every frame the field is painted) purely for *rendering* purposes.
    // This is a separate split from the one done in rebuildResults() below
    // for *simulation* purposes — both must stay in sync on the same
    // `text.split('\n')` semantics for line indices to line up between "is
    // this line accepted" (computed once, on text change) and "what color
    // is line N" (recomputed every paint). They do, since both simply call
    // `.split('\n')` on the same underlying `text`.
    final lines = text.split('\n');
    final children = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      // NOTE: the `Colors.white` fallback just below is a bare Colors
      // constant, not sourced from AppThemeNotifier the way virtually
      // every other color in this file (and the wider app) is. On a light
      // theme, plain white text in the batch field would be near-invisible
      // against a light background... except the TextField's `fillColor`
      // further down is hardcoded to `const Color(0xFF080D14)` (near-
      // black), independent of the current theme too, so the two
      // hardcoded values happen to stay compatible with each other today.
      // But if the field's background were ever switched to follow the
      // theme (as its border colors already do via `theme.borderMid`),
      // this hardcoded white text would become unreadable in light mode.
      // Worth threading `theme.textLight` through to this controller
      // instead of a bare constant, for future-proofing.
      final color = isAccepted(i)
          ? Colors.green
          : isRejected(i)
              ? Colors.red
              // Neither accepted nor rejected yet — either the line hasn't
              // been "completed" (see isComplete in rebuildResults, e.g.
              // it's the very last line and the user hasn't pressed Enter
              // yet), or it's empty.
              : Colors.white;
      children.add(TextSpan(
        text: lines[i],
        style: GoogleFonts.courierPrime(color: color, fontSize: 16),
      ));
      // Re-insert the newline character between lines (split() consumes
      // the delimiters), styled in the default color so the line break
      // itself doesn't inherit whatever color the preceding line's verdict
      // was. Skipped after the very last line since there's nothing after
      // it to separate.
      if (i != lines.length - 1) {
        children.add(TextSpan(
          text: '\n',
          style: GoogleFonts.courierPrime(color: Colors.white, fontSize: 16),
        ));
      }
    }

    return TextSpan(children: children);
  }
}

/// Opens the batch simulator dialog.
///
/// Exactly one of [pdaSimulator] / [tmSimulator] should be passed for
/// PDA/TM automata respectively; leave both null to batch-test a plain
/// DFA/NFA/regex via [simulator]. This mirrors how the rest of the app
/// distinguishes automaton kind — by which optional simulator argument is
/// non-null — rather than via an explicit enum parameter.
Future<void> showBatchSimulatorDialog(
  BuildContext context, {
  required AutomataSimulator simulator,
  PdaSimulator? pdaSimulator,
  TmSimulator? tmSimulator,
  required StartArrowData? startArrow,
  // The string currently loaded in the main string-simulator panel, plus any
  // extra-tape inputs (TM only). Needed to restore each simulator to its
  // pre-batch state once every candidate line has been tested — see the
  // comment above `rebuildResults()` for why this must be a full rebuild()
  // rather than a manual field-by-field restore.
  required String currentInput,
  List<String> additionalTapeInputs = const [],
}) async {
  // Line indices (not the strings themselves) that came back
  // accept/reject. Declared *outside* the StatefulBuilder's local state
  // deliberately: these Sets are mutated in place by rebuildResults() and
  // read by both the highlight controller (every paint) and the summary
  // chip counts (every dialog rebuild) — using plain mutable Sets captured
  // by closure, rather than State fields, means updates don't by
  // themselves trigger a rebuild; that's *why* every call site that
  // mutates them is paired with an explicit `setLocalState(() {})` nearby
  // (see onChanged and the Import button below).
  final accepted = <int>{};
  final rejected = <int>{};
  // `late` because it's constructed just below, referencing the two Sets
  // above and this dialog's own rebuildResults function, but is itself
  // referenced from within rebuildResults's closure scope too (mutual
  // reference resolved by declaring the variable first and assigning
  // after both are in scope).
  late _BatchHighlightController controller;

  // Each iteration below drives a simulator through rebuild(candidateString)
  // purely to read off its accept/reject verdict, then must put that
  // simulator back exactly how it was so the main screen keeps showing the
  // *original* string's state once this dialog closes.
  //
  // That restoration used to be done by hand-copying a few public fields
  // (tokens, steps, step, states, usedLines). That was never enough:
  //   - AutomataSimulator additionally tracks acceptance via a *private*
  //     field (_configsByStep) that the dialog has no way to reach and copy
  //     back, so finalResult() kept reflecting the last batch line tested.
  //   - PdaSimulator/TmSimulator also carry loop/halt flags
  //     (stackGrowthLoopDetected / noMovesTerminal) and their own `tokens`
  //     list that weren't part of the manual restore, risking a stale
  //     "loop detected" result and a RangeError in remainingInputAt() if a
  //     later string were shorter than the last batch line tested.
  //
  // Rebuilding each simulator against `currentInput` after the test is the
  // one operation guaranteed to reset *all* of that state at once, public
  // or private, because it's the same code path the main screen itself uses
  // to build a simulator's state from a string. The extra rebuild per line
  // is negligible for the string lengths this dialog is used with.
  void rebuildResults() {
    // Full recompute every call, rather than an incremental diff against
    // the previous accepted/rejected sets — simplest-correct approach
    // given this runs on every keystroke; see the performance note further
    // down about this being called twice on import.
    accepted.clear();
    rejected.clear();

    final lines = controller.text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      // Defensively strip stray '\r' (Windows-style CRLF line endings would
      // otherwise leave a trailing carriage-return character glued onto
      // every line except possibly the last after splitting only on '\n').
      final str = lines[i].replaceAll('\r', '');
      // A line only counts as ready to simulate once the user has "closed"
      // it — either it's not the last line at all (so there must be a '\n'
      // after it), or it IS the last line but the whole text also happens
      // to end in '\n' (i.e. they just pressed Enter after typing it). The
      // practical effect: the very last line of a string still being typed
      // (no trailing newline yet) is deliberately left untested — matches
      // the field's own hint text, "Press enter to simulate."
      final isComplete = i < lines.length - 1 || controller.text.endsWith('\n');
      if (!isComplete || str.isEmpty) continue;

      if (tmSimulator != null) {
        // Snapshot the step the user currently has selected/scrubbed to in
        // the main TM step viewer, so it can be restored below — testing a
        // batch line shouldn't silently reset which step the main panel is
        // showing.
        final oldStep = tmSimulator.step;

        tmSimulator.rebuild(str, startArrow: startArrow);
        final result = tmSimulator.result;

        if (result == TmResult.accept) {
          accepted.add(i);
        } else if (result == TmResult.reject) {
          rejected.add(i);
        }
        // Implicit third outcome: neither branch taken (e.g. TmResult has
        // some "running/undecided" state such as a step-limit-exceeded or
        // still-in-progress result) leaves line `i` in neither accepted
        // nor rejected — it will render in the default white/untested
        // color even though it *was* tested. Whether that's intended
        // depends on what other TmResult values exist and mean; worth
        // double-checking TM results that aren't a clean accept/reject
        // (e.g. "undecided"/timeout) don't get silently displayed as if
        // they were simply never run.

        // Restore: rebuild against the ORIGINAL main-panel input (plus its
        // additional tape inputs) — see the large comment above this
        // function for why a full rebuild, not a manual field copy, is
        // required here.
        tmSimulator.rebuild(
          currentInput,
          startArrow: startArrow,
          additionalTapeInputs: additionalTapeInputs,
        );
        // Re-apply the previously-selected step, clamped to the (should be
        // identical, since we rebuilt with the same input) new maxStep —
        // the clamp is a defensive no-op in the common case, not a
        // correctness-critical adjustment.
        tmSimulator.step = oldStep.clamp(-1, tmSimulator.maxStep);
      } else if (pdaSimulator != null) {
        final oldStep = pdaSimulator.step;

        pdaSimulator.rebuild(str, startArrow: startArrow);
        final result = pdaSimulator.finalResult();

        if (result == PdaSimResult.accept) {
          accepted.add(i);
        } else {
          // Unlike the TM branch above, PDA collapses every non-accept
          // result (reject, and presumably also any "undecided"/loop-
          // detected outcome PdaSimResult might have) into `rejected`. This
          // is a deliberate asymmetry with the TM branch — worth confirming
          // it's intentional: if PdaSimResult has a third state (e.g. a
          // stack-growth-loop / non-terminating case, which the big comment
          // above explicitly mentions PdaSimulator can detect via
          // `stackGrowthLoopDetected`), it will be visually indistinguishable
          // here from a clean reject, whereas the TM branch above leaves an
          // analogous "undecided" outcome uncolored instead.
          rejected.add(i);
        }

        pdaSimulator.rebuild(currentInput, startArrow: startArrow);
        pdaSimulator.step = oldStep.clamp(-1, pdaSimulator.maxStep);
      } else {
        // Plain DFA/NFA/regex path.
        final oldStep = simulator.step;

        simulator.rebuild(str, startArrow: startArrow);
        final result = simulator.finalResult();

        if (result == SimResult.accept) {
          accepted.add(i);
        } else {
          rejected.add(i);
        }

        simulator.rebuild(currentInput, startArrow: startArrow);
        simulator.step = oldStep.clamp(-1, simulator.maxStep);
      }
    }
  }

  controller = _BatchHighlightController(
    isAccepted: (i) => accepted.contains(i),
    isRejected: (i) => rejected.contains(i),
  );
  // Re-run the full batch test every time the field's text changes at all
  // (any keystroke, paste, or programmatic `.text =` assignment triggers
  // TextEditingController's internal notifyListeners()).
  controller.addListener(rebuildResults);
  // Run once immediately so results reflect any text the controller starts
  // with (currently none — controller is always constructed empty above —
  // so this initial call is a no-op today, but keeps the function
  // consistent/safe if a future change ever pre-fills the field).
  rebuildResults();

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          final theme = context.watch<AppThemeNotifier>();
          final acceptCount = accepted.length;
          final rejectCount = rejected.length;
          final totalRun    = acceptCount + rejectCount;

          return AlertDialog(
            backgroundColor: theme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.borderMid),
            ),
            title: Text(
              // Title suffix picks TM over PDA over plain, matching the
              // same precedence order rebuildResults() checks simulators
              // in above (tmSimulator first, then pdaSimulator, else the
              // base `simulator`) — kept consistent so the title always
              // accurately reflects which branch is actually running.
              'Batch String Simulator${tmSimulator != null ? ' (TM)' : pdaSimulator != null ? ' (PDA)' : ''}',
              style: GoogleFonts.courierPrime(
                color: theme.textLight,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              // Fixed dialog content size (700x500) rather than something
              // responsive to screen size — reasonable for a desktop-first
              // "power user" dialog like this, but could overflow/clip on a
              // narrow phone-width window (no isCompactLayout-style check
              // here the way other screens in this app use — see
              // responsive_layout.dart).
              width: 700,
              height: 500,
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      // expands + maxLines/minLines: null is the standard
                      // Flutter recipe for "let this TextField grow to
                      // fill its parent's height and scroll internally",
                      // as opposed to auto-sizing to its text content.
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      cursorColor: theme.accent,
                      style: GoogleFonts.courierPrime(
                          color: theme.textLight, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'One string per line...\nPress enter to simulate.',
                        hintStyle: GoogleFonts.courierPrime(color: theme.textDim),
                        filled: true,
                        // Hardcoded near-black fill regardless of app
                        // theme — see the note inside
                        // _BatchHighlightController.buildTextSpan above
                        // about why this currently "works" (it's paired
                        // with a hardcoded white/green/red text palette)
                        // but would break if only one side of that pairing
                        // were ever made theme-aware.
                        fillColor: const Color(0xFF080D14),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.borderMid),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.borderMid),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.accent, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      // The controller's own listener (added above) already
                      // recomputes accepted/rejected on every text change;
                      // this onChanged exists purely to force the
                      // StatefulBuilder to rebuild afterwards (see the note
                      // on `accepted`/`rejected` above for why a rebuild
                      // can't happen automatically here — they're plain
                      // Sets, not part of Flutter's State). By the time
                      // this fires, the controller's listener has already
                      // run synchronously and updated the Sets, so the
                      // rebuild triggered here reads fresh data.
                      onChanged: (_) => setLocalState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Summary row ──────────────────────────────────────────
                  if (totalRun > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          _SummaryChip(
                            label: '$acceptCount accepted',
                            color: const Color(0xFF1FD99A),
                          ),
                          const SizedBox(width: 8),
                          _SummaryChip(
                            label: '$rejectCount rejected',
                            color: const Color(0xFFFF1744),
                          ),
                        ],
                      ),
                    ),

                  // ── Import button ────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D1620),
                            foregroundColor: theme.textMid,
                            side: BorderSide(color: theme.borderMid),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['txt'],
                            );
                            // Two ways this can legitimately be null/empty:
                            // the user cancelled the picker (result == null),
                            // or (on web, most commonly) the picked file's
                            // bytes weren't loaded into memory for some
                            // reason. Either way, bail out silently — no
                            // error is surfaced to the user if a real read
                            // failure (as opposed to a simple cancel)
                            // occurs.
                            if (result == null ||
                                result.files.single.bytes == null) {
                              return;
                            }
                            final text = utf8.decode(
                                result.files.single.bytes!,
                                // Tolerate files that aren't strictly valid
                                // UTF-8 (e.g. saved from an editor using a
                                // different encoding) rather than throwing
                                // and losing the whole import — malformed
                                // bytes get replaced with the Unicode
                                // replacement character instead of
                                // crashing.
                                allowMalformed: true);
                            setLocalState(() {
                              // NOTE (minor redundant work): assigning
                              // `controller.text = text` fires the
                              // controller's own `rebuildResults` listener
                              // (registered above) synchronously as part of
                              // this same setState call, which already
                              // recomputes `accepted`/`rejected` for the
                              // newly-imported text. The explicit
                              // `rebuildResults()` call on the next line
                              // then runs the *entire* batch simulation a
                              // second time back-to-back, computing an
                              // identical result. Harmless for correctness
                              // (idempotent), but for a large imported file
                              // this doubles the simulation work done on
                              // import for no benefit — the explicit call
                              // could be dropped since the listener already
                              // covers it.
                              controller.text = text;
                              rebuildResults();
                            });
                          },
                          child: Text('Import .txt',
                              style: GoogleFonts.courierPrime()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  // Dialog closed (by any means — barrier tap, back button, or
  // programmatic Navigator.pop from elsewhere). `.dispose()` internally
  // clears the controller's listeners, so `rebuildResults` doesn't need to
  // be explicitly removed via `removeListener` first.
  controller.dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small summary chip
// ─────────────────────────────────────────────────────────────────────────────

/// A small rounded pill showing a count + label (e.g. "3 accepted") in a
/// tinted background matching [color], used for the accept/reject summary
/// row above the Import button.
class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // Low-alpha fill of the same color used for the border/text below,
        // giving a consistent "tinted glass" chip look without needing a
        // second explicit color per chip.
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.courierPrime(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}