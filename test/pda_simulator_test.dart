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

    test('3-part comma read,pop,push', () {
      final t = parsePdaLabel('a,X,y');
      expect(t.read, 'a');
      expect(t.pop, 'X');
      expect(t.push, ['y']);
    });

    test('3-character shorthand aXy', () {
      final t = parsePdaLabel('aXy');
      expect(t.read, 'a');
      expect(t.pop, 'X');
      expect(t.push, ['y']);
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

    test('state labels use hint text and disambiguate duplicates', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: ''),
        'n1': NodeData(id: 'n1', position: const Offset(100, 0), label: 'same'),
        'n2': NodeData(id: 'n2', position: const Offset(200, 0), label: 'same'),
      };

      expect(displayNodeLabel('n0', nodes), 'A');
      expect(displayNodeLabel('n1', nodes), 'same:N1');
      expect(displayNodeLabel('n2', nodes), 'same:N2');
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

    test('detects static ε push cycle ~,~|X', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: 'q0'),
      };
      final lines = <String, LineData>{
        'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n0', label: '~,~|X'),
      };

      final sim = PdaSimulator(nodes: nodes, lines: lines);
      sim.rebuild('', startArrow: StartArrowData(nodeId: 'n0'));

      expect(sim.stackGrowthLoopDetected, isTrue);
      expect(sim.activeConfigs, isEmpty);
    });

    test('detects longer ε push cycle across states', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: 'q0'),
        'n1': NodeData(id: 'n1', position: const Offset(80, 0), label: 'q1'),
      };
      final lines = <String, LineData>{
        'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: '~,~|A'),
        'l1': LineData(id: 'l1', nodeAId: 'n1', nodeBId: 'n0', label: '~,~|B'),
      };

      final sim = PdaSimulator(nodes: nodes, lines: lines);
      sim.rebuild('', startArrow: StartArrowData(nodeId: 'n0'));

      expect(sim.stackGrowthLoopDetected, isTrue);
    });

    test('allows ε drain loop ~,X|~', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: 'q0'),
        'n1': NodeData(id: 'n1', position: const Offset(80, 0), label: 'q1', isAccept: true),
      };
      final lines = <String, LineData>{
        'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: '~,∅|X'),
        'l1': LineData(id: 'l1', nodeAId: 'n1', nodeBId: 'n1', label: '~,X|~'),
      };

      final sim = PdaSimulator(nodes: nodes, lines: lines);
      sim.rebuild('', startArrow: StartArrowData(nodeId: 'n0'));

      expect(sim.stackGrowthLoopDetected, isFalse);
      expect(sim.finalResult(), PdaSimResult.accept);
    });

    test('treats read=∅ as ε at end-of-input (null jump)', () {
      final nodes = <String, NodeData>{
        'n0': NodeData(id: 'n0', position: Offset.zero, label: 'q0'),
        'n1': NodeData(id: 'n1', position: const Offset(100, 0), label: 'q1', isAccept: true),
      };
      final lines = <String, LineData>{
        // read=∅, pop=∅, push=~  should be taken as ε when input is fully consumed.
        'l0': LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: '∅,∅|~'),
      };

      final sim = PdaSimulator(nodes: nodes, lines: lines);
      sim.rebuild('', startArrow: StartArrowData(nodeId: 'n0'));

      expect(sim.activeConfigs.isNotEmpty, isTrue);
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
