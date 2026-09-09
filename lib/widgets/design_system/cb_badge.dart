import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

class CbBadge extends StatelessWidget {
  const CbBadge({
    super.key,
    required this.label,
    this.dark = false,
  });

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? CbTokens.surfaceDarkElevated : CbTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(CbTokens.radiusPill),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.captionStrong(
          dark ? CbTokens.onDarkSoft : CbTokens.ink,
        ),
      ),
    );
  }
}
