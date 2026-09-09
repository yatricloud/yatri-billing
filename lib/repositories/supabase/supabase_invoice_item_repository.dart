import 'package:invoiso/models/invoice_item.dart';
import 'package:invoiso/models/product.dart';
import 'package:invoiso/repositories/invoice_item_repository.dart';
import 'package:invoiso/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _tag = 'SupabaseInvoiceItemRepository';

/// Supabase-backed [InvoiceItemRepository].
///
/// Tenant isolation is enforced by RLS (the JWT `tenant_id` claim), so no
/// explicit tenant filter is needed in the queries below.
class SupabaseInvoiceItemRepository implements InvoiceItemRepository {
  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<void> insertInvoiceItems(String invId, InvoiceItem item) async {
    await _c.from('invoice_items').insert({
      'id': item.id,
      'invoice_id': invId,
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
    });
  }

  @override
  Future<List<InvoiceItem>> getInvoiceItemsByInvoiceId(
      String invoiceId) async {
    final maps = await _c
        .from('invoice_items')
        .select()
        .eq('invoice_id', invoiceId)
        .order('id', ascending: true);
    final List<InvoiceItem> items = [];

    for (final map in maps) {
      try {
        final product = Product.fromInvoiceItemsMap(map);
        final rawUnitPrice = map['unit_price'];
        final unitPrice = rawUnitPrice == null
            ? null
            : (rawUnitPrice is int
                ? rawUnitPrice.toDouble()
                : (rawUnitPrice as num).toDouble());
        final rawExtraCost = map['extra_cost'];
        final extraCost = rawExtraCost == null
            ? null
            : (rawExtraCost is int
                ? rawExtraCost.toDouble()
                : (rawExtraCost as num).toDouble());
        items.add(
          InvoiceItem(
            id: map['id'] as String?,
            product: product,
            quantity: (map['quantity'] is num)
                ? (map['quantity'] as num).toDouble()
                : 1.0,
            discount: (map['discount'] is num)
                ? (map['discount'] as num).toDouble()
                : 0.0,
            unitPrice: unitPrice,
            extraCost: extraCost,
            unit: map['unit'] as String?,
            discountPerUnit: (map['discount_per_unit'] as num? ?? 0) == 1,
            isProductSaved: (map['is_product_saved'] as num? ?? 0) == 1,
          ),
        );
      } catch (e, stackTrace) {
        AppLogger.e(_tag, 'Error parsing invoice item row', e, stackTrace);
        continue;
      }
    }

    return items;
  }

  @override
  Future<void> markProductSaved(String invoiceId, String productId) async {
    await _c
        .from('invoice_items')
        .update({'is_product_saved': 1})
        .eq('invoice_id', invoiceId)
        .eq('product_id', productId);
  }
}
