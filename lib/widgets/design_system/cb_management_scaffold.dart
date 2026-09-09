import 'package:flutter/material.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/widgets/design_system/cb_animations.dart';
import 'package:invoiso/widgets/design_system/cb_page_header.dart';

/// Standard layout wrapper for management screens.
class CbManagementScaffold extends StatelessWidget {
  const CbManagementScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions,
    this.loading = false,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CbTokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CbPageHeader(
            title: title,
            subtitle: subtitle,
            actions: actions,
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : CbFadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: body,
                  ),
          ),
        ],
      ),
    );
  }
}
