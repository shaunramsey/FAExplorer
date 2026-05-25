import 'package:flutter_test/flutter_test.dart';

import 'package:automata_designer/main.dart';

void main() {
  testWidgets('Automata Designer loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Automata Designer'), findsOneWidget);
  });
}
