import 'package:flutter_test/flutter_test.dart';
import 'package:invoiso/models/customer.dart';
import 'package:invoiso/models/product.dart';
import 'package:invoiso/models/invoice.dart';
import 'package:invoiso/models/invoice_item.dart';
import 'package:invoiso/repositories/sqlite/sqlite_customer_repository.dart';
import 'package:invoiso/repositories/sqlite/sqlite_product_repository.dart';
import 'package:invoiso/repositories/sqlite/sqlite_invoice_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
      return '.';
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('run backend data seeder logic', () async {
    final customerRepo = SqliteCustomerRepository();
    final productRepo = SqliteProductRepository();
    final invoiceRepo = SqliteInvoiceRepository();

    print('Starting E2E Data Seeding & Verification...');

    // 1. Create Test Customers
    final acmeCustomer = Customer(
      id: 'cust_acme_001',
      name: 'Acme Corp',
      email: 'billing@acmecorp.example.com',
      phone: '9876543210',
      gstin: '22AAAAA0000A1Z5',
      address: '123 Business Rd, Tech Park, Bengaluru, Karnataka 560001',
    );
    await customerRepo.insertCustomer(acmeCustomer);
    print('✅ Customer created: Acme Corp');

    final globalCustomer = Customer(
      id: 'cust_glob_002',
      name: 'Global Tech LLC',
      email: 'finance@globaltech.example.com',
      phone: '1234567890',
      gstin: '07BBBBB0000B2Z6',
      address: '456 Innovation Drive, New Delhi, Delhi 110001',
    );
    await customerRepo.insertCustomer(globalCustomer);
    print('✅ Customer created: Global Tech LLC');

    // Verify Customers
    final customers = await customerRepo.getAllCustomers();
    if (customers.any((c) => c.id == 'cust_acme_001')) {
      print('✅ Verified: Customer Acme Corp exists in DB.');
    } else {
      throw Exception('Failed to fetch Acme Corp');
    }

    // 2. Create Test Products
    final proLicense = Product(
      id: 'prod_lic_001',
      name: 'Enterprise Software License',
      description: 'Annual license for enterprise platform',
      price: 15000.0,
      hsncode: '9983',
      tax_rate: 18,
      stock: 100,
    );
    await productRepo.insertProduct(proLicense);
    print('✅ Product created: Enterprise Software License');

    final consultingService = Product(
      id: 'prod_con_002',
      name: 'Cloud Consulting Services',
      description: 'Hourly rate for cloud architecture consulting',
      price: 5000.0,
      hsncode: '998311',
      tax_rate: 18,
      stock: 100,
      type: 'service',
    );
    await productRepo.insertProduct(consultingService);
    print('✅ Product created: Cloud Consulting Services');

    // Verify Products
    final products = await productRepo.getAllProducts();
    if (products.any((p) => p.id == 'prod_lic_001')) {
      print('✅ Verified: Product Enterprise Software License exists in DB.');
    } else {
      throw Exception('Failed to fetch Enterprise Software License');
    }

    // 3. Create Invoices
    final invoiceItems = [
      InvoiceItem(
        id: 'item_1',
        product: proLicense,
        quantity: 2,
        discount: 1000.0,
      ),
      InvoiceItem(
        id: 'item_2',
        product: consultingService,
        quantity: 10,
        discount: 0.0,
      )
    ];

    final invoice = Invoice(
      id: 'inv_test_001',
      customer: acmeCustomer,
      items: invoiceItems,
      date: DateTime.now(),
      type: 'invoice',
      dueDate: DateTime.now().add(const Duration(days: 15)),
      currencyCode: 'INR',
      notes: 'Thank you for your business.',
    );

    await invoiceRepo.insertInvoice(invoice);
    print('✅ Invoice created: test_001 for Acme Corp');

    // Verify Invoice
    final fetchedInvoice = await invoiceRepo.getInvoiceById('inv_test_001');
    if (fetchedInvoice != null) {
      print('✅ Verified: Invoice exists in DB.');
    } else {
      throw Exception('Failed to fetch Invoice');
    }

    print('\\n🎉 All End-to-End Database Feature Tests Passed successfully as per production constraints.');
  });
}
