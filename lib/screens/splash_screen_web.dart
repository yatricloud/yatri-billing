import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/screens/dashboard_screen.dart';
import 'package:invoiso/screens/login_screen.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class SplashScreenWeb extends ConsumerStatefulWidget {
  const SplashScreenWeb({super.key});

  @override
  ConsumerState<SplashScreenWeb> createState() => _SplashScreenWebState();
}

class _SplashScreenWebState extends ConsumerState<SplashScreenWeb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      try {
        await Supabase.instance.client.auth.refreshSession();
        final current = Supabase.instance.client.auth.currentUser;
        if (current != null) {
          final user =
              await ref.read(authRepositoryProvider).getUserById(current.id);
          if (!mounted) return;
          if (user != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => DashboardScreen(user)),
            );
            return;
          }
        }
      } catch (_) {
        await Supabase.instance.client.auth.signOut();
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CbTokens.canvas,
      body: Center(
        child: CbFadeSlideIn(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: Image.asset(
                  'assets/images/yatricloud_logo.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: CbTokens.spaceLg),
              Text(
                'Yatri Billing Cloud',
                style: AppTypography.titleMd(CbTokens.ink),
              ),
              const SizedBox(height: CbTokens.spaceXs),
              Text(
                'Loading your workspace…',
                style: AppTypography.caption(CbTokens.muted),
              ),
              const SizedBox(height: CbTokens.spaceXl),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CbTokens.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
