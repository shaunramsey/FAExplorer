import 'dart:io';
import 'package:automata_designer/tm_simulator.dart';
import 'package:automata_designer/dsl_code.dart';

void main() {
  const dsl = '''tm mode
n0 = A
n1 = B
n2 = C
n3 = D
n4 = E
n5 = <<ha>>

A = (480.0, 225.3)
B = (894.6, 248.6)
C = (809.3, 483.3)
D = (534.0, 468.0)
E = (1180.6, 673.3)
ha = (1433.3, 846.6)

E to ha = \\0\\0S
A to ha = \\0\\0S
C to E = \\0\\0S
C to C = XXL
D to D = aaL
B to B = aaR\\nXXR
B to C = bXL
C to D = aaL
D to A = XXR
A to B = aXR
''';
  final state = DslCodec.importFromDsl(dsl);
  final tm = TmSimulator(nodes: state.nodes, lines: state.lines);
  final inputs = ['ab', 'aabb', 'aaabbb'];
  for (var input in inputs) {
    tm.rebuild(input, startArrow: state.startArrow);
    stdout.writeln('input=$input result=${tm.result} snapshots=${tm.snapshots.length}');
    for (var i = 0; i < tm.snapshots.length; i++) {
      final s = tm.snapshots[i];
      stdout.writeln('  step=$i node=${s.nodeId} head=${s.inputRelativeHead} tape=${s.tape.cells} used=${s.usedLineId}');
    }
  }
}
