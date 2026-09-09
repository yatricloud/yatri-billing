import 'package:invoiso/common.dart';
import 'package:invoiso/repositories/installation_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_settings_repository.dart';
import 'package:uuid/uuid.dart';

/// Cloud installation id stored in the tenant-scoped Supabase `settings` table.
class SupabaseInstallationRepository implements InstallationRepository {
  final SupabaseSettingsRepository _settings = SupabaseSettingsRepository();

  @override
  Future<String> getOrCreateInstallationId() async {
    final existing = await _settings.getSetting(SettingKey.installationId);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = const Uuid().v4();
    await _settings.setSetting(SettingKey.installationId, id);
    return id;
  }
}
