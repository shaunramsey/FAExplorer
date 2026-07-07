import 'package:flutter_test/flutter_test.dart';

import 'package:automata_designer/models.dart';
import 'package:automata_designer/simulator.dart';

StartArrowData _start(String nodeId) => StartArrowData(nodeId: nodeId);

Map<String, NodeData> _twoStateAcceptGraph() {
  return {
    'n0': NodeData(id: 'n0', position: Offset.zero),
    'n1': NodeData(id: 'n1', position: const Offset(100, 0), isAccept: true),
  };
}

Map<String, LineData> _line(String label) => {
      'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: label),
    };

void main() {
  group('AutomataSimulator transition labels', () {
    test('newline-separated alternatives both match', () {
      final sim = AutomataSimulator(
        nodes: _twoStateAcceptGraph(),
        lines: _line('a\nb'),
      );
      sim.rebuild('b', startArrow: _start('n0'));
      expect(sim.finalResult(), SimResult.accept);
    });

    test('literal \\n-separated alternatives both match', () {
      final sim = AutomataSimulator(
        nodes: _twoStateAcceptGraph(),
        lines: _line(r'a\nb'),
      );
      sim.rebuild('b', startArrow: _start('n0'));
      expect(sim.finalResult(), SimResult.accept);
    });
  });

  group('Tokenizer edge cases', () {
    test('unclosed quote becomes a single token', () {
      final sim = AutomataSimulator(
        nodes: _twoStateAcceptGraph(),
        lines: _line('hello'),
      );
      sim.rebuild('"hello', startArrow: _start('n0'));
      expect(sim.tokens, ['hello']);
      expect(sim.finalResult(), SimResult.accept);
    });

    test('malformed [[ without closing becomes one token', () {
      final sim = AutomataSimulator(
        nodes: _twoStateAcceptGraph(),
        lines: _line('[[BROKEN'),
      );
      sim.rebuild('[[BROKEN', startArrow: _start('n0'));
      expect(sim.tokens, ['[[BROKEN']);
      expect(sim.finalResult(), SimResult.accept);
    });
  });

  group('PdaSimulator step sync', () {
    test('rebuild preserves step within token range', () {
      final nodes = {
        'n0': NodeData(id: 'n0', position: Offset.zero),
        'n1': NodeData(id: 'n1', position: const Offset(100, 0), isAccept: true),
      };
      final lines = {
        'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: 'a'),
      };
      final pda = PdaSimulator(nodes: nodes, lines: lines);
      pda.rebuild('ab', startArrow: _start('n0'));
      pda.step = 1;
      pda.rebuild('ab', startArrow: _start('n0'));
      expect(pda.step, 1);
    });
  });
}
