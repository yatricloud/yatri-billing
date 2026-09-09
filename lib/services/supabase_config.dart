import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Supabase configuration for the Yatri Billing cloud edition.
///
/// SECURITY PRINCIPLES & SAFEGUARDS:
/// 1. NO CREDENTIALS ARE HARDCODED in this repository.
/// 2. Configuration is strictly sourced via environment variables:
///    - Compile time: via `--dart-define-from-file=.env` or `--dart-define=...`
///    - Web runtime: via dynamic `/api/config` (Vercel Environment Variables)
/// 3. If credentials are not provided, the app will NOT connect to or load
///    the database, preventing unauthorized requests and errors.
/// 4. Service role keys are STRICTLY PROHIBITED on the client side:
///    The client automatically validates that the key does NOT contain
///    `role: "service_role"`, protecting your database from bypass attacks.
/// 5. Client queries use the public `anon` key, which enforces Row Level
///    Security (RLS) on all database operations.
class SupabaseConfig {
  SupabaseConfig._();

  // Initialized from compile-time environment definitions (e.g. from .env)
  static String _url = const String.fromEnvironment('SUPABASE_URL');
  static String _anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get url => _url;
  static String get anonKey => _anonKey;

  /// Whether Supabase credentials have been safely configured.
  static bool get isConfigured =>
      _url.trim().isNotEmpty &&
      _anonKey.trim().isNotEmpty &&
      _url.startsWith('http') &&
      !_isServiceRoleKey(_anonKey);

  /// Loads configuration from compile-time defines or runtime web environment.
  static Future<void> load() async {
    // 1. If already set via compile-time --dart-define or --dart-define-from-file=.env
    if (_url.isNotEmpty && _anonKey.isNotEmpty) {
      _validateKey(_anonKey);
      return;
    }

    // 2. On Web runtime, fetch from /api/config (Vercel environment variables)
    if (kIsWeb) {
      try {
        final response = await http.get(Uri.parse('/api/config')).timeout(
          const Duration(seconds: 4),
          onTimeout: () => http.Response('{}', 408),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map) {
            final fetchedUrl = data['supabaseUrl']?.toString() ?? '';
            final fetchedKey = data['supabaseAnonKey']?.toString() ?? '';
            if (fetchedUrl.isNotEmpty && fetchedKey.isNotEmpty) {
              _url = fetchedUrl.trim();
              _anonKey = fetchedKey.trim();
              _validateKey(_anonKey);
              return;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SupabaseConfig] Runtime config fetch skipped: $e');
        }
      }
    }
  }

  /// Validates that the provided key conforms to client security requirements.
  static void _validateKey(String key) {
    if (_isServiceRoleKey(key)) {
      _url = '';
      _anonKey = '';
      throw const FormatException(
        'CRITICAL SECURITY VIOLATION: A Supabase service_role key was detected. '
        'The service_role key bypasses Row Level Security (RLS) and must NEVER '
        'be configured in frontend applications. '
        'Use only the public anon (publishable) key.',
      );
    }
  }

  /// Checks if a JWT token payload has the `service_role` claim.
  static bool _isServiceRoleKey(String key) {
    try {
      final parts = key.split('.');
      if (parts.length == 3) {
        // Normalize base64 URL string
        var payload = parts[1];
        while (payload.length % 4 != 0) {
          payload += '=';
        }
        final decoded = utf8.decode(base64Url.decode(payload));
        return decoded.contains('"role":"service_role"') ||
            decoded.contains('"role": "service_role"');
      }
    } catch (_) {}
    return false;
  }
}
