import 'package:flutter_test/flutter_test.dart';

import 'package:automata_designer/models.dart';

void main() {
  group('LineData.computeGeometry', () {
    test('collinear arc anchor falls back to straight geometry', () {
      final line = LineData(
        id: 'l0',
        nodeAId: 'n0',
        nodeBId: 'n1',
        perpendicularPart: 10,
      );
      final centerA = const Offset(0, 0);
      final centerB = const Offset(200, 0);
      final geometry = line.computeGeometry(centerA, centerB);

      expect(geometry.hasCircle, isFalse);
      expect(geometry.startPoint.dx.isFinite, isTrue);
      expect(geometry.startPoint.dy.isFinite, isTrue);
      expect(geometry.endPoint.dx.isFinite, isTrue);
      expect(geometry.endPoint.dy.isFinite, isTrue);
    });
  });

  group('LineData.labelAlternatives', () {
    test('splits on comma and newline', () {
      final line = LineData(id: 'l0', nodeAId: 'n0', nodeBId: 'n1', label: 'a\nb,c');
      expect(line.labelAlternatives, ['a', 'b', 'c']);
    });
  });
}
