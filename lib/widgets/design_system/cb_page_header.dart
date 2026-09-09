import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

/// Consistent page header for management screens.
class CbPageHeader extends StatelessWidget {
  const CbPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.dark = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? CbTokens.surfaceDark : CbTokens.canvas;
    final titleColor = dark ? CbTokens.onDark : CbTokens.ink;
    final subColor = dark ? CbTokens.onDarkSoft : CbTokens.muted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: dark ? const Color(0xFF2A2D33) : CbTokens.hairline,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleLg(titleColor)),
                if (subtitle != null) ...[
                  const SizedBox(height: CbTokens.spaceXxs),
                  Text(subtitle!, style: AppTypography.bodySm(subColor)),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
