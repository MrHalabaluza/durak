import 'package:flutter_test/flutter_test.dart';
import 'package:ui/main.dart';

void main() {
  testWidgets('Setup screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DurakApp());
    expect(find.text('Начать игру'), findsOneWidget);
  });
}
