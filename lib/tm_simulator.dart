import 'package:flutter/material.dart';

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
      final rawRead = parts[0].trim();
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
      primary: transitions[0],
      secondary: transitions[1],
      behavior: behavior,
      transitions: List.unmodifiable(transitions),
    );
  }

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

  // No bN marker found.
  // ── Compact multi-tape shorthand ─────────────────────────────────────────
  // A label that is exactly 3*N runes (N ≥ 2) where every third rune is a
  // valid direction character (R/L/S/~) is interpreted as N consecutive
  // single-tape 3-rune triples, one per tape (tape 1, tape 2, …).
  //
  // Examples:
  //   aXRa1L  → tape 1: aXR,  tape 2: a1L
  //   aXRa1Lb2S → tape 1: aXR, tape 2: a1L, tape 3: b2S
  //
  // This lets inner-DSL TM transitions be written in the same compact style
  // as blackbox-direct labels without needing explicit N: tape prefixes.
  // Only triggered when the string has no commas and no tape prefix (both of
  // which are handled by the bN path and parseTmLabel above).
  final compactRunes = raw.trim().runes.toList();
  if (compactRunes.length >= 6 && compactRunes.length % 3 == 0 && !raw.contains(':')) {
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
      return TmCompoundTransition.multi(
        transitions: transitions,
        behavior: TmMultiBehavior.crossWrite,
      );
    }
  }

  // No bN marker found → plain single-tape transition (fully backward-compatible).
  return TmCompoundTransition(primary: parseTmLabel(raw));
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
//  If detection fails the alternative is treated as epsilon (no-op transition).
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
/// Returns `null` when the string does not conform to the 3*N-rune format.
///
/// This is the per-alternative parser.  To split a full line label (which
/// may contain multiple comma- or newline-separated alternatives) use
/// [splitBbDirectAlternatives] first.
BbDirectTransition? parseBbDirectLabel(String raw, [int? maxTapes]) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  final runes = s.runes.toList();
  // Must be a multiple of 3.
  if (runes.length % 3 != 0) return null;

  final inferredTapeCount = runes.length ~/ 3;
  if (inferredTapeCount < 1) return null;

  // Validate every direction rune before committing.
  for (int i = 0; i < inferredTapeCount; i++) {
    final dChar = String.fromCharCode(runes[i * 3 + 2]).toUpperCase();
    if (dChar != 'R' && dChar != 'L' && dChar != 'S' && dChar != '~') {
      return null;
    }
  }

  final ops = <BbTapeOp>[];
  for (int i = 0; i < inferredTapeCount; i++) {
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

    ops.add(BbTapeOp(
      read: readSym,
      write: writeSym,
      direction: dir,
      isWildcard: isWildcard,
      noWrite: noWrite,
    ));
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

  ({List<String> cells, int headIndex, int originOffset})? get tapeView =>
      tapeViewForTape(1);

  /// Returns the tape-strip view for tape [tapeIndex] (1-based), or `null`
  /// when there is no current snapshot.  This is the multi-tape-aware
  /// replacement for the old [tapeView] getter, which was hardcoded to tape 1.
  ({List<String> cells, int headIndex, int originOffset})? tapeViewForTape(
      int tapeIndex) {
    final config = _primaryConfig;
    if (config == null) return null;
    final i = (tapeIndex - 1).clamp(0, config.tapes.length - 1);
    final tape = config.tapes[i];
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
    tokens = _tokenize(input);
    _build(startArrow: startArrow, additionalTapeInputs: additionalTapeInputs);
    if (step >= steps.length) step = steps.length - 1;
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step >= steps.length) step = steps.length - 1;
  }

  void _build({
    StartArrowData? startArrow,
    List<String> additionalTapeInputs = const [],
  }) {
    steps.clear();
    noMovesTerminal = false;
    _blackBoxResultCache.clear(); // ← invalidate stale DSL results on every rebuild

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
      return;
    }

    final initialTape = TmTape.fromTokens(tokens);
    final initialTapes = <TmTape>[initialTape];
    final initialHeads = <int>[initialTape.absolutePos(0)];
    final effectiveTapeCount = tapeCount < 1 ? 1 : tapeCount;
    for (int i = 1; i < effectiveTapeCount; i++) {
      // Use the caller-supplied initial content for tapes 2..N when available.
      // Index 0 in additionalTapeInputs corresponds to tape 2 (i == 1), etc.
      final extraIdx = i - 1;
      final TmTape tape;
      if (extraIdx < additionalTapeInputs.length &&
          additionalTapeInputs[extraIdx].isNotEmpty) {
        final extraTokens = _tokenize(additionalTapeInputs[extraIdx]);
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
    debugPrint('ENTERING BLACK BOX: ${node.label}');
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
    } catch (e, st) {
      debugPrint('BLACK BOX ERROR: $e');
      debugPrint('$st');
      _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTapes: const [],
        outputHeadPositions: const [],
      );
      return null;
    }
  }

  // ── Cache key that covers all tapes + all head positions ────────────────

  String _buildBlackBoxCacheKey(NodeData node, TmConfig config) {
    final parts = <String>[node.id];
    for (int i = 0; i < config.tapes.length; i++) {
      parts.add('${config.headPositions[i]}:${config.tapes[i].key}');
    }
    return parts.join('|');
  }

  // ── Run the inner DSL machine against the full outer config ─────────────

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
    ({List<String> tokens, int headRel}) _tapeToInput(int tapeIdx) {
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
      case AutomataMode.ndfa: {
        final t0 = _tapeToInput(0);
        final sim = AutomataSimulator(nodes: graph.nodes, lines: graph.lines);
        sim.rebuild(t0.tokens.join(), startArrow: graph.startArrow);
        if (sim.finalResult() != SimResult.accept) {
          return (accepted: false, outputTapes: const [], outputHeadPositions: const []);
        }
        // NFA: head advances past the entire consumed tape 1; other tapes unchanged.
        final outTapes = <List<String>>[];
        final outHeads = <int>[];
        for (int i = 0; i < outerTapeCount; i++) {
          final t = _tapeToInput(i);
          outTapes.add(t.tokens);
          outHeads.add(i == 0 ? t.tokens.length : t.headRel);
        }
        return (accepted: true, outputTapes: outTapes, outputHeadPositions: outHeads);
      }

      // ── PDA: single-tape, no rewrite ──────────────────────────────────────
      case AutomataMode.pda: {
        final t0 = _tapeToInput(0);
        final sim = PdaSimulator(nodes: graph.nodes, lines: graph.lines);
        sim.rebuild(t0.tokens.join(), startArrow: graph.startArrow);
        if (sim.finalResult() != PdaSimResult.accept) {
          return (accepted: false, outputTapes: const [], outputHeadPositions: const []);
        }
        final outTapes = <List<String>>[];
        final outHeads = <int>[];
        for (int i = 0; i < outerTapeCount; i++) {
          final t = _tapeToInput(i);
          outTapes.add(t.tokens);
          outHeads.add(i == 0 ? t.tokens.length : t.headRel);
        }
        return (accepted: true, outputTapes: outTapes, outputHeadPositions: outHeads);
      }

      // ── Inner TM: multi-tape aware ────────────────────────────────────────
      case AutomataMode.tm: {
        // Determine how many tapes the inner machine needs.  It can use at
        // most as many tapes as the outer machine has, but may use fewer.
        // We set the inner tapeCount to the outer tapeCount so that `N:` tape
        // prefixes in the inner DSL labels correctly address outer tapes 2+.
        final innerTapeCount = outerTapeCount;

        final sim = TmSimulator(nodes: graph.nodes, lines: graph.lines);
        sim.tapeCount = innerTapeCount;

        // Load tape 1 of the inner machine with the outer tape 1 content.
        // After rebuild(), the inner simulator builds the initial config with
        // tapeCount tapes, all starting empty except tape 1 (= the input).
        final t0 = _tapeToInput(0);
        sim.rebuild(t0.tokens.join(), startArrow: graph.startArrow);

        // Overwrite the initial config's extra tapes with the outer tapes 2..N.
        // rebuild() always produces exactly one config in steps[0].
        if (sim.steps.isNotEmpty && sim.steps[0].configs.isNotEmpty && innerTapeCount > 1) {
          final initConfig = sim.steps[0].configs[0];
          TmConfig updated = initConfig;
          for (int i = 1; i < innerTapeCount; i++) {
            final outerTk = _tapeToInput(i);
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
          sim.steps[0] = TmStepSnapshot(
            configs: [updated],
            usedLineIds: sim.steps[0].usedLineIds,
          );
        }

        // Run to completion.
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
            // Inner machine had fewer tapes — carry outer tape unchanged.
            final ot = _tapeToInput(i);
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
        // alternative; a blank label (epsilon) fires unconditionally.
        if (node.isBlackBox) {
          final label = line.label.trim();
          if (label.isEmpty) return true; // unconditional epsilon hop
          for (final alt in splitBbDirectAlternatives(label)) {
            if (alt.isEmpty || alt == '~') return true; // epsilon alt
            final bb = parseBbDirectLabel(alt, effectiveConfig.tapes.length);
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
          if (t.isEpsilon) return true;
          if (t.tapeIndex < 1 || t.tapeIndex > effectiveConfig.tapes.length) continue;
          if (!t.isWildcard) {
            final headSym = effectiveConfig.tapes[t.tapeIndex - 1]
                .read(effectiveConfig.headPositions[t.tapeIndex - 1]);
            final cellSym = headSym.isEmpty ? kBlank : headSym;
            final readSym = t.read.isEmpty ? kBlank : t.read;
            if (readSym != cellSym) continue;
          }

          // For b2 (parallelRead): the secondary tape must also match.
          if (compound.isMultiTape &&
              compound.behavior == TmMultiBehavior.parallelRead) {
            // N-tape path: check all non-wildcard reads.
            if (compound.transitions != null) {
              bool allMatch = true;
              for (int i = 1; i < compound.transitions!.length; i++) {
                final s = compound.transitions![i];
                if (s.isWildcard || s.tapeIndex < 1 || s.tapeIndex > effectiveConfig.tapes.length) continue;
                final sHead = effectiveConfig.headPositions[s.tapeIndex - 1];
                final sSym  = effectiveConfig.tapes[s.tapeIndex - 1].read(sHead);
                final sCell = sSym.isEmpty ? kBlank : sSym;
                final sRead = s.read.isEmpty ? kBlank : s.read;
                if (sRead != sCell) { allMatch = false; break; }
              }
              if (!allMatch) continue;
            } else {
              final s = compound.secondary!;
              if (s.tapeIndex < 1 ||
                  s.tapeIndex > effectiveConfig.tapes.length) continue;
              if (!s.isWildcard) {
                final sHead = effectiveConfig.headPositions[s.tapeIndex - 1];
                final sSym  = effectiveConfig.tapes[s.tapeIndex - 1].read(sHead);
                final sCell = sSym.isEmpty ? kBlank : sSym;
                final sRead = s.read.isEmpty ? kBlank : s.read;
                if (sRead != sCell) continue;
              }
            }
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

        // ── Black-box DSL node ──────────────────────────────────────────────
        // _applyBlackBox (called above) already ran the inner DSL machine and
        // rewrote all tapes.  Outgoing lines from a black-box node carry
        // BbDirectTransition labels that guard which post-DSL tape state
        // enables each hop AND apply per-tape writes/moves after the inner
        // machine finishes.
        //
        // An empty label (or a lone `~`) is an unconditional epsilon hop so
        // users can still route with unlabelled arrows.
        if (node.isBlackBox) {
          final label = line.label.trim();
          if (label.isEmpty || label == '~') {
            // Unconditional epsilon hop — no read/write/move, just retarget.
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
                // Epsilon alternative — unconditional hop.
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

              final bb = parseBbDirectLabel(alt, effectiveConfig.tapes.length);
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
          if (t.isEpsilon) {
            // Epsilon (~) transitions: leave every tape and head as-is.
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
    if (!t.isWildcard) {
      final pRead = t.read.isEmpty ? kBlank : t.read;
      if (pRead != pCell) return null;
    }

    // ── For b2 (parallelRead): also check secondary read ───────────────
    if (compound.behavior == TmMultiBehavior.parallelRead && !s.isWildcard) {
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