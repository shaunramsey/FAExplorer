import 'package:flutter_test/flutter_test.dart';

import 'package:automata_designer/auth/auth_service.dart';
import 'package:automata_designer/main.dart';

void main() {
  testWidgets('Shows login screen on first launch', (WidgetTester tester) async {
    final authService = AuthService(firebaseEnabled: false);
    await authService.init();

    await tester.pumpWidget(MyApp(
      authService: authService,
      firebaseEnabled: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Automata Designer'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
  });
}
