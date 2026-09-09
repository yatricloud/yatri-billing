import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:invoiso/widgets/design_system/cb_button.dart';

/// Empty state placeholder with optional CTA.
class CbEmptyState extends StatelessWidget {
  const CbEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return CbFadeSlideIn(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CbTokens.spaceXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: CbTokens.surfaceStrong,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: CbTokens.muted),
              ),
              const SizedBox(height: CbTokens.spaceLg),
              Text(title, style: AppTypography.titleMd()),
              if (subtitle != null) ...[
                const SizedBox(height: CbTokens.spaceXs),
                Text(
                  subtitle!,
                  style: AppTypography.bodySm(),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: CbTokens.spaceLg),
                CbButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
