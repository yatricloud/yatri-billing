import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:invoiso/widgets/design_system/cb_badge.dart';
import 'package:invoiso/widgets/design_system/cb_card.dart';

/// Split auth layout — dark editorial hero + white form panel.
class CbAuthLayout extends StatelessWidget {
  const CbAuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    this.badge = 'YATRI BILLING CLOUD',
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget form;
  final String badge;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 960;

    if (!isWide) {
      return Scaffold(
        backgroundColor: CbTokens.canvas,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroPanel(
                title: title,
                subtitle: subtitle,
                badge: badge,
                compact: true,
              ),
              Padding(
                padding: const EdgeInsets.all(CbTokens.spaceXl),
                child: CbFadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: form,
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  child: footer,
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: _HeroPanel(
              title: title,
              subtitle: subtitle,
              badge: badge,
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: CbTokens.canvas,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(CbTokens.spaceXxl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: CbFadeSlideIn(
                      delay: const Duration(milliseconds: 150),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          form,
                          if (footer != null) ...[
                            const SizedBox(height: CbTokens.spaceLg),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.badge,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final String badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: CbTokens.surfaceSoft,
          border: Border(bottom: BorderSide(color: CbTokens.hairline)),
        ),
        padding: const EdgeInsets.all(CbTokens.spaceXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CbFadeSlideIn(child: CbBadge(label: badge, dark: false)),
            const SizedBox(height: CbTokens.spaceLg),
            CbFadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Text(
                title,
                style: AppTypography.displayMd(CbTokens.ink).copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: CbTokens.spaceBase),
            CbFadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: Text(
                subtitle,
                style: AppTypography.bodyMd(CbTokens.body),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: CbTokens.surfaceSoft,
        border: Border(right: BorderSide(color: CbTokens.hairline)),
      ),
      padding: const EdgeInsets.all(CbTokens.spaceSection),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Hero text strictly at the top
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CbFadeSlideIn(child: CbBadge(label: badge, dark: false)),
              const SizedBox(height: CbTokens.spaceXxl),
              CbFadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  title,
                  style: AppTypography.displayMd(CbTokens.ink).copyWith(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: CbTokens.spaceBase),
              CbFadeSlideIn(
                delay: const Duration(milliseconds: 160),
                child: Text(
                  subtitle,
                  style: AppTypography.bodyMd(CbTokens.body),
                ),
              ),
            ],
          ),
          // Visual cards cleanly separated below the text, never overlapping
          Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              height: 180,
              width: 380,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Transform.rotate(
                      angle: -0.04,
                      child: const _MockDashboardCard(width: 250, offset: 0),
                    ),
                  ),
                  Positioned(
                    right: 80,
                    bottom: 30,
                    child: Transform.rotate(
                      angle: 0.03,
                      child: const _MockDashboardCard(width: 230, offset: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockDashboardCard extends StatelessWidget {
  const _MockDashboardCard({required this.width, required this.offset});

  final double width;
  final int offset;

  @override
  Widget build(BuildContext context) {
    return CbCard(
      dark: false,
      padding: const EdgeInsets.all(CbTokens.spaceLg),
      animateHover: true,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: CbTokens.hairline,
                borderRadius: BorderRadius.circular(CbTokens.radiusPill),
              ),
            ),
            const SizedBox(height: CbTokens.spaceLg),
            Text(
              offset == 0 ? '₹2,48,500' : '12 invoices',
              style: AppTypography.numberDisplay(CbTokens.ink),
            ),
            const SizedBox(height: CbTokens.spaceXs),
            Text(
              offset == 0 ? 'Revenue this month' : 'Pending collection',
              style: AppTypography.caption(CbTokens.muted),
            ),
            const SizedBox(height: CbTokens.spaceLg),
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: CbTokens.primary,
                borderRadius: BorderRadius.circular(CbTokens.radiusPill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
