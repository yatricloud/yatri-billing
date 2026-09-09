import 'package:invoiso/common.dart';
import 'package:invoiso/domain/customer_identity.dart';
import 'package:invoiso/domain/invoice_calculator.dart';
import 'package:invoiso/domain/invoice_totals_calculator.dart';
import 'package:invoiso/models/additional_cost.dart';
import 'package:invoiso/models/report_models.dart';
import 'package:invoiso/repositories/report_repository.dart';
import 'package:invoiso/utils/app_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [ReportRepository].
///
/// Tenant isolation is enforced by RLS (the JWT `tenant_id` claim), so no
/// explicit tenant filter is needed in the queries below.
///
/// The reference implementation (`lib/database/report_service.dart`) computes
/// every metric in SQLite. PostgREST cannot express those aggregates directly
/// (no cross-table aggregates, no inline CASE/revenue de-embedding), so this
/// implementation fetches the underlying rows — applying the identical
/// date-range string comparison and currency filtering — and reproduces the
/// exact same aggregations in Dart, reusing the shared domain calculators
/// (InvoiceTotalsCalculator / InvoiceCalculator) so results match byte-for-byte.
class SupabaseReportRepository implements ReportRepository {
  SupabaseClient get _c => Supabase.instance.client;

  static const _invoiceCols = [
    'id',
    'customer_id',
    'customer_name',
    'date',
    'due_date',
    'tax_rate',
    'tax_mode',
    'additional_costs',
    'currency_code',
    'currency_symbol',
  ];

  static const _itemCols = [
    'invoice_id',
    'product_name',
    'quantity',
    'unit_price',
    'product_price',
    'discount',
    'discount_per_unit',
    'extra_cost',
    'product_tax_rate',
    'product_price_includes_tax',
    'product_purchase_price',
  ];

  static const _payCols = [
    'invoice_id',
    'receipt_number',
    'amount_paid',
    'date_paid',
    'payment_method',
    'notes',
  ];

  /// Mirrors ReportService._invoiceItemNetSql.
  static double _itemNet(Map<String, dynamic> item) {
    final price = (item['unit_price'] as num?)?.toDouble() ??
        (item['product_price'] as num?)?.toDouble() ??
        0.0;
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    final discount = (item['discount'] as num?)?.toDouble() ?? 0.0;
    final extra = (item['extra_cost'] as num?)?.toDouble() ?? 0.0;
    final perUnit = (item['discount_per_unit'] as num?)?.toInt() ?? 0;
    if (perUnit == 1) {
      return (price - discount) * qty + extra;
    }
    return price * qty - discount + extra;
  }

  /// Mirrors ReportService._invoiceItemTaxableNetSql: backs embedded tax out
  /// of tax-inclusive-priced items so "revenue" stays tax-exclusive. Only
  /// applies in per-item tax mode (matches the reference).
  static double _itemTaxableNet(
    Map<String, dynamic> item, {
    required String taxMode,
  }) {
    final net = _itemNet(item);
    final includesTax = (item['product_price_includes_tax'] as num?)?.toInt() ?? 0;
    final rate = (item['product_tax_rate'] as num?)?.toDouble() ?? 0.0;
    if (taxMode == 'per_item' && includesTax == 1 && rate > 0) {
      return net / (1 + rate / 100.0);
    }
    return net;
  }

  /// Mirrors ReportService._invoiceItemDiscountSql.
  static double _itemDiscount(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    final discount = (item['discount'] as num?)?.toDouble() ?? 0.0;
    final perUnit = (item['discount_per_unit'] as num?)?.toInt() ?? 0;
    return perUnit == 1 ? discount * qty : discount;
  }

  /// COGS for a line: quantity × product_purchase_price snapshot.
  static double _itemCogs(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    final purchase = (item['product_purchase_price'] as num?)?.toDouble() ?? 0.0;
    return qty * purchase;
  }

  // ── Low-level fetchers ─────────────────────────────────────────────────────

  /// Fetches invoices filtered the same way ReportService._loadRows does:
  /// `type = ? AND deleted_at IS NULL` plus optional date range, currency and
  /// (in Dart) customer key. RLS already scopes rows to the tenant.
  Future<List<Map<String, dynamic>>> _fetchInvoices({
    String type = 'Invoice',
    DateTime? from,
    DateTime? to,
    String? currencyCode,
    List<String>? select,
  }) async {
    var b = _c
        .from('invoices')
        .select((select ?? _invoiceCols).join(','))
        .eq('type', type)
        .isFilter('deleted_at', null);
    if (from != null) b = b.gte('date', AppDate.dateKeyStart(from));
    if (to != null) b = b.lte('date', AppDate.dateKeyEnd(to));
    if (currencyCode != null) {
      // Mirrors `(currency_code = ? OR currency_code IS NULL)`.
      b = b.or('currency_code.eq.${_escape(currencyCode)},currency_code.is.null');
    }
    return b;
  }

  Future<List<Map<String, dynamic>>> _fetchItems(List<String> ids) async {
    final out = <Map<String, dynamic>>[];
    for (final chunk in _chunks(ids)) {
      out.addAll(await _c
          .from('invoice_items')
          .select(_itemCols.join(','))
          .inFilter('invoice_id', chunk));
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _fetchPayments(List<String> ids) async {
    final out = <Map<String, dynamic>>[];
    for (final chunk in _chunks(ids)) {
      out.addAll(await _c
          .from('invoice_payments')
          .select(_payCols.join(','))
          .inFilter('invoice_id', chunk));
    }
    return out;
  }

  List<List<String>> _chunks(List<String> ids, {int size = 900}) {
    final out = <List<String>>[];
    for (var i = 0; i < ids.length; i += size) {
      final end = (i + size < ids.length) ? i + size : ids.length;
      out.add(ids.sublist(i, end));
    }
    return out;
  }

  // ── Invoice batch loader (mirrors ReportService._loadRows) ─────────────────

  /// Loads invoices (with their line items and payments) and computes each
  /// invoice's total / paid / outstanding via the shared calculators, exactly
  /// as the SQLite service does. [customerKey] matches the
  /// `COALESCE(NULLIF(customer_id,''), customer_name)` semantics in Dart.
  Future<List<_InvRow>> _loadInvoiceRows({
    DateTime? from,
    DateTime? to,
    String? currencyCode,
    String? customerKey,
  }) async {
    var invRows =
        await _fetchInvoices(from: from, to: to, currencyCode: currencyCode);
    if (invRows.isEmpty) return [];

    if (customerKey != null) {
      invRows = invRows
          .where((r) =>
              CustomerIdentity.key(
                id: r['customer_id'] as String?,
                name: r['customer_name'] as String?,
              ) ==
              customerKey)
          .toList();
      if (invRows.isEmpty) return [];
    }

    final ids = invRows.map((r) => r['id'] as String).toList();
    final itemRows = await _fetchItems(ids);
    final payRows = await _fetchPayments(ids);

    final itemsByInv = <String, List<Map<String, dynamic>>>{};
    for (final r in itemRows) {
      (itemsByInv[r['invoice_id'] as String] ??= []).add(r);
    }
    final paysByInv = <String, List<Map<String, dynamic>>>{};
    for (final r in payRows) {
      (paysByInv[r['invoice_id'] as String] ??= []).add(r);
    }

    return invRows.map((inv) {
      final id = inv['id'] as String;
      final taxMode = TaxModeExtension.fromKey(inv['tax_mode'] as String?);
      final taxRate = (inv['tax_rate'] as num?)?.toDouble() ?? 0.0;
      final items = itemsByInv[id] ?? [];
      final payments = paysByInv[id] ?? [];
      final paid = payments.fold<double>(
          0.0, (s, p) => s + ((p['amount_paid'] as num?)?.toDouble() ?? 0.0));

      final addCosts = AdditionalCost.listFromJson(inv['additional_costs'] as String?)
          .fold(0.0, (s, c) => s + c.amount);
      final totals = InvoiceTotalsCalculator.totals(
        lines: items.map((r) => InvoiceTotalsCalculator.lineFromDbRow(r,
            taxMode: taxMode, globalTaxRatePercent: taxRate * 100)),
        taxMode: taxMode,
        globalTaxRate: taxRate,
        globalTaxRateFormat: TaxRateFormat.fraction,
        additionalCostsTotal: addCosts,
      );
      final total = totals.total;
      final outstanding = InvoiceCalculator.outstanding(total: total, paid: paid);

      return _InvRow(
        id: id,
        customerKey: CustomerIdentity.key(
          id: inv['customer_id'] as String?,
          name: inv['customer_name'] as String?,
        ),
        customerName:
            CustomerIdentity.displayName(inv['customer_name'] as String?),
        date: inv['date'] as String? ?? '',
        dueDate: inv['due_date'] as String?,
        total: total,
        paid: paid,
        outstanding: outstanding,
        currencyCode: inv['currency_code'] as String? ?? 'INR',
        currencySymbol: inv['currency_symbol'] as String? ?? 'Rs.',
        taxMode: taxMode.key,
        taxRate: taxRate,
        items: items,
        payments: payments,
      );
    }).toList();
  }

  /// Net product revenue minus COGS over [rows], using the tax-exclusive line
  /// basis (mirrors ReportService._getTotalProfit).
  static double _profitOf(List<_InvRow> rows) {
    double revenue = 0, cogs = 0;
    for (final inv in rows) {
      for (final item in inv.items) {
        revenue += _itemTaxableNet(item, taxMode: inv.taxMode);
        cogs += _itemCogs(item);
      }
    }
    return revenue - cogs;
  }

  // ── 1. Revenue KPIs ────────────────────────────────────────────────────────

  @override
  Future<RevenueKpi> getRevenueSummary(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);
    if (rows.isEmpty) return RevenueKpi.empty;

    double billed = 0, collected = 0, outstanding = 0;
    for (final r in rows) {
      billed += r.total;
      collected += r.paid;
      outstanding += r.outstanding;
    }
    return RevenueKpi(
      invoiceCount: rows.length,
      billed: billed,
      collected: collected,
      outstanding: outstanding,
      avgInvoiceValue: billed / rows.length,
      profit: _profitOf(rows),
    );
  }

  // ── 2. Monthly revenue trend ───────────────────────────────────────────────

  @override
  Future<List<MonthlyPoint>> getMonthlyRevenueTrend(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);
    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);

    // Billed grouped by invoice date.
    final billedByMonth = <String, double>{};
    for (final r in rows) {
      if (r.date.length >= 7) {
        final m = r.date.substring(0, 7);
        billedByMonth[m] = (billedByMonth[m] ?? 0) + r.total;
      }
    }

    // Collected grouped by payment date (mirrors the SQLite cash-flow view,
    // which filters payments to the same [from,to] window as the invoices).
    final collectedByMonth = <String, double>{};
    for (final inv in rows) {
      for (final p in inv.payments) {
        final d = p['date_paid'] as String? ?? '';
        if (d.isEmpty || d.compareTo(f) < 0 || d.compareTo(t) > 0) continue;
        final m = d.length >= 7 ? d.substring(0, 7) : d;
        collectedByMonth[m] = (collectedByMonth[m] ?? 0) +
            ((p['amount_paid'] as num?)?.toDouble() ?? 0.0);
      }
    }

    // Profit grouped by invoice date (net revenue minus COGS).
    final profitByMonth = <String, double>{};
    for (final inv in rows) {
      final m = inv.date.length >= 7 ? inv.date.substring(0, 7) : inv.date;
      for (final item in inv.items) {
        profitByMonth[m] = (profitByMonth[m] ?? 0) +
            (_itemTaxableNet(item, taxMode: inv.taxMode) - _itemCogs(item));
      }
    }

    final allMonths = {...billedByMonth.keys, ...collectedByMonth.keys}.toList()
      ..sort();

    return allMonths
        .map((m) => MonthlyPoint(
              month: m,
              billed: billedByMonth[m] ?? 0,
              collected: collectedByMonth[m] ?? 0,
              profit: profitByMonth[m] ?? 0,
            ))
        .toList();
  }

  // ── 2b. Daily sales/profit trend ───────────────────────────────────────────

  @override
  Future<List<DailyPoint>> getDailyRevenueTrend(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);

    final byDay = <String, List<_InvRow>>{};
    for (final inv in rows) {
      (byDay[inv.date.length >= 10 ? inv.date.substring(0, 10) : inv.date] ??= [])
          .add(inv);
    }

    final result = byDay.entries.map((e) {
      double billed = 0, cogs = 0;
      for (final inv in e.value) {
        for (final item in inv.items) {
          billed += _itemTaxableNet(item, taxMode: inv.taxMode);
          cogs += _itemCogs(item);
        }
      }
      return DailyPoint(
        date: e.key,
        invoiceCount: e.value.length,
        billed: billed,
        cogs: cogs,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  // ── 3. Payment status breakdown ────────────────────────────────────────────

  @override
  Future<StatusBreakdown> getPaymentStatusBreakdown(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);
    int paid = 0, partial = 0, unpaid = 0;
    for (final r in rows) {
      switch (InvoiceCalculator.paymentStatus(total: r.total, paid: r.paid)) {
        case PaymentStatus.unpaid:
          unpaid++;
        case PaymentStatus.paid:
          paid++;
        case PaymentStatus.partial:
          partial++;
      }
    }
    return StatusBreakdown(paid: paid, partial: partial, unpaid: unpaid);
  }

  // ── 4. Aged receivables (all time, all overdue) ────────────────────────────

  @override
  Future<List<AgedReceivable>> getAgedReceivables(
      {String? currencyCode}) async {
    final rows = await _loadInvoiceRows(currencyCode: currencyCode);
    final now = DateTime.now();
    final result = <AgedReceivable>[];

    for (final r in rows) {
      if (r.outstanding <= InvoiceCalculator.moneyEpsilon) continue;
      final dueDate = r.dueDate != null ? DateTime.tryParse(r.dueDate!) : null;
      final bool noDueDate = dueDate == null;
      final daysOverdue =
          InvoiceCalculator.daysOverdue(dueDate: dueDate, asOf: now);
      result.add(AgedReceivable(
        invoiceId: r.id,
        customerName: r.customerName,
        outstanding: r.outstanding,
        daysOverdue: daysOverdue,
        hasNoDueDate: noDueDate,
      ));
    }
    // Sort: no-due-date last, then by days overdue descending.
    result.sort((a, b) {
      if (a.hasNoDueDate != b.hasNoDueDate) return a.hasNoDueDate ? 1 : -1;
      return b.daysOverdue.compareTo(a.daysOverdue);
    });
    return result;
  }

  // ── 5. Tax collected by rate ───────────────────────────────────────────────

  @override
  Future<List<TaxBucket>> getTaxByRate(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);
    final buckets = <double, double>{};

    // Per-item mode: tax computed per line item's product_tax_rate.
    for (final inv in rows) {
      if (inv.taxMode != 'per_item') continue;
      for (final item in inv.items) {
        final rate = (item['product_tax_rate'] as num?)?.toDouble() ?? 0.0;
        if (rate <= 0) continue;
        final net = _itemNet(item);
        final includesTax =
            (item['product_price_includes_tax'] as num?)?.toInt() ?? 0;
        final tax = includesTax == 1
            ? net * rate / (100 + rate)
            : net * rate / 100;
        buckets[rate] = (buckets[rate] ?? 0) + tax;
      }
    }

    // Global mode: single tax rate applied to the invoice subtotal (excluding
    // additional costs, matching the reference's totals() call).
    for (final inv in rows) {
      if (inv.taxMode != 'global' || inv.taxRate <= 0) continue;
      final totals = InvoiceTotalsCalculator.totals(
        lines: inv.items.map((r) => InvoiceTotalsCalculator.lineFromDbRow(r,
            taxMode: TaxMode.global, globalTaxRatePercent: inv.taxRate * 100)),
        taxMode: TaxMode.global,
        globalTaxRate: inv.taxRate,
        globalTaxRateFormat: TaxRateFormat.fraction,
      );
      final tax = totals.tax;
      final ratePercent = inv.taxRate * 100;
      if (tax > 0) {
        buckets[ratePercent] = (buckets[ratePercent] ?? 0) + tax;
      }
    }

    return (buckets.entries
        .map((e) => TaxBucket(rate: e.key, taxCollected: e.value))
        .toList()
      ..sort((a, b) => a.rate.compareTo(b.rate)));
  }

  // ── 6. Top customers ──────────────────────────────────────────────────────

  @override
  Future<List<TopCustomer>> getTopCustomers(
    DateTime from,
    DateTime to, {
    int limit = 500,
    String? currencyCode,
  }) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);

    final byCustomer = <String, List<_InvRow>>{};
    for (final r in rows) {
      (byCustomer[r.customerKey] ??= []).add(r);
    }

    final result = byCustomer.entries.map((e) {
      double billed = 0, collected = 0, outstanding = 0;
      for (final r in e.value) {
        billed += r.total;
        collected += r.paid;
        outstanding += r.outstanding;
      }
      return TopCustomer(
        name: e.value.first.customerName,
        invoiceCount: e.value.length,
        billed: billed,
        collected: collected,
        outstanding: outstanding,
      );
    }).toList()
      ..sort((a, b) => b.billed.compareTo(a.billed));

    return result.take(limit).toList();
  }

  // ── 6b. Statement customers ────────────────────────────────────────────────

  @override
  Future<List<CustomerStatementCustomer>> getStatementCustomers(
      {String? currencyCode}) async {
    final invRows = await _fetchInvoices(
      select: const ['customer_id', 'customer_name'],
      currencyCode: currencyCode,
    );

    final counts = <String, _CustAgg>{};
    for (final r in invRows) {
      final cid = r['customer_id'] as String?;
      final cname = r['customer_name'] as String?;
      // Mirrors `COALESCE(NULLIF(customer_id,''), customer_name) IS NOT NULL`.
      final hasId = cid != null && cid.trim().isNotEmpty;
      if (!hasId && cname == null) continue;
      final key = CustomerIdentity.key(id: cid, name: cname);
      final name = CustomerIdentity.displayName(cname);
      final agg = counts.putIfAbsent(key, () => _CustAgg(name: name));
      agg.count++;
    }

    return counts.entries
        .map((e) => CustomerStatementCustomer(
              key: e.key,
              name: e.value.name,
              invoiceCount: e.value.count,
            ))
        .toList()
      // COLLATE NOCASE equivalent.
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ── 6c. Customer statements ────────────────────────────────────────────────

  @override
  Future<List<CustomerStatement>> getCustomerStatements(
    String customerKey,
    DateTime from,
    DateTime to, {
    String? currencyCode,
  }) async {
    final rows =
        await _loadInvoiceRows(customerKey: customerKey, currencyCode: currencyCode);
    if (rows.isEmpty) return [];

    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);
    final byCurrency = <String, List<_InvRow>>{};
    for (final row in rows) {
      (byCurrency[row.currencyCode] ??= []).add(row);
    }

    final statements = <CustomerStatement>[];
    for (final entry in byCurrency.entries) {
      final currencyRows = entry.value;
      final invoicesById = {for (final r in currencyRows) r.id: r};

      // Payments across this currency's invoices, ordered like the reference
      // (`ORDER BY date_paid ASC, rowid ASC`). Postgres has no rowid, so we
      // tie-break on invoice id for determinism.
      final allPayments = <Map<String, dynamic>>[];
      for (final inv in currencyRows) {
        allPayments.addAll(inv.payments);
      }
      allPayments.sort((a, b) {
        final d = (a['date_paid'] as String? ?? '')
            .compareTo(b['date_paid'] as String? ?? '');
        if (d != 0) return d;
        return (a['invoice_id'] as String? ?? '')
            .compareTo(b['invoice_id'] as String? ?? '');
      });

      final drafts = <_StatementLineDraft>[];
      double opening = 0;
      double invoiced = 0;
      double paid = 0;
      double overdue = 0;

      for (final invoice in currencyRows) {
        if (invoice.date.compareTo(f) < 0) {
          opening += invoice.total;
        } else if (invoice.date.compareTo(t) <= 0) {
          invoiced += invoice.total;
          drafts.add(_StatementLineDraft(
            date: invoice.date,
            order: 0,
            type: 'Invoice',
            reference: invoice.id,
            description: 'Invoice raised',
            debit: invoice.total,
            credit: 0,
          ));
        }

        final dueDate = invoice.dueDate;
        if (InvoiceCalculator.isOverdue(
          dueDate: dueDate == null ? null : DateTime.tryParse(dueDate),
          outstanding: invoice.outstanding,
        )) {
          overdue += invoice.outstanding;
        }
      }

      for (final payment in allPayments) {
        final invoice = invoicesById[payment['invoice_id'] as String];
        if (invoice == null) continue;
        final date = payment['date_paid'] as String? ?? '';
        final amount = (payment['amount_paid'] as num?)?.toDouble() ?? 0;
        if (date.compareTo(f) < 0) {
          opening -= amount;
        } else if (date.compareTo(t) <= 0) {
          paid += amount;
          final method = payment['payment_method'] as String?;
          drafts.add(_StatementLineDraft(
            date: date,
            order: 1,
            type: 'Payment',
            reference: payment['receipt_number'] as String? ?? invoice.id,
            description: method == null || method.isEmpty
                ? 'Payment for ${invoice.id}'
                : 'Payment for ${invoice.id} ($method)',
            debit: 0,
            credit: amount,
          ));
        }
      }

      drafts.sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.order.compareTo(b.order);
      });

      var running = opening;
      final lines = drafts.map((draft) {
        running += draft.debit - draft.credit;
        return CustomerStatementLine(
          date: draft.date,
          type: draft.type,
          reference: draft.reference,
          description: draft.description,
          debit: draft.debit,
          credit: draft.credit,
          balance: running,
        );
      }).toList();

      statements.add(CustomerStatement(
        customerKey: customerKey,
        customerName: currencyRows.first.customerName,
        currencyCode: entry.key,
        currencySymbol: currencyRows.first.currencySymbol,
        openingBalance: opening,
        invoiced: invoiced,
        paid: paid,
        closingBalance: running,
        overdueBalance: overdue,
        lines: lines,
      ));
    }

    statements.sort((a, b) => a.currencyCode.compareTo(b.currencyCode));
    return statements;
  }

  // ── 7. Top products ───────────────────────────────────────────────────────

  @override
  Future<List<TopProduct>> getTopProducts(
    DateTime from,
    DateTime to, {
    int limit = 500,
    String? currencyCode,
    bool rankByProfit = false,
  }) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);

    final byProduct = <String?, _ProductAgg>{};
    for (final inv in rows) {
      for (final item in inv.items) {
        final name = item['product_name'] as String?;
        final agg = byProduct.putIfAbsent(name, () => _ProductAgg());
        agg.unitsSold += (item['quantity'] as num?)?.toDouble() ?? 0.0;
        agg.revenue += _itemTaxableNet(item, taxMode: inv.taxMode);
        agg.discountGiven += _itemDiscount(item);
        agg.cogs += _itemCogs(item);
      }
    }

    final result = byProduct.entries
        .map((e) => TopProduct(
              name: e.key ?? 'Unknown',
              unitsSold: e.value.unitsSold,
              revenue: e.value.revenue,
              discountGiven: e.value.discountGiven,
              cogs: e.value.cogs,
            ))
        .toList();

    result.sort((a, b) {
      if (rankByProfit) {
        return (b.revenue - b.cogs).compareTo(a.revenue - a.cogs);
      }
      return b.revenue.compareTo(a.revenue);
    });

    return result.take(limit).toList();
  }

  // ── 8. Quotation conversion ────────────────────────────────────────────────

  @override
  Future<QuotationStats> getQuotationStats(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final quotationsIssued = await _countInvoices(
        type: 'Quotation', from: from, to: to, currencyCode: currencyCode);
    final invoicesInPeriod = await _countInvoices(
        type: 'Invoice', from: from, to: to, currencyCode: currencyCode);

    final rate = quotationsIssued == 0
        ? 0.0
        : (invoicesInPeriod / quotationsIssued * 100).clamp(0.0, 100.0);

    return QuotationStats(
      quotationsIssued: quotationsIssued,
      invoicesInPeriod: invoicesInPeriod,
      conversionRate: rate,
    );
  }

  Future<int> _countInvoices({
    required String type,
    DateTime? from,
    DateTime? to,
    String? currencyCode,
  }) async {
    final rows = await _fetchInvoices(
      type: type,
      from: from,
      to: to,
      currencyCode: currencyCode,
      select: const ['id'],
    );
    return rows.length;
  }

  // ── 9. Invoice status list ─────────────────────────────────────────────────

  @override
  Future<List<InvoiceStatusRow>> getInvoiceStatusList(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);
    final now = DateTime.now();
    final result = rows.map((r) {
      final dueDate = r.dueDate != null ? DateTime.tryParse(r.dueDate!) : null;
      final noDueDate = r.dueDate == null;
      final daysOverdue =
          InvoiceCalculator.daysOverdue(dueDate: dueDate, asOf: now);

      final status = switch (
          InvoiceCalculator.paymentStatus(total: r.total, paid: r.paid)) {
        PaymentStatus.paid => 'Paid',
        PaymentStatus.partial => 'Partial',
        PaymentStatus.unpaid => 'Unpaid',
      };

      final isOverdue = InvoiceCalculator.isOverdue(
        dueDate: dueDate,
        outstanding: r.outstanding,
        asOf: now,
      );

      return InvoiceStatusRow(
        id: r.id,
        date: r.date,
        dueDate: r.dueDate,
        customerName: r.customerName,
        total: r.total,
        paid: r.paid,
        outstanding: r.outstanding,
        daysOverdue: daysOverdue,
        hasNoDueDate: noDueDate,
        status: status,
        isOverdue: isOverdue,
      );
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  // ── 10. Missing cost items ─────────────────────────────────────────────────

  @override
  Future<int> getMissingCostItemCount(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadInvoiceRows(from: from, to: to, currencyCode: currencyCode);
    var count = 0;
    for (final inv in rows) {
      for (final item in inv.items) {
        final purchase = (item['product_purchase_price'] as num?)?.toDouble();
        if (purchase == null || purchase == 0) count++;
      }
    }
    return count;
  }

  /// Supabase `.or()` / `.eq()` filters need comma and dot escaped.
  String _escape(String v) =>
      v.replaceAll(',', '%2C').replaceAll('.', '%2E');
}

/// Internal invoice row mirroring ReportService._InvRow, extended with the raw
/// line items and payments (needed to reproduce the item/payment aggregates).
class _InvRow {
  final String id;
  final String customerKey;
  final String customerName;
  final String date;
  final String? dueDate;
  final double total;
  final double paid;
  final double outstanding;
  final String currencyCode;
  final String currencySymbol;
  final String taxMode;
  final double taxRate;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> payments;

  const _InvRow({
    required this.id,
    required this.customerKey,
    required this.customerName,
    required this.date,
    this.dueDate,
    required this.total,
    required this.paid,
    required this.outstanding,
    required this.currencyCode,
    required this.currencySymbol,
    required this.taxMode,
    required this.taxRate,
    required this.items,
    required this.payments,
  });
}

class _StatementLineDraft {
  final String date;
  final int order;
  final String type;
  final String reference;
  final String description;
  final double debit;
  final double credit;

  const _StatementLineDraft({
    required this.date,
    required this.order,
    required this.type,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
  });
}

class _CustAgg {
  final String name;
  int count = 0;
  _CustAgg({required this.name});
}

class _ProductAgg {
  double unitsSold = 0;
  double revenue = 0;
  double discountGiven = 0;
  double cogs = 0;
}
