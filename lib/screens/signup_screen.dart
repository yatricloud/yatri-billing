import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/models/user.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/screens/dashboard_screen.dart';
import 'package:invoiso/screens/login_screen.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:invoiso/widgets/design_system/cb_auth_layout.dart';
import 'package:invoiso/widgets/design_system/cb_button.dart';
import 'package:invoiso/widgets/design_system/cb_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _businessController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _businessController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _signUp() async {
    final business = _businessController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (business.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage('Please fill in all fields');
      return;
    }
    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      _showMessage('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final resp = await client.auth.signUp(
        email: email,
        password: password,
        data: {'business_name': business},
      );

      if (resp.session != null) {
        await client.auth.refreshSession();
        final current = client.auth.currentUser;
        if (current == null) {
          _showMessage('Account created. Please log in.');
          return;
        }
        final user =
            await ref.read(authRepositoryProvider).getUserById(current.id);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(user ??
                User(
                  id: current.id,
                  username: email,
                  password: '',
                  userType: 'admin',
                  passwordChanged: true,
                )),
          ),
        );
      } else {
        _showMessage(
            'Account created! Check your email to confirm, then log in.');
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('Failed to fetch') ||
          errStr.contains('ClientException')) {
        _showMessage(
            'Network error: Unable to connect to Supabase. Check your connection.');
      } else {
        _showMessage('Sign up failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = CbStaggeredList(
      children: [
        Text('Create your account', style: AppTypography.titleLg()),
        const SizedBox(height: CbTokens.spaceXs),
        Text(
          'Start invoicing in minutes with your own secure workspace.',
          style: AppTypography.bodySm(),
        ),
        const SizedBox(height: CbTokens.spaceXl),
        CbTextField(
          controller: _businessController,
          label: 'Business / Company name',
          hint: 'e.g. Acme Corporation',
        ),
        const SizedBox(height: CbTokens.spaceBase),
        CbTextField(
          controller: _emailController,
          label: 'Email',
          hint: 'name@company.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: CbTokens.spaceBase),
        CbTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'Create a strong password',
          obscureText: _obscurePassword,
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
        const SizedBox(height: CbTokens.spaceBase),
        CbTextField(
          controller: _confirmController,
          label: 'Confirm password',
          hint: 'Re-enter your password',
          obscureText: _obscureConfirm,
          onSubmitted: (_) => _signUp(),
          suffix: IconButton(
            icon: Icon(
              _obscureConfirm
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: CbTokens.muted,
            ),
            onPressed: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        const SizedBox(height: CbTokens.spaceXl),
        CbButton(
          label: 'Create account',
          expand: true,
          loading: _isLoading,
          onPressed: _isLoading ? null : _signUp,
        ),
        const SizedBox(height: CbTokens.spaceBase),
        Center(
          child: TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
            child: const Text('Already have an account? Sign in'),
          ),
        ),
      ],
    );

    return CbAuthLayout(
      title: 'Start invoicing\nin minutes.',
      subtitle:
          'Set up your business workspace and invite your team when you are ready.',
      badge: 'GET STARTED',
      form: form,
    );
  }
}
