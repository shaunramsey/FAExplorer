import 'package:flutter_test/flutter_test.dart';
import 'package:automata_designer/dsl_code.dart';
import 'package:automata_designer/simulator.dart';

void main() {
  test('debug blackbox null jump', () {
    const dsl = '''tm mode

n0 = A
n4 = Export 4
n4 blackbox dsl {
  tm mode
  
  n0 = A
  n3 = <<hr>>
  
  n0 = (310.3, 172.0)
  hr = (563.3, 182.9)
  
  n0 to hr = aaR
  
  to n0
  to n0 angle = -1.0000, 0.0000
}

A = (310.3, 172.0)
Export 4 = (484.4, 374.1)

A to Export 4 = aaS
Export 4 to A = aaS

l0(aaS) curve = -107.9
l1(aaS) curve = -75.5

to A
to A angle = -1.0000, 0.0000
''';

    final g = DslCodec.importFromDsl(dsl);
    final sim = AutomataSimulator(nodes: g.nodes, lines: g.lines);
    // Try a single aaS token sequence that should enter the blackbox
    const input = 'aaS';
    sim.rebuild(input, startArrow: g.startArrow);

    print('Tokens: ${sim.tokens}');
    print('states.length = ${sim.states.length}');
    for (int i = -1; i < sim.states.length; i++) {
      sim.step = i;
      print('step=$i activeNodes=${sim.activeNodes} activeLines=${sim.activeLines}');
    }

    // Debug-only prints; no assertions.
  });

  test('tm blackbox can fall off with explicit ? transition', () {
    const dsl = '''tm mode

n0 = A
n1 = B
n2 = C

n1 blackbox dsl {
  tm mode

  n0 = A
  n0 = (0, 0)
  A is accepted

  to n0
}

A to B = a
B to C = ?

to A
''';

    final g = DslCodec.importFromDsl(dsl);
    final sim = AutomataSimulator(nodes: g.nodes, lines: g.lines);
    sim.rebuild('a', startArrow: g.startArrow);

    expect(sim.states.length, greaterThan(1));
    expect(sim.states.last.contains('n2'), isTrue);
  });
}
