// ─────────────────────────────────────────────────────────────────────────────
//  automaton_type_checker.dart
//
//  Classifies a user-built automaton as a DFA or NFA, and produces
//  human-readable explanations of every violation when the wrong type is
//  submitted for a puzzle that requires a specific one.
//
//  Usage (from your puzzle / game-gate layer):
//
//    final result = AutomatonTypeChecker.check(
//      nodes: myNodes,
//      lines: myLines,
//      startArrow: _startArrow,           // StartArrowData? from screen state
//      alphabet: {'a', 'b'},              // symbols the puzzle defines
//      required: RequiredAutomatonType.dfa,
//    );
//
//    if (!result.isCorrectType) {
//      showFeedback(result.primaryMessage, result.detailedViolations);
//    }
// ─────────────────────────────────────────────────────────────────────────────

import 'models.dart'; // NodeData, LineData, StartArrowData

// ─── Public contract ──────────────────────────────────────────────────────────

/// Which automaton type a puzzle requires.
enum RequiredAutomatonType {
  /// Every state must have exactly one transition per alphabet symbol,
  /// no epsilon (ε / ~) transitions, and exactly one start state.
  dfa,

  /// Any nondeterministic finite automaton is acceptable (includes DFAs,
  /// since every DFA is trivially an NFA).
  nfa,
}

/// Severity level of a single violation.
enum ViolationSeverity { error, warning }

/// One concrete reason why the automaton is not of the required type.
class AutomatonViolation {
  const AutomatonViolation({
    required this.severity,
    required this.message,
    this.affectedStateId,
    this.affectedLineId,
  });

  final ViolationSeverity severity;

  /// Plain-English explanation shown to the player.
  final String message;

  /// Optional: which state node this violation is about (for UI highlighting).
  final String? affectedStateId;

  /// Optional: which transition line this violation is about.
  final String? affectedLineId;

  @override
  String toString() => '[${severity.name.toUpperCase()}] $message';
}

/// The full result returned by [AutomatonTypeChecker.check].
class AutomatonTypeResult {
  const AutomatonTypeResult._({
    required this.detectedType,
    required this.requiredType,
    required this.violations,
  });

  /// What we detected the player's automaton to actually be.
  final RequiredAutomatonType detectedType;

  /// What the puzzle requires.
  final RequiredAutomatonType requiredType;

  /// All reasons why the automaton fails to be the required type.
  /// Empty when [isCorrectType] is true.
  final List<AutomatonViolation> violations;

  /// True when the player's automaton satisfies the puzzle requirement.
  bool get isCorrectType => violations.isEmpty;

  /// A single top-level message to show the player (e.g. in a snack-bar or
  /// banner).  Only meaningful when [isCorrectType] is false.
  String get primaryMessage {
    switch (requiredType) {
      case RequiredAutomatonType.dfa:
        return 'Your automaton is an NFA, but this puzzle requires a DFA.';
      case RequiredAutomatonType.nfa:
        // A DFA is always a valid NFA, so this branch fires only when the
        // puzzle explicitly requires a *proper* NFA (i.e. nondeterminism is
        // mandatory — uncommon but supported).
        return 'Your automaton is a DFA, but this puzzle requires a proper NFA '
            '(it must include at least one nondeterministic feature).';
    }
  }

  /// Bullet-point list of violations suitable for an expanded error panel.
  List<String> get detailedViolations =>
      violations.map((v) => v.message).toList();
}

// ─── Checker implementation ───────────────────────────────────────────────────

class AutomatonTypeChecker {
  AutomatonTypeChecker._();

  // ── Epsilon label detection ────────────────────────────────────────────────

  // Labels are split on commas OR newlines.
  // The simulator stores the literal two-character sequence `\n` in DSL strings
  // (not a real newline), so we match both real newlines AND the escaped form.
  static final _labelSplitter = RegExp(r'[,\n]|\\n');

  /// Returns true if [raw] encodes an epsilon (ε / ~ / empty) transition.
  /// Mirrors the logic in AutomataSimulator._isEpsilonLabel.
  ///
  /// NOTE: `?` and `\0` are "null-jump" epsilons that fire only at end-of-input
  /// in the simulator, but for DFA type-checking purposes any unconditional
  /// free-jump counts as an NFA feature.
  static bool _isEpsilonSymbol(String raw) {
    final s = raw.trim();
    return s.isEmpty || s == '~' || s == 'ε' || s == '?' || s == r'\0';
  }

  /// Splits a compound label (e.g. "a,b" or "a\nb") into individual symbols.
  static List<String> _splitLabel(String label) =>
      label.split(_labelSplitter).map((s) => s.trim()).toList();

  // ── Public entry point ────────────────────────────────────────────────────

  /// Checks the player's automaton against [required] and returns a result
  /// describing every violation (if any).
  ///
  /// [startArrow] is the screen's current [StartArrowData?].  The app allows
  /// at most one start arrow, so the only start-state DFA violation possible
  /// is a missing start arrow entirely.
  ///
  /// [alphabet] is the set of input symbols the puzzle defines.  Used to
  /// detect missing transitions (an important DFA violation).  Pass an empty
  /// set to skip that check.
  static AutomatonTypeResult check({
    required Map<String, NodeData> nodes,
    required Map<String, LineData> lines,
    required StartArrowData? startArrow,
    required Set<String> alphabet,
    required RequiredAutomatonType required,
  }) {
    final nfaViolations = _collectNfaFeatures(
      nodes: nodes,
      lines: lines,
      startArrow: startArrow,
      alphabet: alphabet,
    );

    // A graph is a DFA when it has zero NFA features.
    final detectedType = nfaViolations.isEmpty
        ? RequiredAutomatonType.dfa
        : RequiredAutomatonType.nfa;

    switch (required) {
      case RequiredAutomatonType.dfa:
        return AutomatonTypeResult._(
          detectedType: detectedType,
          requiredType: required,
          violations: nfaViolations,
        );

      case RequiredAutomatonType.nfa:
        // Player must have built a *proper* NFA.  A DFA is the only violation.
        if (detectedType == RequiredAutomatonType.dfa) {
          return AutomatonTypeResult._(
            detectedType: detectedType,
            requiredType: required,
            violations: const [
              AutomatonViolation(
                severity: ViolationSeverity.error,
                message:
                    'Your automaton is deterministic (a DFA). This puzzle '
                    'requires nondeterminism — add an ε-transition or give a '
                    'state more than one transition for the same symbol.',
              ),
            ],
          );
        }
        return AutomatonTypeResult._(
          detectedType: detectedType,
          requiredType: required,
          violations: const [],
        );
    }
  }

  // ── NFA feature detection ─────────────────────────────────────────────────

  /// Collects every feature that makes the automaton an NFA rather than a DFA.
  /// Returns an empty list when the automaton qualifies as a valid DFA.
  static List<AutomatonViolation> _collectNfaFeatures({
    required Map<String, NodeData> nodes,
    required Map<String, LineData> lines,
    required StartArrowData? startArrow,
    required Set<String> alphabet,
  }) {
    final violations = <AutomatonViolation>[];

    // ── 1. Missing start state ─────────────────────────────────────────────
    // The app uses a single StartArrowData to designate the start state.
    // If it is absent the automaton has no start state, which is invalid for
    // both DFAs and NFAs, but we report it as a DFA violation here.
    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      violations.add(const AutomatonViolation(
        severity: ViolationSeverity.error,
        message:
            'No start state is set. A DFA must have exactly one start state — '
            'place the start arrow on the initial state.',
      ));
    }

    // Build a lookup: stateId → { symbol → [target state ids] }
    final Map<String, Map<String, List<String>>> transitionMap = {};
    final Map<String, List<String>> epsilonTargets = {};

    for (final line in lines.values) {
      final from = line.nodeAId;
      final to = line.nodeBId;

      for (final symbol in _splitLabel(line.label)) {
        if (_isEpsilonSymbol(symbol)) {
          // ── 2. Epsilon transitions ───────────────────────────────────────
          epsilonTargets.putIfAbsent(from, () => []).add(to);
        } else {
          transitionMap
              .putIfAbsent(from, () => {})
              .putIfAbsent(symbol, () => [])
              .add(to);
        }
      }
    }

    // Report epsilon transitions — one violation per source state.
    epsilonTargets.forEach((stateId, targets) {
      final uniqueTargets = targets.toSet();
      violations.add(AutomatonViolation(
        severity: ViolationSeverity.error,
        affectedStateId: stateId,
        message:
            'State ${_stateNameById(stateId, nodes)} has an ε-transition '
            '(epsilon / empty-string transition) to '
            '${uniqueTargets.map((t) => _stateNameById(t, nodes)).join(', ')}. '
            'DFAs do not allow ε-transitions — every transition must consume '
            'exactly one input symbol.',
      ));
    });

    // ── 3. Nondeterminism: multiple transitions for the same symbol ────────
    transitionMap.forEach((stateId, bySymbol) {
      bySymbol.forEach((symbol, targets) {
        if (targets.length > 1) {
          violations.add(AutomatonViolation(
            severity: ViolationSeverity.error,
            affectedStateId: stateId,
            message:
                'State ${_stateNameById(stateId, nodes)} has '
                '${targets.length} transitions for symbol "$symbol" '
                '(to ${targets.map((t) => _stateNameById(t, nodes)).join(', ')}). '
                'A DFA must have exactly one transition per symbol per state — '
                'this creates nondeterminism.',
          ));
        }
      });
    });

    // ── 4. Missing transitions (incomplete transition function) ────────────
    // Only checked when the caller supplied the puzzle alphabet.
    if (alphabet.isNotEmpty) {
      for (final node in nodes.values) {
        // Halt states intentionally have no outgoing transitions — skip them.
        if (node.isHaltAccept || node.isHaltReject) continue;

        final bySymbol = transitionMap[node.id] ?? {};
        for (final symbol in alphabet) {
          if ((bySymbol[symbol] ?? []).isEmpty) {
            violations.add(AutomatonViolation(
              severity: ViolationSeverity.warning,
              affectedStateId: node.id,
              message:
                  'State ${_stateName(node)} has no transition for symbol '
                  '"$symbol". A complete DFA must define exactly one transition '
                  'for every symbol in every state. '
                  'Consider adding a transition to a dead/trap state.',
            ));
          }
        }
      }
    }

    return violations;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _stateName(NodeData node) =>
      node.label.trim().isNotEmpty ? '"${node.label.trim()}"' : node.id;

  static String _stateNameById(String id, Map<String, NodeData> nodes) {
    final node = nodes[id];
    if (node == null) return id;
    return _stateName(node);
  }
}