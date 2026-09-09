import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

class CbCard extends StatelessWidget {
  const CbCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CbTokens.spaceXl),
    this.dark = false,
    this.onTap,
    this.animateHover = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool dark;
  final VoidCallback? onTap;
  final bool animateHover;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? CbTokens.surfaceDarkElevated : CbTokens.canvas;
    final borderColor =
        dark ? const Color(0xFF2A2D33) : CbTokens.hairline;

    Widget card = AnimatedContainer(
      duration: CbTokens.durationNormal,
      curve: CbTokens.curveDefault,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CbTokens.radiusXl),
        border: Border.all(color: borderColor),
        boxShadow: animateHover ? const [CbTokens.cardShadow] : null,
      ),
      child: child,
    );

    if (onTap != null) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CbTokens.radiusXl),
          child: card,
        ),
      );
    }

    return card;
  }
}

class CbFeatureCard extends StatelessWidget {
  const CbFeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return CbCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: CbTokens.surfaceStrong,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: CbTokens.primary, size: 20),
            ),
          if (icon != null) const SizedBox(width: CbTokens.spaceBase),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMd()),
                const SizedBox(height: CbTokens.spaceXxs),
                Text(subtitle, style: AppTypography.bodySm()),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
