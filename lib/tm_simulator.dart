import 'models.dart';
import 'token_replacements.dart';

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

  /// Absolute index of the left sentinel blank.  The head may sit on this
  /// cell (reading ∅) but moving further left kills the branch.
  final int leftEdgeAbs;

  /// Absolute index of the right sentinel blank.  The head may sit on this
  /// cell (reading ∅) but moving further right kills the branch.
  final int rightEdgeAbs;

  const TmTape({
    required this.cells,
    required this.headOffset,
    required this.leftEdgeAbs,
    required this.rightEdgeAbs,
  });

  /// Builds the initial tape from input tokens.
  ///
  /// Layout:  [∅, tok0, tok1, …, tokN, ∅]
  ///           ^                        ^
  ///       leftEdge                rightEdge
  ///
  /// headOffset = 1  (input position 0 is at absolute index 1)
  /// Head starts at absolutePos(0) = 1.
  factory TmTape.fromTokens(List<String> tokens) {
    final cells = <String>[kBlank, ...tokens, kBlank];
    // headOffset=1: absolute index of the first input symbol.
    // leftEdge =0: the leading blank sentinel.
    // rightEdge=cells.length-1: the trailing blank sentinel.
    return TmTape(
      cells: cells,
      headOffset: 1,
      leftEdgeAbs: 0,
      rightEdgeAbs: cells.length - 1,
    );
  }

  /// Read the symbol at absolute tape position [pos].
  String read(int pos) {
    if (pos < 0 || pos >= cells.length) return kBlank;
    final v = cells[pos];
    return v.isEmpty ? kBlank : v;
  }

  /// True when [headPos] has moved left of the left sentinel (fell off).
  bool isOffLeft(int headPos) => headPos < leftEdgeAbs;

  /// True when [headPos] has moved right of the right sentinel (fell off).
  bool isOffRight(int headPos) => headPos > rightEdgeAbs;

  /// Returns a new tape with [symbol] written at [pos], extending if needed.
  /// Writing at a position left of index 0 shifts all indices; [leftEdgeAbs]
  /// and [rightEdgeAbs] are updated accordingly.
  TmTape write(int pos, String symbol) {
    final newCells    = List<String>.from(cells);
    int newOffset     = headOffset;
    int newLeftEdge   = leftEdgeAbs;
    int newRightEdge  = rightEdgeAbs;

    if (pos < 0) {
      final extension = -pos;
      final blanks = List<String>.filled(extension, kBlank);
      newCells.insertAll(0, blanks);
      newOffset    += extension;
      newLeftEdge  += extension;
      newRightEdge += extension;
      newCells[0] = symbol.isEmpty ? kBlank : symbol;
      return TmTape(cells: newCells, headOffset: newOffset,
                    leftEdgeAbs: newLeftEdge, rightEdgeAbs: newRightEdge);
    }

    while (pos >= newCells.length) newCells.add(kBlank);
    newCells[pos] = symbol.isEmpty ? kBlank : symbol;
    return TmTape(cells: newCells, headOffset: newOffset,
                  leftEdgeAbs: newLeftEdge, rightEdgeAbs: newRightEdge);
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
  final int headPos;   // absolute index into tape.cells
  final TmTape tape;
  final String usedLineId;

  const TmConfig({
    required this.nodeId,
    required this.headPos,
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

/// Maximum total steps across all branches before we declare a loop.
const int kTmMaxSteps = 10000;

class TmSimulator {
  TmSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  // ── Precomputed simulation ──────────────────────────────────────────────
  List<String> tokens = [];

  /// steps[0] = initial config set; steps[i+1] = after one NTM step from steps[i].
  final List<TmStepSnapshot> steps = [];

  /// Whether the simulation hit the step limit (likely infinite loop).
  bool loopDetected = false;

  /// The user-visible step cursor. -1 = before first snapshot.
  int step = -1;

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
    return (
      cells: cells,
      headIndex: config.headPos - tape.absolutePos(startPos),
      originOffset: startPos,
    );
  }

  // ── Simulation result ──────────────────────────────────────────────────

  TmResult get result {
    if (steps.isEmpty) return TmResult.running;
    if (loopDetected) return TmResult.running;
    // Check final snapshot only.
    final last = steps.last;
    if (last.configs.isEmpty) return TmResult.reject;
    for (final c in last.configs) {
      final node = nodes[c.nodeId];
      if (node == null) continue;
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
    _build(startArrow: startArrow);
    if (step >= steps.length) step = steps.length - 1;
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step >= steps.length) step = steps.length - 1;
  }

  void _build({StartArrowData? startArrow}) {
    steps.clear();
    loopDetected = false;

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      return;
    }

    final initialTape = TmTape.fromTokens(tokens);
    final initialConfig = TmConfig(
      nodeId: startArrow.nodeId,
      headPos: initialTape.absolutePos(0),
      tape: initialTape,
      usedLineId: '',
    );

    // Step 0: initial snapshot.
    steps.add(TmStepSnapshot(
      configs: [initialConfig],
      usedLineIds: const {},
    ));

    // BFS across NTM branches.  Each iteration of this loop advances ALL
    // live configs by one transition, producing the next snapshot.
    int totalStepCount = 0;

    while (true) {
      final current = steps.last;
      if (current.configs.isEmpty) break;

      // Check if every config is in a halting state (halt-accept or halt-reject only).
      bool allHalted = true;
      for (final c in current.configs) {
        final node = nodes[c.nodeId];
        if (node == null || node.isHaltAccept || node.isHaltReject) continue;
        allHalted = false;
        break;
      }
      if (allHalted) break;

      // If any config is in a halt-accept, stop expanding — we accept.
      bool anyHaltAccept = false;
      for (final c in current.configs) {
        final node = nodes[c.nodeId];
        if (node != null && node.isHaltAccept) { anyHaltAccept = true; break; }
      }
      if (anyHaltAccept) break;

      // Expand every non-halted config by one step.
      final nextConfigs = <TmConfig>[];
      final nextLines   = <String>{};
      final seenKeys    = <String>{};

      for (final config in current.configs) {
        final node = nodes[config.nodeId];
        if (node == null) continue;

        // Halted configs carry forward unchanged (so they remain visible).
        if (node.isHaltAccept || node.isHaltReject) {
          final k = config.key;
          if (seenKeys.add(k)) nextConfigs.add(config);
          continue;
        }

        // Also accept-state nodes without halting — carry forward and keep alive.
        // (The TM may loop on them, but we still need to display them.)

        final headSym = config.tape.read(config.headPos);
        final cellSym = headSym.isEmpty ? kBlank : headSym;


        for (final line in lines.values) {
          if (line.nodeAId != config.nodeId) continue;

          for (final altRaw in line.label.split('\n')) {
            final t = parseTmLabel(altRaw);
            final readSym = t.read.isEmpty ? kBlank : t.read;

            if (readSym != cellSym) continue;

            // Apply write.
            final writeSym = t.write.isEmpty ? kBlank : t.write;
            final newTape = config.tape.write(config.headPos, writeSym);

            // Apply head move.  Adjust for any left-extension the write may
            // have introduced (writes at pos>=0 never change headOffset).
            final headShift = newTape.headOffset - config.tape.headOffset;
            int newHeadPos = config.headPos + headShift;
            switch (t.direction) {
              case TmDirection.right: newHeadPos += 1; break;
              case TmDirection.left:  newHeadPos -= 1; break;
              case TmDirection.stay:  break;
            }

            // Kill branch if head moved beyond either sentinel blank.
            if (newTape.isOffLeft(newHeadPos) || newTape.isOffRight(newHeadPos)) continue;

            final next = TmConfig(
              nodeId: line.nodeBId,
              headPos: newHeadPos,
              tape: newTape,
              usedLineId: line.id,
            );
            final k = next.key;
            if (seenKeys.add(k)) {
              nextConfigs.add(next);
              nextLines.add(line.id);
            }
          }
        }

        // If no transition fired, this branch dies (implicit reject).
        // Don't carry it forward. // suppress unused warning
      }

      if (nextConfigs.isEmpty) break;

      steps.add(TmStepSnapshot(
        configs: nextConfigs,
        usedLineIds: nextLines,
      ));

      totalStepCount++;
      if (totalStepCount >= kTmMaxSteps) {
        loopDetected = true;
        break;
      }
    }
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
}