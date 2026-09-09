import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';

/// Dark editorial hero banner — Coinbase signature pattern.
class CbHeroBanner extends StatelessWidget {
  const CbHeroBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.badge,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return CbFadeSlideIn(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: CbTokens.spaceXl,
          vertical: CbTokens.spaceLg,
        ),
        decoration: BoxDecoration(
          color: CbTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(CbTokens.radiusXl),
          border: Border.all(color: CbTokens.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: CbTokens.accentTint,
                        borderRadius:
                            BorderRadius.circular(CbTokens.radiusPill),
                      ),
                      child: Text(
                        badge!.toUpperCase(),
                        style: AppTypography.captionStrong(CbTokens.primary),
                      ),
                    ),
                    const SizedBox(height: CbTokens.spaceSm),
                  ],
                  Text(title, style: AppTypography.titleLg(CbTokens.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: CbTokens.spaceXxs),
                    Text(
                      subtitle!,
                      style: AppTypography.bodySm(CbTokens.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
