import 'package:flutter/material.dart';
import 'package:invoiso/services/supabase_config.dart';

/// Minimal, high-end configuration screen shown when environment variables are not set.
///
/// Strictly adheres to minimal monochrome styling (no rainbow colors, no congested text).
class MissingConfigScreen extends StatefulWidget {
  final VoidCallback? onRetry;

  const MissingConfigScreen({super.key, this.onRetry});

  @override
  State<MissingConfigScreen> createState() => _MissingConfigScreenState();
}

class _MissingConfigScreenState extends State<MissingConfigScreen> {
  bool _isChecking = false;
  String? _errorMessage;

  Future<void> _checkConfig() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    try {
      await SupabaseConfig.load();
      if (SupabaseConfig.isConfigured) {
        widget.onRetry?.call();
      } else {
        setState(() {
          _errorMessage =
              'Configuration not found. Please set SUPABASE_URL and SUPABASE_ANON_KEY.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x060F172A),
                    blurRadius: 32,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Minimal Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.shield_outlined,
                        size: 22,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Title with generous bottom margin
                  const Text(
                    'Database Configuration Required',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.4,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Description with relaxed line-height and generous bottom margin
                  const Text(
                    'To protect your data and ensure zero unauthorized database calls, '
                    'connections remain disabled until your environment variables are configured. '
                    'No credentials are hardcoded in this build.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                      height: 1.6,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 16, color: Color(0xFF0F172A)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF334155),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Divider
                  const Divider(color: Color(0xFFF1F5F9), height: 1),
                  const SizedBox(height: 28),

                  // Configuration Steps with generous spacing
                  _buildMinimalStep(
                    'Vercel Deployment',
                    'In your Vercel project, go to Settings > Environment Variables and add SUPABASE_URL and SUPABASE_ANON_KEY.',
                  ),
                  const SizedBox(height: 22),
                  _buildMinimalStep(
                    'Local Development',
                    'Copy .env.example to .env and run with: flutter run -d chrome --dart-define-from-file=.env',
                  ),
                  const SizedBox(height: 22),
                  _buildMinimalStep(
                    'Security Policy',
                    'Supply only your public anon key. The system automatically rejects any service_role key to prevent RLS bypass.',
                  ),

                  const SizedBox(height: 36),

                  // Minimal Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isChecking ? null : _checkConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Check Connection & Reload',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalStep(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
            height: 1.55,
          ),
        ),
      ],
    );
  }
}
