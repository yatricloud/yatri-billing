import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_card.dart';

/// Form/section card with optional dark header band.
class CbSectionCard extends StatelessWidget {
  const CbSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.darkHeader = false,
    this.actions,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final bool darkHeader;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return CbCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CbTokens.spaceLg,
              vertical: CbTokens.spaceBase,
            ),
            decoration: BoxDecoration(
              color: darkHeader ? CbTokens.surfaceDark : CbTokens.surfaceSoft,
              border: Border(
                bottom: BorderSide(
                  color: darkHeader ? const Color(0xFF2A2D33) : CbTokens.hairline,
                ),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(CbTokens.radiusXl),
                topRight: Radius.circular(CbTokens.radiusXl),
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: darkHeader ? CbTokens.onDark : CbTokens.primary,
                    size: 20,
                  ),
                  const SizedBox(width: CbTokens.spaceSm),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.titleMd(
                      darkHeader ? CbTokens.onDark : CbTokens.ink,
                    ),
                  ),
                ),
                if (actions != null) ...actions!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(CbTokens.spaceLg),
            child: child,
          ),
        ],
      ),
    );
  }
}
