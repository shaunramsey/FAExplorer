import 'package:flutter_test/flutter_test.dart';
import 'package:automata_designer/models.dart';
import 'package:automata_designer/simulator.dart';

void main() {
  test('rebuild picks up transitions added after construction', () {
    final nodes = <String, NodeData>{
      'n0': NodeData(id: 'n0', position: const Offset(-50, -50), label: 'q0', isAccept: true),
      'n1': NodeData(id: 'n1', position: const Offset(50, -50), label: 'q1', isAccept: true),
    };
    final lines = <String, LineData>{};

    final sim = AutomataSimulator(nodes: nodes, lines: lines);
    final start = StartArrowData(nodeId: 'n0');

    sim.rebuild('a', startArrow: start);
    expect(sim.finalResult(), SimResult.reject);

    lines['l0'] = LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: 'a');
    sim.rebuild('a', startArrow: start);
    expect(sim.finalResult(), SimResult.accept);
  });

  test('rebuild can run twice without error (no stale adjacency)', () {
    final nodes = <String, NodeData>{
      'n0': NodeData(id: 'n0', position: const Offset(-50, -50), isAccept: true),
    };
    final sim = AutomataSimulator(nodes: nodes, lines: {});
    sim.rebuild('x', startArrow: StartArrowData(nodeId: 'n0'));
    sim.rebuild('y', startArrow: StartArrowData(nodeId: 'n0'));
    expect(sim.tokens, ['y']);
  });

  test('epsilon closure splits labels on commas and newlines', () {
    final nodes = <String, NodeData>{
      'n0': NodeData(id: 'n0', position: const Offset(-50, -50), isAccept: false),
      'n1': NodeData(id: 'n1', position: const Offset(50, -50), isAccept: true),
    };
    final lines = <String, LineData>{
      'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: '~\ny'),
    };

    final sim = AutomataSimulator(nodes: nodes, lines: lines);
    sim.rebuild('y', startArrow: StartArrowData(nodeId: 'n0'));
    expect(sim.finalResult(), SimResult.accept);
  });
}
