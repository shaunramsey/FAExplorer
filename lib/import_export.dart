// ═══════════════════════════════════════════════════════════════════════════
//  import_export.dart
//
//  Combined module — merges the following originals into one file so their
//  internal (non-exported) helper types/functions can share a single
//  compilation unit:
//
//    • dsl_code.dart          — GraphState, DslCodec (DSL / SVG import-export)
//    • latex_export.dart      — LatexExporter, LatexImporter, LaTeX dialogs
//    • fa_to_regex.dart       — FaToRegexResult, faToRegex() (state-elimination)
//    • svg_export.dart        — SvgExporter
//    • fa_to_regex_dialog.dart — showFaToRegexDialog() UI
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert'; // jsonDecode/JsonEncoder (SVG's embedded data script), utf8/base64 (legacy blackbox DSL decoding), htmlEscape (SVG text)
import 'dart:math'; // pi, sin, cos, atan2, min/max — geometry + numbering helpers throughout

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart'; // context.watch<AppThemeNotifier>() in the fa-to-regex dialog

import 'models.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;
import 'widgets/app_theme.dart';


// ─────────────────────────────────────────────────────────────────────────────
// SECTION: dsl_code.dart
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  GraphState  (plain data bag passed in / returned)
// ─────────────────────────────────────────────────────────────────────────────

/// Everything needed to fully describe (and rebuild) one automaton on the
/// canvas. Every import/export path in this file — DSL, SVG, LaTeX — reads
/// from or produces one of these, so it's the shared currency the rest of
/// the app hands around instead of dealing with nodes/lines/mode separately.
class GraphState {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;

  // Next free numeric suffix for a new node/line id ("n{nodeCounter}" /
  // "l{lineCounter}") — kept here (not derived from nodes.length) so ids
  // stay unique even after some nodes/lines have been deleted.
  final int nodeCounter;
  final int lineCounter;
  final AutomataMode automataMode;

  /// Convenience getter for code that still checks the PDA flag.
  bool get pdaMode => automataMode == AutomataMode.pda;

  /// Hit-tests every node and returns the first one containing [point], or
  /// null. Used for tap/drag handling on the canvas.
  NodeData? nodeAt(Offset point) {
    for (final node in nodes.values) {
      if (node.containsPoint(point)) return node;
    }
    return null;
  }

  /// Hit-tests every line (using its two endpoint nodes' current centres,
  /// so this stays correct as nodes move) and returns the first match.
  LineData? lineAt(Offset point) {
    for (final line in lines.values) {
      final a = nodes[line.nodeAId];
      final b = nodes[line.nodeBId];
      if (a == null || b == null) continue; // stale line referencing a deleted node
      if (line.containsPoint(point, a.center, b.center)) return line;
    }
    return null;
  }

  /// True if [point] hits the start arrow (only meaningful when one exists
  /// and its target node still exists).
  bool hitStartArrow(Offset point) {
    if (startArrow == null) return false;
    final node = nodes[startArrow!.nodeId];
    if (node == null) return false;
    return startArrow!.containsPoint(point, node.center);
  }

  const GraphState({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.nodeCounter,
    required this.lineCounter,
    this.automataMode = AutomataMode.ndfa,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  DslCodec
// ─────────────────────────────────────────────────────────────────────────────

/// Converts automata graphs to and from the app's DSL and SVG formats so
/// machines can be saved, imported, and reloaded across sessions.
class DslCodec {
  const DslCodec._(); // static-only class; never instantiated

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Escapes text for safe embedding as a DSL label: backslash first (so a
  /// literal backslash doesn't get mistaken for the start of an escape
  /// sequence added by the second replace), then real newlines become the
  /// two-character sequence `\n`.
  static String _escapeDsl(String text) => text.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');

  /// Inverse of [_escapeDsl]: walks the string char-by-char rather than
  /// using a single regex replace, since `\\` and `\n` need to be told
  /// apart from an escaped backslash followed by a literal 'n'.
  static String _unescapeDsl(String text) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == r'\' && i + 1 < text.length) {
        final next = text[i + 1];
        if (next == 'n') {
          buffer.write('\n'); // \n -> real newline
        } else {
          buffer.write(next); // \\ -> \, or any other \X -> X (lenient fallback)
        }
        i++; // consumed both the backslash and the escaped character
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  // Node ref: prefer label, fall back to id, use id(label) for duplicates.
  /// How a node is *referred to* elsewhere in the exported DSL (transition
  /// lines, position lines, etc): its label if that label is unique among
  /// all nodes, otherwise the disambiguated `id(label)` form so re-import
  /// can tell which of several same-labelled nodes was meant.
  static String _nodeRef(NodeData node, Map<String, NodeData> nodes) {
    final label = node.label.trim();
    if (label.isEmpty) return node.id; // no label at all: fall back to the bare internal id
    final dups = nodes.values.where((n) => n.label.trim() == label).length;
    if (dups <= 1) return _escapeDsl(label);
    return '${node.id}(${_escapeDsl(label)})';
  }

  /// Same idea as [_nodeRef] but for a *line's* label, using the
  /// `~N(label)` occurrence-index form for disambiguation instead of the
  /// line's raw id — see the DSL grammar comment on `line-ref` below for why
  /// (ids get renumbered on reimport, so an index among same-label lines,
  /// in file order, is what actually survives a round-trip).
  static String _lineRef(LineData line, Map<String, LineData> lines) {
    final label = line.label.trim();
    if (label.isEmpty) return line.id;
    final sameLabel = lines.values.where((l) => l.label.trim() == label).toList();
    if (sameLabel.length <= 1) return _escapeDsl(label);
    // Use occurrence index (0-based) so the reference survives id re-numbering
    // on reimport.  Format: ~N(label)  where N is the rank among same-label lines.
    final rank = sameLabel.indexWhere((l) => l.id == line.id);
    return '~$rank(${_escapeDsl(label)})';
  }

  /// Spreadsheet-style base-26 numbering (0 -> A, 1 -> B, … 25 -> Z, 26 ->
  /// AA, …) used as a node's display label when it has no user-entered one.
  /// Note: this is a separate, slightly differently-indexed implementation
  /// of the same idea as models.dart's nodeIdToAlpha (that one parses an
  /// "n7"-style id string; this one takes a plain int index directly).
  static String _numberToAlphaLabel(int index) {
    index += 1; // shift to 1-based so the bijective base-26 math below works out (see nodeIdToAlpha in models.dart for the same trick)
    String result = '';
    while (index > 0) {
      index--;
      result = String.fromCharCode(65 + (index % 26)) + result;
      index ~/= 26;
    }
    return result;
  }

  static Offset _defaultPosition(int count) {
    if (count == 0) return const Offset(300, 300);
    // Arrange nodes in concentric rings around a centre point.
    // Ring 0 holds 7 nodes, ring 1 holds 13, ring 2 holds 19, …
    // Ring radius is capped at 280 px so even deep rings stay within a
    // typical ~800×600 viewport when the canvas origin is near (0,0).
    int ring = 0, capacity = 0, ringSize = 7;
    // Walks forward ring-by-ring (capacities 7, 13, 19, …, each 6 bigger
    // than the last) until `count` falls within the current ring's range,
    // to find which ring the `count`-th node belongs in and how many slots
    // came before it.
    while (capacity + ringSize <= count) {
      capacity += ringSize;
      ring++;
      ringSize += 6;
    }
    final pos = count - capacity; // this node's 0-based slot index within its own ring
    final angle = (2 * pi * pos) / ringSize - pi / 2; // evenly spaced around the ring, starting at the top (-pi/2)
    // Cap radius growth so nodes don't fly off-screen for large graphs.
    final radius = min(280.0, 150.0 + ring * 80.0);
    return Offset(300 + cos(angle) * radius, 300 + sin(angle) * radius);
  }

  // ── DSL EXPORT ─────────────────────────────────────────────────────────────

  /// Serializes [g] to the app's plain-text DSL. Produces the statement
  /// forms documented in the grammar comment on [importFromDsl] below, one
  /// blank-line-separated group per concern (mode, node defs, positions,
  /// accept states, transitions, curves, self-loop angles, start arrow) —
  /// so a human skimming the file can jump straight to the section they
  /// care about.
  static String exportToDsl(GraphState g) {
    final out = <String>[];

    // Mode declaration, only emitted for non-default modes (plain ndfa/dfa
    // needs no explicit line at all — importFromDsl's default is ndfa).
    if (g.automataMode == AutomataMode.pda) {
      out.add('pda mode');
      out.add('');
    } else if (g.automataMode == AutomataMode.tm) {
      out.add('tm mode');
      out.add('');
    } else if (g.automataMode == AutomataMode.regex) {
      out.add('regex mode');
      out.add('');
    }

    // Node definitions
    for (final n in g.nodes.values) {
      final num = int.tryParse(n.id.substring(1)) ?? 0;
      // Auto-generate a display label from the node's numeric id when the
      // user never gave it one, so every exported node line has *some*
      // readable label rather than sitting blank.
      final rawLabel = n.label.trim().isEmpty ? _numberToAlphaLabel(num) : n.label;
      String label = _escapeDsl(rawLabel);
      if (n.isHaltAccept) {
        label = '<<$label>>'; // halt-accept marker, unwrapped again on import
      } else if (n.isHaltReject) {
        label = '>>$label<<'; // halt-reject marker
      }
      out.add('${n.id} = $label');
      if (n.isBlackBox) {
        // Store DSL as human-readable escaped text (not base64) so users can
        // read and edit it directly.  Newlines become the literal \n sequence.
        // Export blackbox DSL in multi-line block format for easy editing
        final dslLines = n.blackBoxDsl.split('\n');
        out.add('${n.id} blackbox dsl {');
        for (final dslLine in dslLines) {
          out.add('  $dslLine');
        }
        out.add('}');
        // These three are only emitted when they differ from their
        // defaults, keeping the common case (tape 1, positional triple
        // mapping) out of the exported text entirely.
        if (n.blackBoxReadTape != 1) {
          out.add('${n.id} blackbox read tape = ${n.blackBoxReadTape}');
        }
        if (n.blackBoxWriteTape != 1) {
          out.add('${n.id} blackbox write tape = ${n.blackBoxWriteTape}');
        }
        if (n.blackBoxActiveTapes.isNotEmpty) {
          out.add('${n.id} blackbox tapes = ${n.blackBoxActiveTapes.join(',')}');
        }
      }
    }
    if (g.nodes.isNotEmpty) out.add(''); // blank-line separator before the next section

    // Positions
    // Every node's (x, y), keyed by its ref — kept as a separate section
    // (rather than folded into the node-definition line above) so the
    // grammar's node-def and position statements can be parsed
    // independently and so hand-edited DSL can freely omit positions.
    bool wrote = false;
    for (final n in g.nodes.values) {
      out.add('${_nodeRef(n, g.nodes)} = (${n.position.dx.toStringAsFixed(1)}, ${n.position.dy.toStringAsFixed(1)})');
      wrote = true;
    }
    if (wrote) out.add('');

    // Accept states
    wrote = false;
    for (final n in g.nodes.values) {
      if (!n.isAccept) continue;
      out.add('${_nodeRef(n, g.nodes)} is accepted');
      wrote = true;
    }
    if (wrote) out.add('');

    // Transitions
    wrote = false;
    for (final l in g.lines.values) {
      final a = g.nodes[l.nodeAId], b = g.nodes[l.nodeBId];
      if (a == null || b == null) continue; // stale line referencing a deleted node
      final ra = _nodeRef(a, g.nodes), rb = _nodeRef(b, g.nodes);
      out.add(l.label.trim().isEmpty ? '$ra to $rb' : '$ra to $rb = ${_escapeDsl(l.label)}');
      wrote = true;
    }
    if (wrote) out.add('');

    // Curves
    // Only lines with a non-negligible bend get an explicit `curve = N`
    // line — a plain straight transition (perpendicularPart ~ 0) doesn't
    // need one, since 0 is the importer's implicit default.
    wrote = false;
    for (final l in g.lines.values) {
      if (l.perpendicularPart.abs() <= 0.5) continue;
      out.add('${_lineRef(l, g.lines)} curve = ${l.perpendicularPart.toStringAsFixed(1)}');
      wrote = true;
    }
    if (wrote) out.add('');

    // Self-loop angles
    // Every self-loop line always gets one of these (unlike curves above,
    // there's no "default" self-loop angle worth omitting — 0 rotation is
    // just as arbitrary a default as any other angle would be).
    wrote = false;
    for (final l in g.lines.values) {
      if (l.nodeAId != l.nodeBId) continue;
      out.add('${_lineRef(l, g.lines)} loop angle = ${l.selfLoopAngle.toStringAsFixed(4)}');
      wrote = true;
    }
    if (wrote) out.add('');

    // Start arrow
    if (g.startArrow != null) {
      final node = g.nodes[g.startArrow!.nodeId];
      if (node != null) {
        final ref = _nodeRef(node, g.nodes);
        final sa = g.startArrow!;
        out.add(sa.label.trim().isEmpty ? 'to $ref' : 'to $ref = ${_escapeDsl(sa.label)}');
        // Length/angle are only written out when they differ from their
        // defaults (100px shaft, direction unchanged/default) — same
        // "don't clutter the common case" approach as blackbox tape fields above.
        if ((sa.length - 100).abs() > 0.5) out.add('to $ref length = ${sa.length.toStringAsFixed(1)}');
        final dir = sa.direction();
        out.add('to $ref angle = ${dir.dx.toStringAsFixed(4)}, ${dir.dy.toStringAsFixed(4)}');
      }
    }

    return out.join('\n').trimRight();
  }

  // ── DSL IMPORT ─────────────────────────────────────────────────────────────
  //
  //  GRAMMAR (informal EBNF)
  //  ───────────────────────
  //  This is the one place the whole format is written down — everything
  //  below is implemented as a chain of line-by-line RegExp checks in
  //  importFromDsl(), in this same order (first match wins). If you add a
  //  new statement form, add a line here too.
  //
  //    program      ::= (statement | comment | blank-line)*
  //    comment      ::= '#' any-text-to-end-of-line          -- stripped, not stored
  //
  //    statement    ::= mode-decl
  //                    | start-arrow
  //                    | line-curve
  //                    | line-loop-angle
  //                    | node-accept
  //                    | edge
  //                    | node-position
  //                    | node-def
  //                    | blackbox-desc
  //                    | blackbox-dsl-inline
  //                    | blackbox-dsl-block      -- multi-line; see below
  //                    | blackbox-read-tape
  //                    | blackbox-write-tape
  //                    | blackbox-tapes
  //                    | bare-node               -- fallback: any other
  //                                                 non-empty line becomes an
  //                                                 isolated node with that
  //                                                 label
  //
  //    mode-decl    ::= ('pda' | 'tm' | 'regex') 'mode' ('on' | 'off')?
  //                      -- bare form (no on/off) means 'on'
  //
  //    start-arrow  ::= 'to' node (
  //                        WS 'length' '=' number
  //                      | WS 'angle' '=' number ',' number
  //                      | '=' label
  //                      )?
  //
  //    line-curve      ::= line-ref WS 'curve' '=' number
  //    line-loop-angle ::= line-ref WS 'loop' WS 'angle' '=' number
  //    node-accept     ::= node WS 'is' WS 'accepted'
  //
  //    edge         ::= node WS 'to' WS node ('=' label)?
  //                      -- creates a transition nodeA → nodeB, optionally
  //                         labelled. The literal ' to ' is the separator,
  //                         so a node LABEL cannot itself contain ' to '.
  //
  //    node-position   ::= label '=' '(' number ',' number ')'
  //    node-def        ::= nodeId '=' label
  //    blackbox-desc   ::= nodeId WS 'blackbox' '=' text
  //    blackbox-dsl-inline ::= nodeId WS 'blackbox' WS 'dsl' '=' escaped-text
  //    blackbox-dsl-block  ::= nodeId WS 'blackbox' WS 'dsl' WS '{' ... '}'
  //                      -- everything between the braces (which may itself
  //                         be several lines of nested DSL) is extracted by
  //                         _preprocessBlackboxBlocks() BEFORE the main
  //                         line-by-line pass runs, and re-injected as its
  //                         own `nodeId blackbox dsl = ...` entry afterwards.
  //    blackbox-read-tape  ::= nodeId WS 'blackbox' WS 'read'  WS 'tape' '=' int
  //    blackbox-write-tape ::= nodeId WS 'blackbox' WS 'write' WS 'tape' '=' int
  //    blackbox-tapes      ::= nodeId WS 'blackbox' WS 'tapes' '=' int (',' int)*
  //                      -- sets NodeData.blackBoxActiveTapes: the 1-based
  //                         tape indices this box's outgoing-line compact
  //                         triples address, in order (e.g. `tapes = 2,3`).
  //                         Omitted/empty preserves the default positional
  //                         mapping (triple i → tape i+1).
  //
  //    node         ::= label | nodeId '(' label ')'
  //                      -- the `id(label)` form disambiguates when the same
  //                         label is used on more than one node; label alone
  //                         is otherwise resolved to the unique node with
  //                         that label
  //    nodeId       ::= 'n' digit+                -- e.g. n0, n1, n17
  //    line-ref     ::= label | '~' int '(' label ')'
  //                      -- '~N(label)' picks the Nth (0-based) line among
  //                         several sharing the same label, in file order
  //
  //    label        ::= ('<<' text '>>')          -- halt-ACCEPT state
  //                    | ('>>' text '<<')          -- halt-REJECT state
  //                    | text
  //    text         ::= any characters, with '\\' and '\n' escaped as
  //                      '\\\\' and '\\n' respectively (see _escapeDsl /
  //                      _unescapeDsl) so labels can safely contain the
  //                      characters this grammar otherwise treats as
  //                      syntax ('=', 'to', etc).
  //
  //  Transition LABEL payloads (the text after `=` on an `edge` line) are
  //  themselves a nested mini-syntax interpreted by the simulators, not by
  //  this parser — see simulator.dart for FA/PDA/TM label formats
  //  (`read,pop|push` for PDA, `tapeIndex:read,write,L/R/S` for TM, etc).
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a [GraphState] on success, or throws a descriptive [Exception].
  static GraphState importFromDsl(String src) {
    // Preprocess: normalize multi-line blackbox dsl blocks into single lines
    final List<String> workspaces = _preprocessBlackboxBlocks(src);
    src = workspaces[0]; // the "main" source text, with every {...} block stripped out (they live in workspaces[1..])

    final Map<String, NodeData> newNodes = <String, NodeData>{};
    final labelToId = <String, String>{};
    final newLines = <String, LineData>{};
    // Maps label → ordered list of line ids (insertion order = occurrence rank).
    // Multiple lines may share the same label; we keep all ids so ~N(label)
    // references can be resolved correctly after a roundtrip.
    final lineLabelToIds = <String, List<String>>{};
    StartArrowData? newStartArrow;
    int nodeCounter = 0, lineCounter = 0;
    AutomataMode automataMode = AutomataMode.ndfa;

    // Heuristic used to auto-detect PDA mode from a transition label that
    // was never explicitly declared with a `pda mode` line: PDA labels look
    // like "read,pop|push" or "read,pop/push" — comma plus one of the two
    // separators — which a plain FA/TM label would never contain together.
    bool looksLikePdaTransitionLabel(String lbl) {
      final s = lbl.trim();
      if (s.isEmpty) return false;
      return s.contains(',') && (s.contains('|') || s.contains('/'));
    }

    // Resolves a `node` grammar reference (either a bare label, or the
    // disambiguating `id(label)` form) to an existing node's id, or null if
    // no such node has been created yet.
    String? idForLabel(String lbl) {
      lbl = _unescapeDsl(lbl.trim());
      final explicit = RegExp(r'^(n\d+)\((.*)\)$').firstMatch(lbl);
      if (explicit != null) return explicit.group(1); // the "id(label)" form: trust the explicit id directly
      if (newNodes.containsKey(lbl)) return lbl; // caller passed a raw node id (e.g. "n3") directly
      return labelToId[lbl]; // plain label lookup
    }

    /// Resolves [lbl] to a node id, creating a brand-new node (with an
    /// auto-assigned id and default ring-layout position) if none exists
    /// for that label yet. This is what lets a `node` reference anywhere in
    /// the file — not just an explicit `nN = label` line — implicitly
    /// declare a node the first time it's mentioned.
    String ensureNode(String lbl) {
      lbl = _unescapeDsl(lbl);
      bool haltAccept = false, haltReject = false;
      bool hasHaltMarker = false;
      // Halt markers wrap the *entire* label, so they're only recognized
      // when they appear at both ends — this is what lets an ordinary
      // label happen to contain "<<" or ">>" characters without being
      // mistaken for a halt marker.
      if (lbl.startsWith('<<') && lbl.endsWith('>>')) {
        haltAccept = true;
        hasHaltMarker = true;
        lbl = lbl.substring(2, lbl.length - 2);
      } else if (lbl.startsWith('>>') && lbl.endsWith('<<')) {
        haltReject = true;
        hasHaltMarker = true;
        lbl = lbl.substring(2, lbl.length - 2);
      }
      final existing = idForLabel(lbl);
      if (existing != null) {
        // Node already exists (e.g. mentioned earlier as a transition
        // endpoint) — just apply the halt marker to it if this mention
        // carried one, rather than creating a duplicate.
        if (hasHaltMarker) {
          newNodes[existing]!.applyHaltFromLabel(haltAccept: haltAccept, haltReject: haltReject);
        }
        return existing;
      }
      final id = 'n${nodeCounter++}';
      final node = NodeData(
        id: id,
        position: _defaultPosition(newNodes.length),
        label: lbl,
        isHaltAccept: haltAccept,
        isHaltReject: haltReject,
      );
      if (node.isHaltState) node.isAccept = false; // halt states use their own visual, not the accept ring — see NodeData.applyHaltFromLabel
      newNodes[id] = node;
      labelToId[lbl] = id;
      return id;
    }

    // ── Main line-by-line pass: try each statement form in grammar order ────
    for (var rawLine in src.split('\n')) {
      final ci = rawLine.indexOf('#');
      if (ci >= 0) rawLine = rawLine.substring(0, ci); // strip a trailing '#' comment
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // ── pda mode [on|off] / tm mode [on|off] / regex mode [on|off] ────────
      final pdaModeMatch = RegExp(r'^pda\s+mode(?:\s+(on|off))?$', caseSensitive: false).firstMatch(line);
      if (pdaModeMatch != null) {
        final flag = pdaModeMatch.group(1)?.toLowerCase();
        if (flag != 'off') automataMode = AutomataMode.pda; // bare "pda mode" (no on/off) also means on
        continue;
      }
      final tmModeMatch = RegExp(r'^tm\s+mode(?:\s+(on|off))?$', caseSensitive: false).firstMatch(line);
      if (tmModeMatch != null) {
        final flag = tmModeMatch.group(1)?.toLowerCase();
        if (flag != 'off') automataMode = AutomataMode.tm;
        continue;
      }
      final regexModeMatch = RegExp(r'^regex\s+mode(?:\s+(on|off))?$', caseSensitive: false).firstMatch(line);
      if (regexModeMatch != null) {
        final flag = regexModeMatch.group(1)?.toLowerCase();
        if (flag != 'off') automataMode = AutomataMode.regex;
        continue;
      }

      // ── to <node> [length/angle/=label] ──────────────────────────────────
      if (line.toLowerCase().startsWith('to ')) {
        final rest = line.substring(3).trim();

        // "to <node> length = N" — sets shaft length, preserving whatever
        // direction/label a previous "to" line (if any) already set.
        final lengthMatch = RegExp(r'^(.+?)\s+length\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(rest);
        if (lengthMatch != null) {
          final nid = ensureNode(_unescapeDsl(lengthMatch.group(1)!.trim()));
          final len = double.parse(lengthMatch.group(2)!);
          newStartArrow ??= StartArrowData(nodeId: nid);
          // If this "length" line points at a *different* node than the
          // start arrow currently targets, retarget it entirely (dropping
          // the old offset) rather than keeping a stale direction from the
          // previous node; otherwise just update length in place.
          newStartArrow = (newStartArrow.nodeId != nid)
              ? StartArrowData(nodeId: nid, length: len, label: newStartArrow.label)
              : StartArrowData(nodeId: nid, offset: newStartArrow.offset, length: len, label: newStartArrow.label);
          continue;
        }

        // "to <node> angle = dx, dy" — sets direction (as an offset vector).
        final angleMatch = RegExp(
          r'^(.+?)\s+angle\s*=\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)$',
          caseSensitive: false,
        ).firstMatch(rest);
        if (angleMatch != null) {
          final nid = ensureNode(_unescapeDsl(angleMatch.group(1)!.trim()));
          final dx = double.parse(angleMatch.group(2)!);
          final dy = double.parse(angleMatch.group(3)!);
          newStartArrow ??= StartArrowData(nodeId: nid);
          newStartArrow = StartArrowData(
            nodeId: nid,
            offset: Offset(dx, dy),
            length: newStartArrow.length,
            label: newStartArrow.label,
          );
          continue;
        }

        // Plain "to <node>" or "to <node> = label" — declares which node is
        // the start state (and optionally its label), superseding any
        // start arrow set by an earlier "to" line entirely (only one start
        // arrow can exist at a time).
        final eq = rest.indexOf('=');
        if (eq >= 0) {
          final nid = ensureNode(_unescapeDsl(rest.substring(0, eq).trim()));
          newStartArrow = StartArrowData(nodeId: nid, label: _unescapeDsl(rest.substring(eq + 1).trim()));
        } else {
          newStartArrow = StartArrowData(nodeId: ensureNode(_unescapeDsl(rest)));
        }
        continue;
      }

      // ── <line> curve = N ──────────────────────────────────────────────────
      final curveMatch = RegExp(r'^(.+?)\s+curve\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(line);
      if (curveMatch != null) {
        final lid = _resolveLineRef(_unescapeDsl(curveMatch.group(1)!.trim()), newLines, lineLabelToIds);
        if (lid != null) newLines[lid]!.perpendicularPart = double.parse(curveMatch.group(2)!);
        continue;
      }

      // ── <line> loop angle = N ─────────────────────────────────────────────
      final loopMatch = RegExp(r'^(.+?)\s+loop\s+angle\s*=\s*(-?[\d.]+)$', caseSensitive: false).firstMatch(line);
      if (loopMatch != null) {
        final lid = _resolveLineRef(_unescapeDsl(loopMatch.group(1)!.trim()), newLines, lineLabelToIds);
        if (lid != null) newLines[lid]!.selfLoopAngle = double.parse(loopMatch.group(2)!);
        continue;
      }

      // ── <node> is accepted ────────────────────────────────────────────────
      final acceptMatch = RegExp(r'^(.+?)\s+is\s+accepted$', caseSensitive: false).firstMatch(line);
      if (acceptMatch != null) {
        final lbl = _unescapeDsl(acceptMatch.group(1)!.trim());
        final acceptNode = newNodes[idForLabel(lbl) ?? ensureNode(lbl)]!;
        if (acceptNode.canToggleNormalAccept) {
          acceptNode.isAccept = true; // no-op for halt states (canToggleNormalAccept is false for those — see NodeData)
        }
        continue;
      }

      // ── <nodeA> to <nodeB> [= label] ──────────────────────────────────────
      final toIdx = _findToSeparator(line);
      if (toIdx >= 0) {
        final leftPart = _unescapeDsl(line.substring(0, toIdx).trim());
        final rightPart = line.substring(toIdx + 4).trim(); // +4 skips past the ' to ' separator itself
        String lineLabel = '', nodeBLabel = rightPart;
        final eq = rightPart.indexOf('=');
        if (eq >= 0) {
          nodeBLabel = _unescapeDsl(rightPart.substring(0, eq).trim());
          lineLabel = _unescapeDsl(rightPart.substring(eq + 1).trim());
        }
        final idA = ensureNode(leftPart), idB = ensureNode(nodeBLabel);
        // Halt states can't have outgoing transitions (see
        // NodeData.canHaveOutgoingTransitions) — silently drop any edge
        // whose source is a halt state rather than erroring the whole import.
        if (newNodes[idA]!.canHaveOutgoingTransitions) {
          final lid = 'l${lineCounter++}';
          newLines[lid] = LineData(id: lid, nodeAId: idA, nodeBId: idB, label: lineLabel);
          newNodes[idA]!.connectedLineIds.add(lid);
          newNodes[idB]!.connectedLineIds.add(lid);
          // Auto-detect PDA mode from the label shape if no explicit `pda
          // mode` line appeared earlier in the file.
          if (lineLabel.isNotEmpty && looksLikePdaTransitionLabel(lineLabel)) {
            if (automataMode == AutomataMode.ndfa) automataMode = AutomataMode.pda;
          }
          if (lineLabel.isNotEmpty) {
            lineLabelToIds.putIfAbsent(lineLabel, () => []).add(lid);
          }
        }
        continue;
      }

      // ── label = (x, y) ───────────────────────────────────────────────────
      final posMatch = RegExp(r'^(.+?)\s*=\s*\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)$').firstMatch(line);
      if (posMatch != null) {
        final lbl = _unescapeDsl(posMatch.group(1)!.trim());
        final nid = idForLabel(lbl) ?? ensureNode(lbl);
        newNodes[nid]!.position = Offset(double.parse(posMatch.group(2)!), double.parse(posMatch.group(3)!));
        continue;
      }

      // ── nN = label ───────────────────────────────────────────────────────
      final nodeDefMatch = RegExp(r'^(n\d+)\s*=\s*(.*)$').firstMatch(line);
      if (nodeDefMatch != null) {
        final id = nodeDefMatch.group(1)!;
        var lbl = _unescapeDsl(nodeDefMatch.group(2)!.trim());
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1; // keep the counter ahead of any explicit id seen, so later auto-generated ids never collide

        bool haltAccept = false, haltReject = false;
        if (lbl.startsWith('<<') && lbl.endsWith('>>')) {
          haltAccept = true;
          lbl = lbl.substring(2, lbl.length - 2);
        } else if (lbl.startsWith('>>') && lbl.endsWith('<<')) {
          haltReject = true;
          lbl = lbl.substring(2, lbl.length - 2);
        }

        if (!newNodes.containsKey(id)) {
          final node = NodeData(
            id: id,
            position: _defaultPosition(newNodes.length),
            label: lbl,
            isHaltAccept: haltAccept,
            isHaltReject: haltReject,
          );
          if (node.isHaltState) node.isAccept = false;
          newNodes[id] = node;
        } else {
          // Node was already implicitly created (e.g. referenced by an
          // earlier transition line before its own `nN = label` line
          // appeared) — update it in place rather than creating a duplicate.
          newNodes[id]!.label = lbl;
          newNodes[id]!.applyHaltFromLabel(haltAccept: haltAccept, haltReject: haltReject);
        }
        if (lbl.isNotEmpty) labelToId[lbl] = id;
        continue;
      }

      // ── nN blackbox = description ────────────────────────────────────────
      final blackBoxDefMatch = RegExp(r'^(n\d+)\s+blackbox\s*=\s*(.*)$', caseSensitive: false).firstMatch(line);
      if (blackBoxDefMatch != null) {
        final id = blackBoxDefMatch.group(1)!;
        final desc = _unescapeDsl(blackBoxDefMatch.group(2)!.trim());
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        final node = newNodes[id] ?? NodeData(id: id, position: _defaultPosition(newNodes.length));
        node.isBlackBox = true;
        node.blackBoxDescription = desc;
        if (node.label.trim().isEmpty) {
          node.label = 'BB ${id.toUpperCase()}'; // placeholder label so a blackbox node created purely via this line still shows something
        }
        newNodes[id] = node;
        continue;
      }

      // ── nN blackbox dsl = <escaped> ──────────────────────────────────────
      // (inline single-line form — the block form is handled after this loop
      //  via the workspaces post-processing pass below)
      final blackBoxDslMatch = RegExp(r'^(n\d+)\s+blackbox\s+dsl\s*=\s*(.*)$', caseSensitive: false).firstMatch(line);
      if (blackBoxDslMatch != null) {
        final id = blackBoxDslMatch.group(1)!;
        final encoded = blackBoxDslMatch.group(2)!.trim();
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        final node = newNodes[id] ?? NodeData(id: id, position: _defaultPosition(newNodes.length));
        node.isBlackBox = true;
        node.blackBoxDsl = _decodeMaybeLegacyBase64(encoded);
        if (node.label.trim().isEmpty) {
          node.label = 'BB ${id.toUpperCase()}';
        }
        newNodes[id] = node;
        continue;
      }

      // ── nN blackbox read tape = N ────────────────────────────────────────
      final bbReadTapeMatch = RegExp(r'^(n\d+)\s+blackbox\s+read\s+tape\s*=\s*(\d+)$', caseSensitive: false).firstMatch(line);
      if (bbReadTapeMatch != null) {
        final id = bbReadTapeMatch.group(1)!;
        final tapeNum = int.tryParse(bbReadTapeMatch.group(2)!) ?? 1;
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        final node = newNodes[id] ?? NodeData(id: id, position: _defaultPosition(newNodes.length));
        node.isBlackBox = true;
        node.blackBoxReadTape = tapeNum < 1 ? 1 : tapeNum; // guard against a malformed "0" or negative value in hand-edited DSL
        if (node.label.trim().isEmpty) {
          node.label = 'BB ${id.toUpperCase()}';
        }
        newNodes[id] = node;
        continue;
      }

      // ── nN blackbox write tape = N ───────────────────────────────────────
      final bbWriteTapeMatch = RegExp(r'^(n\d+)\s+blackbox\s+write\s+tape\s*=\s*(\d+)$', caseSensitive: false).firstMatch(line);
      if (bbWriteTapeMatch != null) {
        final id = bbWriteTapeMatch.group(1)!;
        final tapeNum = int.tryParse(bbWriteTapeMatch.group(2)!) ?? 1;
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        final node = newNodes[id] ?? NodeData(id: id, position: _defaultPosition(newNodes.length));
        node.isBlackBox = true;
        node.blackBoxWriteTape = tapeNum < 1 ? 1 : tapeNum;
        if (node.label.trim().isEmpty) {
          node.label = 'BB ${id.toUpperCase()}';
        }
        newNodes[id] = node;
        continue;
      }

      // ── nN blackbox tapes = N[,N...] ─────────────────────────────────────
      final bbActiveTapesMatch = RegExp(r'^(n\d+)\s+blackbox\s+tapes\s*=\s*([\d,\s]+)$', caseSensitive: false).firstMatch(line);
      if (bbActiveTapesMatch != null) {
        final id = bbActiveTapesMatch.group(1)!;
        final tapes = bbActiveTapesMatch.group(2)!
            .split(',')
            .map((t) => int.tryParse(t.trim()))
            .whereType<int>() // drops any unparseable entries
            .where((t) => t >= 1) // drops any non-positive (invalid tape index) entries
            .toList();
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
        final node = newNodes[id] ?? NodeData(id: id, position: _defaultPosition(newNodes.length));
        node.isBlackBox = true;
        node.blackBoxActiveTapes = tapes;
        if (node.label.trim().isEmpty) {
          node.label = 'BB ${id.toUpperCase()}';
        }
        newNodes[id] = node;
        continue;
      }

      // ── bare label → create node ─────────────────────────────────────────
      // Nothing else matched: per the grammar's `bare-node` fallback, treat
      // the whole line as a label and materialize an isolated node for it.
      ensureNode(_unescapeDsl(line));
    }

    // ── Apply blackbox DSL payloads from the preprocessed workspace entries ──
    //
    // _preprocessBlackboxBlocks() extracted every  `nN blackbox dsl { ... }`
    // block into workspaces[1], workspaces[2], … as a single escaped line of
    // the form:
    //
    //   n2 blackbox dsl = <escaped dsl content>
    //
    // The main loop above handles the inline `nN blackbox dsl = ...` form when
    // it appears literally in workspaces[0], but the block-format payloads live
    // in the extra workspace slots and were deliberately excluded from the main
    // source text.  We apply them here, after all nodes have been created.
    for (int i = 1; i < workspaces.length; i++) {
      final entry = workspaces[i].trim();
      if (entry.isEmpty) continue;

      final bbDslMatch = RegExp(
        r'^(n\d+)\s+blackbox\s+dsl\s*=\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(entry);
      if (bbDslMatch == null) continue;

      final id = bbDslMatch.group(1)!;
      final encoded = bbDslMatch.group(2)!.trim();
      final num = int.tryParse(id.substring(1)) ?? -1;
      if (num >= nodeCounter) nodeCounter = num + 1;

      // The node must already exist from the `nN blackbox = description` line
      // in the main DSL body.  Create a shell only if something went wrong.
      if (!newNodes.containsKey(id)) {
        newNodes[id] = NodeData(
          id: id,
          position: _defaultPosition(newNodes.length),
        );
      }

      final node = newNodes[id]!;
      node.isBlackBox = true;
      node.blackBoxDsl = _decodeMaybeLegacyBase64(encoded);

      if (node.label.trim().isEmpty) {
        node.label = 'BB ${id.toUpperCase()}';
      }
    }

    return GraphState(
      nodes: newNodes,
      lines: newLines,
      startArrow: newStartArrow,
      nodeCounter: nodeCounter,
      lineCounter: lineCounter,
      automataMode: automataMode,
    );
  }

  // ── SVG IMPORT ─────────────────────────────────────────────────────────────

  /// Reads back a [GraphState] previously written by [SvgExporter] — the SVG
  /// itself is only a visual rendering; the actual round-trippable data
  /// lives in a `<script id="automata-data">` JSON payload embedded in it
  /// (see SvgExporter.export below), which is all this method actually reads.
  static GraphState importFromSvg(String svg) {
    final scriptMatch = RegExp(r'<script[^>]*id="automata-data"[^>]*>(.*?)</script>', dotAll: true).firstMatch(svg);

    if (scriptMatch == null) throw Exception('No embedded automata data found.');

    final data = jsonDecode(scriptMatch.group(1)!.trim()) as Map<String, dynamic>;
    final newNodes = <String, NodeData>{};
    final newLines = <String, LineData>{};
    AutomataMode automataMode = AutomataMode.ndfa;

    // Same PDA-label heuristic as importFromDsl — SVG's JSON payload has no
    // separate mode field, so mode is inferred purely from transition
    // label shape here.
    bool looksLikePdaTransitionLabel(String lbl) {
      final s = lbl.trim();
      if (s.isEmpty) return false;
      return s.contains(',') && (s.contains('|') || s.contains('/'));
    }

    for (final n in data['nodes'] as List) {
      final node = NodeData(
        id: n['id'] as String,
        position: Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble()),
        label: (n['label'] as String?) ?? '',
        isAccept: n['accept'] == true,
        isHaltAccept: n['haltAccept'] == true,
        isHaltReject: n['haltReject'] == true,
      );
      if (node.isHaltState) node.isAccept = false;
      newNodes[node.id] = node;
    }

    for (final l in data['lines'] as List) {
      final nodeAId = l['a'] as String;
      if (newNodes[nodeAId]?.canHaveOutgoingTransitions != true) continue; // drop edges sourced from a halt state, same as DSL import

      final line =
          LineData(
              id: l['id'] as String,
              nodeAId: nodeAId,
              nodeBId: l['b'] as String,
              label: (l['label'] as String?) ?? '',
            )
            ..perpendicularPart = (l['curve'] as num?)?.toDouble() ?? 0
            ..selfLoopAngle = (l['loopAngle'] as num?)?.toDouble() ?? 0;
      newLines[line.id] = line;
      newNodes[line.nodeAId]?.connectedLineIds.add(line.id);
      newNodes[line.nodeBId]?.connectedLineIds.add(line.id);

      if (line.label.isNotEmpty && looksLikePdaTransitionLabel(line.label)) {
        if (automataMode == AutomataMode.ndfa) automataMode = AutomataMode.pda;
      }
    }

    StartArrowData? startArrow;
    if (data['startArrow'] != null) {
      final sa = data['startArrow'] as Map<String, dynamic>;
      startArrow = StartArrowData(
        nodeId: sa['nodeId'] as String,
        offset: Offset((sa['dx'] as num).toDouble(), (sa['dy'] as num).toDouble()),
        length: (sa['length'] as num).toDouble(),
        label: (sa['label'] as String?) ?? '',
      );
    }

    // Unlike DSL import (which tracks nodeCounter/lineCounter incrementally
    // as ids are assigned), SVG's ids already exist verbatim in the JSON —
    // so the counters are instead derived after the fact by scanning for
    // the highest numeric suffix actually used, ensuring future new
    // nodes/lines still get fresh, non-colliding ids.
    int highestNode = 0, highestLine = 0;
    for (final id in newNodes.keys) {
      highestNode = max(highestNode, (int.tryParse(id.substring(1)) ?? 0) + 1);
    }
    for (final id in newLines.keys) {
      highestLine = max(highestLine, (int.tryParse(id.substring(1)) ?? 0) + 1);
    }

    return GraphState(
      nodes: newNodes,
      lines: newLines,
      startArrow: startArrow,
      nodeCounter: highestNode,
      lineCounter: highestLine,
      automataMode: automataMode,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────
  /// Preprocesses DSL to convert multi-line blackbox blocks into single-line
  /// format for easier parsing. Converts:
  ///   n0 blackbox dsl {
  ///     n0 = A
  ///     n1 = B
  ///   }
  /// Into: n0 blackbox dsl = n0 = A\nn1 = B
  static List<String> _preprocessBlackboxBlocks(String src) {
    final returns = <String>[""]; // returns[0] will become the "main" workspace text; returns[1..] hold one extracted block payload each
    final lines = src.split('\n');
    final result = <String>[]; // list of lines that are the "main workspace"
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      final blockMatch = RegExp(r'^(n\d+)\s+blackbox\s+dsl\s*{\s*$', caseSensitive: false).firstMatch(line);
      if (blockMatch != null) {
        final nodeId = blockMatch.group(1)!;
        final blockLines = <String>[];
        i++;
        // Collect lines until closing brace
        while (i < lines.length) {
          final rawLine = lines[i];
          final trimmedLine = rawLine.trim();
          if (trimmedLine == '}' || trimmedLine == '} #') break;
          if (trimmedLine.isEmpty) {
            blockLines.add('');
            i++;
            continue;
          }

          // The block's own lines are indented by 2 spaces or a tab in the
          // exported form (see exportToDsl's "  $dslLine" above) — strip
          // exactly one level of that indentation back off so the nested
          // DSL's own content isn't left permanently re-indented.
          String contentLine = rawLine;
          if (contentLine.startsWith('  ')) {
            contentLine = contentLine.substring(2);
          } else if (contentLine.startsWith('\t')) {
            contentLine = contentLine.substring(1);
          }
          blockLines.add(contentLine);
          i++;
        }
        // Convert back to escaped format for old parser
        final String dslContent = blockLines.join('\n');
        returns.add('$nodeId blackbox dsl = ${_escapeDsl(dslContent)}');
      } else {
        result.add(lines[i]);
      }
      i++;
    }
    returns[0] = result.join('\n');
    return returns;
  }

  /// Decodes a blackbox DSL value that may be either the new plain-escaped
  /// text format or the old base64 format (for backward compatibility).
  ///
  /// A pure base64 string only contains `[A-Za-z0-9+/=]`.  A DSL string
  /// almost always contains spaces, newline escapes (`\n`), `=` signs inside
  /// node definitions, etc.  We use that distinction as a heuristic.
  static String _decodeMaybeLegacyBase64(String encoded) {
    final isLikelyBase64 = encoded.isNotEmpty && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(encoded);
    if (isLikelyBase64) {
      try {
        return utf8.decode(base64Decode(encoded));
      } catch (_) {
        // Not valid base64 after all — fall through to plain-text decode.
      }
    }
    return _unescapeDsl(encoded);
  }

  /// Resolves a `line-ref` grammar reference to an internal line id, trying
  /// each accepted form in turn: the new `~N(label)` occurrence-index form,
  /// the legacy explicit `lN(label)` form, a raw internal id, a 1-based
  /// "lN" the user might type by hand, and finally a plain label lookup.
  static String? _resolveLineRef(String lbl, Map<String, LineData> lines, Map<String, List<String>> lineLabelToIds) {
    // New occurrence-index form:  ~N(label) → Nth line (0-based) with that label
    final rankMatch = RegExp(r'^~(\d+)\((.*)\)$', dotAll: true).firstMatch(lbl);
    if (rankMatch != null) {
      final rank = int.tryParse(rankMatch.group(1)!) ?? 0;
      final label = _unescapeDsl(rankMatch.group(2)!);
      final ids = lineLabelToIds[label];
      if (ids != null && rank < ids.length) return ids[rank];
      return null;
    }
    // Legacy explicit-id form:  lN(label) → kept for backward compat, use id directly
    final explicit = RegExp(r'^(l\d+)\((.*)\)$', dotAll: true).firstMatch(lbl);
    if (explicit != null) return explicit.group(1);
    if (lines.containsKey(lbl)) return lbl;
    // Accept 1-based numeric line ids in DSL (e.g. "l1") by mapping them
    // to the internal zero-based ids ("l0"). This makes the DSL friendlier
    // for users who expect 1-based numbering while keeping internal ids as-is.
    final oneBasedMatch = RegExp(r'^l(\d+)$').firstMatch(lbl);
    if (oneBasedMatch != null) {
      final num = int.tryParse(oneBasedMatch.group(1)!) ?? 0;
      if (num > 0) {
        final candidate = 'l${num - 1}';
        if (lines.containsKey(candidate)) return candidate;
      }
    }
    // Plain label lookup: use the first recorded id for this label
    final ids = lineLabelToIds[lbl];
    return ids?.isNotEmpty == true ? ids!.first : null;
  }

  /// Finds the index of the ' to ' separator (space-to-space) in an `edge`
  /// statement — a manual char scan rather than a regex, since the
  /// separator has to be located *before* the left/right sides are each
  /// independently unescaped and reparsed (a regex split would need to
  /// somehow avoid matching ' to ' sequences that are part of an escaped
  /// label, which this scan sidesteps by operating on the still-escaped
  /// raw line first).
  static int _findToSeparator(String s) {
    for (int i = 0; i < s.length - 3; i++) {
      if (s[i] == ' ' && s.substring(i + 1, i + 3).toLowerCase() == 'to' && s[i + 3] == ' ') return i;
    }
    return -1;
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// SECTION: latex_export.dart
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  LatexExporter
//
//  Produces a self-contained LaTeX document using the `tikz` and `automata`
//  packages.  The generated code can be pasted into any LaTeX project and
//  compiled with pdflatex / xelatex / lualatex.
//
//  Round-trip:  DSL  →  LaTeX  (export)
//               LaTeX tikzpicture  →  DSL  (import via LatexImporter)
//
//  Encoding conventions (used by both exporter and importer):
//  • Node ids are stored as tikz node names:  state_n0, state_n1, …
//  • Accept states: [accepting]
//  • Initial state: [initial]
//  • Self-loops:   edge [loop above] etc.  The loop direction is derived from
//    selfLoopAngle.
//  • Multi-label lines are emitted as separate \path edges, one per alternative
//    (comma-/newline-separated in the DSL).
//  • Curved lines (perpendicularPart ≠ 0) use  edge [bend left=N] or
//    edge [bend right=N].  N is clamped to [5, 80] degrees.
//  • Unicode symbols (~, ∅, λ …) are wrapped in $…$ math mode.
//  • Position: we convert canvas px → pt  by dividing by 2.
//    On import we multiply pt × 2 to recover approximate canvas coordinates.
// ─────────────────────────────────────────────────────────────────────────────

// Characters that need no math wrapping (plain ASCII printable, no LaTeX specials).
final _plainAscii = RegExp(r'^[A-Za-z0-9 _\-+*/=<>!;:@#%^&|()[\]{}]+$');

// LaTeX special characters that must be escaped outside math mode.
const _latexEscapes = {
  '\\': r'\textbackslash{}',
  '&': r'\&',
  '%': r'\%',
  '\$': r'\$',
  '#': r'\#',
  '_': r'\_',
  '{': r'\{',
  '}': r'\}',
  '~': r'\textasciitilde{}',
  '^': r'\textasciicircum{}',
};

// Known unicode symbols → LaTeX math equivalents. Also used in reverse
// (see _latexLabelToDsl below) to recover the original unicode on import.
const _unicodeToLatex = {
  '~': r'\varepsilon',
  'λ': r'\lambda',
  '∅': r'\emptyset',
  '∈': r'\in',
  '∉': r'\notin',
  '∪': r'\cup',
  '∩': r'\cap',
  '⊆': r'\subseteq',
  '⊇': r'\supseteq',
  '⊂': r'\subset',
  '⊃': r'\supset',
  '→': r'\rightarrow',
  '←': r'\leftarrow',
  '↔': r'\leftrightarrow',
  '↑': r'\uparrow',
  '↓': r'\downarrow',
  '¬': r'\neg',
  '∧': r'\wedge',
  '∨': r'\vee',
  '⊕': r'\oplus',
  '∀': r'\forall',
  '∃': r'\exists',
  '≤': r'\leq',
  '≥': r'\geq',
  '≠': r'\neq',
  '≈': r'\approx',
  '∞': r'\infty',
  '√': r'\sqrt{}',
  '×': r'\times',
  '÷': r'\div',
  '±': r'\pm',
  '·': r'\cdot',
  'α': r'\alpha',
  'β': r'\beta',
  'γ': r'\gamma',
  'δ': r'\delta',
  'η': r'\eta',
  'θ': r'\theta',
  'ι': r'\iota',
  'κ': r'\kappa',
  'μ': r'\mu',
  'ξ': r'\xi',
  'π': r'\pi',
  'ρ': r'\rho',
  'σ': r'\sigma',
  'τ': r'\tau',
  'φ': r'\varphi',
  'χ': r'\chi',
  'ψ': r'\psi',
  'ω': r'\omega',
  'Γ': r'\Gamma',
  'Δ': r'\Delta',
  'Θ': r'\Theta',
  'Λ': r'\Lambda',
  'Ξ': r'\Xi',
  'Π': r'\Pi',
  'Σ': r'\Sigma',
  'Φ': r'\Phi',
  'Ψ': r'\Psi',
  'Ω': r'\Omega',
  '⊔': r'\sqcup',   // TM blank
  '⊢': r'\vdash',
  '⊣': r'\dashv',
};

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Convert a canvas-pixel coordinate to a LaTeX/tikz pt value.
String _toPt(double px) => (px / 2).toStringAsFixed(1);

/// Convert a tikz pt value back to a canvas pixel offset.
double _fromPt(double pt) => pt * 2;

/// Convert a node id (e.g. "n3") to a safe tikz node name ("state_n3").
String _tikzName(String id) => 'state_$id';


/// Determine the loop direction for self-loop tikz style from [selfLoopAngle]
/// (radians, measured from +x axis, same convention as the canvas).
String _loopDir(double angle) {
  // Angle is the direction the loop bulges outward from the node centre.
  // Normalise to [0, 2π).
  final a = (angle % (2 * pi) + 2 * pi) % (2 * pi);
  if (a >= 7 * pi / 4 || a < pi / 4) return 'loop right';
  if (a >= pi / 4 && a < 3 * pi / 4) return 'loop below';
  if (a >= 3 * pi / 4 && a < 5 * pi / 4) return 'loop left';
  return 'loop above';
}

/// Reverse: return the approximate selfLoopAngle for a given tikz loop keyword.
double _angleFromLoopDir(String dir) {
  switch (dir.trim().toLowerCase()) {
    case 'loop right':  return 0.0;
    case 'loop below':  return pi / 2;
    case 'loop left':   return pi;
    case 'loop above':
    default:            return -pi / 2;
  }
}

/// Convert a DSL label token to a LaTeX label string suitable for edge labels.
/// Single unicode chars are wrapped in $…$.  Plain ASCII is left as-is.
/// Multi-character strings get individual character treatment joined together.
String _labelToLatex(String token) {
  token = token.trim();
  if (token.isEmpty || token == '~') return r'$\varepsilon$';

  // Check if the whole token is plain ASCII (no LaTeX specials) → use as-is.
  if (_plainAscii.hasMatch(token)) return token;

  // Otherwise, convert character by character.
  final buf = StringBuffer();
  bool inMath = false;

  // Math mode is opened/closed lazily around runs of characters that need
  // it, rather than wrapping the whole token in one $…$ — this lets a
  // label mixing plain ASCII and math symbols (e.g. "a→b") come out as
  // "a$\rightarrow$b" instead of unnecessarily putting the plain letters
  // in math mode too.
  void closeMath() {
    if (inMath) { buf.write(r'$'); inMath = false; }
  }

  void openMath() {
    if (!inMath) { buf.write(r'$'); inMath = true; }
  }

  for (final ch in token.characters) {
    final latexMath = _unicodeToLatex[ch];
    if (latexMath != null) {
      openMath();
      buf.write(latexMath);
    } else if (_latexEscapes.containsKey(ch)) {
      closeMath();
      buf.write(_latexEscapes[ch]);
    } else {
      // Plain character — keep in current mode.
      buf.write(ch);
    }
  }
  closeMath(); // in case the token ended while still inside math mode
  return buf.toString();
}

/// Best-effort reverse: strip $…$ delimiters and convert known LaTeX math
/// commands back to their unicode equivalents.  Used by the importer.
String _latexLabelToDsl(String tex) {
  tex = tex.trim();

  // Full tilda shortcuts.
  if (tex == r'$\varepsilon$' || tex == r'$\tilda$' || tex == r'\varepsilon' || tex == r'\tilda') {
    return '~';
  }

  // Strip outer $…$ if present.
  if (tex.startsWith(r'$') && tex.endsWith(r'$') && tex.length > 2) {
    tex = tex.substring(1, tex.length - 1);
  }

  // Replace known LaTeX commands with unicode.
  final reversed = Map.fromEntries(_unicodeToLatex.entries.map((e) => MapEntry(e.value, e.key)));
  // Sort by key length descending so longer commands are matched first —
  // otherwise replacing the shorter r'\eta' before r'\theta' would corrupt
  // '\theta' (which contains '\eta' as a substring) into garbage.
  final sorted = reversed.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));

  for (final e in sorted) {
    tex = tex.replaceAll(e.key, e.value);
  }

  // Unescape basic LaTeX specials.
  tex = tex
      .replaceAll(r'\textbackslash{}', '\\')
      .replaceAll(r'\&', '&')
      .replaceAll(r'\%', '%')
      .replaceAll(r'\$', '\$')
      .replaceAll(r'\#', '#')
      .replaceAll(r'\_', '_')
      .replaceAll(r'\{', '{')
      .replaceAll(r'\}', '}')
      .replaceAll(r'\textasciitilde{}', '~')
      .replaceAll(r'\textasciicircum{}', '^');

  return tex;
}

// ─────────────────────────────────────────────────────────────────────────────
//  LatexExporter
// ─────────────────────────────────────────────────────────────────────────────

/// Exports a graph to LaTeX-friendly text for documentation or sharing.
class LatexExporter {
  const LatexExporter._();

  /// Export a [GraphState] to a complete, compilable LaTeX document string.
  static String export(GraphState g) {
    final buf = StringBuffer();

    buf.writeln(r'% ──────────────────────────────────────────────────────────');
    buf.writeln(r'% Automata Designer – LaTeX export');
    buf.writeln(r'% Compile with: pdflatex / xelatex / lualatex');
    buf.writeln(r'% Required packages: tikz, automata (loaded below)');
    buf.writeln(r'% ──────────────────────────────────────────────────────────');
    buf.writeln(r'\documentclass[tikz,border=10pt]{standalone}');
    buf.writeln(r'\usepackage{tikz}');
    buf.writeln(r'\usetikzlibrary{automata,positioning,arrows.meta}');
    buf.writeln(r'\begin{document}');
    buf.writeln(r'\begin{tikzpicture}[');
    buf.writeln(r'  >={Stealth[round]},');
    buf.writeln(r'  shorten >=1pt,');
    buf.writeln(r'  auto,');
    buf.writeln(r'  node distance=2.8cm,');
    buf.writeln(r'  on grid,');
    buf.writeln(r'  semithick,');
    buf.writeln(r'  initial text=,');   // suppress "start" text on initial arrow
    buf.writeln(r']');

    // ── Comment that encodes the mode so the importer can recover it ──────
    final modeComment = switch (g.automataMode) {
      AutomataMode.pda   => '% mode: pda',
      AutomataMode.tm    => '% mode: tm',
      AutomataMode.ndfa  => '% mode: ndfa',
      AutomataMode.regex => '% mode: regex',
    };
    buf.writeln(modeComment);
    buf.writeln();

    // ── Node definitions ──────────────────────────────────────────────────
    //
    // Format:
    //   \node[state, <options>] (state_nN) at (Xpt, Ypt) {label};
    //
    // Options added as needed:
    //   initial       – start state (has start arrow pointing to it)
    //   accepting     – normal double-ring accept state
    //   accepting by double – same (alias sometimes preferred)

    final startNodeId = g.startArrow?.nodeId;

    for (final node in g.nodes.values) {
      final name = _tikzName(node.id);
      // Canvas position is stored as the node's top-left corner; shift by
      // the node's own centre offset (140x100 rect for black boxes vs
      // 100x100 circle otherwise — matches NodeData.center) before
      // converting to tikz points, so the exported coordinate is the
      // node's visual centre, not its corner.
      final xPt = _toPt(node.position.dx + (node.isBlackBox ? 70 : 50));
      final yPt = _toPt(-(node.position.dy + (node.isBlackBox ? 50 : 50))); // flip y for tikz

      final options = <String>['state'];

      if (node.id == startNodeId) options.add('initial');
      if (node.isAccept && !node.isHaltState) options.add('accepting');
      if (node.isHaltAccept) options.add('accepting');   // halt-accept → accept ring
      if (node.isHaltReject) {
        // Represented as a dashed border; we annotate with a comment.
        options.add('draw=red!70');
      }
      if (node.isBlackBox) options.add('rectangle');     // black-box → box shape

      // Store the original node id in a comment for round-trip fidelity.
      final displayLabel = node.label.trim().isEmpty
          ? nodeIdToAlpha(node.id)
          : node.label;
      final latexLabel = _labelToLatex(displayLabel);

      // id comment so importer can recover node id → label mapping
      buf.writeln(
        '\\node[${options.join(", ")}] '
        '($name) at (${xPt}pt, ${yPt}pt) '
        '{$latexLabel}; % id=${node.id}',
      );
    }
    buf.writeln();

    // ── Edges ─────────────────────────────────────────────────────────────
    //
    // We group outgoing edges from each node together.
    //
    // Format:
    //   \path[->] (state_nA) edge [<opts>] node {label} (state_nB);
    //
    // Bend: perpendicularPart → bend left / bend right with clamped angle.
    // Self-loop: loop above / loop below / loop left / loop right.

    for (final line in g.lines.values) {
      final nodeA = g.nodes[line.nodeAId];
      final nodeB = g.nodes[line.nodeBId];
      if (nodeA == null || nodeB == null) continue;

      final nameA = _tikzName(line.nodeAId);
      final nameB = _tikzName(line.nodeBId);

      // Determine edge style.
      final edgeOpts = <String>[];
      final isSelfLoop = line.nodeAId == line.nodeBId;

      if (isSelfLoop) {
        edgeOpts.add(_loopDir(line.selfLoopAngle));
      } else if (line.perpendicularPart.abs() > 5) {
        // Map perpendicularPart (canvas px, signed) to bend angle (1–80 deg).
        final angle = (line.perpendicularPart.abs() / 3).clamp(5.0, 80.0).round();
        edgeOpts.add(line.perpendicularPart > 0 ? 'bend left=$angle' : 'bend right=$angle');
      }

      // Each DSL alternative becomes a separate edge for clarity.
      final alternatives = line.labelAlternatives;

      for (final alt in alternatives) {
        final latexLabel = _labelToLatex(alt);
        final optsStr = edgeOpts.isEmpty ? '' : '[${edgeOpts.join(", ")}]';
        buf.writeln(
          '\\path[->] ($nameA) edge $optsStr node {$latexLabel} ($nameB);'
          ' % lid=${line.id}',
        );
      }
    }

    // ── Start-arrow label (if non-empty) ──────────────────────────────────
    // Only recorded as a comment (LaTeX's `initial` option draws the arrow
    // itself with no room for custom label text) — LatexImporter reads it
    // back from this comment on re-import.
    if (g.startArrow != null && g.startArrow!.label.trim().isNotEmpty) {
      final startNode = g.nodes[g.startArrow!.nodeId];
      if (startNode != null) {
        buf.writeln();
        buf.writeln(
          '% start arrow label: ${_labelToLatex(g.startArrow!.label)}',
        );
      }
    }

    buf.writeln();
    buf.writeln(r'\end{tikzpicture}');
    buf.writeln(r'\end{document}');

    return buf.toString();
  }

  /// Export just the inner `tikzpicture` block (no document wrapper).
  /// Useful for embedding in an existing LaTeX document.
  static String exportSnippet(GraphState g) {
    final full = export(g);
    // Extract between \begin{tikzpicture} and \end{tikzpicture} (inclusive).
    final start = full.indexOf(r'\begin{tikzpicture}');
    final end = full.indexOf(r'\end{tikzpicture}') + r'\end{tikzpicture}'.length;
    if (start < 0 || end < r'\end{tikzpicture}'.length) return full; // markers not found: fall back to returning the whole document rather than a broken substring
    return full.substring(start, end);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LatexImporter
//
//  Parses a LaTeX tikzpicture (or full document) that was produced by
//  [LatexExporter] and reconstructs a [GraphState].
//
//  The parser is intentionally lenient: it tolerates comments, extra options,
//  and minor formatting differences.  It falls back gracefully when it cannot
//  recover an original node id from the % id=nN comment.
// ─────────────────────────────────────────────────────────────────────────────

/// Imports LaTeX-generated automata descriptions back into the editor graph.
class LatexImporter {
  const LatexImporter._();

  /// Parse [src] (full document or bare tikzpicture) into a [GraphState].
  /// Throws a descriptive [FormatException] if the input cannot be parsed.
  static GraphState import(String src) {
    // ── Mode detection from comment ───────────────────────────────────────
    AutomataMode mode = AutomataMode.ndfa;
    if (RegExp(r'%\s*mode:\s*pda', caseSensitive: false).hasMatch(src)) {
      mode = AutomataMode.pda;
    } else if (RegExp(r'%\s*mode:\s*tm', caseSensitive: false).hasMatch(src)) {
      mode = AutomataMode.tm;
    } else if (RegExp(r'%\s*mode:\s*regex', caseSensitive: false).hasMatch(src)) {
      mode = AutomataMode.regex;
    }

    // ── Extract tikzpicture content ───────────────────────────────────────
    // Accepts either a bare tikzpicture snippet or a full document — if no
    // \begin{tikzpicture}...\end{tikzpicture} wrapper is found, just treat
    // the whole input as the body (lets a user paste a raw snippet without
    // the wrapper and still have it parse).
    final picMatch = RegExp(
      r'\\begin\{tikzpicture\}(.*?)\\end\{tikzpicture\}',
      dotAll: true,
    ).firstMatch(src);
    final body = picMatch != null ? picMatch.group(1)! : src;

    // ── Parse \node lines ─────────────────────────────────────────────────
    //
    // Pattern:
    //   \node[<options>] (<n>) at (<x>pt, <y>pt) {<label>}; % id=nN
    //
    // We use a regex that captures the key groups; options/label may span
    // multiple tokens but the semicolon always terminates the statement.

    final nodeRe = RegExp(
      r'\\node\s*\[([^\]]*)\]\s*\(([^)]+)\)\s*at\s*\((-?[\d.]+)pt\s*,\s*(-?[\d.]+)pt\s*\)\s*\{([^}]*)\}\s*;'
      r'(?:[^\n]*%\s*id=(n\d+))?',
      multiLine: true,
    );

    final newNodes = <String, NodeData>{};
    final tikzNameToId = <String, String>{};   // tikz name → internal id
    int nodeCounter = 0;
    String? initialNodeId;

    for (final m in nodeRe.allMatches(body)) {
      final optStr  = m.group(1)!;
      final tikzName = m.group(2)!;
      final xPt     = double.tryParse(m.group(3)!) ?? 0.0;
      final yPt     = double.tryParse(m.group(4)!) ?? 0.0;
      final rawLabel = m.group(5)!.trim();
      final commentId = m.group(6); // may be null if no % id= comment

      // Recover (or assign) an internal id.
      // A file exported by this app always carries the % id=nN comment; a
      // hand-written tikzpicture (or one edited to drop the comments)
      // instead falls back to assigning fresh sequential ids here.
      String id;
      if (commentId != null) {
        id = commentId;
        final num = int.tryParse(id.substring(1)) ?? -1;
        if (num >= nodeCounter) nodeCounter = num + 1;
      } else {
        id = 'n${nodeCounter++}';
      }

      // Parse options.
      final opts = optStr.split(',').map((s) => s.trim().toLowerCase()).toSet();
      final isAccepting = opts.contains('accepting') ||
          opts.any((o) => o.startsWith('accepting'));
      final isInitial = opts.contains('initial');
      final isRect = opts.contains('rectangle'); // black-box proxy
      final isHaltReject = opts.any((o) => o.contains('red'));

      // Convert tikz coordinates back to canvas coordinates.
      // tikz y is flipped (we negated on export), and the centre offset is baked in.
      final centerX = _fromPt(xPt);
      final centerY = _fromPt(-yPt);
      final posX = centerX - (isRect ? 70 : 50);
      final posY = centerY - (isRect ? 50 : 50);

      // Convert label back from LaTeX.
      final dslLabel = _latexLabelToDsl(rawLabel);
      final displayLabel = (dslLabel == '~') ? '' : dslLabel; // a bare epsilon label means "no label was ever set" (see export's nodeIdToAlpha fallback), not a literal "~" label

      final node = NodeData(
        id: id,
        position: Offset(posX.clamp(0.0, 8000.0), posY.clamp(0.0, 8000.0)), // clamp guards against wildly out-of-range hand-edited coordinates
        label: displayLabel,
        isAccept: isAccepting && !isHaltReject,
        isHaltAccept: false,
        isHaltReject: isHaltReject,
        isBlackBox: isRect,
      );

      newNodes[id] = node;
      tikzNameToId[tikzName] = id;

      if (isInitial) initialNodeId = id;
    }

    if (newNodes.isEmpty) {
      throw FormatException(
        'No \\node statements found.  Make sure the input contains a valid '
        'tikzpicture with automata nodes.',
      );
    }

    // ── Parse \path[->] / \draw[->] edge lines ────────────────────────────
    //
    // Pattern:
    //   \path[->] (nameA) edge [<opts>] node {<label>} (nameB); % lid=lN
    //
    // We also accept \draw[->] as an alias.

    final edgeRe = RegExp(
      r'\\(?:path|draw)\s*\[.*?->\s*\]\s*'
      r'\(([^)]+)\)\s*edge\s*(?:\[([^\]]*)\])?\s*'
      r'node\s*\{([^}]*)\}\s*\(([^)]+)\)\s*;'
      r'(?:[^\n]*%\s*lid=(l\d+))?',
      multiLine: true,
      dotAll: false,
    );

    final newLines = <String, LineData>{};
    int lineCounter = 0;

    for (final m in edgeRe.allMatches(body)) {
      final srcName  = m.group(1)!.trim();
      final optsStr  = (m.group(2) ?? '').trim().toLowerCase();
      final rawLabel = m.group(3)!.trim();
      final dstName  = m.group(4)!.trim();
      final commentLid = m.group(5);

      final idA = tikzNameToId[srcName];
      final idB = tikzNameToId[dstName];
      if (idA == null || idB == null) continue; // skip edges to unknown nodes

      // Recover (or assign) line id.
      String lid;
      if (commentLid != null) {
        lid = commentLid;
        final num = int.tryParse(lid.substring(1)) ?? -1;
        if (num >= lineCounter) lineCounter = num + 1;
      } else {
        lid = 'l${lineCounter++}';
      }

      // Parse label.
      final dslLabel = _latexLabelToDsl(rawLabel);
      final label = (dslLabel == '~') ? '' : dslLabel;

      // Parse bend / loop options.
      double perpPart = 0.0;
      double loopAngle = -pi / 2;

      final isSelfLoop = optsStr.contains('loop');
      if (isSelfLoop) {
        loopAngle = _angleFromLoopDir(optsStr);
      } else {
        final bendMatch = RegExp(r'bend\s+(left|right)(?:\s*=\s*(\d+))?').firstMatch(optsStr);
        if (bendMatch != null) {
          final dir = bendMatch.group(1)!;
          final angle = double.tryParse(bendMatch.group(2) ?? '30') ?? 30.0;
          // Convert angle (degrees) back to approximate perpendicularPart (px).
          perpPart = angle * 3 * (dir == 'left' ? 1 : -1);
        }
      }

      final line = LineData(
        id: lid,
        nodeAId: idA,
        nodeBId: idB,
        label: label,
        perpendicularPart: perpPart,
        selfLoopAngle: loopAngle,
      );

      newLines[lid] = line;
      newNodes[idA]?.connectedLineIds.add(lid);
      newNodes[idB]?.connectedLineIds.add(lid);
    }

    // ── Start arrow ───────────────────────────────────────────────────────
    StartArrowData? startArrow;
    if (initialNodeId != null) {
      startArrow = StartArrowData(
        nodeId: initialNodeId,
        offset: const Offset(-1, 0),
        length: 100,
      );
    }

    // ── Extract start-arrow label from comment ────────────────────────────
    final saLabelMatch = RegExp(
      r'%\s*start arrow label:\s*(.+)',
    ).firstMatch(body);
    if (saLabelMatch != null && startArrow != null) {
      final rawLbl = saLabelMatch.group(1)!.trim();
      startArrow = StartArrowData(
        nodeId: startArrow.nodeId,
        offset: startArrow.offset,
        length: startArrow.length,
        label: _latexLabelToDsl(rawLbl),
      );
    }

    return GraphState(
      nodes: newNodes,
      lines: newLines,
      startArrow: startArrow,
      nodeCounter: nodeCounter,
      lineCounter: lineCounter,
      automataMode: mode,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  showLatexExportDialog
//
//  Displays a dialog showing the exported LaTeX with copy & "export snippet"
//  options.  Wire this up from the automata screen / export history screen.
//
//  Usage:
//    await showLatexExportDialog(context, graphState: state);
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showLatexExportDialog(
  BuildContext context, {
  required GraphState graphState,
  bool snippetOnly = false,
}) async {
  final latex = snippetOnly
      ? LatexExporter.exportSnippet(graphState)
      : LatexExporter.export(graphState);

  await showDialog<void>(
    context: context,
    builder: (ctx) => _LatexExportDialog(latex: latex, snippetOnly: snippetOnly),
  );
}

class _LatexExportDialog extends StatefulWidget {
  final String latex;
  final bool snippetOnly;

  const _LatexExportDialog({required this.latex, this.snippetOnly = false});

  @override
  State<_LatexExportDialog> createState() => _LatexExportDialogState();
}

class _LatexExportDialogState extends State<_LatexExportDialog> {
  bool _showSnippet = false;
  bool _copied = false;

  String get _displayed =>
      _showSnippet ? LatexExporter.exportSnippet(_parseBack()) : widget.latex;

  // Parse the current latex back to a GraphState (just for snippet toggling).
  // We re-parse widget.latex so that toggling doesn't require the original state.
  GraphState _parseBack() {
    try {
      return LatexImporter.import(widget.latex);
    } catch (_) {
      // If parsing fails just return a dummy (the snippet toggle is cosmetic).
      return GraphState(
        nodes: {},
        lines: {},
        startArrow: null,
        nodeCounter: 0,
        lineCounter: 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Export as LaTeX'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Snippet toggle
            Row(
              children: [
                Switch(
                  value: _showSnippet,
                  onChanged: (v) => setState(() { _showSnippet = v; _copied = false; }),
                ),
                const SizedBox(width: 8),
                Text(
                  _showSnippet ? 'Snippet only (no document wrapper)' : 'Full document',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Code box
            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _displayed,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Compile with pdflatex / xelatex / lualatex.\n'
              'Requires: \\usetikzlibrary{automata,positioning,arrows.meta}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
          label: Text(_copied ? 'Copied!' : 'Copy'),
          onPressed: () async {
            await _copyToClipboard(context, _displayed);
            setState(() => _copied = true);
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _copied = false);
            });
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  showLatexImportDialog
//
//  Displays a text-area where the user can paste LaTeX; returns a [GraphState]
//  on success or null if the user cancelled.
//
//  Usage:
//    final state = await showLatexImportDialog(context);
//    if (state != null) { /* apply state */ }
// ─────────────────────────────────────────────────────────────────────────────

Future<GraphState?> showLatexImportDialog(BuildContext context) async {
  return showDialog<GraphState>(
    context: context,
    builder: (ctx) => const _LatexImportDialog(),
  );
}

class _LatexImportDialog extends StatefulWidget {
  const _LatexImportDialog();

  @override
  State<_LatexImportDialog> createState() => _LatexImportDialogState();
}

class _LatexImportDialogState extends State<_LatexImportDialog> {
  final _controller = TextEditingController();
  String? _error;

  void _tryImport() {
    final src = _controller.text.trim();
    if (src.isEmpty) {
      setState(() => _error = 'Please paste some LaTeX first.');
      return;
    }
    try {
      final state = LatexImporter.import(src);
      Navigator.pop(context, state);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Parse error: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Import from LaTeX'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a tikzpicture block or a full document exported by '
              'Automata Designer (or hand-written using the automata library).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLines: 12,
              style: const TextStyle(fontFamily: 'Courier New', fontSize: 11),
              decoration: InputDecoration(
                hintText: r'\begin{tikzpicture}[…]' '\n…\n' r'\end{tikzpicture}',
                hintStyle: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                errorText: _error,
              ),
              onChanged: (_) { if (_error != null) setState(() => _error = null); },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _tryImport,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Clipboard helper
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('LaTeX copied to clipboard')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Extension on SavedExport — add LaTeX type support
//
//  Add  `latex`  to SavedExportType in saved_export.dart, then use
//  SavedExport.latex(name, latex) to create a LaTeX export entry.
// ─────────────────────────────────────────────────────────────────────────────

// NOTE: To add `latex` to the export type system, add the following to
// saved_export.dart:
//
//   enum SavedExportType { graph, blackBox, latex }   ← add latex
//
// And update the serialisation in preferences_store.dart and
// firebase_session_store.dart to handle 'latex' as a type string.
//
// The export-history screen should then show a "LaTeX" badge and provide
// "Copy LaTeX" / "Export LaTeX" options alongside the existing DSL actions.


// ─────────────────────────────────────────────────────────────────────────────
// SECTION: fa_to_regex.dart
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  fa_to_regex.dart
//
//  Converts an NFA or DFA to an equivalent regular expression using the
//  state-elimination (GNFA) algorithm, operating on a proper regex AST
//  throughout so that simplification is structural rather than string-based.
//
//  Notation used in the output string:
//    ~       tilda (empty string)
//    +       alternation  (a + b  means  a | b)
//    (...)   grouping
//    *       Kleene star (postfix)
//    ∅       empty language (no strings accepted)
//
//  The output uses the same operator set parsed by the regex engine in
//  simulator.dart.
// ─────────────────────────────────────────────────────────────────────────────

// ─── Public API ───────────────────────────────────────────────────────────────

/// Outcome of [faToRegex]: either a derived regex string, or a human-readable
/// reason it couldn't be derived (no start state, no states at all, etc).
class FaToRegexResult {
  final String? regex;
  final String? error;

  const FaToRegexResult.ok(String r) : regex = r, error = null;
  const FaToRegexResult.err(String e) : regex = null, error = e;

  bool get isError => error != null;
}

/// Runs the GNFA state-elimination algorithm over the automaton described by
/// [nodes]/[lines]/[startArrow] and returns the equivalent regular expression.
FaToRegexResult faToRegex({
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? startArrow,
}) {
  if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
    return const FaToRegexResult.err(
        'No start state defined. Add a start arrow (▶) and try again.');
  }
  if (nodes.isEmpty) {
    return const FaToRegexResult.err('The automaton has no states.');
  }

  final acceptIds =
      nodes.values.where((n) => n.isAccept).map((n) => n.id).toSet();
  if (acceptIds.isEmpty) {
    // No accept states at all means the automaton accepts nothing — this is
    // a valid (if trivial) answer, not an error condition.
    return const FaToRegexResult.ok('∅');
  }

  // ── Build GNFA as AST-valued transition table ─────────────────────────────
  //
  // Standard GNFA construction: add a fresh super-start (with a single ~
  // edge into the real start state) and a fresh super-accept (with a ~ edge
  // in from every real accept state), so there's exactly one start and one
  // accept state to eliminate down to — after every other state has been
  // eliminated, the single remaining edge super-start → super-accept *is*
  // the answer.
  const String superStart  = '__S__';
  const String superAccept = '__A__';

  final allStates = nodes.keys.toSet();

  // gnfa[from][to] = _RE node (null = ∅ / no edge)
  final Map<String, Map<String, _RE?>> gnfa = {};

  void ensureRow(String s) => gnfa.putIfAbsent(s, () => {});
  for (final s in allStates) {
    ensureRow(s);
  }
  ensureRow(superStart);
  ensureRow(superAccept);

  // Fill transitions from the original automaton edges.
  for (final line in lines.values) {
    final from = line.nodeAId;
    final to   = line.nodeBId;
    if (!allStates.contains(from) || !allStates.contains(to)) continue; // stale line referencing a deleted node

    final alts = line.label
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Turn this line's alternatives (comma-/newline-separated symbols) into
    // one union-of-literals AST node — an empty label is treated as an
    // epsilon edge (fires without consuming input), matching how the FA
    // simulator itself interprets a blank transition label.
    _RE? edgeRe;
    if (alts.isEmpty) {
      edgeRe = const _Eps();
    } else {
      for (final sym in alts) {
        final atom = sym == '~' ? const _Eps() : _Lit(sym);
        edgeRe = edgeRe == null ? atom : _union(edgeRe, atom);
      }
    }

    // Two lines between the same (from, to) pair (shouldn't normally happen
    // given _graph-style builders merge these, but a hand-built or
    // hand-edited graph could still have them) get unioned together rather
    // than the second silently overwriting the first.
    gnfa[from]![to] = _union(gnfa[from]![to], edgeRe);
  }

  // Super-start → original start via ~.
  gnfa[superStart]![startArrow.nodeId] = const _Eps();

  // All accept states → super-accept via ~.
  for (final aId in acceptIds) {
    gnfa[aId]![superAccept] = _union(gnfa[aId]![superAccept], const _Eps());
  }

  // ── State elimination ─────────────────────────────────────────────────────
  final toEliminate = allStates.toList();

  // Re-score and pick the best state to eliminate each round (greedy).
  // Score = sum of string lengths of the new edges that would be created,
  // minus the edges that would be removed.  Lower is better.
  //
  // This greedy ordering (rather than eliminating states in an arbitrary or
  // fixed order) is what keeps the final regex from blowing up into an
  // unreadable mess on graphs with more than a handful of states: each
  // round, eliminating a low-degree/low-fan-out state tends to create
  // shorter replacement edges than eliminating a heavily-connected one
  // would, so preferring cheap eliminations first keeps intermediate
  // expressions smaller throughout.
  int score(String q) {
    final preds = gnfa.keys
        .where((p) => p != q && (gnfa[p]?[q]) != null)
        .toList();
    final succs = (gnfa[q] ?? {})
        .entries
        .where((e) => e.key != q && e.value != null)
        .map((e) => e.key)
        .toList();
    final self = gnfa[q]?[q];

    int cost = 0;
    // Simulates eliminating q: for every (pred, succ) pair, this is the new
    // combined edge pred→succ that eliminating q would produce (pred→q,
    // q's own self-loop starred if present, then q→succ, unioned into
    // whatever pred→succ edge already exists) — `_size(merged) -
    // _size(existing)` is how much bigger that union grows the AST, summed
    // across every pred/succ pair q has.
    for (final p in preds) {
      for (final s in succs) {
        final rPQ = gnfa[p]![q]!;
        final rQR = gnfa[q]![s]!;
        final newEdge = _seq(rPQ, _seq(self != null ? _star(self) : null, rQR));
        final existing = gnfa[p]?[s];
        final merged = _union(existing, newEdge);
        cost += _size(merged) - _size(existing);
      }
    }
    return cost;
  }

  final remaining = toEliminate.toSet();

  while (remaining.isNotEmpty) {
    // Pick the state with minimum elimination cost.
    String best = remaining.first;
    int bestScore = score(best);
    for (final q in remaining) {
      final s = score(q);
      if (s < bestScore) {
        bestScore = s;
        best = q;
      }
    }

    final elim = best;
    remaining.remove(elim);

    final selfLabel = gnfa[elim]?[elim];

    final preds = gnfa.keys
        .where((p) => p != elim && (gnfa[p]?[elim]) != null)
        .toList();
    final succs = (gnfa[elim] ?? {})
        .entries
        .where((e) => e.key != elim && e.value != null)
        .map((e) => e.key)
        .toList();

    // The actual elimination: for every predecessor and successor of
    // `elim`, splice a new direct edge pred → succ that represents "go
    // pred→elim, optionally loop on elim any number of times, then
    // elim→succ" — the textbook GNFA elimination step — merged into
    // whatever direct pred→succ edge may already exist.
    for (final pred in preds) {
      for (final succ in succs) {
        final rPQ = gnfa[pred]![elim]!;
        final rQR = gnfa[elim]![succ]!;
        final middle = selfLabel != null ? _star(selfLabel) : null;
        final newPath = _seq(rPQ, _seq(middle, rQR));
        ensureRow(pred);
        gnfa[pred]![succ] = _union(gnfa[pred]![succ], newPath);
      }
    }

    gnfa.remove(elim);
    for (final row in gnfa.values) {
      row.remove(elim);
    }
  }

  // After every real state has been eliminated, only super-start and
  // super-accept remain — the single edge between them is the answer.
  final result = gnfa[superStart]?[superAccept];
  if (result == null) return const FaToRegexResult.ok('∅'); // no path at all survived elimination: language is empty

  return FaToRegexResult.ok(_print(result));
}

// ─── Regex AST ────────────────────────────────────────────────────────────────

abstract class _RE {
  const _RE();
}

/// Empty language ∅ — never matches anything.
class _Empty extends _RE {
  const _Empty();
}

/// tilda ~ — matches the empty string.
class _Eps extends _RE {
  const _Eps();
}

/// Literal symbol (single character or multi-char token like "ab").
class _Lit extends _RE {
  final String sym;
  const _Lit(this.sym);
}

/// Alternation: left + right.
class _Union extends _RE {
  final _RE left;
  final _RE right;
  const _Union(this.left, this.right);
}

/// Concatenation: left · right.
class _Cat extends _RE {
  final _RE left;
  final _RE right;
  const _Cat(this.left, this.right);
}

/// Kleene star: child*.
class _Star extends _RE {
  final _RE child;
  const _Star(this.child);
}

// ─── Smart constructors (simplify on build) ───────────────────────────────────
//
// These aren't just convenience wrappers — applying algebraic identities
// (∅ is an identity/annihilator, r+r=r, r*+~=r*, …) at construction time
// rather than only at the end is what keeps the AST from growing
// exponentially across dozens of elimination rounds; without this, the
// state-elimination loop above would produce regexes many times longer
// than necessary (or, on bigger graphs, simply too large to be useful).

/// Union of two nullable REs (null = ∅).
_RE? _union(_RE? a, _RE? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _unionNN(a, b);
}

_RE _unionNN(_RE a, _RE b) {
  // ∅ identity
  if (a is _Empty) return b;
  if (b is _Empty) return a;

  // Idempotence: a + a → a
  if (_eq(a, b)) return a;

  // r + r* → r*  and  r* + r → r*
  if (b is _Star && _eq(a, b.child)) return b;
  if (a is _Star && _eq(b, a.child)) return a;

  // r* + ~ → r*  and  ~ + r* → r*  (star already includes tilda)
  if (a is _Star && b is _Eps) return a;
  if (b is _Star && a is _Eps) return b;

  // Flatten nested unions for deduplication:
  // collect all arms, deduplicate, rebuild.
  final arms = <_RE>[];
  void collectArms(_RE r) {
    if (r is _Union) {
      collectArms(r.left);
      collectArms(r.right);
    } else {
      // Only add if not already present.
      if (!arms.any((x) => _eq(x, r))) arms.add(r);
    }
  }
  collectArms(a);
  // Add arms from b that aren't already in the list.
  void collectNewArms(_RE r) {
    if (r is _Union) {
      collectNewArms(r.left);
      collectNewArms(r.right);
    } else {
      if (!arms.any((x) => _eq(x, r))) arms.add(r);
    }
  }
  collectNewArms(b);

  // Apply r + r* → r* reduction on the flat list.
  final reduced = <_RE>[];
  for (final arm in arms) {
    // If a star of this arm is already in the list, skip this arm.
    if (reduced.any((x) => x is _Star && _eq(x.child, arm))) continue;
    // If this is a star and its child is in the list, replace the child.
    if (arm is _Star) {
      reduced.removeWhere((x) => _eq(x, arm.child));
    }
    // If ~ and a star is present, skip ~.
    if (arm is _Eps && reduced.any((x) => x is _Star)) continue;
    reduced.add(arm);
  }

  if (reduced.isEmpty) return const _Empty();
  return reduced.reduce((acc, r) => _Union(acc, r));
}

/// Sequence (concatenation) of two nullable REs (null = identity/skip).
_RE? _seq(_RE? a, _RE? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _seqNN(a, b);
}

_RE _seqNN(_RE a, _RE b) {
  // ∅ annihilates
  if (a is _Empty || b is _Empty) return const _Empty();
  // ~ identity
  if (a is _Eps) return b;
  if (b is _Eps) return a;
  return _Cat(a, b);
}

/// Kleene star.
_RE _star(_RE r) {
  if (r is _Empty) return const _Eps(); // ∅* = ~
  if (r is _Eps)   return const _Eps(); // ~* = ~
  if (r is _Star)  return r;            // (r*)* = r*
  // (r+~)* → r*   (adding ~ inside a star is redundant)
  if (r is _Union) {
    final withoutEps = _removeEpsFromUnion(r);
    if (withoutEps != null && !_eq(withoutEps, r)) return _star(withoutEps);
  }
  return _Star(r);
}

/// Remove ~ arms from a union; returns null if the whole union collapses.
_RE? _removeEpsFromUnion(_RE r) {
  if (r is _Eps) return null;
  if (r is _Union) {
    final l = _removeEpsFromUnion(r.left);
    final rr = _removeEpsFromUnion(r.right);
    if (l == null) return rr;
    if (rr == null) return l;
    return _Union(l, rr);
  }
  return r;
}

// ─── Structural equality ──────────────────────────────────────────────────────

/// Deep structural equality between two AST nodes — used throughout the
/// smart constructors above to detect the identities they simplify (a+a=a,
/// etc), since two syntactically-identical subtrees built at different
/// points in the elimination loop are never the same object instance.
bool _eq(_RE a, _RE b) {
  if (identical(a, b)) return true;
  if (a is _Empty && b is _Empty) return true;
  if (a is _Eps   && b is _Eps)   return true;
  if (a is _Lit   && b is _Lit)   return a.sym == b.sym;
  if (a is _Star  && b is _Star)  return _eq(a.child, b.child);
  if (a is _Cat   && b is _Cat)   return _eq(a.left, b.left) && _eq(a.right, b.right);
  if (a is _Union && b is _Union) return _eq(a.left, b.left) && _eq(a.right, b.right);
  return false;
}

// ─── AST size (used for elimination ordering) ─────────────────────────────────

/// Rough complexity measure (roughly "how many printed characters/tokens"),
/// used only comparatively by [score] above to judge how much an
/// elimination round would grow the graph — not meant to exactly match
/// [_print]'s actual output length.
int _size(_RE? r) {
  if (r == null) return 0;
  if (r is _Empty || r is _Eps || r is _Lit) return 1;
  if (r is _Star)  return 1 + _size(r.child);
  if (r is _Cat)   return _size(r.left) + _size(r.right);
  if (r is _Union) return _size((r).left) + _size(r.right);
  return 1;
}

// ─── Pretty-printer ───────────────────────────────────────────────────────────

/// Converts an AST node to the string syntax understood by the regex engine
/// in simulator.dart.
String _print(_RE r) {
  return _printPrec(r, 0);
}

/// [prec] context: 0 = top/union, 1 = concat, 2 = atom (under star)
String _printPrec(_RE r, int prec) {
  if (r is _Empty) return '∅';
  if (r is _Eps)   return '~';
  if (r is _Lit)   return r.sym.length == 1 ? r.sym : '(${r.sym})'; // a multi-char literal token needs its own parens to print unambiguously

  if (r is _Star) {
    final inner = _printPrec(r.child, 2); // child printed at "atom" precedence: gets its own parens if it's a Cat/Union, since e.g. (ab)* != ab*
    final starred = '$inner*';
    return starred;
  }

  if (r is _Cat) {
    final left  = _printPrec(r.left,  1);
    final right = _printPrec(r.right, 1);
    final s = '$left$right';
    // Wrap if we're inside a star context and the concat has more than one char.
    if (prec >= 2) return '($s)';
    return s;
  }

  if (r is _Union) {
    // Collect all union arms for flat printing.
    // A chain of nested _Union nodes (left-associated by _unionNN's
    // `reduced.reduce`) is flattened back into one flat "a+b+c+…" join here
    // rather than printed as nested parens like "((a+b)+c)".
    final arms = <_RE>[];
    void collect(_RE node) {
      if (node is _Union) { collect(node.left); collect(node.right); }
      else {
        arms.add(node);
      }
    }
    collect(r);
    final s = arms.map((a) => _printPrec(a, 0)).join('+');
    // Wrap if we're in a concat or star context.
    if (prec >= 1) return '($s)';
    return s;
  }

  return '?'; // unreachable: every _RE subtype is handled above
}


// ─────────────────────────────────────────────────────────────────────────────
// SECTION: svg_export.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Renders a graph as an SVG so it can be embedded or downloaded externally.
///
/// The SVG is both a visual rendering *and* a data file: the full graph
/// state is embedded verbatim as JSON inside a `<script id="automata-data">`
/// tag (see the `graphData` map built below), which is exactly what
/// [DslCodec.importFromSvg] reads back out — so an exported SVG round-trips
/// losslessly even though the visible drawing itself is just for humans.
class SvgExporter {
  const SvgExporter._();

  static const double _arrowLen = 15;
  static const double _arrowWing = 9;

  /// Builds an SVG `<polygon>` for a filled triangular arrowhead whose tip
  /// sits at [tip], oriented along [angle] — same construction as the
  /// on-canvas arrowhead painters elsewhere in the app (e.g.
  /// tutorial_screen.dart's _drawArrow), just emitted as markup instead of
  /// drawn on a Canvas.
  static String _arrowhead(Offset tip, double angle) {
    final dx = cos(angle);
    final dy = sin(angle);
    final p1x = tip.dx - _arrowLen * dx + _arrowWing * dy;
    final p1y = tip.dy - _arrowLen * dy - _arrowWing * dx;
    final p2x = tip.dx - _arrowLen * dx - _arrowWing * dy;
    final p2y = tip.dy - _arrowLen * dy + _arrowWing * dx;
    return '<polygon points="${tip.dx},${tip.dy} $p1x,$p1y $p2x,$p2y" fill="var(--fg)"/>';
  }

  /// Pulls the line/arc's endpoint back by the arrowhead's own length, so
  /// the stroked path stops where the arrowhead's back edge is rather than
  /// poking out past its tip.
  static Offset _shortenedEnd(Offset tip, double angle) {
    return Offset(tip.dx - cos(angle) * _arrowLen, tip.dy - sin(angle) * _arrowLen);
  }

  static String export({
    required Map<String, NodeData> nodes,
    required Map<String, LineData> lines,
    required StartArrowData? startArrow,
  }) {
    const double nodeRadius = 42.0;
    const double nodePad = nodeRadius + 4;
    const double pad = 30.0;

    // ── First pass: compute the bounding box of everything that will be
    // drawn, so the SVG's viewBox can be sized to fit exactly (with `pad`
    // margin) rather than using some arbitrary fixed canvas size. ─────────
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    void expandPoint(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    void expandRect(double left, double top, double right, double bottom) {
      expandPoint(left, top);
      expandPoint(right, bottom);
    }

    for (final node in nodes.values) {
      final c = node.center;
      expandRect(c.dx - nodePad, c.dy - nodePad, c.dx + nodePad, c.dy + nodePad);
    }

    for (final line in lines.values) {
      final nodeA = nodes[line.nodeAId];
      final nodeB = nodes[line.nodeBId];
      if (nodeA == null || nodeB == null) continue;

      if (line.label.trim().isNotEmpty) {
        const boxW = kLabelBoxWidth;
        const lineH = 36.0;
        final lineCount = '\n'.allMatches(line.label).length + 1;
        final boxH = lineH * lineCount;
        final pos = line.getTextBoxLocation(nodeA.center, nodeB.center, boxW, boxH, line.label);
        expandRect(pos.dx, pos.dy, pos.dx + boxW, pos.dy + boxH);
      }

      final geometry = line.computeGeometry(nodeA.center, nodeB.center);
      expandPoint(geometry.midPoint.dx, geometry.midPoint.dy);
      expandPoint(geometry.startPoint.dx, geometry.startPoint.dy);
      expandPoint(geometry.endPoint.dx, geometry.endPoint.dy);
    }

    if (startArrow != null) {
      final node = nodes[startArrow.nodeId];
      if (node != null) {
        var dir = startArrow.direction();
        if (dir.distance == 0) dir = const Offset(-0.7071, -0.7071); // same degenerate-direction fallback as StartArrowData.containsPoint (models.dart)
        final center = node.center;
        final arrowEnd = Offset(center.dx + dir.dx * 50, center.dy + dir.dy * 50);
        final arrowStart = Offset(
          arrowEnd.dx + dir.dx * startArrow.length,
          arrowEnd.dy + dir.dy * startArrow.length,
        );
        expandPoint(arrowStart.dx, arrowStart.dy);
        expandPoint(arrowEnd.dx, arrowEnd.dy);

        if (startArrow.label.trim().isNotEmpty) {
          const boxW = kLabelBoxWidth;
          const lineH = 36.0;
          final lineCount = '\n'.allMatches(startArrow.label).length + 1;
          final boxH = lineH * lineCount;
          final perp = Offset(-dir.dy, dir.dx);
          final labelPos = Offset(arrowStart.dx + perp.dx * 30 - boxW / 2, arrowStart.dy + perp.dy * 30 - boxH / 2);
          expandRect(labelPos.dx, labelPos.dy, labelPos.dx + boxW, labelPos.dy + boxH);
        }
      }
    }

    // Nothing was drawn at all (empty graph): fall back to a fixed
    // reasonable canvas size instead of a degenerate/inverted viewBox.
    if (minX == double.infinity) {
      minX = 0;
      minY = 0;
      maxX = 400;
      maxY = 300;
    }

    final vx = minX - pad;
    final vy = minY - pad;
    final vw = (maxX - minX) + pad * 2;
    final vh = (maxY - minY) + pad * 2;

    // ── The embedded round-trip payload: every field DslCodec.importFromSvg
    // needs to fully reconstruct nodes/lines/startArrow/mode is here — the
    // 'version' field lets a future importer detect and handle older
    // payload shapes if this format ever needs to change. ────────────────
    final graphData = {
      'version': 2,
      'nodes': nodes.values.map((n) {
        return {
          'id': n.id,
          'x': n.position.dx,
          'y': n.position.dy,
          'label': n.label,
          'accept': n.isAccept,
          'haltAccept': n.isHaltAccept,
          'haltReject': n.isHaltReject,
        };
      }).toList(),
      'lines': lines.values.map((l) {
        return {
          'id': l.id,
          'a': l.nodeAId,
          'b': l.nodeBId,
          'label': l.label,
          'curve': l.perpendicularPart,
          'loopAngle': l.selfLoopAngle,
        };
      }).toList(),
      'startArrow': startArrow == null
          ? null
          : {
              'nodeId': startArrow.nodeId,
              'dx': startArrow.offset.dx,
              'dy': startArrow.offset.dy,
              'length': startArrow.length,
              'label': startArrow.label,
            },
    };

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg"'
      ' width="${vw.toStringAsFixed(1)}"'
      ' height="${vh.toStringAsFixed(1)}"'
      ' viewBox="${vx.toStringAsFixed(1)} ${vy.toStringAsFixed(1)} ${vw.toStringAsFixed(1)} ${vh.toStringAsFixed(1)}">',
    );
    buffer.writeln();
    // CSS custom properties so the SVG can be recolored (e.g. for a dark
    // background) just by overriding these variables, without touching the
    // markup itself.
    buffer.writeln('''<style>
  :root {
    --fg:          black;
    --node-fill:   none;
    --label-fill:  black;
    --hint-fill:   #888;
  }
</style>
''');
    buffer.writeln('<script type="application/json" id="automata-data">');
    buffer.writeln(const JsonEncoder.withIndent('  ').convert(graphData));
    buffer.writeln('</script>');
    buffer.writeln();

    // ── Transitions ────────────────────────────────────────────────────
    for (final line in lines.values) {
      final nodeA = nodes[line.nodeAId];
      final nodeB = nodes[line.nodeBId];
      if (nodeA == null || nodeB == null) continue;

      final geometry = line.computeGeometry(nodeA.center, nodeB.center);
      const strokeW = 4;

      if (line.nodeAId == line.nodeBId) {
        // Self-loop: full circular arc, drawn with SVG's elliptical-arc
        // path command using equal x/y radii (a true circle). The "1 1"
        // large-arc/sweep flags are fixed here (unlike the general-arc case
        // below) since a self-loop always sweeps the long way around.
        final radius = geometry.circleRadius!;
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final arrowAngle = geometry.arrowAngle!;
        final shortenedEnd = _shortenedEnd(tipPt, arrowAngle);
        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <path d="M ${startPt.dx} ${startPt.dy} A $radius $radius 0 1 1 ${shortenedEnd.dx} ${shortenedEnd.dy}"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, arrowAngle)}');
        buffer.writeln('</g>');
      } else if (geometry.hasCircle) {
        // Curved (non-self-loop) transition: an SVG elliptical arc whose
        // large-arc-flag and sweep-flag are derived directly from the
        // geometry's own sweepAngle sign/magnitude, so the SVG path bends
        // the same way the canvas-rendered arc does.
        final radius = geometry.circleRadius!;
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final arrowAngle = geometry.arrowAngle!;
        final shortenedEnd = _shortenedEnd(tipPt, arrowAngle);
        final largeArc = geometry.sweepAngle!.abs() > pi ? 1 : 0;
        final sweep = geometry.sweepAngle! > 0 ? 1 : 0;
        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <path d="M ${startPt.dx} ${startPt.dy} A $radius $radius 0 $largeArc $sweep ${shortenedEnd.dx} ${shortenedEnd.dy}"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, arrowAngle)}');
        buffer.writeln('</g>');
      } else {
        // Plain straight transition: simple <line>, with the arrow angle
        // derived directly from the start→end direction rather than from
        // geometry.arrowAngle (which is only populated for arcs).
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final angle = atan2(tipPt.dy - startPt.dy, tipPt.dx - startPt.dx);
        final shortenedEnd = _shortenedEnd(tipPt, angle);
        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <line x1="${startPt.dx}" y1="${startPt.dy}" x2="${shortenedEnd.dx}" y2="${shortenedEnd.dy}"'
          ' stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, angle)}');
        buffer.writeln('</g>');
      }

      // Label textbox, positioned via the same LineData.getTextBoxLocation
      // used for on-canvas rendering, so the SVG matches the app's own
      // layout exactly. Multi-line labels become stacked <tspan> elements,
      // each subsequent one shifted down by the fixed line height (36px)
      // via SVG's relative `dy` attribute.
      if (line.label.trim().isNotEmpty) {
        const boxW = kLabelBoxWidth;
        const lineH = 36.0;
        final lineCount = '\n'.allMatches(line.label).length + 1;
        final boxH = lineH * lineCount;
        final textPos = line.getTextBoxLocation(nodeA.center, nodeB.center, boxW, boxH, line.label);
        final parts = line.label.split('\n');
        buffer.writeln(
          '<text x="${(textPos.dx + boxW / 2).toStringAsFixed(1)}" y="${(textPos.dy + 24).toStringAsFixed(1)}"'
          ' font-family="Courier New, monospace" font-weight="bold" font-size="30"'
          ' text-anchor="middle" fill="var(--fg)">',
        );
        for (int i = 0; i < parts.length; i++) {
          if (i == 0) {
            buffer.writeln('  <tspan>${htmlEscape.convert(parts[i])}</tspan>');
          } else {
            buffer.writeln(
              '  <tspan x="${(textPos.dx + boxW / 2).toStringAsFixed(1)}" dy="36">${htmlEscape.convert(parts[i])}</tspan>',
            );
          }
        }
        buffer.writeln('</text>');
      }
      buffer.writeln();
    }

    // ── Nodes ─────────────────────────────────────────────────────────
    const acceptRadius = 34.0;
    const strokeWidth = 3.0;

    for (final node in nodes.values) {
      final center = node.center;
      // A node with no user-entered label displays its auto letter name
      // (nodeIdToAlpha), dimmed via --hint-fill rather than the normal
      // --label-fill, so it visibly reads as a placeholder rather than
      // real user content.
      final hasLabel = node.label.trim().isNotEmpty;
      final displayText = hasLabel ? node.label : nodeIdToAlpha(node.id);
      final textColor = hasLabel ? 'var(--label-fill)' : 'var(--hint-fill)';

      buffer.writeln('<g class="node" data-id="${node.id}">');
      buffer.writeln(
        '  <circle cx="${center.dx}" cy="${center.dy}" r="$nodeRadius"'
        ' fill="var(--node-fill)" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
      );
      if (node.isAccept) {
        // Second, slightly smaller concentric circle — the classic
        // "double-ring" accepting-state marker.
        buffer.writeln(
          '  <circle cx="${center.dx}" cy="${center.dy}" r="$acceptRadius"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }
      if (node.isHaltAccept) {
        // Halt-accept renders as a filled green square instead of the
        // ordinary circle+ring, so it's visually distinct at a glance.
        buffer.writeln(
          '  <rect x="${center.dx - 24}" y="${center.dy - 24}" width="48" height="48"'
          ' fill="green" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }
      if (node.isHaltReject) {
        // Halt-reject renders as a filled red octagon (a hand-built
        // 8-point polygon around the node's centre) — "stop sign" shape.
        final points = [
          '${center.dx - 12},${center.dy - 24}',
          '${center.dx + 12},${center.dy - 24}',
          '${center.dx + 24},${center.dy - 12}',
          '${center.dx + 24},${center.dy + 12}',
          '${center.dx + 12},${center.dy + 24}',
          '${center.dx - 12},${center.dy + 24}',
          '${center.dx - 24},${center.dy + 12}',
          '${center.dx - 24},${center.dy - 12}',
        ].join(' ');
        buffer.writeln(
          '  <polygon points="$points"'
          ' fill="red" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }
      buffer.writeln(
        '  <text x="${center.dx}" y="${center.dy}"'
        ' dominant-baseline="middle" text-anchor="middle"'
        ' font-family="Courier New, monospace" font-weight="bold" font-size="24"'
        ' fill="$textColor">${htmlEscape.convert(displayText)}</text>',
      );
      buffer.writeln('</g>');
      buffer.writeln();
    }

    // ── Start arrow ───────────────────────────────────────────────────
    if (startArrow != null) {
      final node = nodes[startArrow.nodeId];
      if (node != null) {
        var dir = startArrow.direction();
        if (dir.distance == 0) dir = const Offset(-0.7071, -0.7071);
        final center = node.center;
        final tipPt = Offset(center.dx + dir.dx * 50, center.dy + dir.dy * 50);
        final arrowStart = Offset(tipPt.dx + dir.dx * startArrow.length, tipPt.dy + dir.dy * startArrow.length);
        final angle = atan2(tipPt.dy - arrowStart.dy, tipPt.dx - arrowStart.dx);
        final shortenedTip = _shortenedEnd(tipPt, angle);

        buffer.writeln('<g class="start-arrow">');
        buffer.writeln(
          '  <line x1="${arrowStart.dx}" y1="${arrowStart.dy}" x2="${shortenedTip.dx}" y2="${shortenedTip.dy}"'
          ' stroke="var(--fg)" stroke-width="4" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, angle)}');

        if (startArrow.label.trim().isNotEmpty) {
          const boxW = kLabelBoxWidth;
          const lineH = 36.0;
          final lineCount = '\n'.allMatches(startArrow.label).length + 1;
          final boxH = lineH * lineCount;
          final perp = Offset(-dir.dy, dir.dx);
          final labelPos = Offset(arrowStart.dx + perp.dx * 30 - boxW / 2, arrowStart.dy + perp.dy * 30 - boxH / 2);
          final parts = startArrow.label.split('\n');
          buffer.writeln(
            '<text x="${(labelPos.dx + boxW / 2).toStringAsFixed(1)}" y="${(labelPos.dy + 24).toStringAsFixed(1)}"'
            ' font-family="Courier New, monospace" font-weight="bold" font-size="30"'
            ' text-anchor="middle" fill="var(--fg)">',
          );
          for (int i = 0; i < parts.length; i++) {
            if (i == 0) {
              buffer.writeln('  <tspan>${htmlEscape.convert(parts[i])}</tspan>');
            } else {
              buffer.writeln(
                '  <tspan x="${(labelPos.dx + boxW / 2).toStringAsFixed(1)}" dy="36">${htmlEscape.convert(parts[i])}</tspan>',
              );
            }
          }
          buffer.writeln('</text>');
        }
        buffer.writeln('</g>');
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// SECTION: fa_to_regex_dialog.dart
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  fa_to_regex_dialog.dart
//
//  A bottom sheet / dialog that:
//    1. Runs the state-elimination algorithm on the current automaton.
//    2. Displays the resulting regular expression with a copy button.
//    3. Offers a "Load into Regex Panel" shortcut that switches the canvas to
//       Regex mode and pre-fills the panel with the derived expression.
//
//  Import this file and call [showFaToRegexDialog] from the automata screen.
// ─────────────────────────────────────────────────────────────────────────────

// ─── Public entry point ───────────────────────────────────────────────────────

/// Shows the NFA/DFA → Regex dialog.
///
/// [onLoadIntoRegexPanel] is called with the derived regex string when the
/// user taps "Load into Regex Panel".  The caller should switch to regex mode
/// and pre-fill the regex panel text field with this value.
Future<void> showFaToRegexDialog(
  BuildContext context, {
  required Map<String, NodeData> nodes,
  required Map<String, LineData> lines,
  required StartArrowData? startArrow,
  required void Function(String regex) onLoadIntoRegexPanel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FaToRegexDialog(
      nodes: nodes,
      lines: lines,
      startArrow: startArrow,
      onLoadIntoRegexPanel: onLoadIntoRegexPanel,
    ),
  );
}

// ─── Dialog widget ────────────────────────────────────────────────────────────

class _FaToRegexDialog extends StatefulWidget {
  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;
  final StartArrowData? startArrow;
  final void Function(String regex) onLoadIntoRegexPanel;

  const _FaToRegexDialog({
    required this.nodes,
    required this.lines,
    required this.startArrow,
    required this.onLoadIntoRegexPanel,
  });

  @override
  State<_FaToRegexDialog> createState() => _FaToRegexDialogState();
}

class _FaToRegexDialogState extends State<_FaToRegexDialog> {
  // Computed once in initState (the source graph doesn't change while this
  // dialog is open), rather than recomputed on every build.
  late final FaToRegexResult _result;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _result = faToRegex(
      nodes: widget.nodes,
      lines: widget.lines,
      startArrow: widget.startArrow,
    );
  }

  Future<void> _copyToClipboard() async {
    if (_result.regex == null) return; // nothing to copy in the error case
    await Clipboard.setData(ClipboardData(text: _result.regex!));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false); // revert the button back to "Copy" after the confirmation flash
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();

    return Dialog(
      backgroundColor: theme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.transform, color: theme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'NFA / DFA  →  Regex',
                    style: GoogleFonts.courierPrime(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: theme.textLight,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.textMid, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Divider(height: 16, color: theme.borderMid),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Info blurb ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.borderMid),
                    ),
                    child: Text(
                      'Uses the state-elimination (GNFA) algorithm to derive '
                      'an equivalent regular expression from the current automaton. '
                      'The output uses the same syntax as the Regex Panel '
                      '(* = Kleene star,  + = union,  ~ = ~).',
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: theme.textMid,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_result.isError) ...[
                    // ── Error banner ─────────────────────────────────────
                    _ErrorBanner(message: _result.error!),
                  ] else ...[
                    // ── Result box ────────────────────────────────────────
                    Text(
                      'Derived regular expression',
                      style: GoogleFonts.courierPrime(
                        fontSize: 12,
                        color: theme.textDim,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.accent.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: SelectableText(
                        _result.regex!,
                        style: GoogleFonts.courierPrime(
                          fontSize: 17,
                          color: theme.textLight,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Copy button ──────────────────────────────────────
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copyToClipboard,
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                _copied ? const Color(0xFF1FD99A) : theme.textMid,
                            side: BorderSide(
                              color: _copied
                                  ? const Color(0xFF1FD99A)
                                  : theme.borderMid,
                            ),
                          ),
                          icon: Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 16,
                          ),
                          label: Text(
                            _copied ? 'Copied!' : 'Copy',
                            style: GoogleFonts.courierPrime(fontSize: 13),
                          ),
                        ),
                        const Spacer(),
                        // ── Load into Regex Panel ────────────────────────
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onLoadIntoRegexPanel(_result.regex!);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.accent,
                            foregroundColor: Colors.black,
                          ),
                          icon: const Icon(Icons.text_fields, size: 16),
                          label: Text(
                            'Load into Regex Panel',
                            style: GoogleFonts.courierPrime(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    const errorColor = Color(0xFFFF1744);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Light red tint over the current theme's background, rather than a
        // fixed near-black — keeps this legible in light themes too.
        color: Color.alphaBlend(errorColor.withValues(alpha: 0.12), theme.bg),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: errorColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, color: errorColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.courierPrime(
                fontSize: 13,
                color: theme.textLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}