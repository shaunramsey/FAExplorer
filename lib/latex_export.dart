import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'dsl_code.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

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
//  • Unicode symbols (ε, ∅, λ …) are wrapped in $…$ math mode.
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

// Known unicode symbols → LaTeX math equivalents.
const _unicodeToLatex = {
  'ε': r'\varepsilon',
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

/// Reverse a tikz node name back to an internal id.
String? _idFromTikzName(String name) {
  if (name.startsWith('state_n')) return name.substring('state_'.length);
  return null;
}

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
  closeMath();
  return buf.toString();
}

/// Best-effort reverse: strip $…$ delimiters and convert known LaTeX math
/// commands back to their unicode equivalents.  Used by the importer.
String _latexLabelToDsl(String tex) {
  tex = tex.trim();

  // Full epsilon shortcuts.
  if (tex == r'$\varepsilon$' || tex == r'$\epsilon$' || tex == r'\varepsilon' || tex == r'\epsilon') {
    return '~';
  }

  // Strip outer $…$ if present.
  if (tex.startsWith(r'$') && tex.endsWith(r'$') && tex.length > 2) {
    tex = tex.substring(1, tex.length - 1);
  }

  // Replace known LaTeX commands with unicode.
  final reversed = Map.fromEntries(_unicodeToLatex.entries.map((e) => MapEntry(e.value, e.key)));
  // Sort by key length descending so longer commands are matched first.
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
      AutomataMode.pda  => '% mode: pda',
      AutomataMode.tm   => '% mode: tm',
      AutomataMode.ndfa => '% mode: ndfa',
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

    final startNodeId = g.startArrow != null ? g.startArrow!.nodeId : null;

    for (final node in g.nodes.values) {
      final name = _tikzName(node.id);
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
    if (start < 0 || end < r'\end{tikzpicture}'.length) return full;
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
    }

    // ── Extract tikzpicture content ───────────────────────────────────────
    final picMatch = RegExp(
      r'\\begin\{tikzpicture\}(.*?)\\end\{tikzpicture\}',
      dotAll: true,
    ).firstMatch(src);
    final body = picMatch != null ? picMatch.group(1)! : src;

    // ── Parse \node lines ─────────────────────────────────────────────────
    //
    // Pattern:
    //   \node[<options>] (<name>) at (<x>pt, <y>pt) {<label>}; % id=nN
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
      final displayLabel = (dslLabel == '~') ? '' : dslLabel;

      final node = NodeData(
        id: id,
        position: Offset(posX.clamp(0.0, 8000.0), posY.clamp(0.0, 8000.0)),
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
                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
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
                color: theme.colorScheme.onSurface.withOpacity(0.6),
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
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
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