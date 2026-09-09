import 'package:flutter/material.dart';
import 'package:invoiso/database/database_helper.dart';
import 'package:invoiso/screens/login_screen.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/utils/app_logger.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';

const _tag = 'SplashScreen';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initializeApp();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      await DatabaseHelper().database;
    } catch (e, stack) {
      AppLogger.e(_tag, 'Database initialization failed', e, stack);
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Initialization Error'),
          content: Text('Failed to initialize the database.\n\n$e'),
          actions: [
            ElevatedButton(
              onPressed: () => _initializeApp(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
      return;
    }

    AppLogger.d(_tag, 'DB path: ${DatabaseHelper.path}');

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
                  height: 56,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: CbTokens.spaceLg),
              Text(
                'Initializing Yatri Billing…',
                style: AppTypography.bodyMd(CbTokens.muted),
              ),
              const SizedBox(height: CbTokens.spaceXl),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
