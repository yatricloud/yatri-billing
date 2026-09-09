import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_card.dart';

/// Styled list row card for invoices, customers, etc.
class CbListItem extends StatelessWidget {
  const CbListItem({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.actions,
    this.badge,
    this.badgeColor,
    this.onTap,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget>? actions;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CbTokens.spaceSm),
      child: CbCard(
        padding: const EdgeInsets.all(CbTokens.spaceBase),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: CbTokens.spaceBase),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.titleSm(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: CbTokens.spaceXs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: CbTokens.accentTint,
                            borderRadius:
                                BorderRadius.circular(CbTokens.radiusPill),
                            border: Border.all(color: CbTokens.hairline),
                          ),
                          child: Text(
                            badge!,
                            style: AppTypography.captionStrong(
                              badgeColor ?? CbTokens.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTypography.caption(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: CbTokens.spaceBase),
              trailing!,
            ],
            if (actions != null) ...[
              const SizedBox(width: CbTokens.spaceSm),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Circular index/avatar plate for list items.
class CbListLeading extends StatelessWidget {
  const CbListLeading({
    super.key,
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: CbTokens.surfaceStrong,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, color: CbTokens.primary, size: 18)
            : Text(label, style: AppTypography.captionStrong(CbTokens.primary)),
      ),
    );
  }
}
