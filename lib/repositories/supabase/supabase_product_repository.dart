import 'package:invoiso/models/product.dart';
import 'package:invoiso/repositories/product_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [ProductRepository].
///
/// Tenant isolation is enforced by RLS (the JWT `tenant_id` claim), so no
/// explicit tenant filter is needed in the queries below. Deleting a product
/// also removes its rows in `product_metadata` via `ON DELETE CASCADE`.
class SupabaseProductRepository implements ProductRepository {
  SupabaseClient get _c => Supabase.instance.client;

  /// Normalizes a `type` filter: 'both' (or null) means no type filtering.
  String? _typeFilter(String? type) =>
      (type != null && type != 'both') ? type : null;

  @override
  Future<void> insertProduct(Product product) async {
    await _c.from('products').insert(product.toMap());
  }

  @override
  Future<List<Product>> getAllProducts() async {
    final rows = await _c.from('products').select();
    return rows.map(Product.fromMap).toList();
  }

  @override
  Future<int> getTotalProductCount() async {
    final res = await _c
        .from('products')
        .select('id')
        .count(CountOption.exact);
    return res.count;
  }

  @override
  Future<List<Product>> getOutOfStockProducts() async {
    final rows = await _c
        .from('products')
        .select()
        .lte('stock', 0)
        .eq('unlimited_stock', 0)
        .order('name', ascending: true);
    return rows.map(Product.fromMap).toList();
  }

  @override
  Future<Product?> getProductById(String id) async {
    final rows = await _c.from('products').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  @override
  Future<void> updateProduct(Product product) async {
    final updateMap = product.toMap()..remove('id');
    await _c.from('products').update(updateMap).eq('id', product.id);
  }

  @override
  Future<List<Product>> searchProducts(String query, {String? type}) async {
    final typeFilter = _typeFilter(type);
    var builder = _c.from('products').select();
    if (query.trim().isNotEmpty) {
      final q = _escape(query.trim().toLowerCase());
      builder = builder.or(
          'name.ilike.%$q%,alias_name.ilike.%$q%,description.ilike.%$q%');
    }
    if (typeFilter != null) {
      builder = builder.eq('type', typeFilter);
    }
    final rows = await builder;
    return rows.map(Product.fromMap).toList();
  }

  @override
  Future<List<Product>> getProductsPaginated({
    required int offset,
    required int limit,
    String query = '',
    String orderBy = 'name',
    bool orderASC = true,
    String? type,
  }) async {
    final typeFilter = _typeFilter(type);
    var builder = _c.from('products').select();
    if (query.trim().isNotEmpty) {
      final q = _escape(query.trim().toLowerCase());
      builder = builder.or(
          'name.ilike.%$q%,alias_name.ilike.%$q%,description.ilike.%$q%');
    }
    if (typeFilter != null) {
      builder = builder.eq('type', typeFilter);
    }
    final rows = await builder
        .order(orderBy, ascending: orderASC)
        .range(offset, offset + limit - 1);
    return rows.map(Product.fromMap).toList();
  }

  @override
  Future<int> getProductCount([String query = '', String? type]) async {
    final typeFilter = _typeFilter(type);
    var builder = _c
        .from('products')
        .select('id');
    if (query.trim().isNotEmpty) {
      final q = _escape(query.trim().toLowerCase());
      builder = builder.or(
          'name.ilike.%$q%,alias_name.ilike.%$q%,description.ilike.%$q%');
    }
    if (typeFilter != null) {
      builder = builder.eq('type', typeFilter);
    }
    final res = await builder.count(CountOption.exact);
    return res.count;
  }

  @override
  Future<void> deleteProduct(String id) async {
    // `product_metadata` rows are removed by `ON DELETE CASCADE`.
    await _c.from('products').delete().eq('id', id);
  }

  @override
  Future<void> updateProductStock(String id, int newStock) async {
    await _c.from('products').update({'stock': newStock}).eq('id', id);
  }

  @override
  Future<bool> hasSufficientStock(String productId, int quantity) async {
    final product = await getProductById(productId);
    if (product == null) return false;
    return product.unlimitedStock || product.stock >= quantity;
  }

  @override
  Future<Product?> findDuplicateByName(String name) async {
    if (name.trim().isEmpty) return null;
    final rows = await _c
        .from('products')
        .select()
        .ilike('name', name.trim())
        .limit(1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  @override
  Future<void> deleteAllProducts() async {
    await _c.from('products').delete().neq('id', '__none__');
  }

  @override
  Future<void> insertBatch(List<Product> products, {int batchSize = 50}) async {
    if (products.isEmpty) return;
    for (int i = 0; i < products.length; i += batchSize) {
      final chunk = products.sublist(i, (i + batchSize).clamp(0, products.length));
      await _c.from('products').insert(chunk.map((p) => p.toMap()).toList());
    }
  }

  // ─────────────────────────────────────────────
  // ProductMetadata
  // ─────────────────────────────────────────────
  @override
  Future<ProductMetadata?> getProductMetadata(String productId) async {
    final rows = await _c
        .from('product_metadata')
        .select()
        .eq('product_id', productId)
        .limit(1);
    return rows.isEmpty ? null : ProductMetadata.fromMap(rows.first);
  }

  @override
  Future<Map<String, ProductMetadata>> getAllProductMetadata() async {
    final rows = await _c.from('product_metadata').select();
    return {
      for (final m in rows)
        m['product_id'] as String: ProductMetadata.fromMap(m),
    };
  }

  @override
  Future<Map<String, ProductMetadata>> getProductMetadataForIds(
      List<String> productIds) async {
    if (productIds.isEmpty) return {};
    final rows = await _c
        .from('product_metadata')
        .select()
        .inFilter('product_id', productIds);
    return {
      for (final m in rows)
        m['product_id'] as String: ProductMetadata.fromMap(m),
    };
  }

  @override
  Future<void> upsertProductMetadata(ProductMetadata metadata) async {
    if (metadata.isEmpty) {
      await _c
          .from('product_metadata')
          .delete()
          .eq('product_id', metadata.productId);
      return;
    }
    await _c
        .from('product_metadata')
        .upsert(metadata.toMap(), onConflict: 'product_id');
  }

  /// Supabase `.or()` / `.eq()` filters need comma and dot escaped.
  String _escape(String v) =>
      v.replaceAll(',', '%2C').replaceAll('.', '%2E');
}
