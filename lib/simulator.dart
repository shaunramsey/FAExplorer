import 'dart:collection';

import 'dsl_code.dart';
import 'models.dart';
import 'pda_simulator.dart';
import 'tm_simulator.dart';
import 'token_replacements.dart';
import 'widgets/automata_drawer.dart' show AutomataMode;

enum SimResult { accept, reject }

class _SimConfig {
  final String nodeId;
  final List<String> tokens;
  final int inputPos;

  const _SimConfig({
    required this.nodeId,
    required this.tokens,
    required this.inputPos,
  });

  String get key => '$nodeId:$inputPos:${tokens.join('\u0001')}';
}

final _transitionLabelSplitter = RegExp(r'[,\\n]');
final _epsilonLabelSplitter = RegExp(r'[,\n]');

class AutomataSimulator {
  AutomataSimulator({required this.nodes, required this.lines});

  final Map<String, NodeData> nodes;
  final Map<String, LineData> lines;

  List<String> tokens = [];
  final List<Set<String>> states = [];
  final List<Set<String>> usedLines = [];
  final List<List<_SimConfig>> _configsByStep = [];
  // outputHeadPos: index into outputTokens where the outer machine should
  // resume reading after the black box runs.  For NFA/PDA black boxes this is
  // always 0 (the inner machine accepts/rejects the whole input and the outer
  // machine continues from the beginning of the transformed token list).  For
  // TM black boxes it is the absolute tape-head position that the inner TM
  // left its head at, converted to a logical token index so the outer NFA
  // step-loop can use it as the new inputPos.
  final Map<String, ({bool accepted, List<String> outputTokens, int outputHeadPos})>
      _blackBoxResultCache = {};

  int step = -1;

  Set<String> get activeNodes {
    if (states.isEmpty) return {};
    final idx = step + 1;
    if (idx < 0 || idx >= states.length) return {};
    return UnmodifiableSetView(states[idx]);
  }

  Set<String> get activeLines {
    if (usedLines.isEmpty) return {};
    final idx = step + 1;
    if (idx < 0 || idx >= usedLines.length) return {};
    return UnmodifiableSetView(usedLines[idx]);
  }

  void rebuild(String input, {StartArrowData? startArrow}) {
    tokens = _tokenize(input);
    _blackBoxResultCache.clear();
    _buildSimulation(startArrow: startArrow);
    if (step > tokens.length) {
      step = tokens.length;
    }
  }

  void rebuildGraph({StartArrowData? startArrow}) {
    _buildSimulation(startArrow: startArrow);
    if (step > tokens.length) {
      step = tokens.length;
    }
  }

  SimResult finalResult() {
    if (_configsByStep.isEmpty) return SimResult.reject;

    for (final snapshot in _configsByStep) {
      for (final config in snapshot) {
        if (nodes[config.nodeId]?.isHaltAccept == true) {
          return SimResult.accept;
        }
      }
    }

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

  String _normalizeSimToken(String token) => _resolveCommand(token.trim());

  bool _isNullToken(String token) => _normalizeSimToken(token) == '?';

  bool _isEpsilonLabel(String label, bool atEndOfInput, bool nullWasExplicitlyTyped) {
    final normalized = _normalizeSimToken(label);
    if (normalized.isEmpty || normalized == '~') return true;
    if (normalized == '?') return atEndOfInput && !nullWasExplicitlyTyped;
    return false;
  }

  Iterable<String> _epsilonAlternatives(String label) =>
      label.split(_epsilonLabelSplitter).map((s) => s.trim());

  Iterable<String> _transitionAlternatives(String label) =>
      label.split(_transitionLabelSplitter).map((s) => s.trim());

  ({bool accepted, List<String> outputTokens, int outputHeadPos}) _runBlackBox(
    NodeData node,
    List<String> inputTokens,
  ) {
    if (!node.isBlackBox) {
      return (accepted: true, outputTokens: inputTokens, outputHeadPos: 0);
    }

    final cacheKey = '${node.id}:${inputTokens.join('\u0001')}';
    final cached = _blackBoxResultCache[cacheKey];
    if (cached != null) return cached;

    final dsl = node.blackBoxDsl.trim();
    if (dsl.isEmpty) {
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
        outputHeadPos: 0,
      );
    }

    try {
      final graph = DslCodec.importFromDsl(dsl);
      final input = inputTokens.join();
      switch (graph.automataMode) {
        case AutomataMode.ndfa:
          final sim = AutomataSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          final accepted = sim.finalResult() == SimResult.accept;
          return _blackBoxResultCache[cacheKey] = (
            accepted: accepted,
            outputTokens: accepted ? inputTokens : const <String>[],
            outputHeadPos: 0,
          );
        case AutomataMode.pda:
          final sim = PdaSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          final accepted = sim.finalResult() == PdaSimResult.accept;
          return _blackBoxResultCache[cacheKey] = (
            accepted: accepted,
            outputTokens: accepted ? inputTokens : const <String>[],
            outputHeadPos: 0,
          );
        case AutomataMode.tm:
          final sim = TmSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          while (sim.computeNext()) {}
          final hasHaltAccept = _tmHasExplicitHaltAccept(sim);
          if (!hasHaltAccept) {
            return _blackBoxResultCache[cacheKey] = (
              accepted: false,
              outputTokens: const <String>[],
              outputHeadPos: 0,
            );
          }
          final (outputTokens: outTokens, outputHeadPos: outHeadPos) =
              _tmOutputTokensAndHead(sim);
          return _blackBoxResultCache[cacheKey] = (
            accepted: true,
            outputTokens: outTokens,
            outputHeadPos: outHeadPos,
          );
      }
    } catch (_) {
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
        outputHeadPos: 0,
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
    // Instead, pull the halt-accept config directly from the last snapshot.
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

    final outputTokens =
        start >= end ? const <String>[] : cells.sublist(start, end);

    // Translate the absolute head position to an index in outputTokens.
    // Clamp so it always points at a valid position (or 0 for an empty tape).
    int outputHeadPos = 0;
    if (outputTokens.isNotEmpty) {
      outputHeadPos = (rawHeadPos - start).clamp(0, outputTokens.length - 1);
    }

    return (outputTokens: outputTokens, outputHeadPos: outputHeadPos);
  }

  bool _tmHasExplicitHaltAccept(TmSimulator sim) {
    if (sim.steps.isEmpty) return false;
    final last = sim.steps.last;
    for (final config in last.configs) {
      final node = sim.nodes[config.nodeId];
      if (node?.isHaltAccept == true) return true;
    }
    return false;
  }

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
        final result = _runBlackBox(currentNode, current.tokens);
        if (!result.accepted) {
          visitedConfigs.remove(current.key);
          continue;
        }
        effective = _SimConfig(
          nodeId: current.nodeId,
          tokens: result.outputTokens,
          inputPos: result.outputHeadPos,
        );
        if (!visitedConfigs.containsKey(effective.key)) {
          visitedConfigs[effective.key] = effective;
          queue.add(effective);
        } else if (effective.key != current.key) {
          continue;
        }
      }

      if (currentNode.isHaltAccept || currentNode.isHaltReject) continue;

      for (final line in lines.values) {
        if (line.nodeAId != effective.nodeId) continue;
        bool isNormalEpsilon = false;
        bool isNullJump = false;
        final atEndOfInput = effective.inputPos >= effective.tokens.length;
        final nullWasExplicitlyTyped = effective.tokens.any(_isNullToken);

        for (final alt in _epsilonAlternatives(line.label)) {
          final normalized = _normalizeSimToken(alt);
          if (normalized.isEmpty || normalized == '~') isNormalEpsilon = true;
          if (normalized == '?' && atEndOfInput && !nullWasExplicitlyTyped) {
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

  void _buildSimulation({StartArrowData? startArrow}) {
    states.clear();
    usedLines.clear();
    _configsByStep.clear();

    if (startArrow == null || !nodes.containsKey(startArrow.nodeId)) {
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

    const int kMaxSteps = 512;
    int stepsBuilt = 0;
    while (current.isNotEmpty && stepsBuilt < kMaxSteps) {
      final stepLines = <String>{};
      final nextConfigs = <_SimConfig>{};
      bool consumedAny = false;

      for (final config in current) {
        final node = nodes[config.nodeId];
        if (node == null || node.isHaltReject || node.isHaltAccept) continue;

        var effective = config;
        if (node.isBlackBox) {
          final result = _runBlackBox(node, config.tokens);
          if (!result.accepted) continue;
          effective = _SimConfig(
            nodeId: config.nodeId,
            tokens: result.outputTokens,
            inputPos: result.outputHeadPos,
          );
        }

        if (effective.inputPos >= effective.tokens.length) continue;

        final token = effective.tokens[effective.inputPos];
        final nullWasExplicitlyTyped = effective.tokens.any(_isNullToken);

        for (final line in lines.values) {
          if (line.nodeAId != effective.nodeId) continue;
          for (final alt in _transitionAlternatives(line.label)) {
            if (_isEpsilonLabel(alt, false, nullWasExplicitlyTyped)) continue;
            if (_normalizeSimToken(alt) == _normalizeSimToken(token)) {
              consumedAny = true;
              nextConfigs.add(
                _SimConfig(
                  nodeId: line.nodeBId,
                  tokens: effective.tokens,
                  inputPos: effective.inputPos + 1,
                ),
              );
              stepLines.add(line.id);
              break;
            }
          }
        }
      }

      if (!consumedAny || nextConfigs.isEmpty) break;

      final (closureConfigs, closureLines) = _epsilonClosure(nextConfigs);
      current = closureConfigs;
      states.add({for (final c in current) c.nodeId});
      usedLines.add({...stepLines, ...closureLines});
      _configsByStep.add(List<_SimConfig>.from(current));
      stepsBuilt++;
      if (current.isEmpty) break;
    }
  }
}