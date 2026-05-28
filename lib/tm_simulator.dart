import 'models.dart';
import 'token_replacements.dart';
import 'dsl_code.dart';
import 'simulator.dart';
import 'pda_simulator.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

// ─────────────────────────────────────────────────────────────────────────────
//  TM Transition label parsing
//
//  Format:  read , write , direction
//    read      — the tape symbol currently under the head; ∅ (or ~) matches blank
//    write     — the symbol to write; ∅ (or ~) writes a blank
//    direction — R (move right), L (move left), S (stay)
//
//  Multiple alternatives on one transition are separated by newlines.
//
//  3-character shorthand (no separators) is also accepted:
//    aXR   →  read=a  write=X  direction=R
//    ∅∅S   →  blank-read, blank-write, stay
//
//  The blank symbol used on the tape is `∅` (kBlank).
// ─────────────────────────────────────────────────────────────────────────────

/// Blank tape symbol.
const String kBlank = '∅';

/// Direction the TM head moves after executing a transition.
enum TmDirection { right, left, stay }

class TmTransition {
  final String read;
  final String write;
  final TmDirection direction;

  const TmTransition({
    required this.read,
    required this.write,
    required this.direction,
  });
}

/// Parse a single transition alternative string into a [TmTransition].
TmTransition parseTmLabel(String raw) {
  String preprocessed = raw.replaceAll('\\0', kBlank);
  final s = parseTokenText(preprocessed.trim());
  if (s.isEmpty) {
    return TmTransition(read: kBlank, write: kBlank, direction: TmDirection.stay);
  }

  // Format 1: read,write,dir  (comma-separated)
  if (s.contains(',')) {
    final parts = s.split(',');
    if (parts.length >= 3) {
      final read  = _normSym(parts[0]);
      final write = _normSym(parts[1]);
      final dir   = _parseDir(parts[2]);
      return TmTransition(read: read, write: write, direction: dir);
    }
  }

  // Format 2: 3-character / 3-rune shorthand e.g. `aXR` or `∅∅S`
  final runes = s.runes.toList();
  if (runes.length == 3) {
    final read  = _normSym(String.fromCharCode(runes[0]));
    final write = _normSym(String.fromCharCode(runes[1]));
    final dir   = _parseDir(String.fromCharCode(runes[2]));
    return TmTransition(read: read, write: write, direction: dir);
  }

  // Fallback
  return TmTransition(read: _normSym(s), write: _normSym(s), direction: TmDirection.stay);
}

/// Normalize a tape symbol.
/// `~`, `ε`, `∅`, or empty → blank (represented as empty string internally).
String _normSym(String s) {
  final t = parseTokenText(s.trim());
  if (t == '~' || t == 'ε' || t == kBlank || t.isEmpty) return '';
  return t;
}

TmDirection _parseDir(String s) {
  switch (s.trim().toUpperCase()) {
    case 'R': return TmDirection.right;
    case 'L': return TmDirection.left;
    default:  return TmDirection.stay;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TM tape (immutable snapshot)
// ─────────────────────────────────────────────────────────────────────────────

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
    final cells = <String>[kBlank, ...tokens, kBlank];
    // headOffset=1: absolute index of the first input symbol.
    return TmTape(
      cells: cells,
      headOffset: 1,
    );
  }

  /// Read the symbol at absolute tape position [pos].
  String read(int pos) {
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
      return (tape: this, shift: 0);
    }

    final newCells = List<String>.from(cells);
    int newOffset = headOffset;
    int shift = 0;

    if (pos < 0) {
      final extension = -pos;
      newCells.insertAll(0, List<String>.filled(extension, kBlank));
      newOffset += extension;
      shift = extension;
    } else {
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

    while (pos >= newCells.length) newCells.add(kBlank);
    newCells[pos] = symbol.isEmpty ? kBlank : symbol;
    return TmTape(
      cells: newCells,
      headOffset: newOffset,
    );
  }

  /// Convert a logical input index (0 = first input char) to absolute index.
  int absolutePos(int inputIndex) => headOffset + inputIndex;

  /// A key that uniquely describes the tape content (for loop detection).
  String get key => cells.join('|');
}


// ─────────────────────────────────────────────────────────────────────────────
//  NTM Configuration  (state × head position × tape)
// ─────────────────────────────────────────────────────────────────────────────

class TmConfig {
  final String nodeId;
  final int headPos;      // absolute index into tape.cells — where the head IS now (post-move)
  final int readHeadPos;  // absolute index that was READ to fire the transition (pre-move, for display)
  final TmTape tape;
  final String usedLineId;

  const TmConfig({
    required this.nodeId,
    required this.headPos,
    required this.readHeadPos,
    required this.tape,
    required this.usedLineId,
  });

  /// Key used for loop / duplicate detection.
  String get key => '$nodeId:$headPos:${tape.key}';
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

enum TmResult { accept, reject, running }

// ─────────────────────────────────────────────────────────────────────────────
//  NTM Simulator
// ─────────────────────────────────────────────────────────────────────────────

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
  final Map<String, ({bool accepted, List<String> outputTokens})>
      _blackBoxResultCache = {};

  /// Maximum valid value for [step] given the current [steps] list.
  ///
  /// Contract (matches [_snapshotAt]):
  /// - step == -1 → steps[0]
  /// - step ==  0 → steps[1]
  /// - step == maxStep → steps.last
  int get maxStep => steps.isEmpty ? -1 : steps.length - 2;

  // ── Active highlights ──────────────────────────────────────────────────

  Set<String> get activeNodes {
    final snap = _snapshotAt(step);
    return snap?.activeNodeIds ?? {};
  }

  Set<String> get activeLines {
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

  ({List<String> cells, int headIndex, int originOffset})? get tapeView {
    final config = _primaryConfig;
    if (config == null) return null;
    final tape = config.tape;
    const pad = 3;
    final cells = <String>[];
    final startPos = -pad;
    final endPos = tape.cells.length - tape.headOffset + pad;
    for (int rel = startPos; rel < endPos; rel++) {
      final abs = tape.absolutePos(rel);
      cells.add((abs >= 0 && abs < tape.cells.length) ? tape.cells[abs] : kBlank);
    }
    // Highlight the cell that was READ to produce this step (pre-move position),
    // not the post-move position where the head will read next.
    final displayHeadPos = config.readHeadPos;
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
        if (node.isBlackBox) {
          final blackBox = _runBlackBoxOnTape(node, c.tape);
          if (!blackBox.accepted) continue;
        }
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

  void rebuild(String input, {StartArrowData? startArrow}) {
    tokens = _tokenize(input);
    _blackBoxResultCache.clear();
    _build(startArrow: startArrow);
    if (step >= steps.length) step = steps.length - 1;
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step >= steps.length) step = steps.length - 1;
  }

  void _build({StartArrowData? startArrow}) {
    steps.clear();
    noMovesTerminal = false;

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      return;
    }

    final initialTape = TmTape.fromTokens(tokens);
    final initialConfig = TmConfig(
      nodeId: startArrow.nodeId,
      headPos: initialTape.absolutePos(0),
      readHeadPos: initialTape.absolutePos(0),
      tape: initialTape,
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

  /// True if at least one non-halted configuration has an enabled transition.
  bool get canAdvance {
    if (steps.isEmpty) return false;
    final current = steps.last;
    if (current.configs.isEmpty) return false;

    for (final config in current.configs) {
      final node = nodes[config.nodeId];
      if (node == null) continue;
      if (node.isHaltAccept || node.isHaltReject) continue;

      var effectiveConfig = config;
      if (node.isBlackBox) {
        final blackBox = _runBlackBoxOnTape(node, config.tape);
        if (!blackBox.accepted) continue;
        final outputTape = TmTape.fromTokens(blackBox.outputTokens);
        final startHead = outputTape.absolutePos(0);
        effectiveConfig = TmConfig(
          nodeId: config.nodeId,
          headPos: startHead,
          readHeadPos: startHead,
          tape: outputTape,
          usedLineId: config.usedLineId,
        );
      }

      final headSym = effectiveConfig.tape.read(effectiveConfig.headPos);
      final cellSym = headSym.isEmpty ? kBlank : headSym;

      for (final line in lines.values) {
        if (line.nodeAId != effectiveConfig.nodeId) continue;
        for (final altRaw in line.label.split('\n')) {
          final t = parseTmLabel(altRaw);
          final readSym = t.read.isEmpty ? kBlank : t.read;
          if (readSym != cellSym) continue;
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
    final seenKeys = <String>{};

    for (final config in current.configs) {
      final node = nodes[config.nodeId];
      if (node == null) continue;

      // Halt states carry forward unchanged (so they remain visible).
      // Normal accept states are NOT halted — they continue to fire transitions.
      if (node.isHaltAccept || node.isHaltReject) {
        final carried = TmConfig(
          nodeId: config.nodeId,
          headPos: config.headPos,
          readHeadPos: config.headPos, // halted: display current position
          tape: config.tape,
          usedLineId: config.usedLineId,
        );
        final k = carried.key;
        if (seenKeys.add(k)) nextConfigs.add(carried);
        continue;
      }

      var effectiveConfig = config;
      if (node.isBlackBox) {
        final blackBox = _runBlackBoxOnTape(node, config.tape);
        if (!blackBox.accepted) {
          continue;
        }
        final outputTape = TmTape.fromTokens(blackBox.outputTokens);
        final startHead = outputTape.absolutePos(0);
        effectiveConfig = TmConfig(
          nodeId: config.nodeId,
          headPos: startHead,
          readHeadPos: startHead,
          tape: outputTape,
          usedLineId: config.usedLineId,
        );
      }

      final headSym = effectiveConfig.tape.read(effectiveConfig.headPos);
      final cellSym = headSym.isEmpty ? kBlank : headSym;

      for (final line in lines.values) {
        if (line.nodeAId != effectiveConfig.nodeId) continue;

        for (final altRaw in line.label.split('\n')) {
          final t = parseTmLabel(altRaw);
          final readSym = t.read.isEmpty ? kBlank : t.read;

          if (readSym != cellSym) continue;

          // Apply write.
          final writeSym = t.write.isEmpty ? kBlank : t.write;
          final newTape = effectiveConfig.tape.write(
            effectiveConfig.headPos,
            writeSym,
          );

          // Apply head move. Adjust for any left-extension the write may have introduced.
          final headShift = newTape.headOffset - effectiveConfig.tape.headOffset;
          int newHeadPos = effectiveConfig.headPos + headShift;
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
          final readPosPreMove = effectiveConfig.headPos + headShift;
          final extended = newTape.extendToInclude(newHeadPos);
          final extendedTape = extended.tape;
          final extraShift = extended.shift;

          final adjustedHeadPos = newHeadPos + extraShift;
          final adjustedReadPos = readPosPreMove + extraShift;

          final next = TmConfig(
            nodeId: line.nodeBId,
            headPos: adjustedHeadPos,
            readHeadPos: adjustedReadPos, // position that was read (pre-move)
            tape: extendedTape,
            usedLineId: line.id,
          );
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

  List<String> _tokenize(String input) {
    final result = <String>[];
    int i = 0;
    while (i < input.length) {
      if (input[i].trim().isEmpty) { i++; continue; }
      if (i + 1 < input.length && input[i] == '[' && input[i + 1] == '[') {
        final close = input.indexOf(']]', i + 2);
        if (close >= 0) {
          result.add(_resolveCommand(input.substring(i, close + 2)));
          i = close + 2;
          continue;
        }
      }
      if (input[i] == '"') {
        final close = input.indexOf('"', i + 1);
        if (close >= 0) {
          result.add(input.substring(i + 1, close));
          i = close + 1;
          continue;
        }
      }
      if (i + 1 < input.length && input[i] == '\\' && input[i + 1] == '0') {
        result.add(kBlank);
        i += 2;
        continue;
      }
      result.add(input[i]);
      i++;
    }
    return result;
  }

  String _resolveCommand(String token) {
    final trimmed = token.trim();
    if (!trimmed.startsWith('[[') || !trimmed.endsWith(']]')) return token;
    final inner = trimmed.substring(2, trimmed.length - 2).trim().toUpperCase();
    return kTokenReplacements[inner] ?? token;
  }

  ({bool accepted, List<String> outputTokens}) _runBlackBoxOnTape(
    NodeData node,
    TmTape tape,
  ) {
    if (!node.isBlackBox) {
      return (accepted: true, outputTokens: _trimTapeTokens(tape));
    }
    final inputTokens = _trimTapeTokens(tape);
    final cacheKey = '${node.id}:${inputTokens.join('\u0001')}';
    final cached = _blackBoxResultCache[cacheKey];
    if (cached != null) return cached;

    final dsl = node.blackBoxDsl.trim();
    if (dsl.isEmpty) {
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
      );
    }

    try {
      final graph = DslCodec.importFromDsl(dsl);
      switch (graph.automataMode) {
        case AutomataMode.ndfa:
          final sim = AutomataSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(inputTokens.join(), startArrow: graph.startArrow);
          final accepted = sim.finalResult() == SimResult.accept;
          return _blackBoxResultCache[cacheKey] = (
            accepted: accepted,
            outputTokens: inputTokens,
          );
        case AutomataMode.pda:
          final sim = PdaSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(inputTokens.join(), startArrow: graph.startArrow);
          final accepted = sim.finalResult() == PdaSimResult.accept;
          return _blackBoxResultCache[cacheKey] = (
            accepted: accepted,
            outputTokens: inputTokens,
          );
        case AutomataMode.tm:
          final sim = TmSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(inputTokens.join(), startArrow: graph.startArrow);
          while (sim.computeNext()) {}
          if (sim.result != TmResult.accept) {
            return _blackBoxResultCache[cacheKey] = (
              accepted: false,
              outputTokens: const <String>[],
            );
          }
          final output = _trimTapeTokens(sim.currentTape);
          return _blackBoxResultCache[cacheKey] = (
            accepted: true,
            outputTokens: output,
          );
      }
    } catch (_) {
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
      );
    }
  }

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