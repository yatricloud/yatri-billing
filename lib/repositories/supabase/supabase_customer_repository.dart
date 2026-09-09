import 'package:invoiso/models/customer.dart';
import 'package:invoiso/repositories/customer_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [CustomerRepository].
///
/// Tenant isolation is enforced by RLS (the JWT `tenant_id` claim), so no
/// explicit tenant filter is needed in the queries below.
class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<void> insertCustomer(Customer customer) async {
    await _c.from('customers').insert(customer.toMap());
  }

  @override
  Future<void> updateCustomer(Customer customer) async {
    final updateMap = customer.toMap()..remove('id');
    await _c.from('customers').update(updateMap).eq('id', customer.id);
  }

  @override
  Future<Customer?> getCustomerById(String id) async {
    final rows = await _c.from('customers').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  @override
  Future<List<Customer>> getAllCustomers() async {
    final rows = await _c.from('customers').select();
    return rows.map(Customer.fromMap).toList();
  }

  @override
  Future<int> getTotalCustomerCount() async {
    final res = await _c.from('customers').select('id').count(CountOption.exact);
    return res.count;
  }

  @override
  Future<void> deleteCustomer(String id) async {
    await _c.from('customers').delete().eq('id', id);
  }

  @override
  Future<Customer?> findByPhone(String phone) async {
    if (phone.trim().isEmpty) return null;
    final rows = await _c
        .from('customers')
        .select()
        .eq('phone', phone.trim())
        .limit(1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  @override
  Future<Customer?> findByEmail(String email) async {
    if (email.trim().isEmpty) return null;
    final rows = await _c
        .from('customers')
        .select()
        .eq('email', email.trim())
        .limit(1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  @override
  Future<Customer?> findDuplicate(String email, String phone) async {
    final conds = <String>[];
    if (email.trim().isNotEmpty) conds.add('email.eq.${_escape(email.trim())}');
    if (phone.trim().isNotEmpty) conds.add('phone.eq.${_escape(phone.trim())}');
    if (conds.isEmpty) return null;
    final rows = await _c.from('customers').select().or(conds.join(',')).limit(1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  @override
  Future<void> deleteAllCustomers() async {
    await _c.from('customers').delete().neq('id', '__none__');
  }

  @override
  Future<void> insertBatch(List<Customer> customers) async {
    if (customers.isEmpty) return;
    await _c.from('customers').insert(customers.map((c) => c.toMap()).toList());
  }

  @override
  Future<List<Customer>> getCustomersPaginated({
    required int offset,
    required int limit,
    String query = '',
    String orderBy = 'name',
    bool orderASC = true,
  }) async {
    var builder = _c.from('customers').select();
    if (query.isNotEmpty) {
      final q = _escape(query.toLowerCase());
      builder = builder.or('name.ilike.%$q%,email.ilike.%$q%,phone.ilike.%$q%,gstin.ilike.%$q%');
    }
    final rows = await builder
        .order(orderBy, ascending: orderASC)
        .range(offset, offset + limit - 1);
    return rows.map(Customer.fromMap).toList();
  }

  /// Supabase `.or()` / `.eq()` filters need comma and dot escaped.
  String _escape(String v) =>
      v.replaceAll(',', '%2C').replaceAll('.', '%2E');
}
