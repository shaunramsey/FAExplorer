// ─────────────────────────────────────────────────────────────────────────────
//  equivalence_dialog.dart
//
//  Everything related to validating a player/user's automaton against
//  another automaton or a required shape, in one place:
//
//    1. EQUIVALENCE ALGORITHMS — decide whether two automata accept exactly
//       the same language:
//         • checkEquivalence()    — NFA/DFA: exact BFS over the product of
//           both machines' powerset constructions. Produces a short
//           distinguishing witness string when the languages differ.
//         • checkPdaEquivalence() / checkTmEquivalence() — PDA/TM: bounded
//           search over candidate input strings (equivalence is undecidable
//           in general for these models), so the result may come back as
//           unknownCapReached rather than a proof of equivalence.
//
//    2. AUTOMATON TYPE CHECKING — AutomatonTypeChecker.check() classifies a
//       *single* automaton as a DFA or NFA (no comparison to another
//       automaton involved) and produces human-readable violation messages
//       when a puzzle requires a specific type the player didn't build. This
//      is used by the equivalence dialog to give the player feedback when
//      they submit a DFA for a puzzle that explicitly requires nondeterminism.
//
//    3. DIALOG — showEquivalenceDialog() opens a bottom sheet / dialog that
//       lets the user paste or type two DSL strings and runs the equivalence
//       algorithms above, displaying the result from checkEquivalence algorithms
//
//  NOTE: everything in sections 1 and 2 is plain Dart with no dependency on
//  section 3's dialog UI — game_puzzle.dart, game_data.dart, and
//  game_level.dart import this file for algorithm/type-checking access only,
//  never touching the dialog.
// ─────────────────────────────────────────────────────────────────────────────

// Needed for the dialog UI in section 3 (Dialog, TextField, Icons, etc.).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// Brings in `DslCodec.importFromDsl`, used by the dialog to parse the two
// pasted DSL strings into GraphState objects.
import '../import_export.dart';
import '../models.dart';
// Brings in PdaSimulator / TmSimulator and their result enums, used by the
// bounded-search PDA/TM equivalence checks.
import '../simulator.dart';
import '../widgets/app_theme.dart';
// Brings in only the AutomataMode enum (ndfa/regex/pda/tm) from the drawer
import '../widgets/automata_drawer.dart' show AutomataMode;

// ═════════════════════════════════════════════════════════════════════════════
//  1. EQUIVALENCE ALGORITHMS
// ═════════════════════════════════════════════════════════════════════════════

enum EquivalenceStatus {
  equivalent,
  notEquivalent,
  // For PDA/TM: the bounded search exhausted its budget without finding a
  // difference, so equivalence could not be decided either way. (Normal)
  unknownCapReached,
  // One or both automata have no valid start state, so the check couldn't
  // even begin. (Just a quick end to let the user know)
  noStartState,
}

// Immutable value object bundling the status of an equivalence check together
// with the extra data (witness string, which machine accepted it)
class EquivalenceResult {
  final EquivalenceStatus status;
  final String? witness;

  /// Which machine accepts the witness (1 or 2)
  final int acceptedByMachine;

  // Named constructor for the "equivalent" case: no witness needed, and
  // "accepted by" is meaningless (0) since nothing differs.
  const EquivalenceResult.equivalent()
      : status = EquivalenceStatus.equivalent,
        witness = null,
        acceptedByMachine = 0;

  // Named constructor for the "not equivalent" case: caller must supply the
  // witness string and which machine (1 or 2) accepts it.
  // `String this.witness` is Dart's syntax for "initialize the final field
  // `witness` directly from this positional constructor parameter".
  const EquivalenceResult.notEquivalent(String this.witness, this.acceptedByMachine)
      : status = EquivalenceStatus.notEquivalent;

  const EquivalenceResult.capReached()
      : status = EquivalenceStatus.unknownCapReached,
        witness = null,
        acceptedByMachine = 0;

  const EquivalenceResult.noStart()
      : status = EquivalenceStatus.noStartState,
        witness = null,
        acceptedByMachine = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top-level entry point
// ─────────────────────────────────────────────────────────────────────────────

// Exact equivalence check for NFA/DFA (and regex, which compiles down to an
// NFA before reaching here). Named parameters make the two machines'
// nodes/lines/start-arrow triples explicit and hard to mix up at call sites.
EquivalenceResult checkEquivalence({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
}) {
  // Guard: machine 1 must have a start arrow that actually points at an
  // existing node. If not, bail out immediately — there is nothing to search.
  if (startArrow1 == null || !nodes1.containsKey(startArrow1.nodeId)) {
    return const EquivalenceResult.noStart();
  }
  // Same guard for machine 2.
  if (startArrow2 == null || !nodes2.containsKey(startArrow2.nodeId)) {
    return const EquivalenceResult.noStart();
  }

  // Wrap each machine's raw node/line maps in a small adapter that knows how
  // to compute epsilon-closures, symbol steps, and acceptance (see
  // _NfaAdapter below).
  final nfa1 = _NfaAdapter(nodes: nodes1, lines: lines1);
  final nfa2 = _NfaAdapter(nodes: nodes2, lines: lines2);

  // Build the combined concrete alphabet from both machines, then share it so
  // that `.` and `.-X` expand correctly relative to all declared symbols.
  final alphabet = <String>{
    // Spread every concrete symbol used by machine 1's transitions...
    ...nfa1.collectConcreteSymbols(),
    // ...and every concrete symbol used by machine 2's transitions, into one
    // combined set (duplicates collapse automatically since this is a Set).
    ...nfa2.collectConcreteSymbols(),
  };
  // Give each adapter the *union* alphabet so wildcard tokens (`.`, `.-X`)
  // are interpreted consistently across both machines during the BFS.
  nfa1.alphabet = alphabet;
  nfa2.alphabet = alphabet;

  // Initial powerset states after ~-closure of each start node.
  final init1 = nfa1.epsilonClosure({startArrow1.nodeId});
  final init2 = nfa2.epsilonClosure({startArrow2.nodeId});

  // Hand off to the actual product-BFS search.
  return _bfs(nfa1, nfa2, init1, init2, alphabet);
}

// ─────────────────────────────────────────────────────────────────────────────
//  BFS over the cross-product of the two NFAs' powerset constructions
// ─────────────────────────────────────────────────────────────────────────────

// Safety valve: if the BFS visits more than this many distinct powerset-pair
// states, give up rather than risk an unbounded/slow search (large or
// pathological graphs could otherwise blow up combinatorially).
const int _kBfsCap = 8000;

// Explores pairs of "which powerset state is each machine currently in"
// simultaneously, symbol by symbol, looking for an input where exactly one
// machine accepts. This is the classic technique for deciding NFA/DFA
// language equivalence exactly and efficiently (no need to fully determinize
// either machine ahead of time — states are expanded lazily).
EquivalenceResult _bfs(
  _NfaAdapter nfa1,
  _NfaAdapter nfa2,
  Set<String> init1,
  Set<String> init2,
  Set<String> alphabet,
) {
  // BFS node: (frozenSet1, frozenSet2, pathSoFar)
  // We encode a Set<String> as a sorted joined string for use as a map key.
  // Sorting first guarantees that two sets with the same elements in
  // different insertion orders produce identical keys; the NUL separator
  // ('\x00') is chosen because it can't appear in a state id.
  String freeze(Set<String> s) => (s.toList()..sort()).join('\x00');

  // The starting pair, encoded as "frozen(set1)|frozen(set2)".
  final initKey = '${freeze(init1)}|${freeze(init2)}';
  // Map from encoded pair → path of symbols taken to reach it. Doubles as
  // the "visited" set: if a key is present, we've already queued/processed
  // that pair and don't need to do so again.
  final visited = <String, List<String>>{initKey: const []};
  // The BFS frontier. Each record bundles the current powerset state of
  // both machines together with the input string (as a symbol list) that
  // leads to this state from the start.
  final queue = <({Set<String> s1, Set<String> s2, List<String> path})>[
    (s1: init1, s2: init2, path: const []),
  ];

  // Check starting pair immediately (handles ~-only acceptance).
  // This covers the case where the empty string ~ itself is a distinguishing
  // witness (one machine accepts immediately, the other doesn't).
  final initCheck = _checkAcceptance(nfa1, nfa2, init1, init2, const []);
  if (initCheck != null) return initCheck;

  // Standard BFS loop: pop the front of the queue, try every symbol, and
  // enqueue any newly-discovered pair of powerset states.
  while (queue.isNotEmpty) {
    // Abort if the search has grown too large — treat as "can't decide".
    if (visited.length > _kBfsCap) return const EquivalenceResult.capReached();

    // Dequeue the next pair to expand. `removeAt(0)` gives FIFO (true BFS)
    // ordering, which matters because we want the *shortest* distinguishing
    // witness, not just any witness.
    final (:s1, :s2, :path) = queue.removeAt(0);

    // Try every symbol in the shared alphabet as the next input character.
    for (final symbol in alphabet) {
      // Step each machine's powerset state by `symbol`, then re-close under
      // ~/null-jumps to get the next "settled" powerset state.
      final next1 = nfa1.epsilonClosure(nfa1.step(s1, symbol));
      final next2 = nfa2.epsilonClosure(nfa2.step(s2, symbol));

      // Encode the resulting pair the same way as above.
      final key = '${freeze(next1)}|${freeze(next2)}';
      // Skip pairs we've already discovered — no need to re-process.
      if (visited.containsKey(key)) continue;

      // Extend the path with this symbol to record how we got here.
      final newPath = [...path, symbol];
      visited[key] = newPath;

      // Check whether this new pair already distinguishes the two machines.
      final check = _checkAcceptance(nfa1, nfa2, next1, next2, newPath);
      if (check != null) return check;

      // Otherwise, queue it up for further expansion.
      queue.add((s1: next1, s2: next2, path: newPath));
    }
  }

  // Queue exhausted with no distinguishing input found anywhere in the
  // (finite, since both machines have finitely many states) product
  // automaton — the languages are provably identical.
  return const EquivalenceResult.equivalent();
}

/// Returns a non-null [EquivalenceResult] iff [s1] and [s2] differ in
/// acceptance, otherwise null (both accept or both reject → keep searching).
EquivalenceResult? _checkAcceptance(
  _NfaAdapter nfa1,
  _NfaAdapter nfa2,
  Set<String> s1,
  Set<String> s2,
  List<String> path,
) {
  // Does machine 1's current powerset state contain an accepting state?
  final acc1 = nfa1.anyAccepts(s1);
  // Same question for machine 2.
  final acc2 = nfa2.anyAccepts(s2);

  // If both machines agree (both accept or both reject), this input prefix
  // doesn't distinguish them — signal "keep searching" with null.
  if (acc1 == acc2) return null;

  // They disagree: the symbols consumed so far (`path`) is a distinguishing
  // witness. Join the symbol list back into a single display string.
  final witness = path.join();
  // Figure out which machine (1 or 2) is the one that accepts.
  final acceptedBy = acc1 ? 1 : 2;
  return EquivalenceResult.notEquivalent(witness, acceptedBy);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Best-effort PDA/TM equivalence checking by bounded input search
// ─────────────────────────────────────────────────────────────────────────────

// Outcome of simulating one candidate input string on one machine.
// `unknown` covers cases the simulator itself can't resolve confidently,
// e.g. a PDA stuck in a stack-growth loop, or a TM that hasn't halted within
// the step budget — these inputs are simply skipped rather than trusted.
enum _AcceptanceOutcome { accept, reject, unknown }

// Bounded-search equivalence check for pushdown automata. Because language
// equivalence is undecidable for PDAs in general, this can only ever *prove*
// inequivalence (by finding a witness) — it can never prove equivalence, so
// running out of candidates yields `unknownCapReached` rather than
// `equivalent`.
EquivalenceResult checkPdaEquivalence({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
  // Longest candidate input string to try, in tokens.
  int maxInputLength = 4,
  // Maximum number of candidate inputs to simulate before giving up.
  int maxTests = 400,
}) {
  // Same start-state guards as checkEquivalence.
  if (startArrow1 == null || !nodes1.containsKey(startArrow1.nodeId)) {
    return const EquivalenceResult.noStart();
  }
  if (startArrow2 == null || !nodes2.containsKey(startArrow2.nodeId)) {
    return const EquivalenceResult.noStart();
  }

  // Union of both machines' declared stack/read alphabets, used to generate
  // candidate test strings.
  final alphabet = <String>{
    ..._pdaAlphabet(lines1),
    ..._pdaAlphabet(lines2),
  };

  // Delegate the actual "generate inputs, simulate both, compare" loop to
  // the shared helper, plugging in PDA-specific simulate functions.
  return _checkEquivalenceByTestingInputs(
    nodes1: nodes1,
    lines1: lines1,
    startArrow1: startArrow1,
    nodes2: nodes2,
    lines2: lines2,
    startArrow2: startArrow2,
    alphabet: alphabet,
    maxInputLength: maxInputLength,
    maxTests: maxTests,
    // Closures capturing each machine's own nodes/lines/startArrow, so the
    // shared helper only needs to know "simulate this input string".
    simulate1: (input) => _simulatePda(nodes1, lines1, startArrow1, input),
    simulate2: (input) => _simulatePda(nodes2, lines2, startArrow2, input),
  );
}

// Same idea as checkPdaEquivalence but for Turing machines, which also add a
// per-input step budget (`maxStepsPerInput`) since a TM might never halt.
EquivalenceResult checkTmEquivalence({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
  int maxInputLength = 4,
  int maxTests = 400,
  // Caps how many simulation steps a single candidate input may run before
  // it's treated as "unknown" (guards against non-halting machines).
  int maxStepsPerInput = 300,
}) {
  if (startArrow1 == null || !nodes1.containsKey(startArrow1.nodeId)) {
    return const EquivalenceResult.noStart();
  }
  if (startArrow2 == null || !nodes2.containsKey(startArrow2.nodeId)) {
    return const EquivalenceResult.noStart();
  }

  // Union of both machines' tape alphabets.
  final alphabet = <String>{
    ..._tmAlphabet(lines1),
    ..._tmAlphabet(lines2),
  };

  return _checkEquivalenceByTestingInputs(
    nodes1: nodes1,
    lines1: lines1,
    startArrow1: startArrow1,
    nodes2: nodes2,
    lines2: lines2,
    startArrow2: startArrow2,
    alphabet: alphabet,
    maxInputLength: maxInputLength,
    maxTests: maxTests,
    // Each simulate call also threads through the per-input step cap.
    simulate1: (input) => _simulateTm(nodes1, lines1, startArrow1, input, maxStepsPerInput),
    simulate2: (input) => _simulateTm(nodes2, lines2, startArrow2, input, maxStepsPerInput),
  );
}

// Function type alias: "given an input string, return whether the machine
// accepts, rejects, or couldn't decide". Lets checkPdaEquivalence and
// checkTmEquivalence pass in their own simulate logic without the shared
// helper needing to know which kind of machine it's dealing with.
typedef _SimulatorFn = _AcceptanceOutcome Function(String input);

// Shared "generate candidate inputs, run both simulators, compare outcomes"
// loop used by both the PDA and TM equivalence checks above.
EquivalenceResult _checkEquivalenceByTestingInputs({
  required Map<String, NodeData> nodes1,
  required Map<String, LineData> lines1,
  required StartArrowData? startArrow1,
  required Map<String, NodeData> nodes2,
  required Map<String, LineData> lines2,
  required StartArrowData? startArrow2,
  required Set<String> alphabet,
  required int maxInputLength,
  required int maxTests,
  required _SimulatorFn simulate1,
  required _SimulatorFn simulate2,
}) {
  // Lazily generate candidate input strings up to maxInputLength/maxTests
  // (see _generateInputCandidates below — shortest strings first).
  final inputs = _generateInputCandidates(alphabet, maxInputLength, maxTests);
  for (final input in inputs) {
    // Run each machine on the same candidate input.
    final outcome1 = simulate1(input);
    final outcome2 = simulate2(input);

    // If either simulator couldn't confidently decide (e.g. stack blew up,
    // or the TM step budget ran out), this input is inconclusive — skip it
    // rather than treating "unknown" as a mismatch.
    if (outcome1 == _AcceptanceOutcome.unknown || outcome2 == _AcceptanceOutcome.unknown) {
      continue;
    }

    // Both simulators gave a definite answer; if they disagree, we've found
    // a genuine distinguishing witness.
    if (outcome1 != outcome2) {
      final acceptedBy = outcome1 == _AcceptanceOutcome.accept ? 1 : 2;
      return EquivalenceResult.notEquivalent(input, acceptedBy);
    }
  }

  // Every candidate input (within the budget) agreed — but since PDA/TM
  // equivalence is undecidable, this is only ever reported as "unknown",
  // never as a proof of equivalence.
  return const EquivalenceResult.capReached();
}

// Runs a single input string through a PDA simulator and classifies the
// result as accept/reject/unknown.
_AcceptanceOutcome _simulatePda(
  Map<String, NodeData> nodes,
  Map<String, LineData> lines,
  StartArrowData? startArrow,
  String input,
) {
  // Build a fresh simulator instance for this machine's graph.
  final sim = PdaSimulator(nodes: nodes, lines: lines);
  // Feed it the candidate input and run it to completion (or as far as it
  // can go) starting from the given start arrow.
  sim.rebuild(input, startArrow: startArrow);
  // A PDA whose stack keeps growing without bound (e.g. an infinite push
  // loop) can never be trusted to reach a final verdict — treat as unknown.
  if (sim.stackGrowthLoopDetected) return _AcceptanceOutcome.unknown;
  // Otherwise translate the simulator's own accept/reject verdict.
  return sim.finalResult() == PdaSimResult.accept
      ? _AcceptanceOutcome.accept
      : _AcceptanceOutcome.reject;
}

// Runs a single input string through a TM simulator, stepping it manually so
// we can enforce our own step budget (the TM might otherwise loop forever).
_AcceptanceOutcome _simulateTm(
  Map<String, NodeData> nodes,
  Map<String, LineData> lines,
  StartArrowData? startArrow,
  String input,
  int maxStepsPerInput,
) {
  final sim = TmSimulator(nodes: nodes, lines: lines);
  sim.rebuild(input, startArrow: startArrow);

  // Manually advance the simulator one step at a time, instead of calling a
  // "run to completion" method, precisely so we can bail out after
  // maxStepsPerInput steps if the machine hasn't halted yet.
  for (int step = 0; step < maxStepsPerInput; step++) {
    // Stop early if the machine already reached a final verdict.
    if (sim.result != TmResult.running) break;
    // Advance one step; if the simulator itself reports it can't continue
    // (e.g. no matching transition), stop as well.
    if (!sim.computeNext()) break;
  }

  // Still running after the step budget → we genuinely don't know whether
  // it would eventually halt (this is the crux of the halting problem).
  if (sim.result == TmResult.running) return _AcceptanceOutcome.unknown;
  return sim.result == TmResult.accept
      ? _AcceptanceOutcome.accept
      : _AcceptanceOutcome.reject;
}

// Collects the set of "read" symbols used across all of a PDA's transition
// labels, excluding the special stack-bottom marker (which isn't a real
// input symbol).
Set<String> _pdaAlphabet(Map<String, LineData> lines) {
  final alphabet = <String>{};
  // Every transition line in the graph...
  for (final line in lines.values) {
    // ...may have several stacked alternative labels separated by newlines
    // (multiple transitions drawn as one line); check each alternative.
    for (final alt in line.label.split('\n')) {
      // Parse the PDA-specific label syntax (read/pop/push triple).
      final t = parsePdaLabel(alt);
      // Only count real, concrete read symbols — skip empty reads and the
      // reserved stack-bottom marker.
      if (t.read.isNotEmpty && t.read != kStackBottom) {
        alphabet.add(t.read);
      }
    }
  }
  return alphabet;
}

// Same idea as _pdaAlphabet but for Turing machine labels (read/write/move
// triples) — collects every symbol the machine can read off the tape.
Set<String> _tmAlphabet(Map<String, LineData> lines) {
  final alphabet = <String>{};
  for (final line in lines.values) {
    for (final alt in line.label.split('\n')) {
      final t = parseTmLabel(alt);
      if (t.read.isNotEmpty) {
        alphabet.add(t.read);
      }
    }
  }
  return alphabet;
}

// Lazily yields candidate input strings to test, shortest first (starting
// with the empty string), then all length-1 strings, length-2, and so on,
// stopping once either maxInputLength or maxTests is reached. `sync*`
// makes this a synchronous generator — candidates are produced on demand
// rather than all up front, so a caller that finds a witness early doesn't
// pay for generating the rest.
Iterable<String> _generateInputCandidates(
  Set<String> alphabet,
  int maxInputLength,
  int maxTests,
) sync* {
  // Always try the empty string first — many acceptance mismatches show up
  // immediately (e.g. one machine's start state is accepting, the other's
  // isn't).
  yield '';
  // No symbols to extend with — nothing more to try.
  if (alphabet.isEmpty) return;

  // Sort for deterministic, reproducible test ordering across runs.
  final symbols = alphabet.toList()..sort();
  // BFS-style queue of token sequences, so shorter strings are tried before
  // longer ones (breadth-first over string length).
  final queue = <List<String>>[];
  // Seed the queue with every single-symbol string.
  for (final symbol in symbols) {
    queue.add([symbol]);
  }

  // Keep expanding the queue until we run out of budget (maxTests) or work.
  // The `> 1` guard (rather than `> 0`) reserves the last test slot — the
  // empty-string yield above already consumed one of the maxTests budget
  // conceptually, so this keeps the total yields in line with maxTests.
  while (queue.isNotEmpty && maxTests > 1) {
    final tokenSeq = queue.removeAt(0);
    // Turn the token list into the actual DSL-style input string and hand
    // it to the caller.
    yield _encodeInputTokens(tokenSeq);
    maxTests--;
    // Only grow the sequence further if it hasn't hit the length cap yet.
    if (tokenSeq.length < maxInputLength) {
      for (final symbol in symbols) {
        queue.add([...tokenSeq, symbol]);
      }
    }
  }
}

// Converts a list of alphabet tokens back into the flat string format the
// simulators expect. Multi-character tokens (or the literal `"` character)
// must be wrapped in quotes so the simulator's own tokenizer can tell them
// apart from single-character symbols placed back-to-back.
String _encodeInputTokens(List<String> tokens) {
  if (tokens.isEmpty) return '';
  final buffer = StringBuffer();
  for (final token in tokens) {
    // Single ordinary characters can just be concatenated directly.
    if (token.length == 1 && token != '"') {
      buffer.write(token);
    } else {
      // Multi-character tokens (e.g. "ab") need quoting so they're not
      // misread as two separate single-character symbols.
      buffer.write('"');
      // Strip any embedded quote characters defensively before re-quoting.
      buffer.write(token.replaceAll('"', ''));
      buffer.write('"');
    }
  }
  return buffer.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lightweight NFA adapter that operates on the existing model classes
// ─────────────────────────────────────────────────────────────────────────────

/// Splits a raw transition label into individual symbol tokens, correctly
/// handling quoted multi-character tokens such as `"Green Leaf"` and
/// negation prefixes like `.-"Green Leaf","Bar"`.
///
/// Commas and newlines are delimiters only when outside double-quotes.
List<String> _splitLabel(String label) {
  // An entirely blank label still counts as one (empty) token — this is how
  // ~-transitions with no visible text are represented.
  if (label.trim().isEmpty) return const [''];
  final tokens = <String>[];
  final buf = StringBuffer();
  // Tracks whether we're currently inside a double-quoted token, so commas
  // and newlines inside quotes aren't treated as separators.
  bool inQuote = false;
  for (int i = 0; i < label.length; i++) {
    final ch = label[i];
    if (ch == '"') {
      // Toggle quote state; the quote character itself is kept in the
      // buffer so downstream code can still recognise a quoted token.
      inQuote = !inQuote;
      buf.write(ch);
    } else if (!inQuote && (ch == ',' || ch == '\n')) {
      // Outside quotes, comma/newline ends the current token.
      final t = buf.toString().trim();
      if (t.isNotEmpty) tokens.add(t);
      buf.clear();
    } else {
      // Any other character (including commas/newlines inside quotes) is
      // just accumulated into the current token.
      buf.write(ch);
    }
  }
  // Flush whatever's left in the buffer after the loop ends.
  final t = buf.toString().trim();
  if (t.isNotEmpty) tokens.add(t);
  return tokens;
}

// Wraps a single machine's raw node/line maps with NFA-style operations
// (epsilon-closure, step, acceptance test) needed by the BFS above, without
// requiring the underlying model classes themselves to know about
// equivalence checking.
class _NfaAdapter {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  /// The combined alphabet of both NFAs. Set externally by [checkEquivalence]
  /// after both adapters are constructed, so that `.` and `.-X` expand
  /// relative to the full symbol set.
  Set<String> alphabet = {};

  _NfaAdapter({required this.nodes, required this.lines});

  /// Collect every concrete (non-wildcard) input symbol used on transitions.
  /// `.` and `.-…` tokens are excluded here; they are expanded at step-time
  /// against [alphabet].
  Set<String> collectConcreteSymbols() {
    final syms = <String>{};
    // Every transition line in this machine...
    for (final line in lines.values) {
      // ...may encode several alternative symbols on one line; split them.
      for (final raw in _splitLabel(line.label)) {
        // Normalise token-replacement syntax (e.g. [[TILDA]] → ~) first.
        final s = _normalise(raw);
        // Skip ~-transitions and end-of-input null jumps — these aren't
        // "consume a symbol" transitions at all.
        if (s.isEmpty || s == '~' || s == '?' || s == '.') continue;
        // Skip wildcard-with-exclusions tokens too; they're resolved later
        // against the shared alphabet, not added to it directly.
        if (s.startsWith('.-')) continue;
        syms.add(s);
      }
    }
    return syms;
  }

  // Expands the `[[NAME]]` token-replacement syntax (e.g. `[[TILDA]]` → `~`)
  // used in some DSL exports, falling back to the raw string unchanged if it
  // isn't a recognised token name.
  static String _normalise(String s) {
    s = s.trim();
    if (s.startsWith('[[') && s.endsWith(']]')) {
      final inner = s.substring(2, s.length - 2).trim().toUpperCase();
      return kTokenReplacements[inner] ?? s;
    }
    return s;
  }

  /// ~-transitions: label normalises to empty or '~'.
  bool _isEpsilon(String raw) {
    final n = _normalise(raw);
    return n.isEmpty || n == '~';
  }

  /// Null jumps fire only after the current input prefix is fully consumed.
  /// Matches [AutomataSimulator]'s end-of-input `?` / `\0` handling.
  bool _isNullJump(String raw) {
    final n = _normalise(raw);
    return n == '?' || n == r'\0';
  }

  /// For a `.-X,"Y",...` token, returns the set of excluded symbols.
  /// For a bare `.` the excluded set is empty (matches everything in alphabet).
  Set<String> _negationExcludes(String token) {
    // A bare wildcard excludes nothing.
    if (token == '.') return const {};
    final rest = token.substring(2); // strip leading '.-'
    final excludes = <String>{};
    // The remainder may itself be a comma-separated list of symbols to
    // exclude, possibly quoted (e.g. `.-a,"bc"`).
    for (final part in _splitLabel(rest)) {
      final sym = _stripQuotes(part.trim());
      if (sym.isNotEmpty) excludes.add(sym);
    }
    return excludes;
  }

  // Removes a single pair of surrounding double-quotes, if present, from a
  // token (e.g. `"ab"` → `ab`); tokens without quotes pass through unchanged.
  static String _stripQuotes(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// Returns true if the normalised label token [norm] fires on [symbol].
  ///
  /// - Exact match always fires.
  /// - `.` fires on every symbol in [alphabet].
  /// - `.-X` fires on every alphabet symbol NOT in the exclusion list.
  ///   Symbols outside [alphabet] are silently excluded, so `.-y` over
  ///   alphabet {a,b,c} only fires on {a,b,c}, not on 'y' or 'z'.
  bool _labelMatchesSymbol(String norm, String symbol) {
    // Simple case: the label literally is this symbol.
    if (norm == symbol) return true;
    // Wildcard cases: `.` or `.-exclusions`.
    if (norm == '.' || norm.startsWith('.-')) {
      // Wildcards only ever match symbols known to be in the shared
      // alphabet — never symbols outside it.
      if (!alphabet.contains(symbol)) return false;
      // Bare `.` matches everything in the alphabet.
      if (norm == '.') return true;
      // `.-X,...` matches everything in the alphabet except the excluded set.
      return !_negationExcludes(norm).contains(symbol);
    }
    return false;
  }

  /// ~-closure plus end-of-input null jumps (`?`, `\0`) of a set of NFA states.
  ///
  /// The BFS only calls this after the entire current witness prefix has been
  /// consumed, which is exactly when null jumps are allowed in the simulator.
  Set<String> epsilonClosure(Set<String> states) {
    // Start the closure with the given states themselves (every state can
    // trivially "reach itself" via zero ~-transitions).
    final closure = <String>{...states};
    // Depth-first work-stack of states still needing their outgoing
    // ~-transitions explored.
    final stack = [...states];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final node = nodes[cur];
      // Halt states and black-box states never have outgoing ~-transitions
      // that participate in the closure — skip them.
      if (node == null || node.isHaltState || node.isBlackBox) continue;
      // Scan every transition line for ones starting at `cur`.
      for (final line in lines.values) {
        if (line.nodeAId != cur) continue;
        // A single line may bundle several alternative labels.
        for (final alt in _splitLabel(line.label)) {
          // Only ~-transitions and null-jumps belong in the closure.
          if (_isEpsilon(alt) || _isNullJump(alt)) {
            // `closure.add` returns false if the element was already
            // present, letting us avoid re-exploring already-visited
            // states (and prevents infinite loops on ~-cycles).
            if (closure.add(line.nodeBId)) stack.add(line.nodeBId);
          }
        }
      }
    }
    return closure;
  }

  /// States reachable from [states] by consuming [symbol] (before ~-closure).
  ///
  /// An empty result means the machine fell off — the BFS visits the empty
  /// powerset node, which correctly rejects any remaining input.
  Set<String> step(Set<String> states, String symbol) {
    final result = <String>{};
    // For every state currently "active" in the powerset...
    for (final cur in states) {
      final node = nodes[cur];
      // Halt/black-box states can't consume further input.
      if (node == null || node.isHaltState || node.isBlackBox) continue;
      // Check every transition line leaving this state.
      for (final line in lines.values) {
        if (line.nodeAId != cur) continue;
        for (final alt in _splitLabel(line.label)) {
          // If this alternative label matches the symbol being consumed
          // (accounting for wildcards), the destination becomes reachable.
          if (_labelMatchesSymbol(_normalise(alt), symbol)) {
            result.add(line.nodeBId);
          }
        }
      }
    }
    return result;
  }

  /// True if any state in [states] is an accepting state.
  bool anyAccepts(Set<String> states) {
    for (final id in states) {
      final n = nodes[id];
      if (n == null) continue;
      // A halt-accept state (used in some automaton modes) always counts.
      if (n.isHaltAccept) return true;
      // A regular accept state counts too, as long as it isn't also
      // classified as some other kind of halt state.
      if (n.isAccept && !n.isHaltState) return true;
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Token replacement map (mirrors token_replacements.dart)
//  Duplicated here so this file has no extra import dependency.
// ─────────────────────────────────────────────────────────────────────────────

// Maps the human-typeable `[[NAME]]` placeholders (used when a special
// symbol like ~ is awkward to type directly) to their actual Unicode
// character. Kept as a local copy rather than importing the canonical
// version, to keep this file's algorithm section import-free of app-specific
// modules beyond the bare minimum.
const Map<String, String> kTokenReplacements = {
  'tilda': '~',
  'EPS': '~',
  'LAMBDA': 'λ',
  'EMPTY': '∅',
  'EMPTYSET': '∅',
  'NULL': '∅',
  'BLANK': '⊔',
  'DELTA': 'δ',
  'SIGMA': 'Σ',
  'GAMMA': 'Γ',
  'ARROW': '→',
  'RIGHT': '→',
  'LEFT': '←',
  'UP': '↑',
  'DOWN': '↓',
  'STAR': '*',
  'PLUS': '+',
};

// ═════════════════════════════════════════════════════════════════════════════
//  2. AUTOMATON TYPE CHECKING (DFA vs NFA)
// ═════════════════════════════════════════════════════════════════════════════

// ─── Public contract ──────────────────────────────────────────────────────────

/// Which automaton type a puzzle requires.
enum RequiredAutomatonType {
  /// Every state must have exactly one transition per alphabet symbol,
  /// no tilda (~ / ~) transitions, and exactly one start state.
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

  // Debug/log-friendly representation, e.g. "[ERROR] State q0 has ...".
  @override
  String toString() => '[${severity.name.toUpperCase()}] $message';
}

/// The full result returned by [AutomatonTypeChecker.check].
class AutomatonTypeResult {
  // Private named constructor — instances can only be created from within
  // this file (specifically by AutomatonTypeChecker.check below).
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

// Pure static-method utility class (private constructor prevents
// instantiation) that inspects a single automaton's structure and decides
// whether it qualifies as a DFA or is inherently an NFA.
class AutomatonTypeChecker {
  // Private, unnamed, never-called constructor — this class is only ever
  // used via its static members, never instantiated.
  AutomatonTypeChecker._();

  // ── tilda label detection ────────────────────────────────────────────────

  // Labels are split on commas OR newlines.
  // The simulator stores the literal two-character sequence `\n` in DSL strings
  // (not a real newline), so we match both real newlines AND the escaped form.
  static final _labelSplitter = RegExp(r'[,\n]|\\n');

  /// Returns true if [raw] encodes an tilda (~ / ~ / empty) transition.
  /// Mirrors the logic in AutomataSimulator._isEpsilonLabel.
  ///
  /// NOTE: `?` and `\0` are "null-jump" epsilons that fire only at end-of-input
  /// in the simulator, but for DFA type-checking purposes any unconditional
  /// free-jump counts as an NFA feature.
  static bool _isEpsilonSymbol(String raw) {
    final s = raw.trim();
    return s.isEmpty || s == '~' || s == '~' || s == '?' || s == r'\0';
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
    // Gather every reason (if any) this graph fails to be a clean DFA.
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
        // The puzzle wants a DFA — report every NFA-feature violation found
        // directly; an empty list means the player succeeded.
        return AutomatonTypeResult._(
          detectedType: detectedType,
          requiredType: required,
          violations: nfaViolations,
        );

      case RequiredAutomatonType.nfa:
        // Player must have built a *proper* NFA.  A DFA is the only violation.
        if (detectedType == RequiredAutomatonType.dfa) {
          // The player's graph is technically a valid nfa, but it is also a DFA 
          // and the puzzle explicitly requires nondeterminism, so we report that as a violation.
          return AutomatonTypeResult._(
            detectedType: detectedType,
            requiredType: required,
            violations: const [
              AutomatonViolation(
                severity: ViolationSeverity.error,
                message:
                    'Your automaton is deterministic (a DFA). This puzzle '
                    'requires nondeterminism — add an ~-transition or give a '
                    'state more than one transition for the same symbol.',
              ),
            ],
          );
        }
        // Already has at least one NFA feature — requirement satisfied.
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
    // Concrete (non-epsilon) transitions grouped by source state and symbol.
    final Map<String, Map<String, List<String>>> transitionMap = {};
    // ~-transitions grouped by source state (target list only — the symbol
    // is always "epsilon" so no need for a second map level).
    final Map<String, List<String>> epsilonTargets = {};

    // Classify every transition on every line into one of the two maps
    // above.
    for (final line in lines.values) {
      final from = line.nodeAId;
      final to = line.nodeBId;

      // A single line's label may bundle multiple symbols/alternatives.
      for (final symbol in _splitLabel(line.label)) {
        if (_isEpsilonSymbol(symbol)) {
          // ── 2. tilda transitions ───────────────────────────────────────
          epsilonTargets.putIfAbsent(from, () => []).add(to);
        } else {
          // Record this concrete transition under transitionMap[from][symbol].
          transitionMap
              .putIfAbsent(from, () => {})
              .putIfAbsent(symbol, () => [])
              .add(to);
        }
      }
    }

    // Report tilda transitions — one violation per source state.
    epsilonTargets.forEach((stateId, targets) {
      // Deduplicate targets in case the same ~-transition appears twice
      // (e.g. drawn as two overlapping lines) — the message should only
      // list each destination once.
      final uniqueTargets = targets.toSet();
      violations.add(AutomatonViolation(
        severity: ViolationSeverity.error,
        affectedStateId: stateId,
        message:
            'State ${_stateNameById(stateId, nodes)} has an ~-transition '
            '(tilda / empty-string transition) to '
            '${uniqueTargets.map((t) => _stateNameById(t, nodes)).join(', ')}. '
            'DFAs do not allow ~-transitions — every transition must consume '
            'exactly one input symbol.',
      ));
    });

    // ── 3. Nondeterminism: multiple transitions for the same symbol ────────
    transitionMap.forEach((stateId, bySymbol) {
      bySymbol.forEach((symbol, targets) {
        // More than one destination for the same (state, symbol) pair means
        // the machine has to "choose" — that's nondeterminism, forbidden in
        // a DFA.
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
        // A complete DFA needs exactly one transition per symbol per state;
        // check every alphabet symbol against this state's transitions.
        for (final symbol in alphabet) {
          if ((bySymbol[symbol] ?? []).isEmpty) {
            // This is only a `warning`, not an `error`, since an incomplete
            // DFA is still technically well-formed (it just implicitly
            // rejects on the missing symbol) — a softer nudge rather than a
            // hard failure.
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

  // Prefers the state's human-readable label (quoted) for messages; falls
  // back to the raw internal id if the player never renamed it.
  static String _stateName(NodeData node) =>
      node.label.trim().isNotEmpty ? '"${node.label.trim()}"' : node.id;

  // Same as _stateName but looks the node up by id first (some callers only
  // have an id on hand, e.g. transition target lists).
  static String _stateNameById(String id, Map<String, NodeData> nodes) {
    final node = nodes[id];
    if (node == null) return id;
    return _stateName(node);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  3. DIALOG UI
// ═════════════════════════════════════════════════════════════════════════════

// Public entry point that other screens call to pop open the "Compare
// Automata" dialog. `initialDsl` lets a caller (e.g. "check my solution
// against the target") pre-fill the first text box.
Future<void> showEquivalenceDialog(
  BuildContext context, {
  String? initialDsl,
}) {
  return showDialog(
    context: context,
    // `_` (unused parameter) is the inner BuildContext supplied by
    // showDialog — the widget doesn't need it since it reads theme via
    // Provider inside its own build method.
    builder: (_) => _EquivalenceDialog(initialDsl: initialDsl),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

// The stateful widget shell for the dialog; almost all the real state lives
// in _EquivalenceDialogState below.
class _EquivalenceDialog extends StatefulWidget {
  final String? initialDsl;
  const _EquivalenceDialog({this.initialDsl});

  @override
  State<_EquivalenceDialog> createState() => _EquivalenceDialogState();
}

// Holds the two text editors, the tab controller (unused directly for
// switching visible content here but required by the mixin), and the latest
// equivalence check result/errors.
class _EquivalenceDialogState extends State<_EquivalenceDialog>
    with SingleTickerProviderStateMixin {
  // Text controller for "Automaton A"'s DSL input box.
  late final TextEditingController _ctrlA;
  // Text controller for "Automaton B"'s DSL input box.
  late final TextEditingController _ctrlB;
  // Provides the single vsync ticker required by TabController.
  late final TabController _tabController;

  // Latest equivalence result, or null before the first check / after a
  // reset.
  EquivalenceResult? _result;
  // Parse error message for editor A, shown under its text box.
  String? _errorA;
  // Parse error message for editor B, shown under its text box.
  String? _errorB;
  // True while a check is (conceptually) running, to show a spinner and
  // disable the button — the actual computation is synchronous, but this
  // still gives the UI a chance to repaint the "checking" state first.
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill editor A with the caller-supplied DSL, if any; otherwise
    // start empty.
    _ctrlA = TextEditingController(text: widget.initialDsl ?? '');
    _ctrlB = TextEditingController();
    // Length 2 even though nothing in this widget currently displays tabs
    // directly — kept for the mixin requirement / potential future use.
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    // Always dispose text/animation controllers to avoid leaking resources.
    _ctrlA.dispose();
    _ctrlB.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Check ─────────────────────────────────────────────────────────────────

  // Handles the "Check equivalence" button: parses both DSL strings, checks
  // their automaton modes match, then runs the appropriate equivalence
  // algorithm and stores the result in state.
  void _check() {
    // Reset all transient state and show the spinner immediately.
    setState(() {
      _errorA = null;
      _errorB = null;
      _result = null;
      _checking = true;
    });

    // `late final` here lets us assign g1/g2 inside try/catch blocks while
    // still treating them as definitely-assigned afterwards.
    late final GraphState g1, g2;
    try {
      g1 = DslCodec.importFromDsl(_ctrlA.text);
    } catch (e) {
      // Parsing failed for editor A — surface the error and abort the
      // check entirely (no point comparing against an unparsed machine).
      setState(() {
        _errorA = 'Parse error: $e';
        _checking = false;
      });
      return;
    }
    try {
      g2 = DslCodec.importFromDsl(_ctrlB.text);
    } catch (e) {
      setState(() {
        _errorB = 'Parse error: $e';
        _checking = false;
      });
      return;
    }

    // Both parsed, but comparing an NFA to a PDA (for example) is
    // meaningless — require both to be in the same automaton mode.
    if (g1.automataMode != g2.automataMode) {
      setState(() {
        _errorA = 'Automaton A is in ${g1.automataMode.name.toUpperCase()} mode.';
        _errorB = 'Automaton B is in ${g2.automataMode.name.toUpperCase()} mode.';
        _checking = false;
      });
      return;
    }

    // Dispatch to the correct algorithm based on which kind of automaton
    // both machines are.
    late final EquivalenceResult result;
    switch (g1.automataMode) {
      case AutomataMode.ndfa:
      case AutomataMode.regex:
        // Regex mode compiles down to an NFA under the hood, so it shares
        // the exact BFS algorithm with plain NFA/DFA mode.
        result = checkEquivalence(
          nodes1: g1.nodes, lines1: g1.lines, startArrow1: g1.startArrow,
          nodes2: g2.nodes, lines2: g2.lines, startArrow2: g2.startArrow,
        );
        break;
      case AutomataMode.pda:
        result = checkPdaEquivalence(
          nodes1: g1.nodes, lines1: g1.lines, startArrow1: g1.startArrow,
          nodes2: g2.nodes, lines2: g2.lines, startArrow2: g2.startArrow,
        );
        break;
      case AutomataMode.tm:
        result = checkTmEquivalence(
          nodes1: g1.nodes, lines1: g1.lines, startArrow1: g1.startArrow,
          nodes2: g2.nodes, lines2: g2.lines, startArrow2: g2.startArrow,
        );
        break;
    }

    // Publish the final result and stop showing the spinner.
    setState(() {
      _result = result;
      _checking = false;
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  // Builds one labeled DSL text-entry column (used twice: "Automaton A" and
  // "Automaton B"), including its error message if parsing previously failed.
  Widget _dslEditor(
    AppThemeNotifier theme,
    TextEditingController ctrl,
    String label,
    String? error,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Column heading, e.g. "Automaton A".
        Text(
          label,
          style: GoogleFonts.courierPrime(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: theme.textLight,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: theme.bg,
            // Border turns red when this editor has a parse error, giving
            // an at-a-glance signal of which side needs fixing.
            border: Border.all(
              color: error != null ? const Color(0xFFFF1744) : theme.borderMid,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: ctrl,
            // Fixed height text area sized for pasting a full DSL dump.
            maxLines: 14,
            style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
            cursorColor: theme.accent,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(10),
              // No visible Material underline/border — the outer Container
              // above already draws the border.
              border: InputBorder.none,
              hintText: 'Paste DSL here…',
              hintStyle: GoogleFonts.courierPrime(color: theme.textDim, fontSize: 13),
            ),
          ),
        ),
        // Only show the error line if there actually is one.
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: const TextStyle(color: Color(0xFFFF1744), fontSize: 12),
          ),
        ],
      ],
    );
  }

  // Builds the banner shown below the two editors: a spinner while checking,
  // nothing before the first check, or a colour-coded result summary
  // afterwards.
  Widget _resultBanner() {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final r = _result;
    // Nothing to show yet — collapse to zero size rather than leaving an
    // empty gap.
    if (r == null) return const SizedBox.shrink();

    switch (r.status) {
      case EquivalenceStatus.equivalent:
        // Green success banner.
        return _Banner(
          borderColor: const Color(0xFF1FD99A),
          icon: Icons.check_circle_outline,
          iconColor: const Color(0xFF1FD99A),
          title: 'Equivalent',
          body: 'Both automata accept exactly the same language.',
        );

      case EquivalenceStatus.notEquivalent:
        // Witness is guaranteed non-null in this branch by construction of
        // EquivalenceResult.notEquivalent.
        final w = r.witness!;
        // Show a friendly label for the empty-string witness instead of a
        // blank/confusing string.
        final wDisplay = w.isEmpty ? '\\0 (the empty string)' : '"$w"';
        // Figure out the human labels ("A"/"B") for which machine accepted
        // vs. which didn't, based on the internal 1/2 machine index.
        final other = r.acceptedByMachine == 1 ? 'B' : 'A';
        final accepted = r.acceptedByMachine == 1 ? 'A' : 'B';
        // Orange "difference found" banner.
        return _Banner(
          borderColor: const Color(0xFFFF6D00),
          icon: Icons.highlight_off,
          iconColor: const Color(0xFFFF9E40),
          title: 'Not Equivalent',
          body: 'Distinguishing witness: $wDisplay\n'
              'Automaton $accepted accepts this string, automaton $other does not.',
        );

      case EquivalenceStatus.unknownCapReached:
        // Still shown with a green/positive icon since, in practice, running
        // out of search budget without finding a counter-example usually
        // means the machines probably are equivalent — but the body text is
        // careful to state this isn't a proof.
        return _Banner(
          borderColor: const Color(0xFF1FD99A),
          icon: Icons.check,
          iconColor: const Color(0xFF1FD99A),
          title: 'Likely Equivalent',
          body: 'No distinguishing string was found within the checked bounds. '
              'For NFA/DFA, this means the algorithm could not prove inequivalence. '
              'For PDA/TM, the search is intentionally bounded.',
        );

      case EquivalenceStatus.noStartState:
        // Red warning banner — this is a setup problem, not a
        // language-equivalence result.
        return _Banner(
          borderColor: const Color(0xFFFF1744),
          icon: Icons.warning_amber_outlined,
          iconColor: const Color(0xFFFF1744),
          title: 'Missing start state',
          body: 'One or both automata have no start state defined. '
              'Add a start arrow (▶) and try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds automatically whenever the app theme changes.
    final theme = context.watch<AppThemeNotifier>();
    return Dialog(
      backgroundColor: theme.surface,
      // Keeps the dialog from touching the screen edges on small viewports.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        // Caps the dialog's size so it doesn't grow to fill huge desktop
        // windows.
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: Column(
          // Shrink-wrap vertically to content rather than forcing max height.
          mainAxisSize: MainAxisSize.min,
          // Let children (like the editors) stretch to the full width.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows, color: theme.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Compare Automata',
                    style: GoogleFonts.courierPrime(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.textLight),
                  ),
                  // Pushes the close button to the far right of the row.
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.textMid),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Divider(height: 16, color: theme.borderMid),

            // Scrollable body so long error/result text never overflows on
            // small screens.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Instruction blurb
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.borderMid),
                      ),
                      child: Text(
                        'Paste the DSL for two automata. For NFA/DFA, the checker can prove equivalence exactly. '
                        'For PDA/TM, it performs a bounded search for a distinguishing input string. '
                        'If no counterexample is found within the search bound, equivalence remains unknown.',
                        style: GoogleFonts.courierPrime(fontSize: 12, color: theme.textMid),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Two-column layout on wide screens ──
                    // Reflows from a side-by-side layout (wide windows) to a
                    // stacked layout (narrow/mobile) based on available width.
                    LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth > 500;
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _dslEditor(theme, _ctrlA, 'Automaton A', _errorA)),
                            const SizedBox(width: 16),
                            Expanded(child: _dslEditor(theme, _ctrlB, 'Automaton B', _errorB)),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _dslEditor(theme, _ctrlA, 'Automaton A', _errorA),
                          const SizedBox(height: 16),
                          _dslEditor(theme, _ctrlB, 'Automaton B', _errorB),
                        ],
                      );
                    }),

                    const SizedBox(height: 20),
                    _resultBanner(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            Divider(height: 1, color: theme.borderMid),

            // ── Actions ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: theme.textMid),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    // Disable the button entirely while a check is already
                    // in flight, to prevent duplicate/overlapping checks.
                    onPressed: _checking ? null : _check,
                    icon: const Icon(Icons.compare),
                    label: const Text('Check equivalence'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small reusable banner widget
// ─────────────────────────────────────────────────────────────────────────────

// Generic colour-coded info banner (icon + title + body) reused for every
// result state in _resultBanner() above.
class _Banner extends StatelessWidget {
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _Banner({
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // A light tint of the semantic color over the current theme's
        // background, rather than a fixed near-black — so body text (which
        // uses theme.textMid below) stays readable in light themes too.
        color: Color.alphaBlend(borderColor.withValues(alpha: 0.12), theme.bg),
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.courierPrime(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.courierPrime(
                    fontSize: 13,
                    color: theme.textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}