import 'models.dart';
import 'token_replacements.dart';
import 'dsl_code.dart';
import 'simulator.dart';
import 'pda_simulator.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

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

  const TmTransition({
    required this.read,
    required this.write,
    required this.direction,
    this.tapeIndex = 1,
    this.isEpsilon = false,
  });
}

/// Parse a single transition alternative string into a [TmTransition].
TmTransition parseTmLabel(String raw) {
  String preprocessed = raw.replaceAll('\\0', kBlank);
  String s = parseTokenText(preprocessed.trim());
  if (s.isEmpty) {
    return TmTransition(read: kBlank, write: kBlank, direction: TmDirection.stay);
  }

  // All-tilde label → unconditional epsilon jump (no read/write/move).
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
    return TmTransition(
      read: kBlank, write: kBlank, direction: TmDirection.stay, tapeIndex: tapeIndex,
    );
  }

  // After stripping a tape prefix, an all-tilde remainder is still an
  // unconditional epsilon jump (tape index is irrelevant in that case).
  if (s.runes.every((r) => r == '~'.codeUnitAt(0))) {
    return TmTransition(
      read: '', write: '', direction: TmDirection.stay, isEpsilon: true,
    );
  }

  // Format 1: read,write,dir  (comma-separated)
  if (s.contains(',')) {
    final parts = s.split(',');
    if (parts.length >= 3) {
      final read  = _normSym(parts[0]);
      final write = _normSym(parts[1]);
      final dir   = _parseDir(parts[2]);
      return TmTransition(read: read, write: write, direction: dir, tapeIndex: tapeIndex);
    }
  }

  // Format 2: 3-character / 3-rune shorthand e.g. `aXR` or `∅∅S`
  final runes = s.runes.toList();
  if (runes.length == 3) {
    final read  = _normSym(String.fromCharCode(runes[0]));
    final write = _normSym(String.fromCharCode(runes[1]));
    final dir   = _parseDir(String.fromCharCode(runes[2]));
    return TmTransition(read: read, write: write, direction: dir, tapeIndex: tapeIndex);
  }

  // Fallback
  return TmTransition(read: _normSym(s), write: _normSym(s), direction: TmDirection.stay, tapeIndex: tapeIndex);
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

/// Wraps one (or two) [TmTransition] operations that are applied atomically
/// on a single transition arrow.
///
/// When [secondary] is `null` this is identical to a plain single-tape
/// [TmTransition]; the [behavior] field is irrelevant in that case.
class TmCompoundTransition {
  final TmTransition primary;
  final TmTransition? secondary;
  final TmMultiBehavior behavior;

  const TmCompoundTransition({
    required this.primary,
    this.secondary,
    this.behavior = TmMultiBehavior.crossWrite,
  });

  bool get isMultiTape => secondary != null;
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
/// `1:aXR`, long `1:a,X,R`, tape-prefixed, ε, etc.).
TmCompoundTransition parseTmCompoundLabel(String raw) {
  final parts = raw.trim().split(',');

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
    final looksLikeOp = (String s) => s.contains(':') || s.length >= 3;
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

  // No bN marker found → plain single-tape transition (fully backward-compatible).
  return TmCompoundTransition(primary: parseTmLabel(raw));
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
  /// same tapes and head positions (used for epsilon transitions and
  /// black-box hops, which don't move any head).
  TmConfig retarget({required String nodeId, required String usedLineId}) {
    return TmConfig(
      nodeId: nodeId,
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
  final Map<String, ({bool accepted, List<String> outputTokens, int outputHeadPos})>
      _blackBoxResultCache = {};

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

  // ── Active highlights ──────────────────────────────────────────────────

  Set<String> get activeNodes {
    final snap = _snapshotAt(step);
    return snap?.activeNodeIds ?? {};
  }

  Set<String> get activeLines {
    // At step=-1 the simulation hasn't moved yet; no transition has fired.
    if (step < 0) return {};
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
          final blackBox = _runBlackBoxOnTape(node, c.tape, headPos: c.headPos);
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
    final initialTapes = <TmTape>[initialTape];
    final initialHeads = <int>[initialTape.absolutePos(0)];
    final effectiveTapeCount = tapeCount < 1 ? 1 : tapeCount;
    for (int i = 1; i < effectiveTapeCount; i++) {
      final empty = TmTape.empty();
      initialTapes.add(empty);
      initialHeads.add(empty.absolutePos(0));
    }
    final initialConfig = TmConfig(
      nodeId: startArrow.nodeId,
      tapes: initialTapes,
      headPositions: initialHeads,
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

  /// Runs [node]'s inner machine (if it is a black box) against the tape it
  /// is configured to read from, and splices the result into the tape it is
  /// configured to write to. Other tapes pass through unchanged.
  ///
  /// Returns `null` if the black box rejects (so the caller should drop this
  /// branch). For non-black-box nodes, returns [config] unchanged.
  ///
  /// [node.blackBoxReadTape] / [node.blackBoxWriteTape] are 1-based and
  /// clamped to the valid tape range — out-of-range values fall back to tape 1.
  TmConfig? _applyBlackBox(NodeData node, TmConfig config) {
    if (!node.isBlackBox) return config;

    final tapeCountForConfig = config.tapes.length;
    final readTape = node.blackBoxReadTape.clamp(1, tapeCountForConfig);
    final writeTape = node.blackBoxWriteTape.clamp(1, tapeCountForConfig);

    final blackBox = _runBlackBoxOnTape(
      node,
      config.tapes[readTape - 1],
      headPos: config.headPositions[readTape - 1],
    );
    if (!blackBox.accepted) return null;

    final outputTape = TmTape.fromTokens(blackBox.outputTokens);
    final outputHeadPos = outputTape.absolutePos(blackBox.outputHeadPos);

    return config.withTape(
      writeTape,
      outputTape,
      headPos: outputHeadPos,
      readHeadPos: outputHeadPos,
    );
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

      final effectiveConfig = _applyBlackBox(node, config);
      if (effectiveConfig == null) continue;

      for (final line in lines.values) {
        if (line.nodeAId != effectiveConfig.nodeId) continue;
        for (final altRaw in line.label.split('\n')) {
          final compound = parseTmCompoundLabel(altRaw);
          final t = compound.primary;
          if (t.isEpsilon) return true;
          if (t.tapeIndex < 1 || t.tapeIndex > effectiveConfig.tapes.length) continue;
          final headSym = effectiveConfig.tapes[t.tapeIndex - 1]
              .read(effectiveConfig.headPositions[t.tapeIndex - 1]);
          final cellSym = headSym.isEmpty ? kBlank : headSym;
          final readSym = t.read.isEmpty ? kBlank : t.read;
          if (readSym != cellSym) continue;

          // For b2 (parallelRead): the secondary tape must also match.
          if (compound.isMultiTape &&
              compound.behavior == TmMultiBehavior.parallelRead) {
            final s = compound.secondary!;
            if (s.tapeIndex < 1 ||
                s.tapeIndex > effectiveConfig.tapes.length) continue;
            final sHead = effectiveConfig.headPositions[s.tapeIndex - 1];
            final sSym  = effectiveConfig.tapes[s.tapeIndex - 1].read(sHead);
            final sCell = sSym.isEmpty ? kBlank : sSym;
            final sRead = s.read.isEmpty ? kBlank : s.read;
            if (sRead != sCell) continue;
          }

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
        final carried = config.retarget(nodeId: config.nodeId, usedLineId: config.usedLineId);
        final k = carried.key;
        if (seenKeys.add(k)) nextConfigs.add(carried);
        continue;
      }

      final effectiveConfig = _applyBlackBox(node, config);
      if (effectiveConfig == null) {
        continue;
      }

      for (final line in lines.values) {
        if (line.nodeAId != effectiveConfig.nodeId) continue;

        for (final altRaw in line.label.split('\n')) {
          final compound = parseTmCompoundLabel(altRaw);
          final t = compound.primary;

          final TmConfig next;
          if (node.isBlackBox || t.isEpsilon) {
            // Blackbox nodes and epsilon transitions: no write or move.
            // For blackbox nodes all tape work was done inside the blackbox.
            // For epsilon (~) transitions every tape and head is left as-is.
            next = effectiveConfig.retarget(nodeId: line.nodeBId, usedLineId: line.id);
          } else if (compound.isMultiTape) {
            // ── Multi-tape conjunctive transition (b1 / b2) ──────────────
            final result = _applyCompoundTm(compound, effectiveConfig, line.nodeBId, line.id);
            if (result == null) continue;
            next = result;
          } else {
            if (t.tapeIndex < 1 || t.tapeIndex > effectiveConfig.tapes.length) continue;
            final tapeIdx = t.tapeIndex - 1;
            final activeTape = effectiveConfig.tapes[tapeIdx];
            final activeHeadPos = effectiveConfig.headPositions[tapeIdx];

            final headSym = activeTape.read(activeHeadPos);
            final cellSym = headSym.isEmpty ? kBlank : headSym;
            final readSym = t.read.isEmpty ? kBlank : t.read;
            if (readSym != cellSym) continue;

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
  /// Returns the new [TmConfig] on success, or `null` if the transition's
  /// read conditions are not satisfied (so the caller can `continue` the
  /// branch-expansion loop).
  ///
  /// For [TmMultiBehavior.crossWrite] (`b1`):
  ///   - Primary tape read must match.
  ///   - If it does, primary write+move AND secondary write+move are applied.
  ///   - The secondary tape's read symbol is **not** checked.
  ///
  /// For [TmMultiBehavior.parallelRead] (`b2`):
  ///   - BOTH primary and secondary read symbols must match simultaneously.
  ///   - If both match, both writes and head moves are applied atomically.
  ///
  /// When [compound.primary] and [compound.secondary] target the same tape
  /// index, the secondary write takes effect last (overwriting the primary
  /// write at that cell). This edge-case should be avoided in practice.
  TmConfig? _applyCompoundTm(
    TmCompoundTransition compound,
    TmConfig config,
    String targetNodeId,
    String lineId,
  ) {
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
    final pRead = t.read.isEmpty ? kBlank : t.read;
    if (pRead != pCell) return null;

    // ── For b2 (parallelRead): also check secondary read ───────────────
    if (compound.behavior == TmMultiBehavior.parallelRead) {
      final sIdx  = s.tapeIndex - 1;
      final sTape = config.tapes[sIdx];
      final sHead = config.headPositions[sIdx];
      final sSym  = sTape.read(sHead);
      final sCell = sSym.isEmpty ? kBlank : sSym;
      final sRead = s.read.isEmpty ? kBlank : s.read;
      if (sRead != sCell) return null;
    }

    // ── Apply primary write + move ──────────────────────────────────────
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

    // ── Apply secondary write + move ────────────────────────────────────
    // Always snapshot the ORIGINAL tape so that if primary and secondary
    // happen to target the same tape, the primary write doesn't silently
    // influence the secondary's starting state.
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

    // ── Build the new config ────────────────────────────────────────────
    // Apply primary first, then secondary (secondary wins if same tape index).
    var next = config.withTape(
      t.tapeIndex, newPTape,
      headPos: adjPHead, readHeadPos: adjPRead,
      usedLineId: lineId, nodeId: targetNodeId,
    );
    next = next.withTape(
      s.tapeIndex, newSTape,
      headPos: adjSHead, readHeadPos: adjSRead,
      usedLineId: lineId,
    );
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

  /// Run the black-box inner machine on the cells of [tape] starting at
  /// [headPos] (the outer TM's current head position).
  ///
  /// The inner machine only sees the slice  tape[headPos..]  (leading and
  /// trailing blanks stripped).  On success the outer tape is reconstructed
  /// as  tape[0..headPos)  +  innerOutput  +  tape[headPos+sliceLen..]  and
  /// [outputHeadPos] is the absolute position in that reconstructed tape where
  /// the inner machine left its head.
  ///
  /// The cache key includes [headPos] so that the same node visited at
  /// different head positions produces separate cache entries.
  ({bool accepted, List<String> outputTokens, int outputHeadPos}) _runBlackBoxOnTape(
    NodeData node,
    TmTape tape, {
    int? headPos,
  }) {
    // Use the supplied headPos, or fall back to the tape's logical origin (for
    // callers that haven't been updated yet / non-blackbox nodes).
    final int effectiveHeadPos = headPos ?? tape.absolutePos(0);

    if (!node.isBlackBox) {
      final fullTokens = _trimTapeTokens(tape);
      // Translate absolute effectiveHeadPos to an index in the trimmed list.
      final cells = tape.cells;
      int trimStart = 0;
      while (trimStart < cells.length &&
          (cells[trimStart].isEmpty || cells[trimStart] == kBlank)) {
        trimStart++;
      }
      final relativeHeadPos =
          (effectiveHeadPos - trimStart).clamp(0, fullTokens.isEmpty ? 0 : fullTokens.length - 1);
      return (accepted: true, outputTokens: fullTokens, outputHeadPos: relativeHeadPos);
    }

    // Extract the full tape as non-blank tokens so we can slice from headPos.
    final allCells = tape.cells;
    // Convert absolute headPos to an index in allCells (it already is absolute).
    // Build a list of (absoluteIndex, symbol) pairs for non-blank cells so we
    // can locate the slice boundary.
    //
    // The "slice" the inner machine sees is: everything at or after effectiveHeadPos
    // up to the end of the non-blank region.
    int tapeNonBlankEnd = allCells.length;
    while (tapeNonBlankEnd > 0 &&
        (allCells[tapeNonBlankEnd - 1].isEmpty ||
            allCells[tapeNonBlankEnd - 1] == kBlank)) {
      tapeNonBlankEnd--;
    }
    // The slice start is effectiveHeadPos (clamped into the valid range).
    final sliceStart = effectiveHeadPos.clamp(0, tapeNonBlankEnd);
    final sliceEnd = tapeNonBlankEnd;
    final slicedCells = sliceStart < sliceEnd
        ? allCells.sublist(sliceStart, sliceEnd)
        : const <String>[];
    // Strip trailing blanks from the slice (leading blanks are already gone
    // because we start exactly at the head).
    final inputTokens = slicedCells
        .map((c) => (c.isEmpty || c == kBlank) ? '' : c)
        .toList();
    // Remove any leading/trailing empties from the inner input so the inner
    // machine gets a clean tape.
    int iStart = 0, iEnd = inputTokens.length;
    while (iStart < iEnd && inputTokens[iStart].isEmpty) iStart++;
    while (iEnd > iStart && inputTokens[iEnd - 1].isEmpty) iEnd--;
    final cleanInput = iStart < iEnd ? inputTokens.sublist(iStart, iEnd) : const <String>[];

    final cacheKey = '${node.id}:$effectiveHeadPos:${cleanInput.join('\u0001')}';
    final cached = _blackBoxResultCache[cacheKey];
    if (cached != null) return cached;

    final dsl = node.blackBoxDsl.trim();
    if (dsl.isEmpty) {
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
        outputHeadPos: effectiveHeadPos,
      );
    }

    // Helper: reconstruct the full token list and translate the inner head pos
    // back to an absolute position in the outer tape.
    ({List<String> outputTokens, int outputHeadPos}) _splice(
      List<String> innerOutput,
      int innerHeadRelative,
    ) {
      // Cells before the slice (the part the outer TM already processed).
      final before = sliceStart > 0
          ? allCells
              .sublist(0, sliceStart)
              .map((c) => (c.isEmpty || c == kBlank) ? '' : c)
              .toList()
          : const <String>[];
      // Cells after the slice (untouched by the inner machine).
      final after = sliceEnd < allCells.length
          ? allCells
              .sublist(sliceEnd)
              .map((c) => (c.isEmpty || c == kBlank) ? '' : c)
              .toList()
          : const <String>[];

      final full = [...before, ...innerOutput, ...after];
      // Strip overall leading/trailing blanks to get the trimmed token list.
      int fs = 0, fe = full.length;
      while (fs < fe && full[fs].isEmpty) fs++;
      while (fe > fs && full[fe - 1].isEmpty) fe--;
      final trimmed = fs < fe ? full.sublist(fs, fe) : const <String>[];

      // Absolute head pos in the reconstructed tape = before.length + innerHeadRelative.
      final absHead = before.length + innerHeadRelative;
      // Translate to an index in the trimmed list.
      // Allow one-past-end (== trimmed.length) so a head that moved off the
      // right edge of the non-blank content is not snapped back onto the last
      // symbol.  TmTape.fromTokens wraps the token list with a leading and a
      // trailing blank, so absolutePos(trimmed.length) correctly resolves to
      // the trailing blank cell.
      final relHead = (absHead - fs).clamp(0, trimmed.length);
      return (outputTokens: trimmed, outputHeadPos: relHead);
    }

    try {
      final graph = DslCodec.importFromDsl(dsl);
      switch (graph.automataMode) {
        case AutomataMode.ndfa:
          final sim = AutomataSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(cleanInput.join(), startArrow: graph.startArrow);
          final accepted = sim.finalResult() == SimResult.accept;
          if (!accepted) {
            return _blackBoxResultCache[cacheKey] = (
              accepted: false,
              outputTokens: const <String>[],
              outputHeadPos: effectiveHeadPos,
            );
          }
          // NFA: no tape rewrite; head advances past the consumed slice.
          final spliced = _splice(cleanInput, cleanInput.length);
          return _blackBoxResultCache[cacheKey] = (
            accepted: true,
            outputTokens: spliced.outputTokens,
            outputHeadPos: spliced.outputHeadPos,
          );
        case AutomataMode.pda:
          final sim = PdaSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(cleanInput.join(), startArrow: graph.startArrow);
          final accepted = sim.finalResult() == PdaSimResult.accept;
          if (!accepted) {
            return _blackBoxResultCache[cacheKey] = (
              accepted: false,
              outputTokens: const <String>[],
              outputHeadPos: effectiveHeadPos,
            );
          }
          final splicedPda = _splice(cleanInput, cleanInput.length);
          return _blackBoxResultCache[cacheKey] = (
            accepted: true,
            outputTokens: splicedPda.outputTokens,
            outputHeadPos: splicedPda.outputHeadPos,
          );
        case AutomataMode.tm:
          final sim = TmSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(cleanInput.join(), startArrow: graph.startArrow);
          while (sim.computeNext()) {}
          if (sim.result != TmResult.accept) {
            return _blackBoxResultCache[cacheKey] = (
              accepted: false,
              outputTokens: const <String>[],
              outputHeadPos: effectiveHeadPos,
            );
          }
          // Do NOT use sim.currentTape — it goes through the step cursor
          // (sim.step == -1) and returns the *initial* tape.  Pull the
          // halt-accept config directly from the final snapshot instead.
          TmConfig? haltConfig;
          if (sim.steps.isNotEmpty) {
            for (final c in sim.steps.last.configs) {
              if (sim.nodes[c.nodeId]?.isHaltAccept == true) {
                haltConfig = c;
                break;
              }
            }
            haltConfig ??= sim.steps.last.configs.firstOrNull;
          }
          final innerHeadRelative = _computeOutputHeadPos(haltConfig);
          final innerOutput = _trimTapeTokens(haltConfig?.tape);
          final splicedTm = _splice(innerOutput, innerHeadRelative);
          return _blackBoxResultCache[cacheKey] = (
            accepted: true,
            outputTokens: splicedTm.outputTokens,
            outputHeadPos: splicedTm.outputHeadPos,
          );
      }
    } catch (_) {
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
        outputHeadPos: effectiveHeadPos,
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

  /// Compute the head position in the trimmed output tokens based on the
  /// halt config's tape and head position.
  ///
  /// The returned value may equal [trimmedLength] when the head has moved one
  /// cell past the last non-blank symbol (i.e. it is sitting on a blank just
  /// beyond the right edge of the content).  Callers must handle this
  /// "one-past-end" case — TmTape.fromTokens wraps the token list with a
  /// leading and a trailing blank, so absolutePos(trimmedLength) maps exactly
  /// onto the trailing blank cell, which is the correct behaviour.
  int _computeOutputHeadPos(TmConfig? haltConfig) {
    if (haltConfig == null) return 0;
    final tape = haltConfig.tape;
    final rawHeadPos = haltConfig.headPos; // absolute index

    // Locate the non-blank region of the tape.
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

    if (start >= end) return 0; // empty tape

    // Translate the absolute head position to an index in the trimmed output.
    // Allow one-past-end (== trimmedLength) so that a head that moved off the
    // right edge of the content is not incorrectly snapped back onto the last
    // symbol.  Clamp to [0, trimmedLength] (inclusive on both ends).
    final trimmedLen = end - start;
    return (rawHeadPos - start).clamp(0, trimmedLen);
  }
}