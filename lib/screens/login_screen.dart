import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/constants.dart';
import 'package:invoiso/providers/app_config_provider.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/screens/change_password_screen.dart';
import 'package:invoiso/screens/dashboard_screen.dart';
import 'package:invoiso/screens/signup_screen.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:invoiso/widgets/design_system/cb_auth_layout.dart';
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
    final usernameText = cfg.isCloud ? 'Email' : 'Username';

    if (username.isEmpty || password.isEmpty) {
      _showSnack('Please enter $usernameText and password');
      return;
    }

    setState(() => _isLoading = true);
    final user =
        await ref.read(authRepositoryProvider).getUser(username, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user == null) {
      _showSnack('Invalid credentials');
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
    final isCloud = cfg.isCloud;

    final form = CbStaggeredList(
      children: [
        if (!isCloud)
          _CloudPromoBanner()
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/yatricloud_logo.png',
                width: 44,
                height: 44,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Yatri ',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        letterSpacing: -0.5,
                      ),
                    ),
                    TextSpan(
                      text: 'Billing',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF007CFF),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: CbTokens.spaceLg),
        Text(
          isCloud ? 'Sign in to your workspace' : 'Welcome back',
          style: AppTypography.titleLg(),
        ),
        const SizedBox(height: CbTokens.spaceXs),
        Text(
          isCloud
              ? 'Manage invoices, customers, and reports from anywhere.'
              : 'Sign in to continue to Yatri Billing.',
          style: AppTypography.bodySm(),
        ),
        const SizedBox(height: CbTokens.spaceXl),
        CbTextField(
          controller: _usernameController,
          label: isCloud ? 'Email' : 'Username',
          hint: isCloud ? 'name@company.com' : 'Enter username',
          keyboardType:
              isCloud ? TextInputType.emailAddress : TextInputType.text,
        ),
        const SizedBox(height: CbTokens.spaceBase),
        CbTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'Enter your password',
          obscureText: _obscurePassword,
          onSubmitted: (_) => _login(cfg),
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: CbTokens.muted,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: CbTokens.spaceXl),
        CbButton(
          label: 'Sign in',
          expand: true,
          loading: _isLoading,
          onPressed: _isLoading ? null : () => _login(cfg),
        ),
        if (isCloud) ...[
          const SizedBox(height: CbTokens.spaceBase),
          CbButton(
            label: 'Create an account',
            variant: CbButtonVariant.secondary,
            expand: true,
            onPressed: _isLoading
                ? null
                : () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    );
                  },
          ),
        ],
      ],
    );

    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Email contact
        InkWell(
          onTap: () => launchUrl(
            Uri.parse('mailto:info@yatricloud.com'),
            mode: LaunchMode.externalApplication,
          ),
          borderRadius: BorderRadius.circular(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mail_outline_rounded, size: 14, color: CbTokens.muted),
              const SizedBox(width: 5),
              Text(
                'info@yatricloud.com',
                style: AppTypography.caption().copyWith(
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CbTokens.spaceXs),
        // Phone contact
        InkWell(
          onTap: () => launchUrl(
            Uri.parse('tel:+919724823602'),
            mode: LaunchMode.externalApplication,
          ),
          borderRadius: BorderRadius.circular(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phone_outlined, size: 14, color: CbTokens.muted),
              const SizedBox(width: 5),
              Text(
                '+91 9724823602',
                style: AppTypography.caption().copyWith(
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CbTokens.spaceXs),
        Text(AppConfig.version, style: AppTypography.caption()),
      ],
    );


    if (isCloud) {
      return CbAuthLayout(
        title: 'Invoice management,\nreimagined.',
        subtitle:
            'Create invoices, track payments, and run your business — securely in the cloud.',
        form: form,
        footer: footer,
      );
    }

    return Scaffold(
      backgroundColor: CbTokens.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CbTokens.spaceXxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                form,
                const SizedBox(height: CbTokens.spaceLg),
                footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudPromoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: CbTokens.surfaceSoft,
      borderRadius: BorderRadius.circular(CbTokens.radiusXl),
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse('https://yatricloud.com'),
          mode: LaunchMode.externalApplication,
        ),
        borderRadius: BorderRadius.circular(CbTokens.radiusXl),
        child: Padding(
          padding: const EdgeInsets.all(CbTokens.spaceBase),
          child: Row(
            children: [
              const Icon(Icons.cloud_outlined, color: CbTokens.primary),
              const SizedBox(width: CbTokens.spaceSm),
              Expanded(
                child: Text(
                  'Need multi-device access? Try Yatri Billing Cloud.',
                  style: AppTypography.bodySm(CbTokens.ink),
                ),
              ),
              const Icon(Icons.arrow_forward, size: 16, color: CbTokens.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.url,
    this.icon,
  });

  final String label;
  final String url;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: CbTokens.muted),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.caption().copyWith(
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }
}
