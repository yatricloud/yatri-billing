// Web (cloud) entry point for Yatri Billing.
//
// This is a web-only build: it initializes Supabase and wires the Supabase
// repository implementations behind the shared repository interfaces. There is
// no dart:io / window_manager / sqflite_ffi here, so it compiles cleanly for
// Flutter web. The desktop offline app keeps its own entry (lib/main.dart).
//
// Build with:  flutter build web -t lib/main_web.dart
// Serve locally:  flutter run -d chrome -t lib/main_web.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/constants.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/providers/supabase_repository_overrides.dart';
import 'package:invoiso/providers/theme_provider.dart';
import 'package:invoiso/repositories/supabase/supabase_company_info_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_installation_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_invoice_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_payment_repository.dart';
import 'package:invoiso/repositories/supabase/supabase_settings_repository.dart';
import 'package:invoiso/screens/splash_screen_web.dart';
import 'package:invoiso/services/backend_services.dart';
import 'package:invoiso/services/supabase_config.dart';
import 'package:invoiso/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();

  // Error handlers.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('[PlatformDispatcher] Unhandled error: $error');
      debugPrint('Stack: $stack');
    }
    return true;
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Something went wrong', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              kDebugMode ? details.exceptionAsString() : 'Please reload the page.',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  };

  // Initialize Supabase with the public client credentials.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // Non-widget services (PDF, export, analytics) read repos from here.
  BackendServices.configure(
    settings: SupabaseSettingsRepository(),
    companyInfo: SupabaseCompanyInfoRepository(),
    invoices: SupabaseInvoiceRepository(),
    payments: SupabasePaymentRepository(),
    installation: SupabaseInstallationRepository(),
  );

  runApp(ProviderScope(
    overrides: supabaseRepositoryOverrides,
    child: const MyApp(),
  ));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final key = await ref.read(settingsRepositoryProvider).getThemeMode();
    if (!mounted) return;
    ref.read(themeModeProvider.notifier).state = themeModeFromKey(key);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.name,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      home: const SplashScreenWeb(),
    );
  }
}
