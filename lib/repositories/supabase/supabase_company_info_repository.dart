import 'package:invoiso/models/company_info.dart';
import 'package:invoiso/repositories/company_info_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [CompanyInfoRepository].
///
/// There is a single `company_info` row per tenant (a UNIQUE constraint on
/// `tenant_id`), so both [insertCompanyInfo] and [updateCompanyInfo] upsert
/// the same row. Tenant isolation is enforced by RLS (the JWT `tenant_id`
/// claim), so no explicit tenant filter is needed in the queries below.
class SupabaseCompanyInfoRepository implements CompanyInfoRepository {
  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<CompanyInfo?> getCompanyInfo() async {
    final rows = await _c.from('company_info').select().limit(1);
    return rows.isEmpty ? null : CompanyInfo.fromMap(rows.first);
  }

  @override
  Future<int> insertCompanyInfo(CompanyInfo info) async {
    final map = info.toMap()..remove('id');
    final res = await _c
        .from('company_info')
        .upsert(map, onConflict: 'tenant_id')
        .select();
    return res.isEmpty ? 0 : 1;
  }

  @override
  Future<int> updateCompanyInfo(CompanyInfo info) async {
    final map = info.toMap()..remove('id');
    final res = await _c
        .from('company_info')
        .upsert(map, onConflict: 'tenant_id')
        .select();
    return res.isEmpty ? 0 : 1;
  }
}
