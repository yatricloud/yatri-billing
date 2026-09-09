import 'package:uuid/uuid.dart';

import 'package:invoiso/domain/invoice_calculator.dart';
import 'package:invoiso/domain/payment_receipt_numbers.dart';
import 'package:invoiso/models/invoice.dart';
import 'package:invoiso/models/invoice_payment.dart';
import 'package:invoiso/repositories/payment_repository.dart';
import 'package:invoiso/utils/app_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [PaymentRepository].
///
/// Tenant isolation is enforced by RLS (the JWT `tenant_id` claim), so no
/// explicit tenant filter is needed in the queries below.
class SupabasePaymentRepository implements PaymentRepository {
  SupabaseClient get _c => Supabase.instance.client;
  static const _uuid = Uuid();

  @override
  Future<InvoicePayment> addPayment({
    required Invoice invoice,
    required double amountPaid,
    required DateTime datePaid,
    String? paymentMethod,
    String? notes,
  }) async {
    // 1. Snapshot: total already paid before this installment
    final previousRows = await _c
        .from('invoice_payments')
        .select('amount_paid, receipt_number')
        .eq('invoice_id', invoice.id);
    final previouslyPaid = previousRows.fold<double>(
      0.0,
      (sum, row) => sum + ((row['amount_paid'] as num?)?.toDouble() ?? 0.0),
    );

    // 2. Determine next receipt suffix using MAX to avoid reuse after deletions
    final receiptNumber = PaymentReceiptNumbers.nextReceiptNumber(
      invoiceId: invoice.id,
      existingReceiptNumbers:
          previousRows.map((row) => row['receipt_number'] as String?),
    );

    // 3. Compute tax portion proportionally
    final taxAmountPaid = invoice.total > 0
        ? (amountPaid * (invoice.tax / invoice.total))
        : 0.0;

    // 4. Snapshot: balance remaining after this installment
    final balanceAfter = InvoiceCalculator.outstanding(
      total: invoice.total,
      paid: previouslyPaid + amountPaid,
    );

    final saved = InvoicePayment(
      id: _uuid.v4(),
      invoiceId: invoice.id,
      invoiceNumber: invoice.invoiceNumber ?? invoice.id,
      receiptNumber: receiptNumber,
      amountPaid: amountPaid,
      taxAmountPaid: taxAmountPaid,
      previouslyPaid: previouslyPaid,
      balanceAfter: balanceAfter,
      datePaid: datePaid,
      paymentMethod: paymentMethod,
      notes: notes,
    );

    await _c.from('invoice_payments').insert(saved.toMap());
    return saved;
  }

  @override
  Future<int> addPaymentBatch({
    required List<Invoice> invoices,
    required DateTime datePaid,
    String? paymentMethod,
    String? notes,
  }) async {
    if (invoices.isEmpty) return 0;

    final payments = <Map<String, dynamic>>[];
    int count = 0;

    for (final invoice in invoices) {
      final amountPaid = invoice.outstandingBalance;
      if (amountPaid <= InvoiceCalculator.moneyEpsilon) continue;

      final previousRows = await _c
          .from('invoice_payments')
          .select('amount_paid, receipt_number')
          .eq('invoice_id', invoice.id);
      final previouslyPaid = previousRows.fold<double>(
        0.0,
        (sum, row) => sum + ((row['amount_paid'] as num?)?.toDouble() ?? 0.0),
      );

      final receiptNumber = PaymentReceiptNumbers.nextReceiptNumber(
        invoiceId: invoice.id,
        existingReceiptNumbers:
            previousRows.map((row) => row['receipt_number'] as String?),
      );

      final taxAmountPaid = invoice.total > 0
          ? (amountPaid * (invoice.tax / invoice.total))
          : 0.0;

      final payment = InvoicePayment(
        id: _uuid.v4(),
        invoiceId: invoice.id,
        invoiceNumber: invoice.invoiceNumber ?? invoice.id,
        receiptNumber: receiptNumber,
        amountPaid: amountPaid,
        taxAmountPaid: taxAmountPaid,
        previouslyPaid: previouslyPaid,
        balanceAfter: 0.0,
        datePaid: datePaid,
        paymentMethod: paymentMethod,
        notes: notes,
      );

      payments.add(payment.toMap());
      count++;
    }

    if (payments.isNotEmpty) {
      await _c.from('invoice_payments').insert(payments);
    }
    return count;
  }

  @override
  Future<List<InvoicePayment>> getPaymentsForInvoice(String invoiceId) async {
    final rows = await _c
        .from('invoice_payments')
        .select()
        .eq('invoice_id', invoiceId)
        .order('date_paid', ascending: true);
    return rows.map(InvoicePayment.fromMap).toList();
  }

  @override
  Future<double> getTotalPaidForInvoice(String invoiceId) async {
    final rows = await _c
        .from('invoice_payments')
        .select('amount_paid')
        .eq('invoice_id', invoiceId);
    return rows.fold<double>(
      0.0,
      (sum, row) => sum + ((row['amount_paid'] as num?)?.toDouble() ?? 0.0),
    );
  }

  @override
  Future<Map<String, double>> getTotalPaidBatch(
      List<String> invoiceIds) async {
    if (invoiceIds.isEmpty) return {};
    final rows = await _c
        .from('invoice_payments')
        .select('invoice_id, amount_paid')
        .inFilter('invoice_id', invoiceIds);
    final totals = <String, double>{};
    for (final row in rows) {
      final id = row['invoice_id'] as String;
      totals[id] =
          (totals[id] ?? 0.0) + ((row['amount_paid'] as num?)?.toDouble() ?? 0.0);
    }
    return totals;
  }

  @override
  Future<void> deletePayment(String paymentId) async {
    await _c.from('invoice_payments').delete().eq('id', paymentId);
  }

  @override
  Future<List<InvoicePayment>> getAllPaymentsBetween(
      DateTime from, DateTime to) async {
    final rows = await _c
        .from('invoice_payments')
        .select()
        .gte('date_paid', AppDate.dateKey(from))
        .lte('date_paid', AppDate.dateKey(to))
        .order('date_paid', ascending: true);
    return rows.map(InvoicePayment.fromMap).toList();
  }

  @override
  Future<double> getTaxPaidBetween(DateTime from, DateTime to) async {
    final rows = await _c
        .from('invoice_payments')
        .select('tax_amount_paid')
        .gte('date_paid', AppDate.dateKey(from))
        .lte('date_paid', AppDate.dateKey(to));
    return rows.fold<double>(
      0.0,
      (sum, row) =>
          sum + ((row['tax_amount_paid'] as num?)?.toDouble() ?? 0.0),
    );
  }
}
