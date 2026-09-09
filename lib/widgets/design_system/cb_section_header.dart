import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:invoiso/widgets/design_system/cb_badge.dart';

/// Section header with optional badge and trailing text.
class CbSectionHeader extends StatelessWidget {
  const CbSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.icon,
    this.actions,
    this.animate = true,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final IconData? icon;
  final List<Widget>? actions;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: CbTokens.surfaceStrong,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: CbTokens.primary, size: 18),
          ),
          const SizedBox(width: CbTokens.spaceSm),
        ],
        Text(title, style: AppTypography.titleMd()),
        if (badge != null) ...[
          const SizedBox(width: CbTokens.spaceSm),
          CbBadge(label: badge!),
        ],
        const Spacer(),
        if (subtitle != null)
          Text(subtitle!, style: AppTypography.caption()),
        if (actions != null) ...actions!,
      ],
    );

    if (animate) return CbFadeSlideIn(child: content);
    return content;
  }
}
