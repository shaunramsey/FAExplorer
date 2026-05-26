import 'package:flutter_test/flutter_test.dart';
import 'package:automata_designer/models.dart';
import 'package:automata_designer/pda_simulator.dart';
import 'package:automata_designer/dsl_code.dart';
import 'package:flutter/material.dart';

void main() {
  group('parsePdaLabel', () {
    test('standard a,x|y notation', () {
      final t = parsePdaLabel('a,x|y');
      expect(t.read, 'a');
      expect(t.pop, 'x');
      expect(t.push, ['y']);
    });

    test('epsilon and empty push', () {
      final t = parsePdaLabel('~,~/~');
      expect(t.read, isEmpty);
      expect(t.pop, isEmpty);
      expect(t.push, isEmpty);
    });

    test('legacy slash notation', () {
      final t = parsePdaLabel('a,Z/A Z');
      expect(t.read, 'a');
      expect(t.pop, 'Z');
      expect(t.push, ['A', 'Z']);
    });

    test('bottom marker and multi-push', () {
      final t = parsePdaLabel('a,∅|A ∅');
      expect(t.read, 'a');
      expect(t.pop, '∅');
      expect(t.push, ['A', '∅']);
    });
  });

  group('PdaSimulator', () {
    test('NPDA branches: two stacks after reading a', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: 'q0'),
        'n1': NodeData(id: 'n1', position: const Offset(100, 0), label: 'q1'),
        'n2': NodeData(id: 'n2', position: const Offset(200, 0), label: 'q2'),
      };
      final lines = <String, LineData>{
        'l1': LineData(id: 'l1', nodeAId: 'n0', nodeBId: 'n1', label: 'a,~|A'),
        'l2': LineData(id: 'l2', nodeAId: 'n0', nodeBId: 'n2', label: 'a,~|B'),
      };

      final sim = PdaSimulator(nodes: nodes, lines: lines);
      sim.rebuild('a', startArrow: StartArrowData(nodeId: 'n0'));
      sim.step = 1;

      expect(sim.activeConfigs.length, 2);
      expect(sim.allCurrentStacks.map((s) => s.join()), containsAll(['A', 'B']));
    });

    test('pop bottom marker on empty stack', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: 'q0', isAccept: true),
      };
      final lines = <String, LineData>{
        'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n0', label: '~,∅|~'),
      };

      final sim = PdaSimulator(nodes: nodes, lines: lines);
      sim.rebuild('', startArrow: StartArrowData(nodeId: 'n0'));
      sim.step = 0;

      expect(sim.finalResult(), PdaSimResult.accept);
    });

    test('remaining input tracks position', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: 'q0'),
        'n1': NodeData(id: 'n1', position: const Offset(100, 0), label: 'q1'),
      };
      final lines = <String, LineData>{
        'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: 'a,~|~'),
      };

      final sim = PdaSimulator(nodes: nodes, lines: lines);
      sim.rebuild('ab', startArrow: StartArrowData(nodeId: 'n0'));
      sim.step = 1;

      expect(sim.remainingInputAt(0), 'b');
    });
  });

  group('DslCodec pda mode', () {
    test('round-trips pda mode directive', () {
      const dsl = '''
pda mode
n0 = q0
q0 to q1 = a,x|y
''';

      final state = DslCodec.importFromDsl(dsl);
      expect(state.pdaMode, isTrue);

      final exported = DslCodec.exportToDsl(state);
      expect(exported.trimLeft().startsWith('pda mode'), isTrue);
    });
  });
}
