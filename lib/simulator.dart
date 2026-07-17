// ─────────────────────────────────────────────────────────────────────────────
//  simulator.dart
//
//  Step-by-step simulation engines for DFA/NFA, PDA, and TM automata:
//  AutomataSimulator, PdaSimulator, TmSimulator.
//
//  regexToNfa / regexToDfa (regex → graph conversion) now live in
//  regex_engine.dart and are re-exported below rather than duplicated here.
// ─────────────────────────────────────────────────────────────────────────────

// Queue (used by PdaSimulator's epsilon-closure worklist) and
// UnmodifiableSetView (used by AutomataSimulator's activeNodes/activeLines
// getters, so callers can't mutate the simulator's internal state through
// them) both come from dart:collection.
import 'dart:collection';

// DslCodec.importFromDsl — used to parse a black-box node's embedded DSL
// program into a fresh GraphState so its inner machine can be simulated.
import 'import_export.dart';
// NodeData, LineData, StartArrowData, GraphState — the shared graph data
// types every simulator here operates over.
import 'models.dart';
// parseTokenText — resolves `[[KEY]]` tokens (e.g. `[[DELTA]]` -> 'δ') inside
// transition labels and simulation input before matching.
import 'token_replacements.dart';
// Only AutomataMode is needed from the drawer widget, to switch on which
// kind of graph a black box's inner DSL describes.
import 'widgets/automata_drawer.dart' show AutomataMode;

// Re-export the regex engine so existing code that only imports
// simulator.dart (automata_screen.dart, sim_panels.dart, game_puzzle.dart,
// study_mode_screen.dart) still sees RegexConversionResult / regexToNfa /
// regexToDfa without needing its own import — `export`, not `import`,
// is what makes symbols transitively visible in Dart.
export 'regex_engine.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  AUTOMATA / PDA / TM SIMULATORS
// ═════════════════════════════════════════════════════════════════════════════

// Outcome of a DFA/NFA run — deliberately just two values (no "running"
// state, unlike TmResult below) because AutomataSimulator always precomputes
// the entire step history up front in _buildSimulation, so a final verdict
// is available immediately after rebuild() rather than needing to be polled
// mid-computation.
enum SimResult { accept, reject }

/// Wildcard label — matches any single input token (but not tilda).
const String kWildcard = '.';

/// Parses a negated-wildcard label of the form ".-X" or ".-XY" into the
/// excluded tokens.  Returns null if [label] is not in that form.
List<String>? _parseNegatedWildcard(String label) {
  // Must start with ".-" (dot dash) and have at least one excluded char.
  // Minimum valid form is ".-X" (3 chars: dot, dash, one excluded symbol).
  if (label.length < 3) return null;
  if (label[0] != '.' || label[1] != '-') return null;
  // Splits the excluded-symbols suffix into individual characters (one
  // excluded token per character); the `.where(isNotEmpty)` guards against
  // a pathological empty-string entry from split(''), though in practice
  // splitting a non-empty string on '' never actually produces one.
  final excluded = label.substring(2).split('').where((s) => s.isNotEmpty).toList();
  // ".-" with nothing after the dash isn't a valid negated-wildcard (nothing
  // to exclude), so it's rejected rather than treated as "exclude nothing".
  return excluded.isEmpty ? null : excluded;
}

// One reachable (state, remaining-input, read-position) configuration during
// DFA/NFA simulation. Deliberately holds the FULL token list plus a cursor
// (inputPos) rather than a sliced remaining-tokens list, because black-box
// nodes can rewrite `tokens` mid-run (see AutomataSimulator._runBlackBox) —
// keeping the whole list plus a position makes "how much has been consumed"
// and "what a black box rewrote" both representable without juggling two
// separate lists that could drift out of sync.
class _SimConfig {
  final String nodeId;
  final List<String> tokens;
  final int inputPos;

  const _SimConfig({
    required this.nodeId,
    required this.tokens,
    required this.inputPos,
  });

  // Used as a Map/Set dedup key throughout the epsilon-closure and
  // step-building code below. \u0001 (a control character that can never
  // appear in a legitimate token) joins the token list unambiguously, so two
  // configs with genuinely different token lists never collide into the same
  // key just because a plain "," or similar separator happened to appear
  // inside a token.
  String get key => '$nodeId:$inputPos:${tokens.join('\u0001')}';
}

// Match comma, newline, or a literal "\n" escape — same rules as models.dart
// and equivalence_dialog.dart.
// Two separately-declared RegExps with byte-for-byte identical patterns:
// kept as two names (rather than one shared constant) because they're
// conceptually used for two different purposes below (splitting a
// tilda-only label vs. splitting a full consuming-transition label), even
// though today they happen to use the same split rule.
final _transitionLabelSplitter = RegExp(r'[,\n]|\\n');
final _epsilonLabelSplitter = RegExp(r'[,\n]|\\n');

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED TOKENIZER
//
//  Used by AutomataSimulator, PdaSimulator, and TmSimulator. Previously each
//  class carried its own copy of this pair of methods; they had already
//  drifted (TM's copy resolved `\0` to the tape blank symbol instead of the
//  FA/PDA "null token" `?`). That divergence is now explicit via
//  [nullEscapeToken] instead of living as an undocumented difference between
//  three near-identical blocks of code.
// ─────────────────────────────────────────────────────────────────────────────

/// Splits [input] into simulation tokens.
///
/// * `[[KEY]]` command tokens are resolved via [_resolveCommand].
/// * `"..."` quoted spans become a single multi-character token.
/// * `\0` becomes [nullEscapeToken] — the FA/PDA simulators want this to be
///   `?` (the "null token"), while the TM simulator wants the tape's actual
///   blank symbol (`kBlank`), since a TM's tape has a real blank rather than
///   a null-jump marker.
/// * Everything else is split one character at a time.
List<String> _tokenize(String input, {String nullEscapeToken = '?'}) {
  final result = <String>[];
  int i = 0;
  while (i < input.length) {
    // Whitespace between tokens is simply dropped rather than becoming its
    // own token — a typed input like "a b c" tokenizes the same as "abc".
    if (input[i].trim().isEmpty) {
      i++;
      continue;
    }
    // `[[...]]` command token, e.g. `[[DELTA]]` -> one token representing 'δ'.
    if (i + 1 < input.length && input[i] == '[' && input[i + 1] == '[') {
      final close = input.indexOf(']]', i + 2);
      if (close >= 0) {
        result.add(_resolveCommand(input.substring(i, close + 2)));
        i = close + 2;
        continue;
      }
      // Malformed [[ without closing ]] — treat the remainder as one token.
      result.add(input.substring(i));
      break;
    }
    // `"..."` quoted span becomes ONE multi-character token, letting a user
    // type e.g. "ab" to mean a single two-letter token rather than two
    // separate single-character tokens 'a' and 'b'.
    if (input[i] == '"') {
      final close = input.indexOf('"', i + 1);
      if (close >= 0) {
        result.add(input.substring(i + 1, close));
        i = close + 1;
        continue;
      }
      // Unclosed quote — consume the rest as a single token.
      result.add(input.substring(i + 1));
      break;
    }
    // \0 in user input is treated as the null/empty token.
    // Two-character escape sequence (backslash + '0') collapses to whatever
    // [nullEscapeToken] the caller asked for — see the doc comment above for
    // why FA/PDA and TM want different tokens here.
    if (i + 1 < input.length && input[i] == '\\' && input[i + 1] == '0') {
      result.add(nullEscapeToken);
      i += 2;
      continue;
    }
    // Fallback: every other character becomes its own single-character
    // token — the default one-symbol-per-token behavior for plain,
    // unquoted, non-command input.
    result.add(input[i]);
    i++;
  }
  return result;
}

/// Resolves a `[[KEY]]` command token to its symbol via [kTokenReplacements].
/// Returns [token] unchanged if it isn't a well-formed `[[...]]` command.
String _resolveCommand(String token) {
  final trimmed = token.trim();
  if (!trimmed.startsWith('[[') || !trimmed.endsWith(']]')) return token;
  // Strip the surrounding brackets, trim incidental whitespace the user
  // might have typed inside them, and uppercase — kTokenReplacements' keys
  // (see token_replacements.dart) are all uppercase, so this makes the
  // lookup effectively case-insensitive on the user's input even though the
  // table itself is case-sensitive.
  final inner = trimmed.substring(2, trimmed.length - 2).trim().toUpperCase();
  // Unrecognized key falls back to the original token unchanged (brackets
  // and all), same "leave it alone if we don't understand it" convention as
  // parseTokenText in token_replacements.dart.
  return kTokenReplacements[inner] ?? token;
}

/// Runs a DFA/NFA step-by-step and records every reachable configuration so
/// the UI can highlight the active states and transitions as the machine advances.
// Unlike TmSimulator (which computes one step at a time on demand via
// computeNext(), so it can be paused/fast-forwarded interactively),
// AutomataSimulator eagerly computes the ENTIRE run up front inside
// rebuild()/_buildSimulation() and stores every round in `states` /
// `usedLines` / `_configsByStep`. The `step` cursor then just indexes into
// that precomputed history — stepping forward or backward is just moving the
// cursor, no recomputation. This works because NFA/DFA simulation over a
// bounded input is cheap and always terminates (capped at kMaxSteps below),
// unlike a TM which can run indefinitely.
class AutomataSimulator {
  AutomataSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  List<String> tokens = [];
  // states[i] = the set of active node ids after round i (states[0] is the
  // initial epsilon-closure before any input is consumed).
  final List<Set<String>> states = [];
  // usedLines[i] = the set of line ids traversed to reach states[i] — used
  // by the UI to highlight which transitions just fired.
  final List<Set<String>> usedLines = [];
  // The full _SimConfig objects (node + remaining tokens + input position)
  // behind each round of `states` — richer than `states` alone since two
  // configs can share a nodeId but differ in input position/tokens (e.g.
  // after a black box rewrote the token stream on one branch but not
  // another).
  final List<List<_SimConfig>> _configsByStep = [];
  // outputHeadPos: index into outputTokens where the outer machine should
  // resume reading after the black box runs.  For NFA/PDA black boxes this is
  // always 0 (the inner machine accepts/rejects the whole input and the outer
  // machine continues from the beginning of the transformed token list).  For
  // TM black boxes it is the absolute tape-head position that the inner TM
  // left its head at, converted to a logical token index so the outer NFA
  // step-loop can use it as the new inputPos.
  // Cache keyed by "$nodeId:$inputPos:$slicedTokensJoined" (built in
  // _runBlackBox) so the same black-box node visited with the same
  // remaining-input slice during the same rebuild() isn't re-simulated.
  final Map<String, ({bool accepted, List<String> outputTokens, int outputHeadPos})>
      _blackBoxResultCache = {};

  int step = -1;

  /// Maximum valid value for [step] given the current [states] list.
  ///
  /// Mirrors [TmSimulator.maxStep]: step=-1 → states[0], step==maxStep →
  /// states.last. Once the computation halts (all branches die, or a
  /// halt-accept state is reached) `states` simply stops growing — there is
  /// no padding past that point — so this is also the point past which the
  /// UI must refuse to step forward.
  // states.length - 2, not - 1: step uses a -1-based offset (step=-1 means
  // "before round 0"), so the valid step range is -1..(states.length - 2)
  // — i.e. states.length possible rounds map to states.length - 1 distinct
  // step values starting from -1, and the last of those is states.length-2.
  int get maxStep => states.isEmpty ? -1 : states.length - 2;

  Set<String> get activeNodes {
    if (states.isEmpty) return {};
    // step=-1 -> idx=0 (the initial round, before any input is consumed).
    final idx = step + 1;
    if (idx < 0 || idx >= states.length) return {};
    // Wrapped so callers can't mutate the simulator's internal `states[idx]`
    // set through the returned reference.
    return UnmodifiableSetView(states[idx]);
  }

  Set<String> get activeLines {
    // idx mirrors activeNodes: step=-1 -> idx=0, which is the initial
    // tilda closure computed before any input is consumed. That closure
    // can include free ~ jumps, and their lines belong in usedLines[0] just
    // like their destination nodes belong in states[0] — so this must not
    // special-case step < 0 to empty, or those free-jump lines never
    // highlight until the player actually takes a step.
    if (usedLines.isEmpty) return {};
    final idx = step + 1;
    if (idx < 0 || idx >= usedLines.length) return {};
    return UnmodifiableSetView(usedLines[idx]);
  }

  void rebuild(String input, {StartArrowData? startArrow}) {
    tokens = _tokenize(input);
    // A fresh input means every previously-cached black-box result (keyed
    // partly by remaining-token-slice) is potentially stale, so the whole
    // cache is invalidated rather than trying to selectively evict entries.
    _blackBoxResultCache.clear();
    _buildSimulation(startArrow: startArrow);
    // step uses a -1 offset (see activeNodes/activeLines): valid range is
    // -1..maxStep. Clamping against tokens.length is wrong whenever the
    // computation halts before consuming all input (halt-accept mid-string,
    // or every branch dying) — states stops growing at that point, so
    // clamping to tokens.length would leave step pointing past the end of
    // the recorded history and activeNodes/activeLines would silently go
    // empty.
    if (step > maxStep) {
      step = maxStep;
    }
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _blackBoxResultCache.clear(); // ← match rebuild()'s cache invalidation
    // Unlike rebuild(), this doesn't retokenize `tokens` — used when only
    // the graph (nodes/lines) changed, e.g. after an edit in the editor,
    // while the simulated input string stays the same.
    _buildSimulation(startArrow: startArrow);
    if (step > maxStep) {
      step = maxStep;
    }
  }

  SimResult finalResult() {
    if (_configsByStep.isEmpty) return SimResult.reject;

    // A halt-accept reached at ANY point during the recorded run (not just
    // the final round) is decisive — unlike a plain accept state, halt-accept
    // means the machine is considered to have stopped there, so its presence
    // anywhere in the history is enough to call the whole run an accept.
    for (final snapshot in _configsByStep) {
      for (final config in snapshot) {
        if (nodes[config.nodeId]?.isHaltAccept == true) {
          return SimResult.accept;
        }
      }
    }

    // No halt-accept anywhere: fall back to the classic NFA acceptance rule
    // — accept iff some branch in the FINAL round is both in an accept state
    // AND has consumed the entire input (inputPos == tokens.length). Configs
    // that stopped early (didn't reach maxStep because their own token slice
    // was shorter, e.g. after a black-box rewrite) are skipped via the
    // `inputPos < tokens.length` continue below.
    bool anyAccept = false;
    for (final config in _configsByStep.last) {
      final node = nodes[config.nodeId];
      if (node == null) continue;
      if (config.inputPos < config.tokens.length) continue;
      if (node.isHaltAccept) return SimResult.accept;
      if (node.isHaltReject) continue;
      if (node.isAccept) anyAccept = true;
    }

    return anyAccept ? SimResult.accept : SimResult.reject;
  }

  // Runs a raw label token through [[KEY]] command resolution after
  // trimming — the single normalization path every comparison below funnels
  // through so "?" vs "[[?]]"-style variants are all compared consistently.
  String _normalizeSimToken(String token) => _resolveCommand(token.trim());

  // '?' is this simulator's convention for the "null token" — see the
  // _isEpsilonLabel doc/comments below for what that means in practice.
  bool _isNullToken(String token) => _normalizeSimToken(token) == '?';

  // Determines whether a transition label should be treated as a "free"
  // (input-consuming-nothing) move during epsilon-closure computation.
  // Two independent cases both count as epsilon-like here:
  //   1. A genuinely blank/tilda label (~ or empty) — the classic NFA
  //      epsilon transition.
  //   2. A `?` or `\0` label, but ONLY when the input is already fully
  //      consumed (atEndOfInput) AND the user's actual input didn't
  //      explicitly contain a literal `?`/`\0` token themselves
  //      (nullWasExplicitlyTyped) — this is the "null jump" convention: a
  //      transition meant to fire once input runs out, distinct from
  //      matching a literal `?` character typed by the user.
  bool _isEpsilonLabel(String label, bool atEndOfInput, bool nullWasExplicitlyTyped) {
    final normalized = _normalizeSimToken(label);
    if (normalized.isEmpty || normalized == '~') return true;
    // Both `?` and `\0` on a transition label mean "null jump" (tilda at end-of-input).
    if ((normalized == '?' || normalized == r'\0') && atEndOfInput && !nullWasExplicitlyTyped) {
      return true;
    }
    return false;
  }

  // Splits a label into its alternative branches for epsilon-closure
  // purposes and trims each. Multiple alternatives on one line (e.g. a
  // multi-line label with several possible transitions) are tried
  // independently — this is what gives NFA-style branching.
  Iterable<String> _epsilonAlternatives(String label) =>
      label.split(_epsilonLabelSplitter).map((s) => s.trim());

  // Same splitting rule as _epsilonAlternatives, kept as a separate method
  // (see the two RegExp declarations' comment above) purely for readability
  // at each call site — this one is used when checking consuming
  // (non-epsilon) transitions.
  Iterable<String> _transitionAlternatives(String label) =>
      label.split(_transitionLabelSplitter).map((s) => s.trim());

  /// Run the black-box inner machine on the tokens that the outer machine has
  /// NOT yet consumed, i.e. [inputTokens] sliced from [inputPos] onward.
  ///
  /// [inputPos] is the outer machine's current read pointer (the index of the
  /// first token the black box should see).  The returned [outputHeadPos] is
  /// already translated back to an absolute index in the *full* [inputTokens]
  /// list so callers can use it directly as the new outer [inputPos].
  ///
  /// The cache key includes [inputPos] so that the same black-box node visited
  /// at different pointer positions produces separate cache entries.
  ({bool accepted, List<String> outputTokens, int outputHeadPos}) _runBlackBox(
    NodeData node,
    List<String> inputTokens,
    int inputPos,
  ) {
    // Non-black-box node: identity passthrough, nothing to run.
    if (!node.isBlackBox) {
      return (accepted: true, outputTokens: inputTokens, outputHeadPos: inputPos);
    }

    // Slice the token list to only what the outer machine hasn't consumed yet.
    // If inputPos is out of range treat it as an empty slice rather than
    // returning the whole input (which would confuse the inner machine).
    final slicedTokens = (inputPos >= 0 && inputPos <= inputTokens.length)
      ? (inputPos < inputTokens.length ? inputTokens.sublist(inputPos) : <String>[]) 
      : <String>[];

    // Cache lookup keyed on the node plus exactly what the inner machine
    // will actually see (position + remaining tokens) — a hit here skips
    // re-parsing the black box's DSL and re-running its whole simulator.
    final cacheKey = '${node.id}:$inputPos:${slicedTokens.join('\u0001')}';
    final cached = _blackBoxResultCache[cacheKey];
    if (cached != null) return cached;

    final dsl = node.blackBoxDsl.trim();
    if (dsl.isEmpty) {
      // No inner program configured — the black box can never accept.
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
        outputHeadPos: inputPos,
      );
    }

    try {
      final graph = DslCodec.importFromDsl(dsl);
      final input = slicedTokens.join();
      switch (graph.automataMode) {
        case AutomataMode.ndfa:
        case AutomataMode.regex:
          // Inner machine is itself an NFA/DFA — recursively build a fresh
          // AutomataSimulator for it (black boxes can nest arbitrarily deep).
          final sim = AutomataSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          final accepted = sim.finalResult() == SimResult.accept;
          // NFA/PDA black boxes consume their entire slice and the outer machine
          // continues from the end of that slice (i.e. inputPos + slicedTokens.length).
          return _blackBoxResultCache[cacheKey] = (
            accepted: accepted,
            outputTokens: accepted ? inputTokens : const <String>[],
            outputHeadPos: accepted ? inputPos + slicedTokens.length : inputPos,
          );
        case AutomataMode.pda:
          final sim = PdaSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          final accepted = sim.finalResult() == PdaSimResult.accept;
          return _blackBoxResultCache[cacheKey] = (
            accepted: accepted,
            outputTokens: accepted ? inputTokens : const <String>[],
            outputHeadPos: accepted ? inputPos + slicedTokens.length : inputPos,
          );
        case AutomataMode.tm:
          final sim = TmSimulator(nodes: graph.nodes, lines: graph.lines);
          // The outer machine here (NFA/PDA) has no tape concept of its own,
          // so there's no "outer tape count" to inherit. But the black box's
          // *own* DSL may still use multiple tapes purely for its internal
          // computation (e.g. a scratch tape) — without this, the simulator
          // would default to a single tape and silently ignore any
          // transition inside the box that targets tape 2+.
          sim.tapeCount = detectRequiredTapeCount(graph.nodes, graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          // Runs the inner TM to completion (computeNext() keeps returning
          // true until it halts or gets stuck) rather than stepping it
          // interactively — the black box is a black box, only its final
          // verdict and output tape matter to the outer machine.
          while (sim.computeNext()) {}
          if (sim.result != TmResult.accept) {
            return _blackBoxResultCache[cacheKey] = (
              accepted: false,
              outputTokens: const <String>[],
              outputHeadPos: inputPos,
            );
          }
          final (outputTokens: outTokens, outputHeadPos: innerHeadPos) =
              _tmOutputTokensAndHead(sim);
          // The TM black box may rewrite its slice.  Reconstruct the full token
          // list as: tokens before inputPos  +  TM's output  +  tokens after the slice.
          final tokensAfter = inputPos + slicedTokens.length < inputTokens.length
              ? inputTokens.sublist(inputPos + slicedTokens.length)
              : const <String>[];
          final reconstructed = [
            ...inputTokens.sublist(0, inputPos),
            ...outTokens,
            ...tokensAfter,
          ];
          // innerHeadPos is relative to outTokens; translate to the reconstructed list.
          final absoluteHeadPos = inputPos + innerHeadPos;
          return _blackBoxResultCache[cacheKey] = (
            accepted: true,
            outputTokens: reconstructed,
            outputHeadPos: absoluteHeadPos,
          );
      }
    } catch (_) {
      // Malformed inner DSL, or any other unexpected failure while running
      // it — treat the black box as a dead branch rather than propagating
      // the exception up into the outer simulation.
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
        outputHeadPos: inputPos,
      );
    }
  }

  /// Returns the trimmed output tokens from the inner TM's tape **and** the
  /// logical index (into those output tokens) where the inner TM's head was
  /// sitting when it halted.  This lets the outer machine resume reading from
  /// the correct position in the transformed token list.
  ({List<String> outputTokens, int outputHeadPos}) _tmOutputTokensAndHead(
      TmSimulator sim) {
    // Do NOT use sim.currentTape / sim.currentHeadPos — those go through the
    // step cursor (sim.step) which is still -1 after computeNext() finishes,
    // so they would return the *initial* tape rather than the final one.
    // Instead, pull an accepting config from the last snapshot.
    TmConfig? haltConfig;
    if (sim.steps.isNotEmpty) {
      final finalConfigs = sim.steps.last.configs;
      // Prefer an explicit halt-accept config; fall back to any plain accept
      // config; fall back to whatever's first if neither exists (defensive
      // — shouldn't normally be reached since the caller already checked
      // sim.result == TmResult.accept before calling this).
      haltConfig = finalConfigs.where(
        (c) => sim.nodes[c.nodeId]?.isHaltAccept == true,
      ).firstOrNull;
      haltConfig ??= finalConfigs.where(
        (c) => sim.nodes[c.nodeId]?.isAccept == true,
      ).firstOrNull;
      haltConfig ??= finalConfigs.firstOrNull;
    }

    final tape = haltConfig?.tape;
    final rawHeadPos = haltConfig?.headPos ?? 0; // absolute index
    if (tape == null) return (outputTokens: const <String>[], outputHeadPos: 0);

    // Build a map from absolute tape index → trimmed output index so we can
    // translate the head position after stripping leading/trailing blanks.
    final cells = tape.cells;
    int start = 0;
    int end = cells.length;
    while (start < end && (cells[start].isEmpty || cells[start] == kBlank)) {
      start++;
    }
    while (end > start &&
        (cells[end - 1].isEmpty || cells[end - 1] == kBlank)) {
      end--;
    }

    // Normalize cell values: the inner TM tape stores blanks as kBlank='∅',
    // but the outer FA simulator represents blanks as '' (empty string).
    // Without this, any cell the inner TM wrote as blank would appear as the
    // literal '∅' token in the reconstructed outer token list, breaking
    // downstream matching.  Non-blank symbols are passed through unchanged.
    final outputTokens = start >= end
        ? const <String>[]
        : cells.sublist(start, end).map((c) => (c.isEmpty || c == kBlank) ? '' : c).toList();

    // Translate the absolute head position to an index in outputTokens.
    // Allow one-past-end (== outputTokens.length) so that a head that moved
    // off the right edge of the non-blank content (A→B→C→ case) is not
    // snapped back onto the last symbol.  The outer sim treats an inputPos
    // equal to tokens.length as "all input consumed", which is exactly right.
    int outputHeadPos = 0;
    if (outputTokens.isNotEmpty) {
      outputHeadPos = (rawHeadPos - start).clamp(0, outputTokens.length);
    }

    return (outputTokens: outputTokens, outputHeadPos: outputHeadPos);
  }

  // Computes the epsilon-closure of [startConfigs]: every config reachable
  // via free (non-consuming) moves — tilda transitions, null jumps, and
  // black-box hops that don't consume outer input — without advancing the
  // input position. Returns both the closure's config set and the set of
  // line ids traversed to build it (for UI highlighting).
  (Set<_SimConfig>, Set<String>) _epsilonClosure(Set<_SimConfig> startConfigs) {
    final visitedConfigs = <String, _SimConfig>{
      for (final cfg in startConfigs) cfg.key: cfg,
    };
    final linesUsed = <String>{};
    final queue = <_SimConfig>[...startConfigs];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final currentNode = nodes[current.nodeId];
      if (currentNode == null) continue;

      var effective = current;
      if (currentNode.isBlackBox) {
        // A black box sitting at the head of the epsilon-closure worklist
        // gets run eagerly (even though we haven't "stepped" input) so its
        // rewritten output tokens/position are what subsequent free moves
        // from this node see.
        final result = _runBlackBox(currentNode, current.tokens, current.inputPos);
        if (!result.accepted) {
          // If inner machine rejected, keep the original config so we can
          // still explore tilda/null transitions from the black-box node.
          effective = current;
        } else {
          effective = _SimConfig(
            nodeId: current.nodeId,
            tokens: result.outputTokens,
            inputPos: result.outputHeadPos,
          );
          if (!visitedConfigs.containsKey(effective.key)) {
            visitedConfigs[effective.key] = effective;
            queue.add(effective);
          } else if (effective.key != current.key) {
            // The rewritten config was already visited via a different path
            // and differs from the original — nothing new to explore from
            // here under `effective`; skip straight to the next queue item
            // rather than falling through to explore outgoing lines twice.
            continue;
          }
        }
      }

      // Don't follow outgoing transitions from halt states, but do include
      // them in the active set (already added to visitedConfigs on enqueue).
      if (currentNode.isHaltAccept || currentNode.isHaltReject) continue;

      for (final line in lines.values) {
        if (line.nodeAId != effective.nodeId) continue;
        bool isNormalEpsilon = false;
        bool isNullJump = false;
        final atEndOfInput = effective.inputPos >= effective.tokens.length;

        for (final alt in _epsilonAlternatives(line.label)) {
          final normalized = _normalizeSimToken(alt);
          // Whether the user's ACTUAL typed input (not the black-box-rewritten
          // `effective` tokens) contains a literal '?' — this is what
          // distinguishes "the user really typed a ? character" from "input
          // just happens to be exhausted", per _isEpsilonLabel's contract.
          final nullWasExplicitlyTyped = current.tokens.any(_isNullToken);

          if (normalized.isEmpty || normalized == '~') isNormalEpsilon = true;
          // Both `?` and `\0` on a transition label act as null jumps
          // (tilda transitions that fire only when input is exhausted).
          if ((normalized == '?' || normalized == r'\0') &&
              atEndOfInput &&
              (!nullWasExplicitlyTyped || currentNode.isBlackBox)) {
            isNullJump = true;
          }
        }

        if (!isNormalEpsilon && !isNullJump) continue;

        final next = _SimConfig(
          nodeId: line.nodeBId,
          tokens: effective.tokens,
          inputPos: effective.inputPos,
        );
        if (visitedConfigs.containsKey(next.key)) continue;
        linesUsed.add(line.id);
        visitedConfigs[next.key] = next;
        queue.add(next);
      }
    }

    return (visitedConfigs.values.toSet(), linesUsed);
  }

  // Precomputes the ENTIRE step-by-step run (see the class-level comment
  // above for why this is done eagerly rather than lazily). Populates
  // states/usedLines/_configsByStep, one entry per round, starting with
  // round 0 (the initial epsilon-closure before consuming anything).
  void _buildSimulation({StartArrowData? startArrow}) {
    states.clear();
    usedLines.clear();
    _configsByStep.clear();

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      // No valid start state — record a single empty round rather than
      // leaving the lists empty, so maxStep/activeNodes etc. still have a
      // well-defined (if empty) round 0 to look at.
      states.add({});
      usedLines.add({});
      _configsByStep.add(const <_SimConfig>[]);
      return;
    }

    final initialConfig = _SimConfig(
      nodeId: startArrow.nodeId,
      tokens: List<String>.from(tokens),
      inputPos: 0,
    );
    final (initialClosure, initialLines) = _epsilonClosure({initialConfig});

    Set<_SimConfig> current = initialClosure;
    states.add({for (final c in current) c.nodeId});
    usedLines.add(Set.from(initialLines));
    _configsByStep.add(List<_SimConfig>.from(current));

    // Safety valve against runaway/infinite simulation (e.g. a graph with a
    // black-box cycle that never terminates) — caps the recorded history at
    // 512 rounds rather than looping forever.
    const int kMaxSteps = 512;
    int stepsBuilt = 0;
    while (current.isNotEmpty && stepsBuilt < kMaxSteps) {
      final stepLines = <String>{};
      final nextConfigs = <_SimConfig>{};
      bool consumedAny = false;

      bool hasHaltAccept = false;
      for (final config in current) {
        final node = nodes[config.nodeId];
        if (node == null || node.isHaltReject) continue;
        // haltAccept: the current set already contains this config in
        // _configsByStep.  Just flag it so we stop after this iteration.
        if (node.isHaltAccept) {
          hasHaltAccept = true;
          continue;
        }

        var effective = config;
        if (node.isBlackBox) {
          final result = _runBlackBox(node, config.tokens, config.inputPos);
          // Rejected inner machine kills this branch outright (unlike the
          // epsilon-closure case above, which kept exploring free moves from
          // a rejected black box — here we're trying to CONSUME input via
          // this node, and a rejecting black box has nothing valid to
          // consume with).
          if (!result.accepted) continue;
          effective = _SimConfig(
            nodeId: config.nodeId,
            tokens: result.outputTokens,
            inputPos: result.outputHeadPos,
          );
        }

        // If the black box (or normal config) has consumed all tokens, it
        // cannot fire a normal consuming transition — but it CAN take outgoing
        // transitions (treated as unconditional hops) because the black box
        // itself did the consumption.  Follow every outgoing line from the
        // black-box node as an tilda hop so chaining works without requiring
        // ~ labels after the black box.  Also add the effective config itself
        // so _epsilonClosure can pick up any null/tilda transitions on the
        // black-box node.
        if (effective.inputPos >= effective.tokens.length) {
          if (node.isBlackBox) {
            consumedAny = true;
            // Follow every outgoing line as an unconditional hop.
            for (final line in lines.values) {
              if (line.nodeAId != effective.nodeId) continue;
              nextConfigs.add(_SimConfig(
                nodeId: line.nodeBId,
                tokens: effective.tokens,
                inputPos: effective.inputPos,
              ));
              stepLines.add(line.id);
            }
            // Also add the effective config itself so tilda/null transitions
            // on the BB node are picked up by _epsilonClosure.
            nextConfigs.add(effective);
          }
          continue;
        }

        // Whether the user actually typed a literal '?'/'\0' anywhere in
        // THIS branch's own token stream — passed to _isEpsilonLabel below
        // so a genuinely-typed '?' character is matched literally rather
        // than misread as the "null jump" convention.
        final nullWasExplicitlyTyped = config.tokens.any(_isNullToken);

        for (final line in lines.values) {
          if (line.nodeAId != effective.nodeId) continue;
          for (final alt in _transitionAlternatives(line.label)) {
            if (_isEpsilonLabel(alt, false, nullWasExplicitlyTyped)) continue;

            // ── wildcard and negated-wildcard handling ──────────────────
            // A bare "." matches any single token (wildcard).
            // ".-X" or ".-XY" matches any single token that is NOT in the
            // excluded set after the dash.
            final altTrimmed = alt.trim();
            if (altTrimmed == kWildcard) {
              // Plain wildcard: matches exactly one token (not tilda).
              consumedAny = true;
              nextConfigs.add(_SimConfig(
                nodeId: line.nodeBId,
                tokens: effective.tokens,
                inputPos: effective.inputPos + 1,
              ));
              stepLines.add(line.id);
              // `break` here stops checking further alternatives on THIS
              // line for THIS config — the wildcard already matched, so
              // there's no need to also test any other alternative on the
              // same line label against the same input position.
              break;
            }
            final negExcluded = _parseNegatedWildcard(altTrimmed);
            if (negExcluded != null) {
              // Negated wildcard: matches any single token not in the excluded list.
              final inputToken = _normalizeSimToken(effective.tokens[effective.inputPos]);
              if (!negExcluded.map(_normalizeSimToken).contains(inputToken)) {
                consumedAny = true;
                nextConfigs.add(_SimConfig(
                  nodeId: line.nodeBId,
                  tokens: effective.tokens,
                  inputPos: effective.inputPos + 1,
                ));
                stepLines.add(line.id);
                break;
              }
              continue;
            }
            // ────────────────────────────────────────────────────────────

            // Treat the transition label as a sequence of tokens and attempt
            // to match that sequence starting at the current input position.
            // This is what lets a single transition label consume MULTIPLE
            // input tokens at once (e.g. a quoted multi-character label),
            // not just one.
            final labelTokens = _tokenize(alt);
            final normalizedLabel = labelTokens.map(_normalizeSimToken).toList();
            final remaining = effective.tokens.length - effective.inputPos;
            // Label is longer than what's left to consume — can't possibly
            // match, skip without doing the per-character comparison below.
            if (normalizedLabel.length > remaining) continue;

            var allMatch = true;
            for (int i = 0; i < normalizedLabel.length; i++) {
              if (normalizedLabel[i] != _normalizeSimToken(effective.tokens[effective.inputPos + i])) {
                allMatch = false;
                break;
              }
            }
            if (!allMatch) continue;

            consumedAny = true;
            nextConfigs.add(
              _SimConfig(
                nodeId: line.nodeBId,
                tokens: effective.tokens,
                inputPos: effective.inputPos + normalizedLabel.length,
              ),
            );
            stepLines.add(line.id);
            break;
          }
        }
      }

      // No branch consumed anything this round (dead end), or every branch
      // that could have advanced produced no successors — the computation
      // has nothing left to explore, so stop recording further rounds.
      if (!consumedAny || nextConfigs.isEmpty) break;
      // A halt-accept was reached this round (flagged above) — that round is
      // already recorded; stop here rather than computing a further round
      // past the halt.
      if (hasHaltAccept) break;

      final (closureConfigs, closureLines) = _epsilonClosure(nextConfigs);
      current = closureConfigs;
      states.add({for (final c in current) c.nodeId});
      usedLines.add({...stepLines, ...closureLines});
      _configsByStep.add(List<_SimConfig>.from(current));
      stepsBuilt++;
      if (current.isEmpty) break;
    }

    // No padding here. `states` / `usedLines` / `_configsByStep` simply stop
    // growing at the round where the computation halted — whether that's a
    // halt-accept state, every branch dying, or the kMaxSteps safety cap.
    // [maxStep] reflects that real stopping point, and the UI (sim_panels.dart)
    // refuses to step `step` past it. This is what actually makes "reached
    // halt-accept" behave like a halt: no further computation is shown, the
    // last recorded round (the one containing the halt-accept state, plus
    // whatever other branches were still alive when it fired) stays on
    // screen, and the ACCEPT badge appears as soon as step reaches it —
    // instead of padding fake repeated/frozen rounds out to tokens.length,
    // which is what previously made unrelated live branches vanish once the
    // step cursor was clamped to tokens.length elsewhere in the UI.
  }
}
// ──────────────────────────────────────────────────────────────────────────────
//  PDA SIMULATOR
//  (merged from pda_simulator.dart)
// ──────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
//  PDA Transition label parsing
//
//  Standard notation:  read , pop | push
//    read  — input symbol consumed, or ~ / ~ for tilda
//    pop   — stack symbol popped, or ~ / ~ for no pop
//    push  — stack symbol(s) pushed; space-separated, left-most ends on top
//            or ~ for push nothing
//
//  Legacy slash form (read,pop/push or read/pop) is still accepted.
//
//  Multiple alternatives on one transition are separated by newlines.
//
//  Examples:
//    a,x|y       read a, pop x, push y
//    ~,~/~       tilda, no stack change
//    b,x|~       read b, pop x, push nothing
//    a,∅|A ∅    read a, pop bottom marker ∅, push A then ∅
// ─────────────────────────────────────────────────────────────────────────────

// A single parsed alternative from a PDA transition label.
class PdaTransition {
  /// Input symbol to consume.  Empty string = tilda.
  final String read;

  /// Stack symbol to pop.  Empty string = don't pop.
  final String pop;

  /// Stack symbols to push, left-to-right (so [0] ends on top).
  final List<String> push;

  const PdaTransition({
    required this.read,
    required this.pop,
    required this.push,
  });
}

/// Bottom-of-stack marker (also available as [[\0]] in labels).
const String kStackBottom = '∅';

/// Parses a single alternative like "a,x|y" into a [PdaTransition].
// Tries each supported label format in order of specificity, falling back
// to a plain FA-style "read only" transition if nothing else matches — this
// mirrors parseTmLabel's layered-fallback style further down in the file.
PdaTransition parsePdaLabel(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return const PdaTransition(read: '', pop: '', push: []);

  final hasComma = s.contains(',');
  final hasPipeOrSlash = s.contains('|') || s.contains('/');

  // Format 1: read,pop,push (3-part comma) e.g. `a,X,y`
  if (hasComma && !hasPipeOrSlash) {
    final parts = s.split(',');
    if (parts.length == 3) {
      final read = _normalize(parts[0]);
      final pop = _normalize(parts[1]);
      final push = _parsePushString(parts[2]);
      return PdaTransition(read: read, pop: pop, push: push);
    }
  }

  // Format 2: read,pop|push or read,pop/push (legacy)
  final firstComma = s.indexOf(',');
  if (firstComma >= 0) {
    final read = _normalize(s.substring(0, firstComma));
    final rest = s.substring(firstComma + 1);
    final sep = _findPopPushSeparator(rest);
    if (sep >= 0) {
      final pop = _normalize(rest.substring(0, sep));
      final push = _parsePushString(rest.substring(sep + 1));
      return PdaTransition(read: read, pop: pop, push: push);
    }

    // Format 3: read,pop (no push)
    final pop = _normalize(rest);
    return PdaTransition(read: read, pop: pop, push: const []);
  }

  // Format 4: 3-character shorthand e.g. `aXy` => read=a pop=X push=y
  if (!hasPipeOrSlash) {
    // .runes rather than direct string indexing, so a shorthand label built
    // from non-BMP characters (e.g. certain symbol glyphs) is measured in
    // actual Unicode code points, not UTF-16 code units.
    final runes = s.runes.toList();
    if (runes.length == 3) {
      final read = _normalize(String.fromCharCode(runes[0]));
      final pop = _normalize(String.fromCharCode(runes[1]));
      final pushTok = _normalize(String.fromCharCode(runes[2]));
      return PdaTransition(
        read: read,
        pop: pop,
        push: pushTok.isEmpty ? const [] : [pushTok],
      );
    }
  }

  // Fallback: plain FA-style label — treat as read only.
  return PdaTransition(read: _normalize(s), pop: '', push: const []);
}

/// Prefer `|` (standard); fall back to `/` (legacy).
int _findPopPushSeparator(String s) {
  final pipe = s.indexOf('|');
  final slash = s.indexOf('/');
  // Pipe wins whenever it's present and appears no later than any slash —
  // this correctly prefers `|` even if a `/` also happens to appear further
  // along in the string (e.g. inside an unrelated push symbol).
  if (pipe >= 0 && (slash < 0 || pipe < slash)) return pipe;
  if (slash >= 0) return slash;
  return -1;
}

List<String> _parsePushString(String raw) {
  final t = _normalize(raw);
  if (t.isEmpty) return [];
  // Space-separated form lets a push symbol be more than one character
  // (e.g. "AB CD" pushes two multi-char symbols); without a space, each
  // character in the string becomes its own single-character push symbol.
  if (t.contains(' ')) {
    return t.split(' ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  return t.split('').toList();
}

// Shared "tilda means empty" normalization for PDA label pieces — either
// tilda glyph collapses to '', which is this simulator's convention for
// "no read / no pop / no push" throughout the PDA code below.
String _normalize(String s) {
  final t = s.trim();
  if (t == '~' || t == '~') return '';
  return t;
}

// ─────────────────────────────────────────────────────────────────────────────
//  PDA Configuration  (state × remaining-input × stack)
// ─────────────────────────────────────────────────────────────────────────────

// One reachable (state, input position, stack contents) configuration
// during PDA simulation. Unlike _SimConfig above, this doesn't carry the
// full token list — PDA black boxes (handled inline in _build/_epsilonClosure
// below) don't rewrite the outer token stream the way TM black boxes can, so
// there's no need to track a per-config token list, just the shared `tokens`
// field on PdaSimulator plus this config's read position.
class PdaConfig {
  final String nodeId;
  final int inputPos;
  final List<String> stack;

  const PdaConfig({
    required this.nodeId,
    required this.inputPos,
    required this.stack,
  });

  // Stack contents joined bottom-to-top (`.reversed` since `stack` is stored
  // top-of-stack-last, i.e. stack.last is the top) — used as part of the
  // dedup key below so two configs with the same state/input but genuinely
  // different stack contents are treated as distinct.
  String get stackKey => stack.reversed.join('|');

  String get key => '$nodeId:$inputPos:$stackKey';

  // Value-equality override (needed because PdaConfig is stored in Sets —
  // see `result.add(next)` in _epsilonClosure below — where structural
  // equality, not reference identity, is what determines "already visited").
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdaConfig) return false;
    if (nodeId != other.nodeId || inputPos != other.inputPos) return false;
    if (stack.length != other.stack.length) return false;
    for (int i = 0; i < stack.length; i++) {
      if (stack[i] != other.stack[i]) return false;
    }
    return true;
  }

  // Must be consistent with == above (equal objects -> equal hashCodes) for
  // Set/Map membership checks to behave correctly.
  @override
  int get hashCode => Object.hash(nodeId, inputPos, Object.hashAll(stack));
}

/// One active NPDA configuration shown in the UI.
// Read-only mirror of PdaConfig exposed to the UI layer — kept as a
// separate type (rather than exposing PdaConfig directly) so UI code
// doesn't depend on PdaConfig's equality/hashCode machinery, which exists
// purely for the simulator's own internal dedup bookkeeping.
class PdaActiveConfig {
  final String nodeId;
  final int inputPos;
  final List<String> stack;

  const PdaActiveConfig({
    required this.nodeId,
    required this.inputPos,
    required this.stack,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

enum PdaSimResult { accept, reject }

// One recorded round of PDA simulation — the PDA analogue of
// AutomataSimulator's parallel states/usedLines/_configsByStep lists, but
// bundled into a single object per round here instead of three parallel
// lists.
class PdaStepSnapshot {
  final List<PdaActiveConfig> configs;
  final Set<String> usedLineIds;

  const PdaStepSnapshot({required this.configs, required this.usedLineIds});

  Set<String> get activeNodeIds => {for (final c in configs) c.nodeId};
}

/// Executes a PDA over the input while tracking the stack contents for every
/// active configuration, which lets the UI animate both state and stack progress.
// Same eager-precompute-the-whole-run design as AutomataSimulator (see its
// class comment) — `steps` is built once in _build() / rebuild(), and `step`
// is just a cursor into that precomputed list.
class PdaSimulator {
  PdaSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  List<String> tokens = [];
  final List<PdaStepSnapshot> steps = [];

  int step = -1;

  /// Maximum valid value for [step] given the current [steps] list.
  ///
  /// Mirrors [TmSimulator.maxStep] / [AutomataSimulator.maxStep]: step=-1 →
  /// steps[0], step==maxStep → steps.last. `steps` stops growing once the
  /// computation halts (halt-accept reached, every branch dies, or a stack
  /// growth loop is detected) — there is no padding past that point.
  int get maxStep => steps.isEmpty ? -1 : steps.length - 2;

  /// Set when ~-transitions can grow the stack without bound (e.g. `~,~|A` in a cycle).
  bool stackGrowthLoopDetected = false;

  Set<String> get activeNodes {
    final idx = step + 1;
    if (idx < 0 || idx >= steps.length) return {};
    return steps[idx].activeNodeIds;
  }

  Set<String> get activeLines {
    // idx mirrors activeNodes: step=-1 -> idx=0, the initial tilda
    // closure computed before any input is consumed. Free ~ jumps taken in
    // that closure belong here just as their destination nodes belong in
    // steps[0].activeNodeIds — don't special-case step < 0 to empty.
    final idx = step + 1;
    if (idx < 0 || idx >= steps.length) return {};
    return steps[idx].usedLineIds;
  }

  PdaStepSnapshot? get _currentSnapshot {
    final idx = step + 1;
    if (idx < 0 || idx >= steps.length) return null;
    return steps[idx];
  }

  List<PdaActiveConfig> get activeConfigs =>
      _currentSnapshot?.configs ?? const [];

  List<String> get currentStack {
    final configs = activeConfigs;
    if (configs.isEmpty) return [];
    // Arbitrarily shows the FIRST active config's stack (the UI's
    // single-stack display can only show one at a time even when multiple
    // NPDA branches are alive simultaneously) — see allCurrentStacks below
    // for the multi-branch view.
    return List.unmodifiable(configs.first.stack);
  }

  List<List<String>> get allCurrentStacks =>
      activeConfigs.map((c) => List<String>.unmodifiable(c.stack)).toList();

  /// Remaining input for config [index] at the current step.
  String remainingInputAt(int index) {
    final configs = activeConfigs;
    if (index < 0 || index >= configs.length) return '';
    return tokens.sublist(configs[index].inputPos).join();
  }

  void rebuild(String input, {StartArrowData? startArrow}) {
    tokens = _tokenize(input);
    _build(startArrow: startArrow);
    // See AutomataSimulator.rebuild for why this must clamp against maxStep
    // rather than tokens.length: `steps` stops growing as soon as the PDA
    // halts, which can happen before every token is consumed.
    if (step > maxStep) step = maxStep;
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step > maxStep) step = maxStep;
  }

  PdaSimResult finalResult() {
    if (steps.isEmpty) return PdaSimResult.reject;
    // An unbounded ~-closure stack growth is not a genuine accept, even if
    // the last recorded round happens to contain an accept state — the
    // machine never actually reached a settled halting configuration.
    // (Previously this fell out as a side effect of padding the steps list
    // with empty snapshots; now that there's no padding, check explicitly.)
    if (stackGrowthLoopDetected) return PdaSimResult.reject;

    // A haltAccept anywhere in the simulation history means accept.
    for (final snap in steps) {
      for (final c in snap.configs) {
        if (nodes[c.nodeId]?.isHaltAccept == true) return PdaSimResult.accept;
      }
    }

    final last = steps.last;
    if (last.configs.isEmpty) return PdaSimResult.reject;

    // Classic PDA acceptance check on the final round: accept if any
    // surviving branch is in an accept state. Unlike AutomataSimulator's
    // finalResult(), this doesn't additionally check "consumed all input"
    // per-config — `steps` only advances by consuming one token per round
    // across the whole tokens list (see _build below), so by the time the
    // loop over tokens finishes, every surviving branch has, by
    // construction, consumed the same number of tokens.
    bool anyAccept = false;
    for (final c in last.configs) {
      final node = nodes[c.nodeId];
      if (node == null) continue;
      if (node.isHaltAccept) return PdaSimResult.accept;
      if (node.isHaltReject) continue;
      if (node.isAccept) anyAccept = true;
    }

    return anyAccept ? PdaSimResult.accept : PdaSimResult.reject;
  }

  // PDA-specific symbol normalizer: unlike AutomataSimulator's
  // _normalizeSimToken (which only resolves [[KEY]] commands), this also
  // runs the raw string through parseTokenText directly (rather than the
  // trim-then-resolve wrapper _resolveCommand uses) and treats tilda as
  // empty — matching the "tilda means empty" convention used throughout
  // PdaTransition parsing above.
  String _normalizeSym(String s) {
    final resolved = parseTokenText(s.trim());
    if (resolved == '~' || resolved == '~') return '';
    return resolved;
  }

  PdaActiveConfig _toActive(PdaConfig c) => PdaActiveConfig(
        nodeId: c.nodeId,
        inputPos: c.inputPos,
        stack: c.stack,
      );

  // Precomputes the PDA's entire run, one round per input token, mirroring
  // AutomataSimulator._buildSimulation's eager-precompute design but with a
  // token-driven outer loop instead: PDA transitions always consume exactly
  // one input symbol when non-epsilon (no multi-token labels the way FA
  // labels can have), so the natural loop bound is `tokens.length` rather
  // than an arbitrary step cap.
  void _build({StartArrowData? startArrow}) {
    steps.clear();
    stackGrowthLoopDetected = false;

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      steps.add(const PdaStepSnapshot(configs: [], usedLineIds: {}));
      return;
    }

    final initial = PdaConfig(
      nodeId: startArrow.nodeId,
      inputPos: 0,
      stack: const [],
    );
    final (initConfigs, initLines) = _epsilonClosure({initial});
    // A stack-growth loop can be detected even during the very first
    // (pre-input) epsilon-closure — bail out with `steps` left empty rather
    // than recording a snapshot for a closure that never actually settled.
    if (stackGrowthLoopDetected) return;

    steps.add(PdaStepSnapshot(
      configs: initConfigs.map(_toActive).toList(),
      usedLineIds: initLines,
    ));

    Set<PdaConfig> current = initConfigs;

    for (int ti = 0; ti < tokens.length; ti++) {
      final token = _normalizeSym(tokens[ti]);
      final nextConfigs = <PdaConfig>{};
      final stepLines = <String>{};
      bool hasHaltAccept = false;

      for (final config in current) {
        final node = nodes[config.nodeId];
        if (node == null) continue;
        if (node.isHaltReject) continue;

        if (node.isHaltAccept) {
          // This branch already halted-and-accepted on an earlier round —
          // it's frozen and cannot consume further tokens. Flag it so we
          // stop growing `steps` after this round (the round containing this
          // config is already the last entry in `steps`), but keep
          // processing the other configs in `current` below so their
          // transitions aren't silently discarded.
          hasHaltAccept = true;
          continue;
        }

        for (final line in lines.values) {
          if (line.nodeAId != config.nodeId) continue;

          for (final altRaw in line.label.split('\n')) {
            final t = parsePdaLabel(altRaw);
            final readSym = _normalizeSym(t.read);
            // Empty read symbol means this alternative is epsilon-only —
            // not a candidate for consuming `token` this round (epsilon
            // alternatives are instead handled entirely inside
            // _epsilonClosure, called after this loop).
            if (readSym.isEmpty) continue;

            // ── wildcard / negated-wildcard on the read symbol ──────────
            bool readMatches;
            if (readSym == '.') {
              // Plain wildcard — matches any single input token.
              readMatches = true;
            } else if (readSym.length >= 3 && readSym[0] == '.' && readSym[1] == '-') {
              // Negated wildcard ".-X[Y…]" — matches any token NOT excluded.
              final excluded = readSym.substring(2).split('').map(_normalizeSym).toList();
              readMatches = !excluded.contains(token);
            } else {
              readMatches = (readSym == token);
            }
            if (!readMatches) continue;
            // ────────────────────────────────────────────────────────────

            final popSym = _normalizeSym(t.pop);
            final pushSyms = t.push.map(_normalizeSym).toList();

            final newStack = _applyStackOp(config.stack, popSym, pushSyms);
            // null means the required pop couldn't be satisfied (e.g. popping
            // a specific symbol that isn't on top) — this alternative can't
            // fire for this config.
            if (newStack == null) continue;

            nextConfigs.add(PdaConfig(
              nodeId: line.nodeBId,
              inputPos: ti + 1,
              stack: newStack,
            ));
            stepLines.add(line.id);
          }
        }
      }

      // A halt-accept branch was found in `current` this round. That round
      // is already the last entry in `steps` (added at the bottom of the
      // previous loop iteration, or as the initial snapshot) — stop here
      // rather than computing/appending a further round. This is what makes
      // "reached halt-accept" actually halt the visible computation instead
      // of continuing to advance other still-alive branches past it.
      if (hasHaltAccept) break;

      final (closedConfigs, closedLines) = _epsilonClosure(nextConfigs);
      if (stackGrowthLoopDetected) return;
      current = closedConfigs;
      steps.add(PdaStepSnapshot(
        configs: current.map(_toActive).toList(),
        usedLineIds: {...stepLines, ...closedLines},
      ));

      if (current.isEmpty) break;
    }
    // No padding: `steps` simply stops growing at whichever round the loop
    // above broke out of (halt-accept reached, every branch died, a stack
    // growth loop was detected, or all tokens were consumed). [maxStep]
    // reflects that real stopping point and the UI refuses to step past it.
  }

  // PDA epsilon-closure: explores every reachable configuration via tilda
  // (and "null jump" — see below) transitions without consuming input,
  // updating the stack along the way. Uses a FIFO Queue (breadth-first)
  // rather than the LIFO list AutomataSimulator._epsilonClosure uses —
  // either traversal order reaches the same final closure set, the choice
  // here doesn't affect correctness.
  (Set<PdaConfig>, Set<String>) _epsilonClosure(Set<PdaConfig> start) {
    final visited = <String>{};
    final result = <PdaConfig>{...start};
    final linesUsed = <String>{};
    final queue = Queue<PdaConfig>.from(start);

    // Mirror the string simulator's "null jump" rule:
    // treat input-read symbol `∅` as tilda *only* when at end-of-input,
    // and only if the input did not explicitly contain `∅`.
    final nullWasExplicitlyTyped = tokens.any((t) => _normalizeSym(t) == kStackBottom);

    // Safety valve distinct from AutomataSimulator's kMaxSteps: this guards
    // specifically against the stack growing without bound during a single
    // epsilon-closure pass (e.g. a `~,~|A` self-loop that keeps pushing),
    // which would otherwise never terminate since epsilon-closure has no
    // input to exhaust.
    const int kMaxStackHeightDuringEpsilonClosure = 200;

    while (queue.isNotEmpty) {
      final config = queue.removeFirst();
      final key = config.key;
      if (visited.contains(key)) continue;
      visited.add(key);

      final node = nodes[config.nodeId];
      if (node == null || node.isHaltAccept || node.isHaltReject) continue;

      for (final line in lines.values) {
        if (line.nodeAId != config.nodeId) continue;

        for (final altRaw in line.label.split('\n')) {
          final t = parsePdaLabel(altRaw);
          final readSym = _normalizeSym(t.read);
          final atEndOfInput = config.inputPos == tokens.length;
          final isNullJumpRead = readSym == kStackBottom && atEndOfInput && !nullWasExplicitlyTyped;
          // Only a genuinely empty read (tilda) or a null-jump read (∅ at
          // end-of-input, when the user didn't literally type ∅) qualifies
          // as a free move here; anything else needs an actual input token
          // to consume and is handled in _build's main loop instead.
          if (readSym.isNotEmpty && !isNullJumpRead) continue;

          final popSym = _normalizeSym(t.pop);
          final pushSyms = t.push.map(_normalizeSym).toList();

          final newStack = _applyStackOp(config.stack, popSym, pushSyms);
          if (newStack == null) continue;

          // A "free push" epsilon move — no pop required, but pushes at
          // least one real symbol — is exactly the shape that can loop
          // forever (~,~|A in a self-loop keeps growing the stack every
          // pass with nothing to ever stop it). Detect and bail before the
          // stack grows unboundedly rather than hanging.
          final nonEmptyPushCount = pushSyms.where((s) => s.isNotEmpty).length;
          final isFreePushEpsilonMove = popSym.isEmpty && nonEmptyPushCount > 0;
          if (isFreePushEpsilonMove &&
              newStack.length > kMaxStackHeightDuringEpsilonClosure) {
            stackGrowthLoopDetected = true;
            return (result, linesUsed);
          }

          final next = PdaConfig(
            nodeId: line.nodeBId,
            inputPos: config.inputPos,
            stack: newStack,
          );

          // Set.add returns false if an equal element (per PdaConfig's ==
          // override) already exists — used here both to dedupe `result`
          // and, in the same expression, to decide whether this is a
          // genuinely new config worth enqueueing/recording as a used line.
          if (result.add(next)) {
            linesUsed.add(line.id);
            queue.add(next);
          }
        }
      }
    }

    return (result, linesUsed);
  }

  // Applies one pop then N pushes to a copy of `stack`, returning the new
  // stack, or null if the pop was required but not satisfiable (this
  // alternative can't fire).
  List<String>? _applyStackOp(
    List<String> stack,
    String popSym,
    List<String> pushSyms,
  ) {
    List<String> s = List<String>.from(stack);

    if (popSym.isNotEmpty) {
      if (!_canPop(s, popSym)) return null;
      // Only actually remove a cell if the stack is non-empty — popping the
      // implicit bottom marker off an empty stack (see _canPop's special
      // case for kStackBottom below) is a legal no-op rather than an error.
      if (s.isNotEmpty) s.removeLast();
    }

    // Push in reverse order so pushSyms[0] ends up on top: iterating the
    // push list backwards and always adding to the end of `s` means the
    // LAST thing added (pushSyms[0]) sits at s.last, matching the doc
    // comment "[0] ends on top" on PdaTransition.push.
    for (int i = pushSyms.length - 1; i >= 0; i--) {
      if (pushSyms[i].isNotEmpty) s.add(pushSyms[i]);
    }

    return s;
  }

  // Whether `popSym` can legally be popped off `stack`. kStackBottom (∅) is
  // special: it's treated as always poppable when the stack is genuinely
  // empty (an implicit bottom marker beneath everything), OR when it's
  // explicitly present on top — this lets `∅` be used both as a real pushed
  // marker and as shorthand for "the stack is at its floor."
  bool _canPop(List<String> stack, String popSym) {
    if (popSym == kStackBottom) {
      if (stack.isEmpty) return true;
      return stack.last == kStackBottom;
    }
    if (stack.isEmpty) return false;
    return stack.last == popSym;
  }
}
// ──────────────────────────────────────────────────────────────────────────────

//  TM SIMULATOR
//  (merged from tm_simulator.dart)
// ──────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
//  TM Transition label parsing
//
//  Format:  [tape:] read , write , direction
//    tape      — optional 1-based tape index this transition reads/writes/moves.
//                 Defaults to tape 1 when omitted (so all pre-existing labels
//                 keep working unchanged).
//    read      — the tape symbol currently under the head; ∅ (or ~) matches blank
//    write     — the symbol to write; ∅ (or ~) writes a blank
//    direction — R (move right), L (move left), S (stay)
//
//  Multiple alternatives on one transition are separated by newlines. Each
//  alternative may target a different tape independently, e.g.:
//      1:aXR
//      2:b1S
//
//  3-character shorthand (no read/write/dir separators) is also accepted, with
//  the same optional tape prefix:
//    aXR     →  tape=1, read=a  write=X  direction=R
//    2:aXR   →  tape=2, read=a  write=X  direction=R
//    ∅∅S     →  tape=1, blank-read, blank-write, stay
//
//  The blank symbol used on the tape is `∅` (kBlank).
// ─────────────────────────────────────────────────────────────────────────────

/// Blank tape symbol.
const String kBlank = '∅';

/// Direction the TM head moves after executing a transition.
enum TmDirection { right, left, stay }

// A single parsed single-tape TM transition (one alternative of a label,
// pre-multi-tape-compound-parsing — see TmCompoundTransition below for the
// wrapper that adds multi-tape support).
class TmTransition {
  final String read;
  final String write;
  final TmDirection direction;

  /// 1-based index of the tape this transition reads from, writes to, and
  /// moves the head on. Defaults to 1 when no `N:` prefix is present.
  final int tapeIndex;

  /// True when the label is `~` (or all tildes): unconditional jump that
  /// neither reads, writes, nor moves the head.
  final bool isEpsilon;

  /// True when the read symbol was `~` in the shorthand/comma format,
  /// meaning "match any symbol on this tape" (wildcard read).
  /// Distinct from [isEpsilon] — the head still moves and writes occur.
  final bool isWildcard;

  const TmTransition({
    required this.read,
    required this.write,
    required this.direction,
    this.tapeIndex = 1,
    this.isEpsilon = false,
    this.isWildcard = false,
  });
}

/// Parses one transition alternative into a TM action, including shorthand,
/// wildcard reads, blank-symbol handling, and optional tape-index prefixes.
TmTransition parseTmLabel(String raw) {
  // Normalize the `\0` escape to the real blank glyph BEFORE any other
  // processing, so every subsequent check (all-tilde detection, rune-count
  // shorthand detection, etc.) sees a consistent representation regardless
  // of which way the user typed a blank.
  String preprocessed = raw.replaceAll('\\0', kBlank);
  String s = parseTokenText(preprocessed.trim());
  if (s.isEmpty) {
    // Blank label defaults to a stationary blank-to-blank no-op transition
    // on tape 1 — a reasonable default for an unlabeled arrow rather than
    // treating it as an error.
    return TmTransition(read: kBlank, write: kBlank, direction: TmDirection.stay);
  }

  // All-tilde label → unconditional tilda jump (no read/write/move).
  if (s.isNotEmpty && s.runes.every((r) => r == '~'.codeUnitAt(0))) {
    return TmTransition(
      read: '', write: '', direction: TmDirection.stay, isEpsilon: true,
    );
  }

  // Optional leading "N:" tape-index prefix. Only consumed when N is a
  // positive integer and is immediately followed by ':' — this keeps any
  // label that happens to contain ':' for other reasons (none currently do)
  // from being misread, and ensures omitting the prefix is always safe.
  int tapeIndex = 1;
  final prefixMatch = RegExp(r'^(\d+):(.*)$').firstMatch(s);
  if (prefixMatch != null) {
    final n = int.tryParse(prefixMatch.group(1)!);
    if (n != null && n >= 1) {
      tapeIndex = n;
      s = prefixMatch.group(2)!.trim();
    }
  }

  if (s.isEmpty) {
    // Just a tape prefix with nothing after it, e.g. "2:" — treat as a
    // stationary blank-to-blank no-op on that tape, mirroring the
    // no-prefix-at-all empty-label case above.
    return TmTransition(
      read: kBlank, write: kBlank, direction: TmDirection.stay, tapeIndex: tapeIndex,
    );
  }

  // After stripping a tape prefix, an all-tilde remainder is still an
  // unconditional tilda jump (tape index is irrelevant in that case).
  if (s.runes.every((r) => r == '~'.codeUnitAt(0))) {
    return TmTransition(
      read: '', write: '', direction: TmDirection.stay, isEpsilon: true,
    );
  }

  // Format 1: read,write,dir  (comma-separated)
  if (s.contains(',')) {
    final parts = s.split(',');
    if (parts.length >= 3) {
      final rawRead = parts[0].trim();
      // A bare tilda specifically in the READ position (not write/direction)
      // means "wildcard": the transition still writes and moves, it just
      // doesn't check what's under the head first. Checked against the raw
      // (pre-_normSym) string since _normSym would otherwise collapse tilda
      // to '', indistinguishable from other blank-like inputs.
      final isWildcard = rawRead == '~';
      final read  = isWildcard ? '' : _normSym(rawRead);
      final write = _normSym(parts[1]);
      final dir   = _parseDir(parts[2]);
      return TmTransition(read: read, write: write, direction: dir, tapeIndex: tapeIndex, isWildcard: isWildcard);
    }
  }

  // Format 2: 3-character / 3-rune shorthand e.g. `aXR` or `∅∅S`
  final runes = s.runes.toList();
  if (runes.length == 3) {
    final rawReadChar = String.fromCharCode(runes[0]);
    final isWildcard = rawReadChar == '~';
    final read  = isWildcard ? '' : _normSym(rawReadChar);
    final write = _normSym(String.fromCharCode(runes[1]));
    final dir   = _parseDir(String.fromCharCode(runes[2]));
    return TmTransition(read: read, write: write, direction: dir, tapeIndex: tapeIndex, isWildcard: isWildcard);
  }

  // Fallback: doesn't match any recognized format — degrade gracefully to
  // reading and immediately re-writing the same (whole, un-split) string as
  // both read and write, staying in place, rather than throwing.
  return TmTransition(read: _normSym(s), write: _normSym(s), direction: TmDirection.stay, tapeIndex: tapeIndex);
}

/// Normalize a tape symbol.
/// `~`, `~`, `∅`, or empty → blank (represented as empty string internally).
String _normSym(String s) {
  final t = parseTokenText(s.trim());
  if (t == '~' || t == '~' || t == kBlank || t.isEmpty) return '';
  return t;
}

TmDirection _parseDir(String s) {
  switch (s.trim().toUpperCase()) {
    case 'R': return TmDirection.right;
    case 'L': return TmDirection.left;
    // Anything other than 'R'/'L' (including a genuinely invalid character)
    // defaults to Stay rather than throwing — consistent with this file's
    // general preference for graceful fallbacks over parse errors in label
    // text, since labels are free-form user input.
    default:  return TmDirection.stay;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Multi-tape conjunctive transition  (b1 / b2 syntax)
//
//  Line label format (single alternative):
//
//    primaryOp,bN,secondaryOp
//
//  where primaryOp and secondaryOp each use the same syntax as a normal
//  single-tape transition alternative (shorthand or long form, with optional
//  N: tape prefix):
//
//    1:aXR,b1,3:a1S   — tape 1 read must match; tape 3 written unconditionally
//    1:aXR,b2,2:01S   — both tapes must match (classic parallel multi-tape step)
//
//  bN marker must appear between two non-empty tape operations (index ≥ 1).
//
//  Default behaviour (no bN): each newline-separated alternative is an
//  independent NTM branch exactly as before. All existing labels are unaffected.
//
//  ─── Behavior semantics ─────────────────────────────────────────────────────
//  b1  crossWrite  — read primary tape only.  If the primary read matches,
//                    apply the primary write+move AND write to the secondary
//                    tape (the secondary's read symbol is NOT checked).
//
//  b2  parallelRead — read primary AND secondary tapes simultaneously.
//                    The transition fires only when BOTH read symbols match.
//                    Both writes and both head moves are then applied atomically.
// ─────────────────────────────────────────────────────────────────────────────

/// How the two parts of a compound (multi-tape) transition relate.
enum TmMultiBehavior {
  /// `b1` — primary tape read fires; secondary tape is written unconditionally
  /// (its read symbol is not checked).
  crossWrite,

  /// `b2` — both tape read conditions must match simultaneously before
  /// either write is applied.
  parallelRead,
}

/// Wraps one (or more) [TmTransition] operations that are applied atomically
/// on a single transition arrow.
///
/// When [secondary] is `null` and [transitions] is `null` this is identical
/// to a plain single-tape [TmTransition]; the [behavior] field is irrelevant.
///
/// When [transitions] is non-null (created via [TmCompoundTransition.multi])
/// it holds N≥2 per-tape operations; [primary]/[secondary] are derived from
/// the list for backward-compat access.
class TmCompoundTransition {
  final TmTransition primary;
  final TmTransition? secondary;
  final TmMultiBehavior behavior;

  /// Non-null when this transition was created from the compact multi-tape
  /// shorthand (e.g. `aXRa1Lb2S`).  Holds all N per-tape operations in
  /// tape-index order (index 0 = tape 1, ...).  [primary] and [secondary] are
  /// always consistent with transitions[0] and transitions[1] when present.
  final List<TmTransition>? transitions;

  const TmCompoundTransition({
    required this.primary,
    this.secondary,
    this.behavior = TmMultiBehavior.crossWrite,
    this.transitions,
  });

  /// Build a multi-tape compound transition from N per-tape operations.
  /// [transitions] must have at least 2 entries.
  factory TmCompoundTransition.multi({
    required List<TmTransition> transitions,
    TmMultiBehavior behavior = TmMultiBehavior.crossWrite,
  }) {
    assert(transitions.length >= 2);
    return TmCompoundTransition(
      // primary/secondary are kept in sync with transitions[0]/[1] so code
      // that only knows about the classic 2-tape form (predating the N-tape
      // shorthand) still sees sensible values without needing to branch on
      // which construction path was used.
      primary: transitions[0],
      secondary: transitions[1],
      behavior: behavior,
      transitions: List.unmodifiable(transitions),
    );
  }

  // True whenever there's more than one tape operation to apply, regardless
  // of whether this came from the classic bN-marker path (secondary != null)
  // or the N-tape compact-shorthand path (transitions with >=2 entries).
  bool get isMultiTape => secondary != null || (transitions != null && transitions!.length >= 2);
}

/// Parse a single transition-alternative string (one line of a label) into a
/// [TmCompoundTransition].
///
/// Detects the `primaryOp,bN,secondaryOp` multi-tape format: the `bN` marker
/// (exactly `b1` or `b2`) must appear between two non-empty parts when the
/// label is split by commas.  Every existing single-tape label is unaffected
/// because no normal TM token matches `^b[12]$` in isolation.
///
/// The primary and secondary raw strings are each forwarded to [parseTmLabel],
/// so they can use any format that function already understands (shorthand
/// `1:aXR`, long `1:a,X,R`, tape-prefixed, ~, etc.).
TmCompoundTransition parseTmCompoundLabel(String raw) {
  // Normalize the literal `\0` escape to the real blank glyph (∅) *before*
  // any rune-count-based detection below. Without this, a label typed with
  // `\0` (2 characters) has a different rune count than the visually
  // identical label typed with `∅` (1 character) — which throws off the
  // compact multi-tape triple-count check further down and makes `\0`
  // silently NOT equivalent to `∅`, even though single-tape parseTmLabel
  // already treats the two as the same symbol.
  final normalized = raw.replaceAll('\\0', kBlank);
  final parts = normalized.trim().split(',');

  // Scan for a `b1` / `b2` marker that has at least one part before it and
  // at least one part after it.  We require the primary raw to have at least
  // 3 characters (or contain a colon) to avoid false-positive matches like
  // `a,b1,R` where `b1` would be intended as a write symbol.
  for (int i = 1; i < parts.length - 1; i++) {
    final marker = parts[i].trim();
    if (!RegExp(r'^b[12]$').hasMatch(marker)) continue;

    final primaryRaw   = parts.sublist(0, i).join(',').trim();
    final secondaryRaw = parts.sublist(i + 1).join(',').trim();

    // Sanity-check: both sides must look like real tape operations
    // (≥3 chars or tape-prefixed) so we don't misparse `a,b1,R`.
    bool looksLikeOp(String s) => s.contains(':') || s.length >= 3;
    if (!looksLikeOp(primaryRaw) || !looksLikeOp(secondaryRaw)) continue;

    final behavior = marker == 'b2'
        ? TmMultiBehavior.parallelRead
        : TmMultiBehavior.crossWrite;

    return TmCompoundTransition(
      primary:   parseTmLabel(primaryRaw),
      secondary: parseTmLabel(secondaryRaw),
      behavior:  behavior,
    );
  }

  // No bN marker found.
  // ── Compact multi-tape shorthand ─────────────────────────────────────────
  // A label that is exactly 3*N runes (N ≥ 2) where every third rune is a
  // valid direction character (R/L/S/~) is interpreted as N consecutive
  // per-tape 3-rune triples, one per tape (tape 1, tape 2, …).
  //
  // Examples:
  //   aXRa1L  → tape 1: aXR,  tape 2: a1L
  //   aXRa1Rb2S → tape 1: aXR, tape 2: a1R, tape 3: b2S
  //
  // Semantics: parallelRead — ALL non-wildcard reads must match simultaneously
  // before any write fires. This mirrors _applyBbDirectTransition (used for
  // blackbox outgoing-line labels), so `aXRa1R` checks both tape 1 for `a`
  // AND tape 2 for `a` before writing. Use the explicit `b1` marker syntax
  // when you want crossWrite (secondary read unchecked).
  //
  // Only triggered when the string has no commas and no tape prefix (both of
  // which are handled by the bN path and parseTmLabel above).
  final compactRunes = normalized.trim().runes.toList();
  if (compactRunes.length >= 6 && compactRunes.length % 3 == 0 && !normalized.contains(':')) {
    final tapeCount = compactRunes.length ~/ 3;
    bool allDirsValid = true;
    for (int i = 0; i < tapeCount; i++) {
      final dChar = String.fromCharCode(compactRunes[i * 3 + 2]).toUpperCase();
      if (dChar != 'R' && dChar != 'L' && dChar != 'S' && dChar != '~') {
        allDirsValid = false;
        break;
      }
    }
    if (allDirsValid) {
      // Parse all N triples into a MultiTapeCompoundTransition.
      // Triple i → tape (i+1), parsed via parseTmLabel with tapeIndex injected.
      final transitions = <TmTransition>[];
      for (int i = 0; i < tapeCount; i++) {
        final tripleRaw = String.fromCharCodes(compactRunes.sublist(i * 3, i * 3 + 3));
        final base = parseTmLabel(tripleRaw);
        // parseTmLabel has no way to know which tape a bare 3-rune triple
        // belongs to inside a compact shorthand — it always defaults to
        // tapeIndex 1 — so the correct 1-based index is injected here
        // afterward, based on the triple's position, while carrying over
        // everything else parseTmLabel already correctly determined
        // (read/write/direction/epsilon/wildcard).
        transitions.add(TmTransition(
          read: base.read,
          write: base.write,
          direction: base.direction,
          tapeIndex: i + 1, // 1-based tape index
          isEpsilon: base.isEpsilon,
          isWildcard: base.isWildcard,
        ));
      }
      // Return as a MultiTapeCompoundTransition so all tapes are applied atomically.
      // Use parallelRead so every non-wildcard read is checked before any write
      // fires — matching the semantics of _applyBbDirectTransition and the
      // user-visible expectation that `aXRa1R` checks both tapes.
      // (crossWrite is only correct for the explicit `b1` marker syntax, which
      // documents that the secondary read is intentionally NOT checked.)
      return TmCompoundTransition.multi(
        transitions: transitions,
        behavior: TmMultiBehavior.parallelRead,
      );
    }
  }

  // No bN marker found → plain single-tape transition (fully backward-compatible).
  return TmCompoundTransition(primary: parseTmLabel(normalized));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Black-box line label  (multi-tape direct format)
//
//  Lines **leaving** a black-box node use a compact per-tape notation instead
//  of the inner-DSL approach.  Each newline-separated alternative is a
//  concatenation of exactly N triples (one per tape, left-to-right):
//
//      RWD   where R = read symbol, W = write symbol, D = direction (R/L/S)
//
//  `~` in any position is a wildcard / no-op:
//    • R position: `~` matches any symbol on that tape (don't check).
//    • W position: `~` means "write nothing" — leave the tape cell unchanged.
//    • D position: `~` is treated as Stay (S).
//
//  Examples (2-tape machine):
//    aaRaYS  — tape1: read a, write a, Right; tape2: read a, write Y, Stay
//    bbL~~S  — tape1: read b, write b, Left;  tape2: wildcard, no-write, Stay
//
//  A label is detected as blackbox-direct when:
//    1. It comes from a line whose source node is a black box.
//    2. After stripping whitespace it is exactly 3*N runes (N ≥ 1).
//    3. The last rune of each triple is a valid direction (R/L/S/~).
//
//  If detection fails the alternative is treated as tilda (no-op transition).
// ─────────────────────────────────────────────────────────────────────────────

/// One per-tape operation parsed from a blackbox-direct label.
class BbTapeOp {
  /// The symbol to match on this tape's head cell. Empty string = wildcard
  /// (matches any symbol, including blank).
  final String read;

  /// The symbol to write. Empty string = write blank (∅).
  /// Ignored when [noWrite] is true.
  final String write;

  /// Head movement after the write.
  final TmDirection direction;

  /// Whether the read is a wildcard (~).
  final bool isWildcard;

  /// When true, the write position contained `~` meaning "leave the cell
  /// unchanged" (no-op write). This is distinct from writing blank (∅).
  final bool noWrite;

  const BbTapeOp({
    required this.read,
    required this.write,
    required this.direction,
    required this.isWildcard,
    this.noWrite = false,
  });
}

/// A parsed blackbox-direct transition alternative: one [BbTapeOp] per tape.
class BbDirectTransition {
  /// One entry per tape (index 0 = tape 1, …).
  final List<BbTapeOp> ops;

  const BbDirectTransition(this.ops);

  int get tapeCount => ops.length;
}

/// Try to parse a single blackbox-direct alternative string.
///
/// The tape count is **inferred** from the label: a valid label is exactly
/// 3*N runes where N ≥ 1 and every third rune (direction) is R/L/S/~.
/// For example `aXRa1R` is 6 runes → 2 tapes; `aXRa1RbYS` is 9 runes → 3 tapes.
///
/// The optional [maxTapes] argument can be supplied to cap the inferred tape
/// count when the simulator has fewer tapes than the label implies — it is
/// only used as an upper bound and does **not** cause rejection when the label
/// encodes more tapes (the extra ops are simply ignored at apply-time via the
/// guard in [_applyBbDirectTransition]).
///
/// The optional [activeTapes] argument mirrors [NodeData.blackBoxActiveTapes]:
/// when non-empty, the label's triples are read positionally (triple *i* →
/// `activeTapes[i]`) instead of mapping triple *i* → tape *i+1*. Every tape
/// **not** listed in [activeTapes] is filled in with an implicit
/// wildcard-read / no-write / stay op, exactly as if the label had spelled
/// out `~~S` for that tape. The number of triples in the label must equal
/// `activeTapes.length` exactly — a mismatch is treated as a malformed label
/// (returns `null`), since there's no sensible partial mapping to fall back to.
///
/// Returns `null` when the string does not conform to the 3*N-rune format.
///
/// This is the per-alternative parser.  To split a full line label (which
/// may contain multiple comma- or newline-separated alternatives) use
/// [splitBbDirectAlternatives] first.
BbDirectTransition? parseBbDirectLabel(String raw, [int? maxTapes, List<int>? activeTapes]) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  final runes = s.runes.toList();
  // Must be a multiple of 3.
  if (runes.length % 3 != 0) return null;

  final tripleCount = runes.length ~/ 3;
  if (tripleCount < 1) return null;

  // Validate every direction rune before committing.
  // (Validated in a separate pass before actually building any BbTapeOp
  // objects, so a label that fails validation partway through triple 3
  // doesn't leave a partially-built, inconsistent result to clean up.)
  for (int i = 0; i < tripleCount; i++) {
    final dChar = String.fromCharCode(runes[i * 3 + 2]).toUpperCase();
    if (dChar != 'R' && dChar != 'L' && dChar != 'S' && dChar != '~') {
      return null;
    }
  }

  final parsedOps = <BbTapeOp>[];
  for (int i = 0; i < tripleCount; i++) {
    final rChar = String.fromCharCode(runes[i * 3]);
    final wChar = String.fromCharCode(runes[i * 3 + 1]);
    final dChar = String.fromCharCode(runes[i * 3 + 2]).toUpperCase();

    final isWildcard = rChar == '~';
    final readSym = isWildcard ? '' : _normSym(rChar);

    // `~` in write position = no-write (leave cell unchanged).
    // Any other symbol (including `∅`) = write that symbol (∅ → blank '').
    final noWrite = wChar == '~';
    final writeSym = noWrite ? '' : _normSym(wChar);
    final dir = _parseDir(dChar);

    parsedOps.add(BbTapeOp(
      read: readSym,
      write: writeSym,
      direction: dir,
      isWildcard: isWildcard,
      noWrite: noWrite,
    ));
  }

  // ── No active-tapes mapping: original positional behavior ───────────────
  // Triple i → tape i+1, in order.
  if (activeTapes == null || activeTapes.isEmpty) {
    return BbDirectTransition(parsedOps);
  }

  // ── Active-tapes mapping ─────────────────────────────────────────────────
  // Triple count must match activeTapes exactly; anything else is malformed
  // for this node (either padded with extra triples or missing some).
  if (tripleCount != activeTapes.length) return null;

  final highestActive = activeTapes.fold<int>(0, (m, t) => t > m ? t : m);
  // The result must be sized to cover the highest tape actually referenced —
  // either by activeTapes or by the caller-supplied maxTapes upper bound,
  // whichever is larger, so every tape slot the simulator has gets an
  // explicit op (defaulting to `untouched` below) rather than being left
  // unaddressed.
  final size = (maxTapes != null && maxTapes > highestActive) ? maxTapes : highestActive;

  // Implicit op for every tape *not* listed in activeTapes: wildcard read,
  // no write, stay — equivalent to an explicit `~~S` triple.
  const untouched = BbTapeOp(
    read: '',
    write: '',
    direction: TmDirection.stay,
    isWildcard: true,
    noWrite: true,
  );

  final ops = List<BbTapeOp>.filled(size, untouched);
  for (int i = 0; i < tripleCount; i++) {
    final tapeIndex = activeTapes[i]; // 1-based
    if (tapeIndex < 1 || tapeIndex > size) continue; // out-of-range guard
    ops[tapeIndex - 1] = parsedOps[i];
  }

  return BbDirectTransition(ops);
}

/// Split a blackbox outgoing-line label into individual alternatives.
///
/// Normal (non-blackbox) transition alternatives are separated by `\n`.
/// Blackbox-direct labels additionally allow `,` as a separator because
/// each alternative is a fixed-width `3*N`-rune block and commas never
/// appear inside a valid alternative.  Both separators produce the same
/// NTM branching behaviour — each alternative is tried independently.
///
/// Empty tokens after splitting are discarded.
List<String> splitBbDirectAlternatives(String label) {
  // Replace commas with newlines, then split on newlines.
  return label
      .replaceAll(',', '\n')
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tape-count auto-detection
//
//  A black box's *own* inner DSL program can reference tapes purely for its
//  own internal computation (e.g. a scratch tape) — these have no
//  corresponding "outer" tape and nothing else tells the simulator they're
//  needed. If the machine that's about to run the DSL only allocates as many
//  tapes as the outer context happens to have (or just 1, when the outer
//  context has no tape concept at all, e.g. an NFA), any transition inside
//  the black box that targets a higher tape index is silently skipped —
//  the box behaves as if it only ever has tape 1, no matter what its own
//  lines say.
//
//  [detectRequiredTapeCount] scans every line label in [lines] — plus, since
//  black boxes can be nested, the lines of every black-box DSL reachable from
//  [nodes] — and returns the highest tape index referenced anywhere (minimum
//  1). Callers should size a [TmSimulator] to at least this many tapes before
//  running it against this set of nodes/lines.
// ─────────────────────────────────────────────────────────────────────────────

int detectRequiredTapeCount(Map<String, NodeData> nodes, Map<String, LineData> lines) {
  int maxTape = 1;

  // Scans one line label for tape-index references and bumps maxTape as
  // needed; shared between the plain-line loop and (indirectly, via
  // recursion) nested black-box DSLs below.
  void scanLabel(String label) {
    if (label.trim().isEmpty) return;

    for (final raw in label.split('\n')) {
      final s = raw.trim();
      if (s.isEmpty) continue;

      // N: tape-prefix format — also covers bN compound labels like
      // "1:aXR,b2,2:01S", since the regex just finds every "<digits>:".
      final prefixes = RegExp(r'(\d+):').allMatches(s);
      for (final m in prefixes) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > maxTape) maxTape = n;
      }

      // Compact 3*N shorthand with no prefixes/commas, e.g. aXRa1L = 2 tapes.
      // This covers both the plain-TM compact shorthand and blackbox-direct
      // outgoing-line labels, which use the same per-tape triple format.
      if (!s.contains(':') && !s.contains(',')) {
        final runes = s.runes.toList();
        if (runes.length >= 3 && runes.length % 3 == 0) {
          bool allDirsValid = true;
          final inferredTapes = runes.length ~/ 3;
          for (int i = 0; i < inferredTapes; i++) {
            final d = String.fromCharCode(runes[i * 3 + 2]).toUpperCase();
            if (d != 'R' && d != 'L' && d != 'S' && d != '~') {
              allDirsValid = false;
              break;
            }
          }
          if (allDirsValid && inferredTapes > maxTape) maxTape = inferredTapes;
        }
      }
    }
  }

  for (final line in lines.values) {
    // A black box with blackBoxActiveTapes set addresses tapes by that list
    // rather than by triple position, so the label's own triple count tells
    // us nothing about which tape indices are involved — only the active-
    // tapes list does. Use it directly instead of running the generic scan.
    final sourceNode = nodes[line.nodeAId];
    if (sourceNode != null && sourceNode.isBlackBox && sourceNode.blackBoxActiveTapes.isNotEmpty) {
      final highestActive =
          sourceNode.blackBoxActiveTapes.fold<int>(0, (m, t) => t > m ? t : m);
      if (highestActive > maxTape) maxTape = highestActive;
      continue;
    }
    scanLabel(line.label);
  }

  // Recurse into nested black-box DSLs — their tape references count too,
  // since the inner machine they describe runs with its own tape count.
  for (final node in nodes.values) {
    if (!node.isBlackBox || node.blackBoxDsl.trim().isEmpty) continue;
    try {
      final inner = DslCodec.importFromDsl(node.blackBoxDsl);
      final nestedMax = detectRequiredTapeCount(inner.nodes, inner.lines);
      if (nestedMax > maxTape) maxTape = nestedMax;
    } catch (_) {
      // Malformed inner DSL — ignore here; actually running it will surface
      // the problem as a rejection instead.
    }
  }

  return maxTape;
}

// ─────────────────────────────────────────────────────────────────────────────
//  TM tape (immutable snapshot)
// ─────────────────────────────────────────────────────────────────────────────

// Every mutation (write, extendToInclude) returns a NEW TmTape rather than
// mutating in place — this immutability is what lets TmConfig/TmSimulator
// keep a full branching history of snapshots (steps[]) without different
// branches accidentally sharing and corrupting each other's tape state.
class TmTape {
  final List<String> cells;
  final int headOffset; // absolute index of logical input position 0

  const TmTape({
    required this.cells,
    required this.headOffset,
  });

  /// Builds the initial tape from input tokens.
  ///
  /// Layout:  [∅, tok0, tok1, …, tokN, ∅]
  ///
  /// headOffset = 1  (input position 0 is at absolute index 1)
  /// Head starts at absolutePos(0) = 1.
  factory TmTape.fromTokens(List<String> tokens) {
    // One blank sentinel cell on each side of the input — guarantees there's
    // always at least one blank cell immediately adjacent to the input
    // region, so the very first extendToInclude/write call (if the head
    // moves left of index 1 or right past the input) has somewhere sensible
    // to land without needing a special first-extension case.
    final cells = <String>[kBlank, ...tokens, kBlank];
    // headOffset=1: absolute index of the first input symbol.
    return TmTape(
      cells: cells,
      headOffset: 1,
    );
  }

  /// Builds an empty tape (used for tapes 2..N, which start with nothing
  /// written on them).
  ///
  /// Layout: [∅] — a single blank cell. headOffset = 0, so absolutePos(0) = 0
  /// and the head starts sitting on that blank cell.
  factory TmTape.empty() {
    return const TmTape(cells: [kBlank], headOffset: 0);
  }

  /// Read the symbol at absolute tape position [pos].
  String read(int pos) {
    // Positions outside the currently-allocated cell range are, by the "tape
    // is conceptually unbounded" model, implicitly blank — no need to have
    // physically extended the list yet just to read from it.
    if (pos < 0 || pos >= cells.length) return kBlank;
    final v = cells[pos];
    return v.isEmpty ? kBlank : v;
  }

  /// Ensure the tape has a cell at absolute position [pos].
  ///
  /// The TM tape is conceptually unbounded and filled with blanks outside the
  /// allocated range. If the head moves beyond either end, we extend the tape
  /// with blanks so the branch can continue computing.
  ///
  /// Returns the new tape and an index shift (non-zero only when extending left).
  ({TmTape tape, int shift}) extendToInclude(int pos) {
    if (pos >= 0 && pos < cells.length) {
      // Already within the allocated range — nothing to extend, and
      // shift=0 tells the caller no index translation is needed.
      return (tape: this, shift: 0);
    }

    final newCells = List<String>.from(cells);
    int newOffset = headOffset;
    int shift = 0;

    if (pos < 0) {
      // Extending left is the tricky case: inserting blanks at the FRONT of
      // the list shifts every existing absolute index to the right by
      // `extension` — hence bumping headOffset by the same amount and
      // returning that amount as `shift`, so callers can translate any
      // absolute position they were tracking (e.g. a head position computed
      // before this extension) into the new indexing scheme.
      final extension = -pos;
      newCells.insertAll(0, List<String>.filled(extension, kBlank));
      newOffset += extension;
      shift = extension;
    } else {
      // Extending right is simpler: appending to the end doesn't disturb
      // any existing index, so headOffset (and therefore shift) stays put.
      while (pos >= newCells.length) {
        newCells.add(kBlank);
      }
    }

    return (tape: TmTape(cells: newCells, headOffset: newOffset), shift: shift);
  }

  /// Returns a new tape with [symbol] written at [pos], extending if needed.
  /// Writing at a position left of index 0 shifts all indices; the sentinels
  /// shift along with the tape.
  TmTape write(int pos, String symbol) {
    final newCells    = List<String>.from(cells);
    int newOffset     = headOffset;

    if (pos < 0) {
      // Same left-extension logic as extendToInclude above, but folded
      // directly into the write since we need to both make room for
      // `pos` AND set the symbol at the new (shifted) index 0 in one pass.
      final extension = -pos;
      final blanks = List<String>.filled(extension, kBlank);
      newCells.insertAll(0, blanks);
      newOffset    += extension;
      newCells[0] = symbol.isEmpty ? kBlank : symbol;
      return TmTape(
        cells: newCells,
        headOffset: newOffset,
      );
    }

    while (pos >= newCells.length) {
      newCells.add(kBlank);
    }
    newCells[pos] = symbol.isEmpty ? kBlank : symbol;
    return TmTape(
      cells: newCells,
      headOffset: newOffset,
    );
  }

  /// Convert a logical input index (0 = first input char) to absolute index.
  int absolutePos(int inputIndex) => headOffset + inputIndex;

  /// A key that uniquely describes the tape content (for loop detection).
  // Used as part of TmConfig.key below — two tapes with identical `cells`
  // (in the same order) produce the same key regardless of headOffset,
  // which is intentional: headOffset is bookkeeping for translating logical
  // <-> absolute positions, not part of the tape's actual content.
  String get key => cells.join('|');
}


// ─────────────────────────────────────────────────────────────────────────────
//  NTM Configuration  (state × head position × tape)
// ─────────────────────────────────────────────────────────────────────────────

// One reachable (state, tapes, head positions) configuration during TM
// simulation. Unlike PdaConfig, this doesn't override == /hashCode — TM
// configs are deduped via the string `key` getter compared through
// `seenKeys` Sets in TmSimulator.computeNext below, rather than via
// Set<TmConfig> structural equality.
class TmConfig {
  final String nodeId;

  /// One tape per configured tape slot (tapes[0] = tape 1, tapes[1] = tape 2, …).
  final List<TmTape> tapes;

  /// Absolute index into tapes[i].cells — where the head on tape i+1 IS now
  /// (post-move). Same length/order as [tapes].
  final List<int> headPositions;

  /// Absolute index that was READ on tape i+1 to fire the transition
  /// (pre-move, for display). Same length/order as [tapes].
  final List<int> readHeadPositions;

  final String usedLineId;

  const TmConfig({
    required this.nodeId,
    required this.tapes,
    required this.headPositions,
    required this.readHeadPositions,
    required this.usedLineId,
  });

  /// Convenience accessors for tape 1 — used throughout the UI and by the
  /// single-tape black-box machinery. tapes[0] is always tape 1.
  TmTape get tape => tapes[0];
  int get headPos => headPositions[0];
  int get readHeadPos => readHeadPositions[0];

  /// Key used for loop / duplicate detection — includes every tape's
  /// content and head position so configs that differ only on tape 2+ are
  /// treated as distinct.
  String get key {
    final parts = <String>[nodeId];
    for (int i = 0; i < tapes.length; i++) {
      parts.add('${headPositions[i]}:${tapes[i].key}');
    }
    return parts.join('|');
  }

  /// Returns a copy of this config with tape [tapeIndex] (1-based) replaced
  /// by [newTape], and its head/read-head positions updated. All other tapes
  /// are carried over unchanged.
  TmConfig withTape(
    int tapeIndex,
    TmTape newTape, {
    required int headPos,
    required int readHeadPos,
    String? usedLineId,
    String? nodeId,
  }) {
    final i = tapeIndex - 1;
    // Copy every list rather than mutating in place, preserving the same
    // "every config is an independent immutable snapshot" contract as TmTape
    // above.
    final newTapes = List<TmTape>.from(tapes);
    final newHeads = List<int>.from(headPositions);
    final newReadHeads = List<int>.from(readHeadPositions);
    newTapes[i] = newTape;
    newHeads[i] = headPos;
    newReadHeads[i] = readHeadPos;
    return TmConfig(
      nodeId: nodeId ?? this.nodeId,
      tapes: newTapes,
      headPositions: newHeads,
      readHeadPositions: newReadHeads,
      usedLineId: usedLineId ?? this.usedLineId,
    );
  }

  /// Returns a copy of this config with a new [nodeId] / [usedLineId] but the
  /// same tapes and head positions (used for tilda transitions and
  /// black-box hops, which don't move any head).
  TmConfig retarget({required String nodeId, required String usedLineId}) {
    return TmConfig(
      nodeId: nodeId,
      // tapes itself is reused unchanged (not copied) since tilda/hop moves
      // never touch tape content — only headPositions is duplicated below
      // to seed readHeadPositions from the current (unmoved) head, since a
      // tilda move has nothing new to report as "what was read".
      tapes: tapes,
      headPositions: List<int>.from(headPositions),
      readHeadPositions: List<int>.from(headPositions),
      usedLineId: usedLineId,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  One UI-visible step snapshot (set of active configs)
// ─────────────────────────────────────────────────────────────────────────────

class TmStepSnapshot {
  final List<TmConfig> configs;
  final Set<String> usedLineIds;

  const TmStepSnapshot({required this.configs, required this.usedLineIds});

  Set<String> get activeNodeIds => {for (final c in configs) c.nodeId};
}

// ─────────────────────────────────────────────────────────────────────────────
//  TM simulation result
// ─────────────────────────────────────────────────────────────────────────────

// Unlike SimResult/PdaSimResult (which are only ever computed AFTER the
// whole run finishes, since those simulators precompute eagerly), TmResult
// has a third `running` value — TmSimulator advances one step at a time on
// demand (see computeNext() below), so at any given moment the machine may
// genuinely still be mid-computation with no verdict yet.
enum TmResult { accept, reject, running }

// ─────────────────────────────────────────────────────────────────────────────
//  NTM Simulator
// ─────────────────────────────────────────────────────────────────────────────

/// Simulates a Turing machine across one or more tapes and records each
/// branching step so the app can replay the computation in the canvas UI.
// Unlike AutomataSimulator/PdaSimulator (which eagerly precompute the WHOLE
// run in one pass — see their class comments), TmSimulator computes lazily,
// one global expansion step at a time, via computeNext(). This is necessary
// because a TM computation is not guaranteed to terminate at all (unlike a
// bounded-input NFA/PDA run) — callers (the UI's play/step controls, or a
// black box running an inner TM to completion) decide how far to advance.
class TmSimulator {
  TmSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  // ── Precomputed simulation ──────────────────────────────────────────────
  List<String> tokens = [];

  /// steps[0] = initial config set; steps[i+1] = after one NTM step from steps[i].
  final List<TmStepSnapshot> steps = [];

  /// The user-visible step cursor. -1 = before first snapshot.
  int step = -1;

  /// Set to true when the current live configuration set has **no enabled
  /// transitions** (all branches would die on the next computation).
  ///
  /// We treat this as a terminal condition (machine halts), and acceptance is
  /// determined from the current live configs:
  /// - accept if any config is in a normal accept state
  /// - reject otherwise
  bool noMovesTerminal = false;

  /// Maximum valid value for [step] given the current [steps] list.
  ///
  /// Contract (matches [_snapshotAt]):
  /// - step == -1 → steps[0]
  /// - step ==  0 → steps[1]
  /// - step == maxStep → steps.last
  int get maxStep => steps.isEmpty ? -1 : steps.length - 2;

  /// Number of tapes this TM uses.
  ///
  /// Each configuration carries one [TmTape] per slot (tapes[0] = tape 1,
  /// tapes[1] = tape 2, …). Tape 1 always starts pre-loaded with the input;
  /// tapes 2..N start empty. Transitions address a tape via an optional
  /// `N:` prefix on their label (see [parseTmLabel]); transitions without a
  /// prefix act on tape 1, so existing single-tape graphs are unaffected.
  ///
  /// Defaults to 1. Call [rebuildGraph] (or [rebuild]) after changing this so
  /// the initial configuration is reconstructed with the new tape count.
  int tapeCount = 1;
  /// Cache of black-box execution results keyed by node-id + all tape contents
  /// + all head positions.  Avoids re-running the inner DSL machine when the
  /// outer TM revisits the same black-box node with identical tape state.
  final Map<String, ({
    bool accepted,
    List<List<String>> outputTapes,
    List<int> outputHeadPositions,
  })> _blackBoxResultCache = {};

  // ── Active highlights ──────────────────────────────────────────────────

  Set<String> get activeNodes {
    final snap = _snapshotAt(step);
    return snap?.activeNodeIds ?? {};
  }

  Set<String> get activeLines {
    // idx mirrors activeNodes: step=-1 -> idx=0, the initial tilda
    // closure computed before any input is consumed. Free ~ jumps taken in
    // that closure belong here just as their destination nodes belong in
    // snap.activeNodeIds — don't special-case step < 0 to empty.
    final snap = _snapshotAt(step);
    return snap?.usedLineIds ?? {};
  }

  TmStepSnapshot? _snapshotAt(int s) {
    final idx = s + 1;
    if (idx < 0 || idx >= steps.length) return null;
    return steps[idx];
  }

  /// Current snapshot for UI display.
  TmStepSnapshot? get currentSnapshot => _snapshotAt(step);

  /// All active configs at the current step (for the config panel).
  List<TmConfig> get activeConfigs => currentSnapshot?.configs ?? const [];

  // ── Tape view helpers (uses first config for the tape strip display) ───

  TmConfig? get _primaryConfig {
    final snap = currentSnapshot;
    if (snap == null || snap.configs.isEmpty) return null;
    // Prefer a halting-accept config if one exists.
    for (final c in snap.configs) {
      final node = nodes[c.nodeId];
      if (node != null && node.isHaltAccept) return c;
    }
    return snap.configs.first;
  }

  TmTape? get currentTape => _primaryConfig?.tape;
  int get currentHeadPos => _primaryConfig?.headPos ?? 0;

  ({List<String> cells, int headIndex, int originOffset})? get tapeView =>
      tapeViewForTape(1);

  /// Returns the tape-strip view for tape [tapeIndex] (1-based), or `null`
  /// when there is no current snapshot.  This is the multi-tape-aware
  /// replacement for the old [tapeView] getter, which was hardcoded to tape 1.
  ({List<String> cells, int headIndex, int originOffset})? tapeViewForTape(
      int tapeIndex) {
    final config = _primaryConfig;
    if (config == null) return null;
    // Clamp rather than index directly: a caller could ask for a tape index
    // the current config doesn't actually have (e.g. UI still showing a
    // tape-2 panel right after tapeCount was reduced back to 1) — falling
    // back to the last real tape avoids an out-of-range crash.
    final i = (tapeIndex - 1).clamp(0, config.tapes.length - 1);
    final tape = config.tapes[i];
    // Padding cells shown beyond the tape's currently-allocated content on
    // both ends, purely so the visual tape strip always has a bit of
    // breathing room around the interesting region rather than stopping
    // exactly at the edge of allocated cells.
    const pad = 3;
    final cells = <String>[];
    final startPos = -pad;
    final endPos = tape.cells.length - tape.headOffset + pad;
    for (int rel = startPos; rel < endPos; rel++) {
      final abs = tape.absolutePos(rel);
      cells.add((abs >= 0 && abs < tape.cells.length) ? tape.cells[abs] : kBlank);
    }
    // Highlight the current head position (post-move) so the tape strip shows
    // WHERE THE HEAD IS NOW, not where it last read from.  The config panel
    // uses readHeadPositions separately for its "last read" annotation.
    final displayHeadPos = config.headPositions[i];
    return (
      cells: cells,
      headIndex: displayHeadPos - tape.absolutePos(startPos),
      originOffset: startPos,
    );
  }

  // ── Simulation result ──────────────────────────────────────────────────

  TmResult get result {
    if (steps.isEmpty) return TmResult.running;
    // Check final snapshot only.
    final last = steps.last;
    // If we're not halted/stuck yet, the machine is still running even if it
    // is currently sitting in an accept state.
    if (!isHaltedOrStuck) return TmResult.running;

    // Terminal because no moves remain: accept iff any live config is accept.
    if (noMovesTerminal) {
      for (final c in last.configs) {
        final node = nodes[c.nodeId];
        if (node == null) continue;
        if (node.isHaltReject) continue;
        if (node.isAccept) return TmResult.accept;
      }
      return TmResult.reject;
    }

    if (last.configs.isEmpty) return TmResult.reject;
    for (final c in last.configs) {
      final node = nodes[c.nodeId];
      if (node == null) continue;
      // Explicit halt-accept always wins.
      if (node.isHaltAccept) return TmResult.accept;
    }
    return TmResult.reject;
  }

  // Same shape as `result` above but scoped to whatever snapshot the `step`
  // cursor currently points at, rather than the final/last snapshot — used
  // by the UI to show a per-step verdict as the user scrubs through the
  // recorded history rather than only the end-of-run verdict.
  TmResult get currentStepResult {
    final snap = currentSnapshot;
    if (snap == null) return TmResult.running;
    for (final c in snap.configs) {
      final node = nodes[c.nodeId];
      if (node == null) continue;
      if (node.isHaltAccept) return TmResult.accept;
      if (node.isHaltReject) return TmResult.reject;
    }
    return TmResult.running;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  void rebuild(
    String input, {
    StartArrowData? startArrow,
    /// Initial content for tapes 2, 3, … (index 0 = tape 2, index 1 = tape 3, …).
    /// Each string is tokenised exactly like the tape-1 input.
    /// Tapes not covered by this list start empty (backward-compatible default).
    List<String> additionalTapeInputs = const [],
  }) {
    // nullEscapeToken: kBlank (not the FA/PDA default '?') — a TM's tape has
    // a genuine blank symbol, so `\0` in the input should become that blank,
    // not the FA/PDA "null jump" marker (see the shared-tokenizer section
    // comment near the top of this file for the full rationale).
    tokens = _tokenize(input, nullEscapeToken: kBlank);
    _build(startArrow: startArrow, additionalTapeInputs: additionalTapeInputs);
    // step uses a -1 offset (see _snapshotAt): valid range is -1..maxStep.
    // Clamping against steps.length directly is off-by-one and can leave
    // step pointing past the end of the rebuilt snapshot list, which makes
    // currentSnapshot/activeNodes/activeLines return null/empty — i.e. the
    // TM head/tape highlighting silently disappears after any edit.
    if (step > maxStep) step = maxStep;
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step > maxStep) step = maxStep;
  }

  // Builds ONLY the initial (step 0) snapshot — unlike AutomataSimulator/
  // PdaSimulator's _build, which precompute every round, this simulator's
  // "build" step is deliberately shallow; computeNext() (further below) is
  // what actually advances the computation one step at a time afterward.
  void _build({
    StartArrowData? startArrow,
    List<String> additionalTapeInputs = const [],
  }) {
    steps.clear();
    noMovesTerminal = false;
    _blackBoxResultCache.clear(); // ← invalidate stale DSL results on every rebuild

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      // No valid start — leave `steps` empty. Unlike AutomataSimulator/
      // PdaSimulator, no placeholder empty snapshot is added here; every
      // getter in this class already treats an out-of-range/empty `steps`
      // as "nothing to show" via _snapshotAt's null return.
      return;
    }

    final initialTape = TmTape.fromTokens(tokens);
    final initialTapes = <TmTape>[initialTape];
    final initialHeads = <int>[initialTape.absolutePos(0)];
    // Guard against a caller having set tapeCount to something nonsensical
    // (0 or negative) — always allocate at least tape 1.
    final effectiveTapeCount = tapeCount < 1 ? 1 : tapeCount;
    for (int i = 1; i < effectiveTapeCount; i++) {
      // Use the caller-supplied initial content for tapes 2..N when available.
      // Index 0 in additionalTapeInputs corresponds to tape 2 (i == 1), etc.
      final extraIdx = i - 1;
      final TmTape tape;
      if (extraIdx < additionalTapeInputs.length &&
          additionalTapeInputs[extraIdx].isNotEmpty) {
        final extraTokens = _tokenize(additionalTapeInputs[extraIdx], nullEscapeToken: kBlank);
        tape = TmTape.fromTokens(extraTokens);
      } else {
        tape = TmTape.empty();
      }
      initialTapes.add(tape);
      initialHeads.add(tape.absolutePos(0));
    }
    final initialConfig = TmConfig(
      nodeId: startArrow.nodeId,
      tapes: initialTapes,
      headPositions: initialHeads,
      // readHeadPositions starts identical to headPositions — nothing has
      // been "read to get here" yet, so the initial read position is
      // wherever the head starts.
      readHeadPositions: List<int>.from(initialHeads),
      usedLineId: '',
    );

    // Step 0: initial snapshot.
    steps.add(TmStepSnapshot(
      configs: [initialConfig],
      usedLineIds: const {},
    ));
  }

  /// True if the *current* snapshot cannot advance.
  bool get isHaltedOrStuck {
    final current = steps.isEmpty ? null : steps.last;
    if (current == null) return true;
    if (current.configs.isEmpty) return true;
    if (noMovesTerminal) return true;

    // Stop once any explicit halt-accept exists.
    for (final c in current.configs) {
      final node = nodes[c.nodeId];
      if (node != null && node.isHaltAccept) return true;
    }

    // Stop once every live branch is halted (halt-accept / halt-reject).
    for (final c in current.configs) {
      final node = nodes[c.nodeId];
      if (node == null) continue;
      if (!node.isHaltAccept && !node.isHaltReject) return false;
    }
    // If not all halted, we may still be stuck (no enabled moves).
    return !canAdvance;
  }

  /// Executes the inner DSL machine stored in [node.blackBoxDsl] against the
  /// outer TM's current tape configuration, and returns an updated [TmConfig]
  /// with all tapes rewritten to reflect the inner machine's output.
  ///
  /// The inner machine is a full TM (NFA/PDA/TM depending on the DSL header).
  /// It receives the **full content** of every outer tape as its input tapes:
  ///   • tape 1 of the inner machine ← outer tape 1
  ///   • tape 2 of the inner machine ← outer tape 2 (if configured)
  ///   • … and so on up to the inner machine's tape count
  ///
  /// After the inner machine halts-accept, each output tape is spliced back
  /// into the corresponding outer tape slot.  Tapes that the inner machine
  /// does not touch (because it has fewer tapes than the outer TM) are carried
  /// over from the original outer config unchanged.
  ///
  /// Returns `null` when:
  ///   • The node is not a black-box (caller should never reach this path).
  ///   • The inner machine rejects — the outer NTM branch dies.
  ///   • The DSL is empty or malformed.
  ///
  /// For non-black-box nodes this method is never called; the caller guards
  /// with [node.isBlackBox] before invoking.
  TmConfig? _applyBlackBox(NodeData node, TmConfig config) {
    // Defensive identity passthrough: every actual call site already checks
    // node.isBlackBox first (see canAdvance/computeNext above), so this
    // branch is a belt-and-suspenders guard rather than something normally
    // exercised.
    if (!node.isBlackBox) return config;

    final dsl = node.blackBoxDsl.trim();
    if (dsl.isEmpty) return null; // no DSL → branch dies

    // Build a cache key that covers all tape contents + all head positions so
    // re-entering the same black-box with identical state reuses the result.
    final cacheKey = _buildBlackBoxCacheKey(node, config);
    final cached = _blackBoxResultCache[cacheKey];
    if (cached != null) {
      if (!cached.accepted) return null;
      return _rebuildConfigFromBlackBoxResult(cached, config);
    }

    try {
      final graph = DslCodec.importFromDsl(dsl);
      final result = _executeBlackBoxDsl(graph, config);
      _blackBoxResultCache[cacheKey] = result;
      if (!result.accepted) return null;
      return _rebuildConfigFromBlackBoxResult(result, config);
    } catch (_) {
      // Malformed inner DSL, or any other unexpected failure while running
      // it — cache the rejection too (same as a genuine inner-reject) so a
      // broken black box doesn't get re-parsed and re-attempted on every
      // subsequent visit within the same rebuild().
      _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTapes: const [],
        outputHeadPositions: const [],
      );
      return null;
    }
  }

  // ── Cache key that covers all tapes + all head positions ────────────────

  // Mirrors TmConfig.key's shape (nodeId + per-tape "headPos:tapeContentKey"
  // pairs) but is deliberately a separate method rather than reusing
  // config.key directly — this key is scoped to caching _executeBlackBoxDsl
  // results for one specific `node`, so the node id is prefixed to keep
  // results for different black-box nodes from ever colliding even if two
  // black boxes happened to see identical tape states.
  String _buildBlackBoxCacheKey(NodeData node, TmConfig config) {
    final parts = <String>[node.id];
    for (int i = 0; i < config.tapes.length; i++) {
      parts.add('${config.headPositions[i]}:${config.tapes[i].key}');
    }
    return parts.join('|');
  }

  // ── Run the inner DSL machine against the full outer config ─────────────

  // Runs one black box's inner DSL program (whichever automaton kind it
  // describes) against the outer TM's current tapes, and reports back
  // per-tape trimmed output tokens plus each tape's resulting head position
  // — the raw ingredients _rebuildConfigFromBlackBoxResult needs to splice
  // the result back into the outer TmConfig.
  ({
    bool accepted,
    List<List<String>> outputTapes,
    List<int> outputHeadPositions,
  }) _executeBlackBoxDsl(GraphState graph, TmConfig outerConfig) {
    // Build per-tape trimmed token lists and relative head positions from the
    // outer config to hand to the inner machine.
    final outerTapeCount = outerConfig.tapes.length;

    // Helper: trim a TmTape to its non-blank content and translate the
    // absolute head position to a 0-based index in that trimmed list.
    ({List<String> tokens, int headRel}) tapeToInput(int tapeIdx) {
      final tape = outerConfig.tapes[tapeIdx];
      final absHead = outerConfig.headPositions[tapeIdx];
      final tokens = _trimTapeTokens(tape);
      // Locate where the non-blank region starts in the raw cells so we can
      // translate the absolute head position to a relative one.
      final cells = tape.cells;
      int trimStart = 0;
      while (trimStart < cells.length &&
          (cells[trimStart].isEmpty || cells[trimStart] == kBlank)) {
        trimStart++;
      }
      final headRel = (absHead - trimStart).clamp(0, tokens.isEmpty ? 0 : tokens.length);
      return (tokens: tokens, headRel: headRel);
    }

    switch (graph.automataMode) {
      // ── NFA: single-tape, no rewrite ──────────────────────────────────────
      case AutomataMode.ndfa:
      case AutomataMode.regex: {
        final t0 = tapeToInput(0);
        final sim = AutomataSimulator(nodes: graph.nodes, lines: graph.lines);
        sim.rebuild(t0.tokens.join(), startArrow: graph.startArrow);
        if (sim.finalResult() != SimResult.accept) {
          return (accepted: false, outputTapes: const [], outputHeadPositions: const []);
        }
        // NFA: head advances past the entire consumed tape 1; other tapes unchanged.
        final outTapes = <List<String>>[];
        final outHeads = <int>[];
        for (int i = 0; i < outerTapeCount; i++) {
          final t = tapeToInput(i);
          outTapes.add(t.tokens);
          // Tape 1's head jumps to the end (the whole input was consumed by
          // the inner NFA); every other tape is untouched, so its head
          // stays exactly where it started (t.headRel).
          outHeads.add(i == 0 ? t.tokens.length : t.headRel);
        }
        return (accepted: true, outputTapes: outTapes, outputHeadPositions: outHeads);
      }

      // ── PDA: single-tape, no rewrite ──────────────────────────────────────
      case AutomataMode.pda: {
        final t0 = tapeToInput(0);
        final sim = PdaSimulator(nodes: graph.nodes, lines: graph.lines);
        sim.rebuild(t0.tokens.join(), startArrow: graph.startArrow);
        if (sim.finalResult() != PdaSimResult.accept) {
          return (accepted: false, outputTapes: const [], outputHeadPositions: const []);
        }
        // Same "tape 1 fully consumed, everything else untouched" rule as
        // the NFA case above.
        final outTapes = <List<String>>[];
        final outHeads = <int>[];
        for (int i = 0; i < outerTapeCount; i++) {
          final t = tapeToInput(i);
          outTapes.add(t.tokens);
          outHeads.add(i == 0 ? t.tokens.length : t.headRel);
        }
        return (accepted: true, outputTapes: outTapes, outputHeadPositions: outHeads);
      }

      // ── Inner TM: multi-tape aware ────────────────────────────────────────
      case AutomataMode.tm: {
        // Determine how many tapes the inner machine needs. It needs at
        // least as many tapes as the outer machine has (so `N:` tape
        // prefixes in the inner DSL labels can address outer tapes 2+), but
        // it may also reference *extra* tapes purely for its own internal
        // scratch use — those have no corresponding outer tape, so the outer
        // tape count alone isn't always enough. Scan the inner DSL's own
        // lines (and anything it nests) to make sure we never under-allocate
        // and silently drop transitions that target those scratch tapes.
        final requiredInnerTapes = detectRequiredTapeCount(graph.nodes, graph.lines);
        final innerTapeCount =
            requiredInnerTapes > outerTapeCount ? requiredInnerTapes : outerTapeCount;

        final sim = TmSimulator(nodes: graph.nodes, lines: graph.lines);
        sim.tapeCount = innerTapeCount;

        // Load tape 1 of the inner machine with the outer tape 1 content.
        // After rebuild(), the inner simulator builds the initial config with
        // tapeCount tapes, all starting empty except tape 1 (= the input).
        final t0 = tapeToInput(0);
        sim.rebuild(t0.tokens.join(), startArrow: graph.startArrow);

        // Overwrite the initial config's extra tapes with the outer tapes 2..N.
        // Only tapes that actually exist on the outer side can be seeded this
        // way — any inner tapes beyond outerTapeCount are pure scratch space
        // for the black box's own program and simply start blank (the
        // default for a freshly rebuilt tape slot).
        // rebuild() always produces exactly one config in steps[0].
        if (sim.steps.isNotEmpty && sim.steps[0].configs.isNotEmpty && innerTapeCount > 1) {
          final initConfig = sim.steps[0].configs[0];
          TmConfig updated = initConfig;
          for (int i = 1; i < innerTapeCount; i++) {
            if (i >= outerTapeCount) break; // no corresponding outer tape — leave blank
            final outerTk = tapeToInput(i);
            final innerTape = TmTape.fromTokens(outerTk.tokens);
            // Position the inner head at the same relative position as the
            // outer head so the inner machine starts scanning the right cell.
            final innerHead = innerTape.absolutePos(outerTk.headRel.clamp(0, outerTk.tokens.length));
            updated = updated.withTape(
              i + 1,
              innerTape,
              headPos: innerHead,
              readHeadPos: innerHead,
            );
          }
          // Directly mutate steps[0] in place (rather than going through
          // rebuild() again) since we only need to patch the already-built
          // initial snapshot's single config with the seeded extra tapes.
          sim.steps[0] = TmStepSnapshot(
            configs: [updated],
            usedLineIds: sim.steps[0].usedLineIds,
          );
        }

        // Run to completion — a black box is opaque to the outer machine, so
        // only the final verdict and tapes matter, not the inner machine's
        // own step-by-step history.
        while (sim.computeNext()) {}

        if (sim.result != TmResult.accept) {
          return (accepted: false, outputTapes: const [], outputHeadPositions: const []);
        }

        // Find the halt-accept config.
        TmConfig? haltConfig;
        if (sim.steps.isNotEmpty) {
          for (final c in sim.steps.last.configs) {
            if (sim.nodes[c.nodeId]?.isHaltAccept == true) {
              haltConfig = c;
              break;
            }
          }
          // Defensive fallback: sim.result already confirmed acceptance, so
          // a halt-accept config should always be found above — but if
          // somehow none was (e.g. acceptance came from a plain, non-halt
          // accept state instead), fall back to whatever config is present.
          haltConfig ??= sim.steps.last.configs.firstOrNull;
        }
        if (haltConfig == null) {
          return (accepted: false, outputTapes: const [], outputHeadPositions: const []);
        }

        // Extract trimmed output tokens and translated head positions for
        // every tape the inner machine operated on.
        final outTapes = <List<String>>[];
        final outHeads = <int>[];
        for (int i = 0; i < innerTapeCount; i++) {
          if (i >= haltConfig.tapes.length) {
            // Inner machine had fewer tapes — carry outer tape unchanged
            // (or blank, for a scratch tape index that has no outer
            // counterpart).
            if (i >= outerTapeCount) {
              outTapes.add(const <String>[]);
              outHeads.add(0);
              continue;
            }
            final ot = tapeToInput(i);
            outTapes.add(ot.tokens);
            outHeads.add(ot.headRel);
          } else {
            final innerTape = haltConfig.tapes[i];
            final innerHead = haltConfig.headPositions[i];
            final tokens = _trimTapeTokens(innerTape);
            // Translate absolute inner head to relative position in trimmed tokens.
            final cells = innerTape.cells;
            int trimStart = 0;
            while (trimStart < cells.length &&
                (cells[trimStart].isEmpty || cells[trimStart] == kBlank)) {
              trimStart++;
            }
            final headRel = (innerHead - trimStart).clamp(0, tokens.length);
            outTapes.add(tokens);
            outHeads.add(headRel);
          }
        }
        return (accepted: true, outputTapes: outTapes, outputHeadPositions: outHeads);
      }
    }
  }

  // ── Rebuild the outer TmConfig from inner-machine output ────────────────

  // Splices the black box's per-tape output (from _executeBlackBoxDsl) back
  // into a fresh TmConfig, preserving everything about `originalConfig`
  // (node id, usedLineId, any tapes the inner machine didn't touch) except
  // the tapes that were actually rewritten.
  TmConfig _rebuildConfigFromBlackBoxResult(
    ({
      bool accepted,
      List<List<String>> outputTapes,
      List<int> outputHeadPositions,
    }) result,
    TmConfig originalConfig,
  ) {
    // Start from the original config (preserves node id, usedLineId, etc.)
    // and overwrite each tape slot with the inner machine's output.
    TmConfig updated = originalConfig;
    final outerCount = originalConfig.tapes.length;
    final innerCount = result.outputTapes.length;

    for (int i = 0; i < outerCount; i++) {
      if (i >= innerCount) break; // inner machine had fewer tapes — leave unchanged

      final tokens = result.outputTapes[i];
      final headRel = result.outputHeadPositions[i];

      final newTape = TmTape.fromTokens(tokens);
      // TmTape.fromTokens lays out: [∅, tok0, tok1, …, tokN, ∅] with headOffset=1.
      // absolutePos(headRel) maps the relative head back to an absolute index.
      // Clamp to [0, cells.length-1] so we never reference an out-of-bounds cell.
      final absHead = newTape.absolutePos(headRel)
          .clamp(0, newTape.cells.length - 1);

      updated = updated.withTape(
        i + 1, // withTape is 1-based
        newTape,
        headPos: absHead,
        readHeadPos: absHead,
      );
    }

    return updated;
  }

  /// True if at least one non-halted configuration has an enabled transition.
  // Deliberately structured as a "dry run" that mirrors computeNext()'s own
  // traversal (same black-box handling, same per-alternative checks) but
  // returns `true` the instant ANY branch finds a fireable transition,
  // without actually building/appending a new TmStepSnapshot — this is what
  // lets isHaltedOrStuck ask "could this machine take a step?" without
  // mutating `steps`.
  bool get canAdvance {
    if (steps.isEmpty) return false;
    final current = steps.last;
    if (current.configs.isEmpty) return false;

    for (final config in current.configs) {
      final node = nodes[config.nodeId];
      if (node == null) continue;
      if (node.isHaltAccept || node.isHaltReject) continue;

      final effectiveConfig = _applyBlackBox(node, config);
      if (effectiveConfig == null) continue;

      for (final line in lines.values) {
        if (line.nodeAId != effectiveConfig.nodeId) continue;
        // ── Black-box DSL node ───────────────────────────────────────────────
        // _applyBlackBox ran the inner DSL and rewrote the tapes.  Outgoing
        // lines from a blackbox use BbDirectTransition labels to guard which
        // post-DSL tape state enables each hop.  Parse and check each
        // alternative; a blank label (tilda) fires unconditionally.
        if (node.isBlackBox) {
          final label = line.label.trim();
          if (label.isEmpty) return true; // unconditional tilda hop
          for (final alt in splitBbDirectAlternatives(label)) {
            if (alt.isEmpty || alt == '~') return true; // tilda alt
            final bb = parseBbDirectLabel(alt, effectiveConfig.tapes.length, node.blackBoxActiveTapes);
            if (bb == null) continue; // malformed label — not a fireable transition
            // Check non-wildcard reads.
            bool allMatch = true;
            final applyCount = bb.tapeCount.clamp(0, effectiveConfig.tapes.length);
            for (int ti = 0; ti < applyCount; ti++) {
              final op = bb.ops[ti];
              if (op.isWildcard) continue;
              final headSym = effectiveConfig.tapes[ti].read(effectiveConfig.headPositions[ti]);
              final cellSym = headSym.isEmpty ? kBlank : headSym;
              final readSym = op.read.isEmpty ? kBlank : op.read;
              if (readSym != cellSym) { allMatch = false; break; }
            }
            if (allMatch) return true;
          }
          continue;
        }

        // ── Normal / compound transitions ────────────────────────────────────
        for (final altRaw in line.label.split('\n')) {
          final compound = parseTmCompoundLabel(altRaw);
          final t = compound.primary;

          // Only a genuinely single-tape all-tilde label is an unconditional
          // jump. Inside a multi-tape compound (e.g. compact shorthand
          // `~~~∅1R`), an all-tilde triple just marks ITS tape as sitting
          // out — short-circuiting here would skip checking the other
          // tape(s)' read requirements entirely.
          if (t.isEpsilon && !compound.isMultiTape) return true;

          if (t.tapeIndex < 1 || t.tapeIndex > effectiveConfig.tapes.length) continue;
          if (!t.isWildcard && !t.isEpsilon) {
            final headSym = effectiveConfig.tapes[t.tapeIndex - 1]
                .read(effectiveConfig.headPositions[t.tapeIndex - 1]);
            final cellSym = headSym.isEmpty ? kBlank : headSym;
            final readSym = t.read.isEmpty ? kBlank : t.read;
            if (readSym != cellSym) continue;
          }

          // For b2 (parallelRead): the secondary tape must also match.
          if (compound.isMultiTape &&
              compound.behavior == TmMultiBehavior.parallelRead) {
            // N-tape path: check all non-wildcard, non-epsilon reads.
            if (compound.transitions != null) {
              bool allMatch = true;
              // Starts at i=1, not 0: transitions[0] is the primary tape,
              // already checked above via `t` — this loop only needs to
              // verify the remaining (secondary+) tapes.
              for (int i = 1; i < compound.transitions!.length; i++) {
                final s = compound.transitions![i];
                if (s.isWildcard || s.isEpsilon || s.tapeIndex < 1 || s.tapeIndex > effectiveConfig.tapes.length) continue;
                final sHead = effectiveConfig.headPositions[s.tapeIndex - 1];
                final sSym  = effectiveConfig.tapes[s.tapeIndex - 1].read(sHead);
                final sCell = sSym.isEmpty ? kBlank : sSym;
                final sRead = s.read.isEmpty ? kBlank : s.read;
                if (sRead != sCell) { allMatch = false; break; }
              }
              if (!allMatch) continue;
            } else {
              // Classic 2-tape bN-marker path: just the one secondary transition.
              final s = compound.secondary!;
              if (s.tapeIndex < 1 ||
                  s.tapeIndex > effectiveConfig.tapes.length) {
                continue;
              }
              if (!s.isWildcard && !s.isEpsilon) {
                final sHead = effectiveConfig.headPositions[s.tapeIndex - 1];
                final sSym  = effectiveConfig.tapes[s.tapeIndex - 1].read(sHead);
                final sCell = sSym.isEmpty ? kBlank : sSym;
                final sRead = s.read.isEmpty ? kBlank : s.read;
                if (sRead != sCell) continue;
              }
            }
          }

          // Every applicable read check above passed (or was skipped as
          // wildcard/epsilon) without hitting a `continue` — this
          // alternative is fireable, so the machine as a whole can advance.
          return true;
        }
      }
    }
    return false;
  }

  /// Advance the NTM by exactly one computation step (one global expansion).
  ///
  /// Returns true if a new step snapshot was appended.
  /// Returns false if the machine is halted/stuck (halt reached or no moves).
  // Every currently-live config gets its turn: halted configs are carried
  // forward as-is, live configs try every outgoing line/alternative (NTM
  // branching — one config can spawn multiple next-configs), and any config
  // whose node has no fireable transition simply doesn't appear in
  // `nextConfigs` (implicit reject for that branch, no explicit bookkeeping
  // needed).
  bool computeNext() {
    if (steps.isEmpty) return false;
    final current = steps.last;
    if (current.configs.isEmpty) {
      return false;
    }
    if (isHaltedOrStuck) {
      return false;
    }

    final nextConfigs = <TmConfig>[];
    final nextLines = <String>{};
    // Dedup set across ALL branches this round (not per-config) — two
    // different starting configs that happen to converge on the exact same
    // resulting (node, tapes, heads) triple only need to be represented
    // once in nextConfigs.
    final seenKeys = <String>{};

    for (final config in current.configs) {
      final node = nodes[config.nodeId];
      if (node == null) continue;

      // Halt states carry forward unchanged (so they remain visible).
      // Normal accept states are NOT halted — they continue to fire transitions.
      if (node.isHaltAccept || node.isHaltReject) {
        final carried = config.retarget(nodeId: config.nodeId, usedLineId: config.usedLineId);
        final k = carried.key;
        if (seenKeys.add(k)) nextConfigs.add(carried);
        continue;
      }

      final effectiveConfig = _applyBlackBox(node, config);
      if (effectiveConfig == null) {
        // Black box rejected (or malformed) — this branch dies; nothing
        // added to nextConfigs, matching every other "branch dies" case in
        // this loop (no explicit dead-branch bookkeeping needed).
        continue;
      }

      for (final line in lines.values) {
        if (line.nodeAId != effectiveConfig.nodeId) continue;

        // ── Black-box DSL node ──────────────────────────────────────────────
        // _applyBlackBox (called above) already ran the inner DSL machine and
        // rewrote all tapes.  Outgoing lines from a black-box node carry
        // BbDirectTransition labels that guard which post-DSL tape state
        // enables each hop AND apply per-tape writes/moves after the inner
        // machine finishes.
        //
        // An empty label (or a lone `~`) is an unconditional tilda hop so
        // users can still route with unlabelled arrows.
        if (node.isBlackBox) {
          final label = line.label.trim();
          if (label.isEmpty || label == '~') {
            // Unconditional tilda hop — no read/write/move, just retarget.
            final hopped = effectiveConfig.retarget(
              nodeId: line.nodeBId,
              usedLineId: line.id,
            );
            final k = hopped.key;
            if (seenKeys.add(k)) {
              nextConfigs.add(hopped);
              nextLines.add(line.id);
            }
          } else {
            // Parse and evaluate each alternative independently (NTM branching).
            for (final alt in splitBbDirectAlternatives(label)) {
              if (alt.isEmpty || alt == '~') {
                // tilda alternative — unconditional hop.
                final hopped = effectiveConfig.retarget(
                  nodeId: line.nodeBId,
                  usedLineId: line.id,
                );
                final k = hopped.key;
                if (seenKeys.add(k)) {
                  nextConfigs.add(hopped);
                  nextLines.add(line.id);
                }
                continue;
              }

              final bb = parseBbDirectLabel(alt, effectiveConfig.tapes.length, node.blackBoxActiveTapes);
              if (bb == null) {
                // Unrecognised / malformed format — skip this alternative.
                // Do NOT fire an unconditional hop; the label is meant to guard
                // the transition and we have no valid condition to evaluate.
                continue;
              }

              // _applyBbDirectTransition checks all non-wildcard reads on
              // every tape in the label and applies writes + moves atomically.
              // Returns null when any read condition fails → branch does not fire.
              final next = _applyBbDirectTransition(
                bb, effectiveConfig, line.nodeBId, line.id,
              );
              if (next == null) continue;

              final k = next.key;
              if (seenKeys.add(k)) {
                nextConfigs.add(next);
                nextLines.add(line.id);
              }
            }
          }
          continue;
        }

        for (final altRaw in line.label.split('\n')) {
          final compound = parseTmCompoundLabel(altRaw);
          final t = compound.primary;

          final TmConfig next;
          if (compound.isMultiTape) {
            // ── Multi-tape conjunctive transition (b1 / b2 / compact shorthand) ──
            // Checked before the plain-epsilon branch below: inside a
            // multi-tape label, an all-tilde triple (e.g. the `~~~` in
            // `~~~∅1R`) means "this tape sits out," not "the whole line is
            // an unconditional jump." _applyCompoundTm / _applyNTapeTransition
            // already know how to skip just that one tape's read/write/move.
            final result = _applyCompoundTm(compound, effectiveConfig, line.nodeBId, line.id);
            if (result == null) continue;
            next = result;
          } else if (t.isEpsilon) {
            // tilda (~) transitions: leave every tape and head as-is.
            next = effectiveConfig.retarget(nodeId: line.nodeBId, usedLineId: line.id);
          } else {
            if (t.tapeIndex < 1 || t.tapeIndex > effectiveConfig.tapes.length) continue;
            final tapeIdx = t.tapeIndex - 1;
            final activeTape = effectiveConfig.tapes[tapeIdx];
            final activeHeadPos = effectiveConfig.headPositions[tapeIdx];

            final headSym = activeTape.read(activeHeadPos);
            final cellSym = headSym.isEmpty ? kBlank : headSym;
            if (!t.isWildcard) {
              final readSym = t.read.isEmpty ? kBlank : t.read;
              if (readSym != cellSym) continue;
            }

            // Apply write.
            final writeSym = t.write.isEmpty ? kBlank : t.write;
            final newTape = activeTape.write(activeHeadPos, writeSym);

            // Apply head move. Adjust for any left-extension the write may have introduced.
            final headShift = newTape.headOffset - activeTape.headOffset;
            int newHeadPos = activeHeadPos + headShift;
            switch (t.direction) {
              case TmDirection.right:
                newHeadPos += 1;
                break;
              case TmDirection.left:
                newHeadPos -= 1;
                break;
              case TmDirection.stay:
                break;
            }

            // Extend tape if the head moved beyond either end.
            final readPosPreMove = activeHeadPos + headShift;
            final extended = newTape.extendToInclude(newHeadPos);
            final extendedTape = extended.tape;
            final extraShift = extended.shift;

            // Both the post-move head position AND the pre-move (read) head
            // position need the SAME extra left-shift applied, since a left
            // extension shifts every existing absolute index uniformly —
            // otherwise readHeadPos (used purely for UI display of "what was
            // just read") would drift out of sync with the tape's new
            // indexing after this extension.
            final adjustedHeadPos = newHeadPos + extraShift;
            final adjustedReadPos = readPosPreMove + extraShift;

            next = effectiveConfig.withTape(
              t.tapeIndex,
              extendedTape,
              headPos: adjustedHeadPos,
              readHeadPos: adjustedReadPos, // position that was read (pre-move)
              usedLineId: line.id,
              nodeId: line.nodeBId,
            );
          }
          final k = next.key;
          if (seenKeys.add(k)) {
            nextConfigs.add(next);
            nextLines.add(line.id);
          }
        }
      }
      // If no transition fired, this branch dies (implicit reject). Don't carry it forward.
    }

    // If nothing can move, all remaining branches die. Append an empty snapshot
    // so the machine properly halts. Acceptance is determined from the current
    // live configuration set (see [noMovesTerminal]).
    if (nextConfigs.isEmpty) {
      // NOTE: despite the comment above saying "append an empty snapshot",
      // no snapshot is actually appended here — `steps` is simply left as-is
      // and `noMovesTerminal` is set instead, which is what `result` and
      // `isHaltedOrStuck` actually key off of to treat this as a halt. The
      // comment describes an earlier implementation strategy that no longer
      // matches the code.
      noMovesTerminal = true;
      return false;
    }

    steps.add(TmStepSnapshot(
      configs: nextConfigs,
      usedLineIds: nextLines,
    ));
    noMovesTerminal = false;
    return true;
  }

  /// Apply a compound (multi-tape) transition atomically.
  ///
  /// Handles both the classic 2-tape primary/secondary form and the N-tape
  /// [TmCompoundTransition.multi] form created by the compact shorthand parser.
  ///
  /// Returns the new [TmConfig] on success, or `null` if any required read
  /// condition is not satisfied.
  TmConfig? _applyCompoundTm(
    TmCompoundTransition compound,
    TmConfig config,
    String targetNodeId,
    String lineId,
  ) {
    // ── N-tape path (compact shorthand aXRa1Lb2S…) ──────────────────────
    // Delegates entirely to _applyNTapeTransition, which already knows how
    // to check every tape's read (per `behavior`) and apply every write/move
    // atomically — nothing further to do on this path.
    if (compound.transitions != null) {
      return _applyNTapeTransition(
        compound.transitions!, config, targetNodeId, lineId,
        behavior: compound.behavior,
      );
    }

    // ── Classic 2-tape primary/secondary path (bN marker syntax) ────────
    final t = compound.primary;
    final s = compound.secondary!;

    // ── Guard: tape indices must be in range ───────────────────────────
    if (t.tapeIndex < 1 || t.tapeIndex > config.tapes.length) return null;
    if (s.tapeIndex < 1 || s.tapeIndex > config.tapes.length) return null;

    // ── Check primary read ─────────────────────────────────────────────
    final pIdx  = t.tapeIndex - 1;
    final pTape = config.tapes[pIdx];
    final pHead = config.headPositions[pIdx];
    final pSym  = pTape.read(pHead);
    final pCell = pSym.isEmpty ? kBlank : pSym;
    if (!t.isWildcard && !t.isEpsilon) {
      final pRead = t.read.isEmpty ? kBlank : t.read;
      if (pRead != pCell) return null;
    }

    // ── For b2 (parallelRead): also check secondary read ───────────────
    // b1 (crossWrite) deliberately skips this check — its whole point is
    // that the secondary tape is written unconditionally, without regard to
    // what's currently under its head.
    if (compound.behavior == TmMultiBehavior.parallelRead && !s.isWildcard && !s.isEpsilon) {
      final sIdx  = s.tapeIndex - 1;
      final sTape = config.tapes[sIdx];
      final sHead = config.headPositions[sIdx];
      final sSym  = sTape.read(sHead);
      final sCell = sSym.isEmpty ? kBlank : sSym;
      final sRead = s.read.isEmpty ? kBlank : s.read;
      if (sRead != sCell) return null;
    }

    // ── Apply primary write + move (skip entirely if this side is an
    //    epsilon/no-op tape — leave it untouched rather than force-writing
    //    blank over whatever the cell already held) ───────────────────────
    var next = config;
    if (!t.isEpsilon) {
      final pWrite  = t.write.isEmpty ? kBlank : t.write;
      var newPTape  = pTape.write(pHead, pWrite);
      final pShift  = newPTape.headOffset - pTape.headOffset;
      int newPHead  = pHead + pShift;
      switch (t.direction) {
        case TmDirection.right: newPHead += 1; break;
        case TmDirection.left:  newPHead -= 1; break;
        case TmDirection.stay:  break;
      }
      final pExt    = newPTape.extendToInclude(newPHead);
      newPTape      = pExt.tape;
      final adjPHead = newPHead  + pExt.shift;
      final adjPRead = (pHead + pShift) + pExt.shift;

      next = next.withTape(
        t.tapeIndex, newPTape,
        headPos: adjPHead, readHeadPos: adjPRead,
        usedLineId: lineId, nodeId: targetNodeId,
      );
    } else {
      // Primary tape sits out (epsilon): only retarget the node/line,
      // leave every tape completely untouched.
      next = next.retarget(nodeId: targetNodeId, usedLineId: lineId);
    }

    // ── Apply secondary write + move (same epsilon skip as above) ────────
    // Applied AFTER the primary (via `next.withTape`, building on the
    // already-updated `next` rather than the original `config`), so if
    // both operations somehow targeted the same tape, the secondary's
    // write/move would win — consistent with the "later entries overwrite
    // earlier ones on the same tape" rule documented on
    // _applyNTapeTransition below.
    if (!s.isEpsilon) {
      final sIdx    = s.tapeIndex - 1;
      final sTapeOrig = config.tapes[sIdx];
      final sHead   = config.headPositions[sIdx];
      final sWrite  = s.write.isEmpty ? kBlank : s.write;
      var newSTape  = sTapeOrig.write(sHead, sWrite);
      final sShift  = newSTape.headOffset - sTapeOrig.headOffset;
      int newSHead  = sHead + sShift;
      switch (s.direction) {
        case TmDirection.right: newSHead += 1; break;
        case TmDirection.left:  newSHead -= 1; break;
        case TmDirection.stay:  break;
      }
      final sExt    = newSTape.extendToInclude(newSHead);
      newSTape      = sExt.tape;
      final adjSHead = newSHead  + sExt.shift;
      final adjSRead = (sHead + sShift) + sExt.shift;

      next = next.withTape(
        s.tapeIndex, newSTape,
        headPos: adjSHead, readHeadPos: adjSRead,
        usedLineId: lineId,
      );
    }
    return next;
  }

  /// Apply N per-tape transitions atomically (used by compact shorthand).
  ///
  /// For [TmMultiBehavior.crossWrite] (the default for compact shorthand):
  ///   only tape-1's read is checked; all other tapes are written unconditionally.
  /// For [TmMultiBehavior.parallelRead]:
  ///   every non-wildcard read across all tapes must match simultaneously.
  ///
  /// Tapes not present in [config] (index out of range) are silently skipped.
  TmConfig? _applyNTapeTransition(
    List<TmTransition> transitions,
    TmConfig config,
    String targetNodeId,
    String lineId, {
    TmMultiBehavior behavior = TmMultiBehavior.crossWrite,
  }) {
    // ── Phase 1: read checks ─────────────────────────────────────────────
    // Every tape's read is validated BEFORE any write is applied — this two-
    // phase structure (check everything, then mutate everything) is what
    // makes the whole multi-tape transition atomic: a read failing on tape 3
    // must not leave tapes 1-2 partially written.
    for (int i = 0; i < transitions.length; i++) {
      final t = transitions[i];
      if (t.isEpsilon || t.isWildcard) continue;
      // For crossWrite, only check tape 1 (index 0).
      if (behavior == TmMultiBehavior.crossWrite && i > 0) continue;
      if (t.tapeIndex < 1 || t.tapeIndex > config.tapes.length) continue;
      final tapeIdx = t.tapeIndex - 1;
      final headSym = config.tapes[tapeIdx].read(config.headPositions[tapeIdx]);
      final cellSym = headSym.isEmpty ? kBlank : headSym;
      final readSym = t.read.isEmpty ? kBlank : t.read;
      if (readSym != cellSym) return null;
    }

    // ── Phase 2: apply all writes + moves atomically ─────────────────────
    // Build an updated config by applying each transition's write + move.
    // We snapshot all original tapes first so concurrent writes to different
    // tapes don't interfere with each other's read-position calculations.
    final origTapes = List<TmTape>.from(config.tapes);
    final origHeads = List<int>.from(config.headPositions);

    // Accumulate mutations as we go; later entries overwrite earlier ones on
    // the same tape (consistent with _applyCompoundTm's secondary-wins rule).
    final newTapes = List<TmTape>.from(config.tapes);
    final newHeads = List<int>.from(config.headPositions);
    final newReadHeads = List<int>.from(config.headPositions);

    for (int i = 0; i < transitions.length; i++) {
      final t = transitions[i];
      if (t.isEpsilon) continue;
      if (t.tapeIndex < 1 || t.tapeIndex > config.tapes.length) continue;
      final tapeIdx = t.tapeIndex - 1;

      // Reads from origTapes/origHeads (the pre-mutation snapshot), NOT from
      // newTapes/newHeads — every tape's write/move is computed relative to
      // its state at the START of this phase, so two transitions targeting
      // different tapes never see each other's in-progress changes.
      final origTape = origTapes[tapeIdx];
      final origHead = origHeads[tapeIdx];

      final writeSym = t.write.isEmpty ? kBlank : t.write;
      var newTape = origTape.write(origHead, writeSym);
      final shift = newTape.headOffset - origTape.headOffset;
      int newHead = origHead + shift;
      final readPos = newHead; // pre-move read position

      switch (t.direction) {
        case TmDirection.right: newHead += 1; break;
        case TmDirection.left:  newHead -= 1; break;
        case TmDirection.stay:  break;
      }

      final extended = newTape.extendToInclude(newHead);
      newTape = extended.tape;
      final extraShift = extended.shift;
      final adjHead = newHead + extraShift;
      final adjRead = readPos + extraShift;

      newTapes[tapeIdx] = newTape;
      newHeads[tapeIdx] = adjHead;
      newReadHeads[tapeIdx] = adjRead;
    }

    return TmConfig(
      nodeId: targetNodeId,
      tapes: newTapes,
      headPositions: newHeads,
      readHeadPositions: newReadHeads,
      usedLineId: lineId,
    );
  }

  /// Apply a blackbox-direct transition ([BbDirectTransition]) to [config].
  ///
  /// Each [BbTapeOp] in [bb.ops] maps to a tape (index 0 = tape 1, …).
  ///
  /// Read matching:
  ///   - [BbTapeOp.isWildcard] → always matches (skip the read check).
  ///   - Otherwise the cell under the head must equal [BbTapeOp.read].
  ///
  /// Write semantics:
  ///   - [BbTapeOp.write] is non-empty → write that symbol.
  ///   - [BbTapeOp.write] is empty     → leave the cell unchanged (no-write).
  ///
  /// Returns the new [TmConfig] if all non-wildcard reads match, or `null`
  /// when the transition cannot fire (so the caller can `continue`).
  TmConfig? _applyBbDirectTransition(
    BbDirectTransition bb,
    TmConfig config,
    String targetNodeId,
    String lineId,
  ) {
    // ── Guard: clamp to available tapes (label may encode fewer OR more tapes
    //    than the simulator currently has; only apply ops for tapes that exist).
    final applyCount = bb.tapeCount.clamp(0, config.tapes.length);

    // ── Phase 1: check all non-wildcard reads (only for tapes we will apply) ──
    // Same "check everything, then mutate everything" two-phase structure as
    // _applyNTapeTransition above, for the same atomicity reason.
    for (int ti = 0; ti < applyCount; ti++) {
      final op = bb.ops[ti];
      if (op.isWildcard) continue;
      final headSym = config.tapes[ti].read(config.headPositions[ti]);
      final cellSym = headSym.isEmpty ? kBlank : headSym;
      final readSym = op.read.isEmpty ? kBlank : op.read;
      if (readSym != cellSym) return null;
    }

    // ── Phase 2: apply all writes + moves atomically ─────────────────────
    // Start from the current config and accumulate tape mutations one by one.
    TmConfig next = TmConfig(
      nodeId: targetNodeId,
      tapes: List<TmTape>.from(config.tapes),
      headPositions: List<int>.from(config.headPositions),
      readHeadPositions: List<int>.from(config.headPositions),
      usedLineId: lineId,
    );

    for (int ti = 0; ti < applyCount; ti++) {
      final op = bb.ops[ti];
      final tape = next.tapes[ti];
      final headPos = next.headPositions[ti];

      // Write (or leave unchanged).
      // op.noWrite=true  → `~` in write position: leave the cell unchanged.
      // op.noWrite=false → write op.write (which may be '' meaning blank ∅).
      TmTape newTape;
      if (op.noWrite) {
        // no-write: keep the cell unchanged; may still extend for move.
        newTape = tape;
      } else {
        // write op.write; empty string means write blank (∅).
        final writeSym = op.write.isEmpty ? kBlank : op.write;
        newTape = tape.write(headPos, writeSym);
      }

      // Account for any left-extension the write introduced.
      final shift = newTape.headOffset - tape.headOffset;
      int newHead = headPos + shift;
      final readPos = newHead; // position that was read (pre-move)

      switch (op.direction) {
        case TmDirection.right: newHead += 1; break;
        case TmDirection.left:  newHead -= 1; break;
        case TmDirection.stay:  break;
      }

      // Extend if the head moved off either end.
      final extended = newTape.extendToInclude(newHead);
      newTape = extended.tape;
      final extraShift = extended.shift;
      final adjHead = newHead + extraShift;
      final adjRead = readPos + extraShift;

      // Mutate next in-place for this tape slot.
      // (Rebuilds the three parallel lists and a new TmConfig each
      // iteration rather than mutating in place — consistent with every
      // other config/tape type in this file being treated as immutable.)
      final newTapes = List<TmTape>.from(next.tapes);
      final newHeads = List<int>.from(next.headPositions);
      final newReadHeads = List<int>.from(next.readHeadPositions);
      newTapes[ti] = newTape;
      newHeads[ti] = adjHead;
      newReadHeads[ti] = adjRead;
      next = TmConfig(
        nodeId: next.nodeId,
        tapes: newTapes,
        headPositions: newHeads,
        readHeadPositions: newReadHeads,
        usedLineId: next.usedLineId,
      );
    }

    return next;
  }

  /// Undo the most recently appended step snapshot, if possible.
  ///
  /// This is used by time-bounded fast-forward: if we exceed the time budget
  /// after computing a step, we can roll back that last step and stop.
  bool undoLastStep() {
    if (steps.length <= 1) return false; // keep initial snapshot
    steps.removeLast();
    if (step > maxStep) step = maxStep;
    // If we removed the terminal no-moves state, clear the flag.
    noMovesTerminal = false;
    return true;
  }

  // ── Tokenizer ─────────────────────────────────────────────────────────
  //
  // NOTE: this simulator's own tokenize()/resolveCommand() pair (which used
  // to live here) has been removed in favor of the shared _tokenize() /
  // _resolveCommand() functions defined near the top of this file — see the
  // "SHARED TOKENIZER" section comment for why the three simulators'
  // previously-duplicated copies had drifted and were unified. rebuild()
  // above calls the shared _tokenize() directly with
  // nullEscapeToken: kBlank. The one TM-specific helper that remains here,
  // _trimTapeTokens, isn't part of that shared tokenizer contract — it
  // trims an already-built TmTape's blank cells rather than tokenizing raw
  // input text — so it stays local to this class.

  // Strips leading/trailing blank cells from a tape and returns the
  // remaining content as a plain token list (blank cells become '' rather
  // than the literal kBlank glyph, matching how AutomataSimulator/
  // PdaSimulator represent blanks internally — see _tmOutputTokensAndHead's
  // matching normalization step in AutomataSimulator for the FA-side half of
  // this convention).
  List<String> _trimTapeTokens(TmTape? tape) {
    if (tape == null) return const <String>[];
    final normalized = tape.cells.map((c) => c == kBlank ? '' : c).toList();
    int start = 0;
    int end = normalized.length;
    while (start < end && normalized[start].isEmpty) {
      start++;
    }
    while (end > start && normalized[end - 1].isEmpty) {
      end--;
    }
    if (start >= end) return const <String>[];
    return normalized.sublist(start, end);
  }
}