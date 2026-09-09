import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/repositories/supabase/supabase_auth_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_company_info_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_customer_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_invoice_item_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_invoice_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_payment_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_product_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_report_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_settings_repository.dart';

/// Riverpod overrides wiring the cloud (Supabase) repositories behind the
/// shared repository interfaces. Used by the web entry (lib/main_web.dart).
final supabaseRepositoryOverrides = <Override>[
  customerRepositoryProvider.overrideWith(
        (ref) => SupabaseCustomerRepository(),
  ),
  invoiceRepositoryProvider.overrideWith(
        (ref) => SupabaseInvoiceRepository(),
  ),
  productRepositoryProvider.overrideWith(
        (ref) => SupabaseProductRepository(),
  ),
  paymentRepositoryProvider.overrideWith(
        (ref) => SupabasePaymentRepository(),
  ),
  companyInfoRepositoryProvider.overrideWith(
        (ref) => SupabaseCompanyInfoRepository(),
  ),
  settingsRepositoryProvider.overrideWith(
        (ref) => SupabaseSettingsRepository(),
  ),
  reportRepositoryProvider.overrideWith(
        (ref) => SupabaseReportRepository(),
  ),
  invoiceItemRepositoryProvider.overrideWith(
        (ref) => SupabaseInvoiceItemRepository(),
  ),
  authRepositoryProvider.overrideWith(
        (ref) => SupabaseAuthRepository(),
  ),
];
