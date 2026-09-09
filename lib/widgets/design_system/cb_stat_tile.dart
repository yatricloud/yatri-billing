import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_card.dart';

class CbStatTile extends StatelessWidget {
  const CbStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.trend,
    this.positive,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? trend;
  final bool? positive;

  @override
  Widget build(BuildContext context) {
    final trendColor = positive == true
        ? CbTokens.semanticUp
        : positive == false
            ? CbTokens.semanticDown
            : CbTokens.muted;

    return CbCard(
      padding: const EdgeInsets.all(CbTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.captionStrong(CbTokens.primary).copyWith(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.displaySm().copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (trend != null) ...[
            const SizedBox(height: 4),
            Text(trend!, style: AppTypography.captionStrong(trendColor)),
          ],
        ],
      ),
    );
  }
}
