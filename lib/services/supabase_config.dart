/// Supabase configuration for the Yatri Billing cloud edition.
///
/// These are the PUBLIC client credentials (publishable/anon key). They are
/// safe to ship in a browser/web app ONLY because Row Level Security (RLS) is
/// enabled on every table and every query is tenant-scoped via the JWT
/// `tenant_id` claim.
///
/// The service_role key must NEVER be placed here — it bypasses RLS and is for
/// server-side use (Supabase Edge Functions) only.
library;

class SupabaseConfig {
  SupabaseConfig._();

  /// The Supabase project URL, e.g. `https://<ref>.supabase.co`.
  ///
  /// Override at build/run time with `--dart-define=SUPABASE_URL=...`.
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qqxatnlbrmvrygjaurcl.supabase.co',
  );

  /// The public anon (publishable) key.
  ///
  /// Override at build/run time with `--dart-define=SUPABASE_ANON_KEY=...`.
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxeGF0bmxicm12cnlnamF1cmNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyNTU0NzMsImV4cCI6MjEwMTgzMTQ3M30.20Wcncr818Idc0Ldxyplu0c1-_0CoYkJ77-OnGD_Ezo',
  );
}
