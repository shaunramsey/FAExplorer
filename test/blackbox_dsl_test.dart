import 'package:flutter_test/flutter_test.dart';
import 'package:automata_designer/dsl_code.dart';
import 'package:automata_designer/models.dart';
import 'package:automata_designer/widgets/automata_drawer.dart';
import 'package:flutter/material.dart';

void main() {
  test('black box dsl block round-trips with blank lines', () {
    final state = GraphState(
      nodes: {
        'n0': NodeData(id: 'n0', position: const Offset(100, 100), label: 'BB'),
      },
      lines: {},
      startArrow: null,
      nodeCounter: 1,
      lineCounter: 0,
      automataMode: AutomataMode.ndfa,
    );
    final node = state.nodes['n0']!;
    node.isBlackBox = true;
    node.blackBoxDescription = 'My black box';
    node.blackBoxDsl = 'n0 = A\n\nn1 = B';

    final exported = DslCodec.exportToDsl(state);
    final imported = DslCodec.importFromDsl(exported);

    expect(imported.nodes['n0']!.label, 'BB');
    expect(imported.nodes['n0']!.blackBoxDescription, 'My black box');
    expect(imported.nodes['n0']!.blackBoxDsl, 'n0 = A\n\nn1 = B');
  });

  test('black box dsl round-trips leading and trailing blank lines', () {
    final state = GraphState(
      nodes: {
        'n0': NodeData(id: 'n0', position: const Offset(100, 100), label: 'BB'),
      },
      lines: {},
      startArrow: null,
      nodeCounter: 1,
      lineCounter: 0,
      automataMode: AutomataMode.ndfa,
    );
    final node = state.nodes['n0']!;
    node.isBlackBox = true;
    node.blackBoxDescription = 'My black box';
    node.blackBoxDsl = '\nn0 = A\n\nn1 = B\n';

    final exported = DslCodec.exportToDsl(state);
    final imported = DslCodec.importFromDsl(exported);

    expect(imported.nodes['n0']!.blackBoxDsl, '\nn0 = A\n\nn1 = B\n');
  });

  test('black box dsl preserves escaped backslashes and \n in labels', () {
    final state = GraphState(
      nodes: {
        'n0': NodeData(id: 'n0', position: const Offset(100, 100), label: 'BB'),
      },
      lines: {},
      startArrow: null,
      nodeCounter: 1,
      lineCounter: 0,
      automataMode: AutomataMode.ndfa,
    );
    final node = state.nodes['n0']!;
    node.isBlackBox = true;
    node.blackBoxDescription = 'Escaped content';
    node.blackBoxDsl = 'B to B = aaR\\nXXR\nC to E = \\\\0\\0R';

    final exported = DslCodec.exportToDsl(state);
    final imported = DslCodec.importFromDsl(exported);

    expect(imported.nodes['n0']!.blackBoxDsl, 'B to B = aaR\\nXXR\nC to E = \\\\0\\0R');
  });
}
