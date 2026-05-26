import 'dart:collection';
import 'models.dart';
import 'token_replacements.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PDA Transition label parsing
//
//  Standard notation:  read , pop | push
//    read  — input symbol consumed, or ~ / ε for epsilon
//    pop   — stack symbol popped, or ~ / ε for no pop
//    push  — stack symbol(s) pushed; space-separated, left-most ends on top
//            or ~ for push nothing
//
//  Legacy slash form (read,pop/push or read/pop) is still accepted.
//
//  Multiple alternatives on one transition are separated by newlines.
//
//  Examples:
//    a,x|y       read a, pop x, push y
//    ~,~/~       epsilon, no stack change
//    b,x|~       read b, pop x, push nothing
//    a,∅|A ∅    read a, pop bottom marker ∅, push A then ∅
// ─────────────────────────────────────────────────────────────────────────────

class PdaTransition {
  /// Input symbol to consume.  Empty string = epsilon.
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
PdaTransition parsePdaLabel(String raw) {
  final s = raw.trim();
  final comma = s.indexOf(',');

  String read = '';
  String pop = '';
  List<String> push = [];

  if (comma < 0) {
    final sep = _findPopPushSeparator(s);
    if (sep >= 0) {
      read = _normalize(s.substring(0, sep));
      push = _parsePushString(s.substring(sep + 1));
    } else {
      read = _normalize(s);
    }
  } else {
    read = _normalize(s.substring(0, comma));
    final rest = s.substring(comma + 1);
    final sep = _findPopPushSeparator(rest);
    if (sep >= 0) {
      pop = _normalize(rest.substring(0, sep));
      push = _parsePushString(rest.substring(sep + 1));
    } else {
      pop = _normalize(rest);
    }
  }

  return PdaTransition(read: read, pop: pop, push: push);
}

/// Prefer `|` (standard); fall back to `/` (legacy).
int _findPopPushSeparator(String s) {
  final pipe = s.indexOf('|');
  final slash = s.indexOf('/');
  if (pipe >= 0 && (slash < 0 || pipe < slash)) return pipe;
  if (slash >= 0) return slash;
  return -1;
}

List<String> _parsePushString(String raw) {
  final t = _normalize(raw);
  if (t.isEmpty) return [];
  if (t.contains(' ')) {
    return t.split(' ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  return t.split('').toList();
}

String _normalize(String s) {
  final t = s.trim();
  if (t == '~' || t == 'ε') return '';
  return t;
}

// ─────────────────────────────────────────────────────────────────────────────
//  PDA Configuration  (state × remaining-input × stack)
// ─────────────────────────────────────────────────────────────────────────────

class PdaConfig {
  final String nodeId;
  final int inputPos;
  final List<String> stack;

  const PdaConfig({
    required this.nodeId,
    required this.inputPos,
    required this.stack,
  });

  String get stackKey => stack.reversed.join('|');

  String get key => '$nodeId:$inputPos:$stackKey';

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

  @override
  int get hashCode => Object.hash(nodeId, inputPos, Object.hashAll(stack));
}

/// One active NPDA configuration shown in the UI.
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

class PdaStepSnapshot {
  final List<PdaActiveConfig> configs;
  final Set<String> usedLineIds;

  const PdaStepSnapshot({required this.configs, required this.usedLineIds});

  Set<String> get activeNodeIds => {for (final c in configs) c.nodeId};
}

class PdaSimulator {
  PdaSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  List<String> tokens = [];
  final List<PdaStepSnapshot> steps = [];

  int step = -1;

  Set<String> get activeNodes {
    final idx = step + 1;
    if (idx < 0 || idx >= steps.length) return {};
    return steps[idx].activeNodeIds;
  }

  Set<String> get activeLines {
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
    if (step > tokens.length) step = tokens.length;
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _build(startArrow: startArrow);
    if (step > tokens.length) step = tokens.length;
  }

  PdaSimResult finalResult() {
    if (steps.isEmpty) return PdaSimResult.reject;
    final last = steps.last;

    if (last.configs.isEmpty) return PdaSimResult.reject;

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

  List<String> _tokenize(String input) {
    final result = <String>[];
    int i = 0;
    while (i < input.length) {
      if (input[i].trim().isEmpty) {
        i++;
        continue;
      }
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

  String _normalizeSym(String s) {
    final resolved = parseTokenText(s.trim());
    if (resolved == '~' || resolved == 'ε') return '';
    return resolved;
  }

  PdaActiveConfig _toActive(PdaConfig c) => PdaActiveConfig(
        nodeId: c.nodeId,
        inputPos: c.inputPos,
        stack: c.stack,
      );

  void _build({StartArrowData? startArrow}) {
    steps.clear();

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

    steps.add(PdaStepSnapshot(
      configs: initConfigs.map(_toActive).toList(),
      usedLineIds: initLines,
    ));

    Set<PdaConfig> current = initConfigs;

    for (int ti = 0; ti < tokens.length; ti++) {
      final token = _normalizeSym(tokens[ti]);
      final nextConfigs = <PdaConfig>{};
      final stepLines = <String>{};

      for (final config in current) {
        final node = nodes[config.nodeId];
        if (node == null) continue;
        if (node.isHaltReject) continue;

        if (node.isHaltAccept) {
          final snap = PdaStepSnapshot(
            configs: [_toActive(config)],
            usedLineIds: const {},
          );
          while (steps.length <= tokens.length) steps.add(snap);
          step = tokens.length;
          return;
        }

        for (final line in lines.values) {
          if (line.nodeAId != config.nodeId) continue;

          for (final altRaw in line.label.split('\n')) {
            final t = parsePdaLabel(altRaw);
            final readSym = _normalizeSym(t.read);
            if (readSym.isEmpty) continue;

            if (readSym != token) continue;

            final popSym = _normalizeSym(t.pop);
            final pushSyms = t.push.map(_normalizeSym).toList();

            final newStack = _applyStackOp(config.stack, popSym, pushSyms);
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

      final (closedConfigs, closedLines) = _epsilonClosure(nextConfigs);
      current = closedConfigs;
      steps.add(PdaStepSnapshot(
        configs: current.map(_toActive).toList(),
        usedLineIds: {...stepLines, ...closedLines},
      ));

      if (current.isEmpty) break;
    }

    while (steps.length <= tokens.length) {
      steps.add(const PdaStepSnapshot(configs: [], usedLineIds: {}));
    }
  }

  (Set<PdaConfig>, Set<String>) _epsilonClosure(Set<PdaConfig> start) {
    final visited = <String>{};
    final result = <PdaConfig>{...start};
    final linesUsed = <String>{};
    final queue = Queue<PdaConfig>.from(start);

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
          if (readSym.isNotEmpty) continue;

          final popSym = _normalizeSym(t.pop);
          final pushSyms = t.push.map(_normalizeSym).toList();

          final newStack = _applyStackOp(config.stack, popSym, pushSyms);
          if (newStack == null) continue;

          final next = PdaConfig(
            nodeId: line.nodeBId,
            inputPos: config.inputPos,
            stack: newStack,
          );

          if (result.add(next)) {
            linesUsed.add(line.id);
            queue.add(next);
          }
        }
      }
    }

    return (result, linesUsed);
  }

  List<String>? _applyStackOp(
    List<String> stack,
    String popSym,
    List<String> pushSyms,
  ) {
    List<String> s = List<String>.from(stack);

    if (popSym.isNotEmpty) {
      if (!_canPop(s, popSym)) return null;
      if (s.isNotEmpty) s.removeLast();
    }

    for (int i = pushSyms.length - 1; i >= 0; i--) {
      if (pushSyms[i].isNotEmpty) s.add(pushSyms[i]);
    }

    return s;
  }

  bool _canPop(List<String> stack, String popSym) {
    if (popSym == kStackBottom) {
      if (stack.isEmpty) return true;
      return stack.last == kStackBottom;
    }
    if (stack.isEmpty) return false;
    return stack.last == popSym;
  }
}
