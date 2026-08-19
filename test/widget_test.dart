import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pakistan_sme_billing/main.dart';

void main() {
  testWidgets('POS Billing Counter smoke test', (WidgetTester tester) async {
    // Build our app with ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: PakistanSmeBillingApp(),
      ),
    );

    // Verify that the POS Billing Counter title is rendered.
    expect(find.text('POS Billing Counter'), findsOneWidget);
    expect(find.text('Cart is empty'), findsOneWidget);
    expect(find.text('Total Amount'), findsOneWidget);
  });
}
