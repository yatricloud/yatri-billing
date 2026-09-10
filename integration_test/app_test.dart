import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoiso/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End Test', () {
    testWidgets('verify dashboard, customers, and products',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 1. Dashboard is visible
      expect(find.textContaining('Payments and revenue'), findsWidgets);

      // 2. Navigate to Customers
      await tester.tap(find.text('Customers').last);
      await tester.pumpAndSettle();
      expect(find.text('Customers'), findsWidgets);

      // Add a Customer
      await tester.tap(find.text('Add Customer').last);
      await tester.pumpAndSettle();
      
      // Fill out Customer Form
      await tester.enterText(find.byType(TextFormField).at(0), 'Test Customer Inc');
      await tester.enterText(find.byType(TextFormField).at(1), 'test@example.com');
      await tester.enterText(find.byType(TextFormField).at(2), '9876543210');
      // tap save
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      // Verify Customer was created
      expect(find.text('Test Customer Inc'), findsWidgets);

      // 3. Navigate to Products
      await tester.tap(find.text('Products').last);
      await tester.pumpAndSettle();
      expect(find.text('Products & Services'), findsWidgets);

      // Add a Product
      await tester.tap(find.text('Add Product').last);
      await tester.pumpAndSettle();
      
      // Fill out Product Form
      await tester.enterText(find.byType(TextFormField).at(0), 'Integration Test Product');
      await tester.enterText(find.byType(TextFormField).at(2), '99.99'); // price
      // tap save
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      // Verify Product was created
      expect(find.text('Integration Test Product'), findsWidgets);

      // 4. Navigate back to Dashboard
      await tester.tap(find.text('Dashboard').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Payments and revenue'), findsWidgets);
    });
  });
}
