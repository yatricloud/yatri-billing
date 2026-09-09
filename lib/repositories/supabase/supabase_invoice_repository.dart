import 'package:uuid/uuid.dart';

import 'package:invoiso/common.dart';
import 'package:invoiso/domain/invoice_calculator.dart';
import 'package:invoiso/domain/invoice_totals_calculator.dart';
import 'package:invoiso/models/additional_cost.dart';
import 'package:invoiso/models/customer.dart';
import 'package:invoiso/models/invoice.dart';
import 'package:invoiso/models/invoice_item.dart';
import 'package:invoiso/models/invoice_payment.dart';
import 'package:invoiso/repositories/invoice_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_invoice_item_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_payment_repository.dart';
import 'package:invoiso/utils/app_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [InvoiceRepository].
///
/// Tenant isolation is enforced by RLS (the JWT `tenant_id` claim), so no
/// explicit tenant filter is needed in the queries below.
///
/// NOTE on ordering: the SQLite implementation orders by the numeric `id`
/// column as a monotonic sequence. Here `id` is a UUID (see [generateNextId]),
/// so chronological ordering uses `created_at` instead.
class SupabaseInvoiceRepository implements InvoiceRepository {
  SupabaseClient get _c => Supabase.instance.client;
  static const _uuid = Uuid();

  // ─────────────────────────────────────────────
  // Write paths

  @override
  Future<void> insertInvoice(Invoice invoice) async {
    await _c.from('invoices').insert(_invoiceRowMap(invoice));
    await _replaceItems(invoice.id, invoice.items);
  }

  @override
  Future<void> updateInvoice(Invoice invoice) async {
    final updateMap = _invoiceRowMap(invoice)..remove('id');
    await _c.from('invoices').update(updateMap).eq('id', invoice.id);
    // Replace items (delete existing + insert new). Payments are left untouched.
    await _replaceItems(invoice.id, invoice.items);
  }

  /// Deletes any existing rows for this invoice then inserts [items].
  Future<void> _replaceItems(String invoiceId, List<InvoiceItem> items) async {
    await _c.from('invoice_items').delete().eq('invoice_id', invoiceId);
    if (items.isNotEmpty) {
      await _c
          .from('invoice_items')
          .insert(items.map((item) => _itemRowMap(item, invoiceId)).toList());
    }
  }

  // ─────────────────────────────────────────────
  // Reads

  @override
  Future<Invoice?> getInvoiceById(String id) async {
    final rows = await _c
        .from('invoices')
        .select()
        .eq('id', id)
        .isFilter('deleted_at', null)
        .limit(1);
    if (rows.isEmpty) return null;

    final items = await SupabaseInvoiceItemRepository()
        .getInvoiceItemsByInvoiceId(id);
    final payments =
        await SupabasePaymentRepository().getPaymentsForInvoice(id);
    return _invoiceFromRow(
      Map<String, dynamic>.from(rows.first),
      items: items,
      payments: payments,
    );
  }

  @override
  Future<List<Invoice>> getAllInvoices() async {
    final rows = await _c
        .from('invoices')
        .select()
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return _buildInvoiceList(rows);
  }

  @override
  Future<List<Invoice>> getInvoicesForExport({
    DateTime? fromDate,
    DateTime? toDate,
    int? fromId,
    int? toId,
    String? filterType,
  }) async {
    var builder = _c.from('invoices').select().isFilter('deleted_at', null);
    if (filterType != null && filterType.isNotEmpty) {
      builder = builder.eq('type', filterType);
    }
    if (fromDate != null) {
      builder = builder.gte('date', AppDate.dateKeyStart(fromDate));
    }
    if (toDate != null) {
      builder = builder.lte('date', AppDate.dateKeyEnd(toDate));
    }
    // `fromId` / `toId` are numeric-range filters over the SQLite integer id.
    // With UUID primary keys these no longer apply, so they are intentionally
    // ignored here.
    final rows = await builder.order('date', ascending: true);
    return _buildInvoiceList(rows);
  }

  @override
  Future<int> countInvoicesForExport({
    DateTime? fromDate,
    DateTime? toDate,
    int? fromId,
    int? toId,
    String? filterType,
  }) async {
    var builder = _c
        .from('invoices')
        .select('id')
        .isFilter('deleted_at', null);
    if (filterType != null && filterType.isNotEmpty) {
      builder = builder.eq('type', filterType);
    }
    if (fromDate != null) {
      builder = builder.gte('date', AppDate.dateKeyStart(fromDate));
    }
    if (toDate != null) {
      builder = builder.lte('date', AppDate.dateKeyEnd(toDate));
    }
    final res = await builder.count(CountOption.exact);
    return res.count;
  }

  @override
  Future<List<Invoice>> getInvoicesPaginated({
    int page = 0,
    int pageSize = 50,
    String searchQuery = '',
    String? filterType,
  }) async {
    var builder = _c.from('invoices').select().isFilter('deleted_at', null);
    if (searchQuery.trim().isNotEmpty) {
      final q = _escape(searchQuery.trim().toLowerCase());
      builder = builder
          .or('customer_name.ilike.%$q%,id.ilike.%$q%');
    }
    if (filterType != null && filterType.isNotEmpty) {
      builder = builder.eq('type', filterType);
    }
    final rows = await builder
        .order('created_at', ascending: false)
        .range(page * pageSize, page * pageSize + pageSize - 1);
    return _buildInvoiceList(rows);
  }

  @override
  Future<int> getInvoiceCount({
    String searchQuery = '',
    String? filterType,
  }) async {
    var builder = _c
        .from('invoices')
        .select('id')
        .isFilter('deleted_at', null);
    if (searchQuery.trim().isNotEmpty) {
      final q = _escape(searchQuery.trim().toLowerCase());
      builder = builder.or('customer_name.ilike.%$q%,id.ilike.%$q%');
    }
    if (filterType != null && filterType.isNotEmpty) {
      builder = builder.eq('type', filterType);
    }
    final res = await builder.count(CountOption.exact);
    return res.count;
  }

  @override
  Future<int> getTotalInvoiceCountIncludingTrashed() async {
    final res = await _c
        .from('invoices')
        .select('id')
        .count(CountOption.exact);
    return res.count;
  }

  // ─────────────────────────────────────────────
  // Delete / restore

  @override
  Future<void> softDeleteInvoice(String id) async {
    await _c.from('invoices').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  @override
  Future<void> restoreInvoice(String id) async {
    await _c.from('invoices').update({'deleted_at': null}).eq('id', id);
  }

  @override
  Future<void> permanentDeleteInvoice(String id) async {
    await _c.from('invoice_items').delete().eq('invoice_id', id);
    await _c.from('invoice_payments').delete().eq('invoice_id', id);
    await _c.from('invoices').delete().eq('id', id);
  }

  @override
  Future<List<Invoice>> getDeletedInvoices() async {
    final rows = await _c
        .from('invoices')
        .select()
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
    return _buildInvoiceList(rows);
  }

  @override
  Future<void> deleteInvoice(String id) async {
    await permanentDeleteInvoice(id);
  }

  // ─────────────────────────────────────────────
  // Numbering

  @override
  Future<String> generateNextId() async {
    // SQLite used a zero-padded global numeric sequence as the PK. With
    // Postgres + RLS a globally unique UUID is the safe equivalent; uniqueness
    // is what matters, not the numeric shape.
    return _uuid.v4();
  }

  @override
  Future<String> generateNextInvoiceNumber(String type) async {
    // Atomically consume the per-type counter via the Postgres RPC.
    final result = await _c.rpc('next_invoice_number', params: {'_type': type});
    final next = (result as num).toInt();
    return next.toString().padLeft(8, '0');
  }

  @override
  Future<String> peekNextId() async {
    // A preview UUID — non-consuming.
    return _uuid.v4();
  }

  @override
  Future<String> peekNextInvoiceNumber(String type) async {
    // Non-consuming preview: read the current counter (without incrementing)
    // and display last+1. Note: if no counter row exists yet this under-counts
    // until [generateNextInvoiceNumber] creates one. Always call
    // [generateNextInvoiceNumber] again at save time.
    final row = await _c
        .from('invoice_counters')
        .select('last_value')
        .eq('type', type)
        .maybeSingle();
    final last = (row?['last_value'] as num?)?.toInt() ?? 0;
    return (last + 1).toString().padLeft(8, '0');
  }

  // ─────────────────────────────────────────────
  // Dashboard / reports (computed in Dart from fetched rows)

  @override
  Future<({int count, double revenue, double outstanding})>
      getDashboardFinancials() async {
    final countRes = await _c
        .from('invoices')
        .select('id')
        .eq('type', 'Invoice')
        .isFilter('deleted_at', null)
        .count(CountOption.exact);
    final count = countRes.count;

    final invoiceRows = await _c
        .from('invoices')
        .select()
        .eq('type', 'Invoice')
        .isFilter('deleted_at', null);

    double revenue = 0.0;
    if (invoiceRows.isNotEmpty) {
      final ids = invoiceRows.map((r) => r['id'] as String).toList();
      final payRows = await _c
          .from('invoice_payments')
          .select('amount_paid')
          .inFilter('invoice_id', ids);
      revenue = payRows.fold<double>(
        0.0,
        (sum, r) => sum + ((r['amount_paid'] as num?)?.toDouble() ?? 0.0),
      );
    }

    final outstanding = await _sumOutstandingForRows(invoiceRows);
    return (count: count, revenue: revenue, outstanding: outstanding);
  }

  @override
  Future<List<Invoice>> getRecentInvoices({int limit = 5}) async {
    final rows = await _c
        .from('invoices')
        .select()
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(limit);
    return _buildInvoiceList(rows);
  }

  @override
  Future<List<Invoice>> getDueSoonInvoices() async {
    final now = DateTime.now();
    final todayStart = AppDate.dateKeyStart(now);
    final tomorrowEnd =
        AppDate.dateKeyStart(DateTime(now.year, now.month, now.day + 2));
    final rows = await _c
        .from('invoices')
        .select()
        .isFilter('deleted_at', null)
        .eq('type', 'Invoice')
        .not('due_date', 'is', null)
        .gte('due_date', todayStart)
        .lt('due_date', tomorrowEnd)
        .order('due_date', ascending: true);
    final invoices = await _buildInvoiceList(rows);
    return invoices
        .where((inv) => inv.outstandingBalance > InvoiceCalculator.moneyEpsilon)
        .toList();
  }

  @override
  Future<List<Invoice>> getOverdueInvoices({int limit = 10}) async {
    final todayStart = AppDate.dateKeyStart(DateTime.now());
    final rows = await _c
        .from('invoices')
        .select()
        .isFilter('deleted_at', null)
        .eq('type', 'Invoice')
        .not('due_date', 'is', null)
        .lt('due_date', todayStart)
        .order('due_date', ascending: true)
        .limit(limit * 3);
    final invoices = await _buildInvoiceList(rows);
    final overdue = invoices
        .where((inv) => InvoiceCalculator.isOverdue(
              dueDate: inv.dueDate,
              outstanding: inv.outstandingBalance,
            ))
        .toList();
    return overdue.length > limit ? overdue.sublist(0, limit) : overdue;
  }

  @override
  Future<List<Map<String, dynamic>>> getMonthlyRevenue() async {
    final now = DateTime.now();
    const months = 6;
    final cutoff =
        '${now.subtract(Duration(days: months * 31)).year.toString().padLeft(4, '0')}-${now.subtract(Duration(days: months * 31)).month.toString().padLeft(2, '0')}-01';

    final invoiceIds = await _c
        .from('invoices')
        .select('id')
        .eq('type', 'Invoice')
        .isFilter('deleted_at', null);
    final ids = invoiceIds.map((r) => r['id'] as String).toList();
    if (ids.isEmpty) return [];

    final payRows = await _c
        .from('invoice_payments')
        .select('date_paid, amount_paid')
        .inFilter('invoice_id', ids)
        .gte('date_paid', cutoff);

    final byMonth = <String, double>{};
    for (final row in payRows) {
      final paid = (row['amount_paid'] as num?)?.toDouble() ?? 0.0;
      final raw = row['date_paid'] as String?;
      if (raw == null || raw.length < 7) continue;
      final month = raw.substring(0, 7);
      byMonth[month] = (byMonth[month] ?? 0.0) + paid;
    }

    final keys = byMonth.keys.toList()..sort();
    return keys
        .map((m) => {'month': m, 'revenue': byMonth[m] ?? 0.0})
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getTopCustomers() async {
    const limit = 5;
    final invoiceRows = await _c
        .from('invoices')
        .select('id, customer_name')
        .eq('type', 'Invoice')
        .isFilter('deleted_at', null);
    final ids = invoiceRows.map((r) => r['id'] as String).toList();

    final paidByInvoice = <String, double>{};
    if (ids.isNotEmpty) {
      final payRows = await _c
          .from('invoice_payments')
          .select('invoice_id, amount_paid')
          .inFilter('invoice_id', ids);
      for (final row in payRows) {
        final invId = row['invoice_id'] as String;
        paidByInvoice[invId] =
            (paidByInvoice[invId] ?? 0.0) +
            ((row['amount_paid'] as num?)?.toDouble() ?? 0.0);
      }
    }

    final byCustomer = <String, ({double totalPaid, int count})>{};
    for (final row in invoiceRows) {
      final name = (row['customer_name'] as String?) ?? '';
      final entry = byCustomer[name] ?? (totalPaid: 0.0, count: 0);
      byCustomer[name] = (
        totalPaid: entry.totalPaid + (paidByInvoice[row['id'] as String] ?? 0.0),
        count: entry.count + 1,
      );
    }

    final results = byCustomer.entries
        .map((e) => {
              'customer_name': e.key,
              'total_paid': e.value.totalPaid,
              'invoice_count': e.value.count,
            })
        .toList();
    results.sort((a, b) {
      final byPaid = (b['total_paid'] as double).compareTo(a['total_paid'] as double);
      if (byPaid != 0) return byPaid;
      return (b['invoice_count'] as int).compareTo(a['invoice_count'] as int);
    });
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  @override
  Future<List<Map<String, dynamic>>> getTopProducts() async {
    const limit = 5;
    final invoiceRows = await _c
        .from('invoices')
        .select('id')
        .eq('type', 'Invoice')
        .isFilter('deleted_at', null);
    final ids = invoiceRows.map((r) => r['id'] as String).toList();
    if (ids.isEmpty) return [];

    final itemRows = await _c
        .from('invoice_items')
        .select('product_name, quantity')
        .inFilter('invoice_id', ids);

    final byProduct = <String, double>{};
    for (final row in itemRows) {
      final name = (row['product_name'] as String?) ?? '';
      if (name.isEmpty) continue;
      final qty = (row['quantity'] as num?)?.toDouble() ?? 0.0;
      byProduct[name] = (byProduct[name] ?? 0.0) + qty;
    }

    final results = byProduct.entries
        .map((e) => {'product_name': e.key, 'total_qty': e.value})
        .toList()
      ..sort((a, b) =>
          (b['total_qty'] as double).compareTo(a['total_qty'] as double));
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  // ─────────────────────────────────────────────
  // Previous balance due

  @override
  Future<double> getPreviousBalanceDueForInvoice(Invoice invoice) async {
    if (invoice.type != 'Invoice' || invoice.customer.id.trim().isEmpty) {
      return 0.0;
    }
    return getPreviousBalanceDueForCustomer(
      customerId: invoice.customer.id,
      currencyCode: invoice.currencyCode,
      asOfDate: invoice.date,
      currentInvoiceId: invoice.id,
    );
  }

  @override
  Future<double> getPreviousBalanceDueForCustomer({
    required String customerId,
    required String currencyCode,
    required DateTime asOfDate,
    String? currentInvoiceId,
  }) async {
    final normalizedCustomerId = customerId.trim();
    if (normalizedCustomerId.isEmpty) return 0.0;

    // Fetch all matching invoices, then apply the date/id ordering in Dart
    // (mirrors the SQLite `substr(date,1,10)` + `id` tie-break logic).
    final invoiceRows = await _c
        .from('invoices')
        .select('id, tax_rate, tax_mode, additional_costs, date')
        .eq('customer_id', normalizedCustomerId)
        .eq('type', 'Invoice')
        .isFilter('deleted_at', null)
        .eq('currency_code', currencyCode);

    final invoiceDateKey = AppDate.dateKey(asOfDate);
    final sameDayId = currentInvoiceId?.trim();

    final prior = <Map<String, dynamic>>[];
    for (final row in invoiceRows) {
      final rowDate = (row['date'] as String?) ?? '';
      final datePart = rowDate.length >= 10 ? rowDate.substring(0, 10) : rowDate;
      final id = row['id'] as String;
      if (datePart.compareTo(invoiceDateKey) < 0) {
        prior.add(Map<String, dynamic>.from(row));
      } else if (datePart == invoiceDateKey &&
          sameDayId != null &&
          sameDayId.isNotEmpty &&
          id.compareTo(sameDayId) < 0) {
        prior.add(Map<String, dynamic>.from(row));
      }
    }

    return _sumOutstandingForRows(prior);
  }

  // ─────────────────────────────────────────────
  // Private helpers

  /// Sums outstanding balances across [invoiceRows] (which must include the
  /// `id`, `tax_rate`, `tax_mode` and `additional_costs` columns). Items and
  /// payments are batch-loaded in two queries.
  Future<double> _sumOutstandingForRows(
      List<Map<String, dynamic>> invoiceRows) async {
    if (invoiceRows.isEmpty) return 0.0;
    final ids = invoiceRows.map((r) => r['id'] as String).toList();

    final itemRows = await _c
        .from('invoice_items')
        .select(
          'invoice_id, unit_price, product_price, quantity, discount, '
          'discount_per_unit, extra_cost, product_tax_rate, '
          'product_price_includes_tax',
        )
        .inFilter('invoice_id', ids);

    final payRows = await _c
        .from('invoice_payments')
        .select('invoice_id, amount_paid')
        .inFilter('invoice_id', ids);

    final itemsByInvoice = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      final invId = row['invoice_id'] as String;
      itemsByInvoice.putIfAbsent(invId, () => []).add(Map<String, dynamic>.from(row));
    }

    final paidByInvoice = <String, double>{};
    for (final row in payRows) {
      final invId = row['invoice_id'] as String;
      paidByInvoice[invId] =
          (paidByInvoice[invId] ?? 0.0) +
          ((row['amount_paid'] as num?)?.toDouble() ?? 0.0);
    }

    double sum = 0.0;
    for (final inv in invoiceRows) {
      final invId = inv['id'] as String;
      final taxRate = (inv['tax_rate'] as num?)?.toDouble() ?? 0.0;
      final taxMode = TaxModeExtension.fromKey(inv['tax_mode'] as String?);
      final items = itemsByInvoice[invId] ?? [];
      final additionalTotal = AdditionalCost
          .listFromJson(inv['additional_costs'] as String?)
          .fold(0.0, (s, c) => s + c.amount);
      final totals = InvoiceTotalsCalculator.totals(
        lines: items.map((r) => InvoiceTotalsCalculator.lineFromDbRow(
              r,
              taxMode: taxMode,
              globalTaxRatePercent: taxRate * 100,
            )),
        taxMode: taxMode,
        globalTaxRate: taxRate,
        globalTaxRateFormat: TaxRateFormat.fraction,
        additionalCostsTotal: additionalTotal,
      );
      sum += InvoiceCalculator.outstanding(
        total: totals.total,
        paid: paidByInvoice[invId] ?? 0.0,
      );
    }
    return sum;
  }

  /// Serializes an [Invoice] to the `invoices` row (denormalized customer
  /// fields + `additional_costs` as a JSON string). Mirrors the SQLite insert.
  Map<String, dynamic> _invoiceRowMap(Invoice invoice) => {
        'id': invoice.id,
        'invoice_number': invoice.invoiceNumber,
        'customer_id': invoice.customer.id,
        'customer_name': invoice.customer.name,
        'customer_email': invoice.customer.email,
        'customer_phone': invoice.customer.phone,
        'customer_address': invoice.customer.address,
        'customer_gstin': invoice.customer.gstin,
        'customer_business_name': invoice.customer.businessName,
        'date': invoice.date.toIso8601String(),
        'notes': invoice.notes,
        'tax_rate': invoice.taxRate,
        'type': invoice.type,
        'invoice_title': invoice.invoiceTitle,
        'currency_code': invoice.currencyCode,
        'currency_symbol': invoice.currencySymbol,
        'tax_mode': invoice.taxMode.key,
        'upi_id': invoice.upiId,
        'bank_account_id': invoice.bankAccountId,
        'due_date': invoice.dueDate?.toIso8601String(),
        'quantity_label': invoice.quantityLabel,
        'additional_costs': AdditionalCost.listToJson(invoice.additionalCosts),
        'previous_balance': invoice.previousBalance,
      };

  /// Serializes an [InvoiceItem] to an `invoice_items` row.
  Map<String, dynamic> _itemRowMap(InvoiceItem item, String invoiceId) => {
        'id': item.id,
        'invoice_id': invoiceId,
        'product_id': item.product.id,
        'product_name': item.product.name,
        'product_description': item.product.description,
        'product_price': item.product.price,
        'product_tax_rate': item.product.tax_rate,
        'product_price_includes_tax': item.product.priceIncludesTax ? 1 : 0,
        'product_hsn_code': item.product.hsncode,
        'quantity': item.quantity,
        'discount': item.discount,
        'unit_price': item.unitPrice,
        'extra_cost': item.extraCost,
        'discount_per_unit': item.discountPerUnit ? 1 : 0,
        'is_product_saved': item.isProductSaved ? 1 : 0,
        'product_type': item.product.type,
        'product_purchase_price': item.product.purchasePrice,
        'product_alias_name': item.product.aliasName,
        'product_unit': item.product.unit,
        'unit': item.unit,
      };

  /// Builds an [Invoice] from a raw `invoices` row (snake_case column keys).
  Invoice _invoiceFromRow(
    Map<String, dynamic> i, {
    List<InvoiceItem> items = const [],
    List<InvoicePayment> payments = const [],
  }) {
    final customer = Customer.fromMap({
      'id': i['customer_id'],
      'name': i['customer_name'],
      'email': i['customer_email'],
      'phone': i['customer_phone'],
      'address': i['customer_address'],
      'gstin': i['customer_gstin'],
      'business_name': i['customer_business_name'] ?? '',
    });
    final taxRateRaw = i['tax_rate'];
    return Invoice(
      id: i['id'] as String,
      invoiceNumber: i['invoice_number'] as String?,
      customer: customer,
      items: items,
      date: DateTime.tryParse(i['date'] as String) ?? DateTime.now(),
      notes: i['notes'] as String?,
      taxRate: (taxRateRaw is num) ? taxRateRaw.toDouble() : 0.0,
      type: (i['type'] as String?) ?? '',
      invoiceTitle: i['invoice_title'] as String?,
      currencyCode: (i['currency_code'] as String?) ?? 'INR',
      currencySymbol: (i['currency_symbol'] as String?) ?? '₹',
      taxMode: TaxModeExtension.fromKey(i['tax_mode'] as String?),
      upiId: i['upi_id'] as String?,
      bankAccountId: i['bank_account_id'] as String?,
      dueDate: i['due_date'] != null
          ? DateTime.tryParse(i['due_date'] as String)
          : null,
      quantityLabel: i['quantity_label'] as String?,
      additionalCosts:
          AdditionalCost.listFromJson(i['additional_costs'] as String?),
      previousBalance: (i['previous_balance'] as num?)?.toDouble() ?? 0.0,
      payments: payments,
    );
  }

  /// Builds a list of [Invoice]s with items (per-invoice) and payments
  /// (batch-loaded in one query).
  Future<List<Invoice>> _buildInvoiceList(
      List<Map<String, dynamic>> invoiceMaps) async {
    if (invoiceMaps.isEmpty) return [];

    final invoices = <Invoice>[];
    for (final map in invoiceMaps) {
      final invoiceId = map['id'] as String?;
      if (invoiceId == null || map['date'] == null) continue;
      final items = await SupabaseInvoiceItemRepository()
          .getInvoiceItemsByInvoiceId(invoiceId);
      invoices.add(_invoiceFromRow(Map<String, dynamic>.from(map), items: items));
    }

    if (invoices.isNotEmpty) {
      final ids = invoices.map((inv) => inv.id).toList();
      final paymentRows = await _c
          .from('invoice_payments')
          .select()
          .inFilter('invoice_id', ids);
      final paymentsByInvoice = <String, List<Map<String, dynamic>>>{};
      for (final row in paymentRows) {
        final invId = row['invoice_id'] as String;
        paymentsByInvoice
            .putIfAbsent(invId, () => [])
            .add(Map<String, dynamic>.from(row));
      }
      for (final inv in invoices) {
        inv.payments = (paymentsByInvoice[inv.id] ?? [])
            .map(InvoicePayment.fromMap)
            .toList();
      }
    }

    return invoices;
  }

  /// Supabase `.or()` / `.eq()` filter values need comma and dot escaped.
  String _escape(String v) =>
      v.replaceAll(',', '%2C').replaceAll('.', '%2E');
}
