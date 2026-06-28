import 'package:flutter_test/flutter_test.dart';
import 'package:brainvault/main.dart';

void main() {
  testWidgets('BrainVault app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const BrainVaultApp());
    expect(find.text('BrainVault'), findsOneWidget);
    expect(find.text('Your external memory'), findsOneWidget);
  });
}
