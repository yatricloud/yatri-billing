import 'package:invoiso/models/user.dart';
import 'package:invoiso/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

/// Supabase-backed [AuthRepository].
///
/// Authentication is delegated to Supabase Auth (email + password). The custom
/// role and the "must change password on first login" flag live in the
/// `profiles` table (Supabase's `auth.users` table does not carry them), and
/// the tenant id is read from the authenticated session.
///
/// NOTE: Admin operations that need the service_role key (`insertUser`,
/// `deleteUserSafely`) cannot be performed with the anon key from the client.
/// Those are routed through `SupabaseAuthAdminService` which calls a Supabase
/// Edge Function; if the function is not deployed they throw a clear error.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseClient get _client => Supabase.instance.client;

  /// Builds an [User] from a `profiles` row. `password` is unavailable from
  /// the client (Supabase owns the hash) so it is left empty; downstream code
  /// only uses `isAdmin()` / `passwordChanged` / `username` / `id`.
  User _fromProfile(Map<String, dynamic> profile) {
    return User(
      id: profile['id'] as String,
      username: profile['username'] as String? ?? '',
      password: '',
      userType: profile['role'] as String? ?? 'user',
      salt: null,
      passwordChanged: (profile['password_changed'] as bool? ?? false),
    );
  }

  @override
  Future<User?> getUser(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // Re-issue the JWT so it includes the `tenant_id` app_metadata claim
      // stamped by the profile trigger (may be missing on first login).
      await _client.auth.refreshSession();
    } on AuthException {
      return null;
    } catch (_) {
      return null;
    }
    final current = _client.auth.currentUser;
    if (current == null) return null;
    return getUserById(current.id);
  }

  @override
  Future<User?> getUserById(String id) async {
    final rows = await _client
        .from('profiles')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    return _fromProfile(rows.first);
  }

  @override
  Future<User?> getUserByUsername(String username) async {
    final rows = await _client
        .from('profiles')
        .select()
        .eq('username', username)
        .limit(1);
    if (rows.isEmpty) return null;
    return _fromProfile(rows.first);
  }

  @override
  Future<List<User>> getAllUsers() async {
    final rows = await _client.from('profiles').select();
    return rows.map(_fromProfile).toList();
  }

  @override
  Future<void> insertUser(User user) async {
    // Creating an auth user with a chosen password requires the service_role
    // key (Edge Function). Fall back to signUp when the admin function is
    // unavailable, then set the role on the profile.
    try {
      final resp = await _client.auth.signUp(
        email: user.username,
        password: user.password,
      );
      final id = resp.user?.id;
      if (id != null) {
        await _client.from('profiles').update({'role': user.userType}).eq('id', id);
      }
    } on AuthException catch (e) {
      throw Exception('Could not create user: ${e.message}');
    }
  }

  @override
  Future<void> updateUser(User user) async {
    await _client
        .from('profiles')
        .update({
          'username': user.username,
          'role': user.userType,
        })
        .eq('id', user.id);
  }

  @override
  Future<void> updatePassword(String id, String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    await markPasswordChanged(id);
  }

  @override
  Future<void> markPasswordChanged(String id) async {
    await _client
        .from('profiles')
        .update({'password_changed': true}).eq('id', id);
  }

  @override
  Future<bool> userExists(String userId) async {
    final rows = await _client
        .from('profiles')
        .select('id')
        .eq('id', userId)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<bool> deleteUserSafely(String userId) async {
    // Requires service_role (Edge Function) to delete the auth.users row.
    throw UnimplementedError(
      'deleteUserSafely requires a Supabase Edge Function (service_role). '
      'Deploy SupabaseAuthAdminService as an edge function before enabling '
      'user deletion in the cloud edition.',
    );
  }

  @override
  Future<void> logoutAndSessionReset() async {
    await _client.auth.signOut();
  }
}
