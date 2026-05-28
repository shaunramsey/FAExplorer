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
  final Map<String, ({bool accepted, List<String> outputTokens})>
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

  ({bool accepted, List<String> outputTokens}) _runBlackBox(
    NodeData node,
    List<String> inputTokens,
  ) {
    if (!node.isBlackBox) return (accepted: true, outputTokens: inputTokens);

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
      final input = inputTokens.join();
      switch (graph.automataMode) {
        case AutomataMode.ndfa:
          final sim = AutomataSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          return _blackBoxResultCache[cacheKey] = (
            accepted: sim.finalResult() == SimResult.accept,
            outputTokens: inputTokens,
          );
        case AutomataMode.pda:
          final sim = PdaSimulator(nodes: graph.nodes, lines: graph.lines);
          sim.rebuild(input, startArrow: graph.startArrow);
          return _blackBoxResultCache[cacheKey] = (
            accepted: sim.finalResult() == PdaSimResult.accept,
            outputTokens: inputTokens,
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
            );
          }
          return _blackBoxResultCache[cacheKey] = (
            accepted: true,
            outputTokens: _tmOutputTokens(sim),
          );
      }
    } catch (_) {
      return _blackBoxResultCache[cacheKey] = (
        accepted: false,
        outputTokens: const <String>[],
      );
    }
  }

  List<String> _tmOutputTokens(TmSimulator sim) {
    final tape = sim.currentTape;
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
          inputPos: 0,
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
            inputPos: 0,
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
