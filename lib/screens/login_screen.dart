import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/constants.dart';
import 'package:invoiso/providers/app_config_provider.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/screens/change_password_screen.dart';
import 'package:invoiso/screens/dashboard_screen.dart';
import 'package:invoiso/screens/signup_screen.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:invoiso/widgets/design_system/cb_button.dart';
import 'package:invoiso/widgets/design_system/cb_text_field.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _login(AppEditionConfig cfg) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      _showSnack(cfg.isCloud
          ? 'Please enter email and password'
          : 'Please enter username and password');
      return;
    }

    setState(() => _isLoading = true);
    final user =
        await ref.read(authRepositoryProvider).getUser(username, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user == null) {
      _showSnack('Invalid credentials. Please try again.');
      return;
    }

    if (cfg.isCloud) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => DashboardScreen(user)),
      );
    } else if (!user.passwordChanged) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChangePasswordScreen(user: user, forced: true),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => DashboardScreen(user)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appEditionConfigProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // slate-50
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: CbFadeSlideIn(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Logo & Brand ────────────────────────────────────
                  const SizedBox(height: 24),
                  _BrandHeader(),
                  const SizedBox(height: 40),

                  // ── Card ────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title
                        const Text(
                          'Sign in',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter your credentials to continue',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Username / Email field
                        CbTextField(
                          controller: _usernameController,
                          label: cfg.isCloud ? 'Email' : 'Username',
                          hint: cfg.isCloud
                              ? 'name@company.com'
                              : 'Enter your username',
                          keyboardType: cfg.isCloud
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                        ),
                        const SizedBox(height: 18),

                        // Password field
                        CbTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: 'Enter your password',
                          obscureText: _obscurePassword,
                          onSubmitted: (_) => _login(cfg),
                          suffix: GestureDetector(
                            onTap: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                _obscurePassword ? 'Show' : 'Hide',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF007CFF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Sign in button
                        CbButton(
                          label: 'Sign in',
                          expand: true,
                          loading: _isLoading,
                          onPressed: _isLoading ? null : () => _login(cfg),
                        ),

                        if (cfg.isCloud) ...[
                          const SizedBox(height: 12),
                          CbButton(
                            label: 'Create an account',
                            variant: CbButtonVariant.secondary,
                            expand: true,
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const SignUpScreen()),
                                    );
                                  },
                          ),
                        ],

                        // Debug hint — local build only
                        if (kDebugMode) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Local build  —  username: admin  ·  password: admin',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Footer ──────────────────────────────────────────
                  _Footer(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/yatricloud_logo.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: CbTokens.primary,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Yatri Billing',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => launchUrl(
            Uri.parse('mailto:info@yatricloud.com'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text(
            'info@yatricloud.com',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              decoration: TextDecoration.underline,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => launchUrl(
            Uri.parse('tel:+919724823602'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text(
            '+91 9724823602',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppConfig.version,
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
