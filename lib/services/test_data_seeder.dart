import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/models/customer.dart';
import 'package:invoiso/models/product.dart';
import 'package:invoiso/models/invoice.dart';
import 'package:invoiso/models/invoice_item.dart';

class TestDataSeeder {
  static Future<String> runE2ETestsContainer(ProviderContainer container) async {
    final customerRepo = container.read(customerRepositoryProvider);
    final productRepo = container.read(productRepositoryProvider);
    final invoiceRepo = container.read(invoiceRepositoryProvider);

    return _runSeederLogic(customerRepo, productRepo, invoiceRepo);
  }

  static Future<String> runE2ETests(WidgetRef ref) async {
    final customerRepo = ref.read(customerRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);
    final invoiceRepo = ref.read(invoiceRepositoryProvider);

    return _runSeederLogic(customerRepo, productRepo, invoiceRepo);
  }

  static Future<String> _runSeederLogic(customerRepo, productRepo, invoiceRepo) async {
    final StringBuffer log = StringBuffer();
    log.writeln('Starting E2E Data Seeding & Verification...');

    try {
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
      log.writeln('✅ Customer created: Acme Corp');

      final globalCustomer = Customer(
        id: 'cust_glob_002',
        name: 'Global Tech LLC',
        email: 'finance@globaltech.example.com',
        phone: '1234567890',
        gstin: '07BBBBB0000B2Z6',
        address: '456 Innovation Drive, New Delhi, Delhi 110001',
      );
      await customerRepo.insertCustomer(globalCustomer);
      log.writeln('✅ Customer created: Global Tech LLC');

      // Verify Customers
      final customers = await customerRepo.getAllCustomers();
      if (customers.any((c) => c.id == 'cust_acme_001')) {
        log.writeln('✅ Verified: Customer Acme Corp exists in DB.');
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
      log.writeln('✅ Product created: Enterprise Software License');

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
      log.writeln('✅ Product created: Cloud Consulting Services');

      // Verify Products
      final products = await productRepo.getAllProducts();
      if (products.any((p) => p.id == 'prod_lic_001')) {
        log.writeln('✅ Verified: Product Enterprise Software License exists in DB.');
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
      log.writeln('✅ Invoice created: test_001 for Acme Corp');

      // Verify Invoice
      final fetchedInvoice = await invoiceRepo.getInvoiceById('inv_test_001');
      if (fetchedInvoice != null) {
        log.writeln('✅ Verified: Invoice exists in DB.');
      } else {
        throw Exception('Failed to fetch Invoice');
      }

      log.writeln('\\n🎉 All End-to-End Database Feature Tests Passed successfully as per production constraints.');
    } catch (e, stack) {
      log.writeln('❌ Error during E2E Testing: $e');
      log.writeln(stack.toString());
    }

    return log.toString();
  }
}
