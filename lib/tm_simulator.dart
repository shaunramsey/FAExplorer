import 'models.dart';
import 'token_replacements.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  TM Transition label parsing
//
//  Format:  read , write , direction
//    read      — the tape symbol currently under the head; ∅ matches blank cell
//    write     — the symbol to write in place; ∅ writes a blank
//    direction — R (move right), L (move left), S (stay)
//
//  Multiple alternatives on one transition are separated by newlines.
//
//  3-character shorthand (no separators) is also accepted:
//    aXR   →  read=a  write=X  direction=R
//    ∅∅S   →  blank-read, blank-write, stay
//
//  The blank symbol used on the tape is `∅` (same as kBlank).
// ─────────────────────────────────────────────────────────────────────────────

/// Blank tape symbol — produced by \0 in labels and used for empty cells.
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
  final s = parseTokenText(raw.trim());
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

  // Fallback: treat whole string as a read symbol, write same, stay.
  return TmTransition(read: _normSym(s), write: _normSym(s), direction: TmDirection.stay);
}

String _normSym(String s) {
  final t = parseTokenText(s.trim());
  if (t == '~' || t == 'ε') return '';   // empty = blank for TM
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
//  TM tape
//
//  Modelled as a list of cells that grows on both ends.
//  [tapeOffset] tracks how far left the tape has been extended so that index 0
//  of the original input maps to position [tapeOffset] in the list.
// ─────────────────────────────────────────────────────────────────────────────

class TmTape {
  final List<String> cells;
  final int headOffset; // index of cell-0 within [cells]

  const TmTape({required this.cells, required this.headOffset});

  /// Build an initial tape from tokens. Cell at [headOffset + i] = tokens[i].
  factory TmTape.fromTokens(List<String> tokens) {
    if (tokens.isEmpty) {
      return TmTape(cells: [kBlank], headOffset: 0);
    }
    return TmTape(
      cells: List<String>.from(tokens),
      headOffset: 0,
    );
  }

  /// Read the symbol at absolute tape position [pos] (blank if out of range).
  String read(int pos) {
    if (pos < 0 || pos >= cells.length) return kBlank;
    return cells[pos];
  }

  /// Returns a new tape with [symbol] written at [pos], extending if needed.
  TmTape write(int pos, String symbol) {
    final newCells = List<String>.from(cells);
    int newOffset = headOffset;

    if (pos < 0) {
      final extension = -pos;
      final blanks = List<String>.filled(extension, kBlank);
      newCells.insertAll(0, blanks);
      newOffset += extension;
      newCells[0] = symbol.isEmpty ? kBlank : symbol;
      return TmTape(cells: newCells, headOffset: newOffset);
    }

    while (pos >= newCells.length) newCells.add(kBlank);
    newCells[pos] = symbol.isEmpty ? kBlank : symbol;
    return TmTape(cells: newCells, headOffset: newOffset);
  }

  /// Convert an input-token index (0 = first input char) to an absolute
  /// tape-list index.
  int absolutePos(int inputIndex) => headOffset + inputIndex;
}

// ─────────────────────────────────────────────────────────────────────────────
//  One snapshot of the TM at a single computation step
// ─────────────────────────────────────────────────────────────────────────────

class TmSnapshot {
  /// Current state (node id).
  final String nodeId;

  /// Absolute head position within [tape.cells].
  final int headPos;

  /// Tape contents at this step.
  final TmTape tape;

  /// Which transition edge was fired to reach this step (empty = initial).
  final String usedLineId;

  const TmSnapshot({
    required this.nodeId,
    required this.headPos,
    required this.tape,
    required this.usedLineId,
  });

  /// Index relative to original input start (may be negative).
  int get inputRelativeHead => headPos - tape.headOffset;
}

// ─────────────────────────────────────────────────────────────────────────────
//  TM simulation result
// ─────────────────────────────────────────────────────────────────────────────

enum TmResult { accept, reject, running }

// ─────────────────────────────────────────────────────────────────────────────
//  TmSimulator
// ─────────────────────────────────────────────────────────────────────────────

/// Maximum steps before we declare the TM is looping.
const int kTmMaxSteps = 10000;

class TmSimulator {
  TmSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  // ── Precomputed simulation ──────────────────────────────────────────────
  List<String> tokens = [];

  /// Snapshots[0] = initial configuration; snapshots[i+1] = after step i.
  final List<TmSnapshot> snapshots = [];

  /// Whether the simulation hit the step limit (likely infinite loop).
  bool loopDetected = false;

  /// The user-visible step cursor. -1 = before first snapshot (start arrow lit).
  int step = -1;

  // ── Active highlights ──────────────────────────────────────────────────
  Set<String> get activeNodes {
    final s = _snapshotAt(step);
    return s == null ? {} : {s.nodeId};
  }

  Set<String> get activeLines {
    final s = _snapshotAt(step);
    return (s == null || s.usedLineId.isEmpty) ? {} : {s.usedLineId};
  }

  TmSnapshot? _snapshotAt(int s) {
    final idx = s + 1;
    if (idx < 0 || idx >= snapshots.length) return null;
    return snapshots[idx];
  }

  /// Current tape state for display. Null if no simulation has been built.
  TmSnapshot? get currentSnapshot => _snapshotAt(step);

  /// The tape as it currently looks (for the UI).
  TmTape? get currentTape => currentSnapshot?.tape;

  /// Absolute head position on the current tape.
  int get currentHeadPos => currentSnapshot?.headPos ?? 0;

  /// Tape cell contents as a display list, with the head index.
  /// Returns a view wide enough to show content plus some blank padding.
  ({List<String> cells, int headIndex, int originOffset})? get tapeView {
    final snap = currentSnapshot;
    if (snap == null) return null;
    final tape = snap.tape;
    // Ensure at least some blank cells on either side for display.
    const pad = 3;
    final cells = <String>[];
    final startPos = -pad; // relative to origin
    final endPos   = tape.cells.length - tape.headOffset + pad;
    for (int rel = startPos; rel < endPos; rel++) {
      final abs = tape.absolutePos(rel);
      cells.add((abs >= 0 && abs < tape.cells.length) ? tape.cells[abs] : kBlank);
    }
    return (
      cells: cells,
      headIndex: snap.headPos - tape.absolutePos(startPos),
      originOffset: startPos,
    );
  }

  // ── Simulation result ──────────────────────────────────────────────────

  TmResult get result {
    if (snapshots.isEmpty) return TmResult.running;
    // Walk forward through snapshots to see if any halt state was reached.
    for (final snap in snapshots) {
      final node = nodes[snap.nodeId];
      if (node == null) continue;
      if (node.isHaltAccept) return TmResult.accept;
      if (node.isHaltReject) return TmResult.reject;
    }
    if (loopDetected) return TmResult.running;
    // Check final snapshot
    final last = snapshots.last;
    final lastNode = nodes[last.nodeId];
    if (lastNode == null) return TmResult.reject;
    if (lastNode.isAccept) return TmResult.accept;
    if (lastNode.isHaltAccept) return TmResult.accept;
    if (lastNode.isHaltReject) return TmResult.reject;
    return TmResult.reject;
  }

  TmResult get currentStepResult {
    final snap = currentSnapshot;
    if (snap == null) return TmResult.running;
    final node = nodes[snap.nodeId];
    if (node == null) return TmResult.running;
    if (node.isHaltAccept) return TmResult.accept;
    if (node.isHaltReject) return TmResult.reject;
    if (node.isAccept) return TmResult.accept;
    return TmResult.running;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  void rebuild(String input, {StartArrowData? startArrow}) {
    tokens = _tokenize(input);
    _build(startArrow: startArrow);
    if (step >= snapshots.length) step = snapshots.length - 1;
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step >= snapshots.length) step = snapshots.length - 1;
  }

  void _build({StartArrowData? startArrow}) {
    snapshots.clear();
    loopDetected = false;

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      return;
    }

    final initialTape = TmTape.fromTokens(tokens);

    // Step 0: initial snapshot — head at position 0 (start of input).
    var snap = TmSnapshot(
      nodeId: startArrow.nodeId,
      headPos: initialTape.absolutePos(0),
      tape: initialTape,
      usedLineId: '',
    );
    snapshots.add(snap);

    for (int i = 0; i < kTmMaxSteps; i++) {
      final node = nodes[snap.nodeId];
      if (node == null) break;

      // Halt states: stop here.
      if (node.isHaltAccept || node.isHaltReject) break;
      if (node.isAccept) break; // accept (non-halt) — treat as final

      // Find a matching transition.
      final headSymbol = snap.tape.read(snap.headPos);
      TmTransition? fired;
      String? firedLineId;

      outer:
      for (final line in lines.values) {
        if (line.nodeAId != snap.nodeId) continue;
        for (final altRaw in line.label.split('\n')) {
          final t = parseTmLabel(altRaw);
          final readSym = t.read.isEmpty ? kBlank : t.read;
          final cellSym = headSymbol.isEmpty ? kBlank : headSymbol;
          if (readSym == cellSym) {
            fired = t;
            firedLineId = line.id;
            break outer;
          }
        }
      }

      if (fired == null) break; // no transition — implicit reject

      // Apply write.
      final writeSym = fired.write.isEmpty ? kBlank : fired.write;
      final newTape = snap.tape.write(snap.headPos, writeSym);

      // Apply move — adjusting for any tape extension that shifted indices.
      final headShift = newTape.headOffset - snap.tape.headOffset;
      int newHeadPos = snap.headPos + headShift;
      switch (fired.direction) {
        case TmDirection.right: newHeadPos += 1; break;
        case TmDirection.left:  newHeadPos -= 1; break;
        case TmDirection.stay:  break;
      }

      // Extend tape if head moved off either end.
      final extendedTape = newTape.write(newHeadPos, newTape.read(newHeadPos));

      // Record.
      snap = TmSnapshot(
        nodeId: line_nodeBId(lines, firedLineId!),
        headPos: newHeadPos,
        tape: extendedTape,
        usedLineId: firedLineId,
      );
      snapshots.add(snap);
    }

    if (snapshots.length > 1 && !_isHalted(snapshots.last.nodeId)) {
      if (snapshots.length >= kTmMaxSteps) {
        loopDetected = true;
      }
    }
  }

  bool _isHalted(String nodeId) {
    final node = nodes[nodeId];
    if (node == null) return false;
    return node.isHaltAccept || node.isHaltReject || node.isAccept;
  }

  // helper to look up the target of a fired line
  static String line_nodeBId(Map<String, LineData> lines, String lineId) {
    return lines[lineId]?.nodeBId ?? '';
  }

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