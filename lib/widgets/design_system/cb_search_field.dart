import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

/// Pill-shaped search input per Coinbase design spec.
class CbSearchField extends StatelessWidget {
  const CbSearchField({
    super.key,
    this.controller,
    this.hint = 'Search…',
    this.onChanged,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: CbTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(CbTokens.radiusPill),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: AppTypography.bodyMd(CbTokens.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.bodyMd(CbTokens.mutedSoft),
          prefixIcon: const Icon(Icons.search, color: CbTokens.muted, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}
