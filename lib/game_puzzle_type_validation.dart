// ─────────────────────────────────────────────────────────────────────────────
//  game_puzzle_type_validation.dart
//
//  Drop-in mixin / helpers that extend your existing puzzle layer with
//  DFA-vs-NFA validation.
//
//  STEP 1 — Add RequiredAutomatonType to your puzzle model
//  ────────────────────────────────────────────────────────
//  In game_puzzle.dart (or wherever your GamePuzzle / PuzzleDefinition lives),
//  add one new field:
//
//    class GamePuzzle {
//      // … existing fields …
//      final RequiredAutomatonType requiredAutomatonType; // ← new
//      final Set<String> alphabet;                        // ← new (if not already present)
//    }
//
//  STEP 2 — Call validateType() before accepting a solution
//  ─────────────────────────────────────────────────────────
//  In your submission handler (game gate, level complete screen, etc.):
//
//    final typeResult = puzzle.validateType(
//      nodes: currentNodes,
//      lines: currentLines,
//    );
//
//    if (!typeResult.isCorrectType) {
//      // Show typeResult.primaryMessage as a banner / toast.
//      // Optionally list typeResult.detailedViolations in an expanded panel.
//      return; // block progression
//    }
//
//    // … proceed with your existing correctness check …
//
// ─────────────────────────────────────────────────────────────────────────────

import 'automaton_type_checker.dart';
import 'models.dart'; // NodeData, LineData

export 'automaton_type_checker.dart'
    show
        RequiredAutomatonType,
        AutomatonTypeResult,
        AutomatonViolation,
        ViolationSeverity;

// ─── Extension on your puzzle model ──────────────────────────────────────────

/// Add `requiredAutomatonType` and `alphabet` to your GamePuzzle class, then
/// call [validateType] inside your submission path.
///
/// Because Dart extensions cannot add fields, you store those two values on the
/// class itself (see Step 1 above) and the extension just supplies the method.
extension GamePuzzleTypeValidation<T extends Object> on T {
  // ignore: avoid_shadowing_type_parameters
  /// Validates that the player's automaton is the type required by this puzzle.
  ///
  /// [required]    — the type this puzzle expects (set on the puzzle definition).
  /// [alphabet]    — the symbol set the puzzle operates over; used to detect
  ///                 missing transitions.  Pass an empty set to skip that check.
  /// [startArrow]  — the screen's current StartArrowData (pass _startArrow from
  ///                 your state).  Required so the checker can detect a missing
  ///                 start state; passing null always produces a false violation.
  AutomatonTypeResult validateAutomatonType({
    required RequiredAutomatonType required,
    required Set<String> alphabet,
    required Map<String, NodeData> nodes,
    required Map<String, LineData> lines,
    required StartArrowData? startArrow,
  }) {
    return AutomatonTypeChecker.check(
      nodes: nodes,
      lines: lines,
      startArrow: startArrow,
      alphabet: alphabet,
      required: required,
    );
  }
}

// ─── Convenience widget helper ────────────────────────────────────────────────

/// Produces a structured, player-facing error message from a failed type check.
///
/// Returns null when [result] reports no violations (the automaton is correct).
///
/// Use this in your UI layer:
///
///   final msg = buildTypeErrorMessage(typeResult);
///   if (msg != null) showErrorBanner(msg);
///
TypeCheckDisplayMessage? buildTypeErrorMessage(AutomatonTypeResult result) {
  if (result.isCorrectType) return null;

  // Separate hard errors from warnings.
  final errors = result.violations
      .where((v) => v.severity == ViolationSeverity.error)
      .toList();
  final warnings = result.violations
      .where((v) => v.severity == ViolationSeverity.warning)
      .toList();

  return TypeCheckDisplayMessage(
    headline: result.primaryMessage,
    errors: errors.map((v) => v.message).toList(),
    warnings: warnings.map((v) => v.message).toList(),
    // IDs for optional UI highlighting of offending states / transitions.
    affectedStateIds:
        result.violations.map((v) => v.affectedStateId).whereType<String>().toSet(),
    affectedLineIds:
        result.violations.map((v) => v.affectedLineId).whereType<String>().toSet(),
  );
}

/// Plain-data class the UI layer consumes.  No Flutter dependency — convert
/// to your preferred widget / dialog in the presentation layer.
class TypeCheckDisplayMessage {
  const TypeCheckDisplayMessage({
    required this.headline,
    required this.errors,
    required this.warnings,
    required this.affectedStateIds,
    required this.affectedLineIds,
  });

  /// Short banner text, e.g. "Your automaton is an NFA, but this puzzle
  /// requires a DFA."
  final String headline;

  /// Each item is one bullet explaining a hard error (ε-transition, duplicate
  /// transition for a symbol, multiple start states).
  final List<String> errors;

  /// Each item is one bullet for a soft warning (missing transition).
  final List<String> warnings;

  /// State node IDs that could be highlighted red in the graph canvas.
  final Set<String> affectedStateIds;

  /// Transition line IDs that could be highlighted red in the graph canvas.
  final Set<String> affectedLineIds;

  /// True when there are only warnings and no hard errors — the player is
  /// close but their DFA is incomplete rather than outright nondeterministic.
  bool get onlyWarnings => errors.isEmpty && warnings.isNotEmpty;

  @override
  String toString() {
    final buffer = StringBuffer()..writeln(headline);
    for (final e in errors) {
      buffer.writeln('  ✗ $e');
    }
    for (final w in warnings) {
      buffer.writeln('  ⚠ $w');
    }
    return buffer.toString().trim();
  }
}

// ─── Usage example (remove before shipping) ──────────────────────────────────
//
// void _onPlayerSubmit(
//   GamePuzzle puzzle,
//   Map<String, NodeData> nodes,
//   Map<String, LineData> lines,
// ) {
//   final typeResult = AutomatonTypeChecker.check(
//     nodes: nodes,
//     lines: lines,
//     alphabet: puzzle.alphabet,
//     required: puzzle.requiredAutomatonType,
//   );
//
//   final msg = buildTypeErrorMessage(typeResult);
//   if (msg != null) {
//     // Block submission and show feedback.
//     _showErrorSheet(
//       headline: msg.headline,
//       bullets: [...msg.errors, ...msg.warnings],
//       highlightStates: msg.affectedStateIds,
//       highlightLines: msg.affectedLineIds,
//     );
//     return;
//   }
//
//   // ── Type is correct.  Continue with your normal solution check. ──
//   final simResult = _runSimulator(nodes, lines, puzzle.testCases);
//   if (simResult.allPassed) {
//     progressStore.markCompleted(puzzle.id);
//   }
// }