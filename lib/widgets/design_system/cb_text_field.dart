import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

class CbTextField extends StatelessWidget {
  const CbTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.onSubmitted,
    this.validator,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.initialValue,
    this.onChanged,
    // prefixIcon kept for API compat but silently ignored — icons removed per design
    @Deprecated('Icons removed from design system') this.prefixIcon,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;
  final bool enabled;
  final int maxLines;
  final int? minLines;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  // ignore: deprecated_member_use_from_same_package
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    // Always use explicit light-mode colours regardless of system dark mode.
    const lightFill = Colors.white;
    const lightBorder = Color(0xFFE2E8F0); // slate-200
    const lightFocusBorder = CbTokens.primary;
    const lightHint = Color(0xFF94A3B8); // slate-400
    const lightText = Color(0xFF0F172A); // slate-900
    const lightLabel = Color(0xFF475569); // slate-600

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: lightLabel,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          initialValue: initialValue,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onFieldSubmitted: onSubmitted,
          onChanged: onChanged,
          validator: validator,
          enabled: enabled,
          maxLines: obscureText ? 1 : maxLines,
          minLines: minLines,
          style: AppTypography.bodyMd(lightText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: lightHint, fontSize: 14),
            suffixIcon: suffix,
            // Explicit light colours — never inherit from theme
            filled: true,
            fillColor: lightFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CbTokens.radiusSm),
              borderSide: const BorderSide(color: lightBorder, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CbTokens.radiusSm),
              borderSide: const BorderSide(color: lightBorder, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CbTokens.radiusSm),
              borderSide: const BorderSide(color: lightFocusBorder, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CbTokens.radiusSm),
              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CbTokens.radiusSm),
              borderSide: const BorderSide(color: Color(0xFFF1F5F9), width: 1),
            ),
          ),
        ),
      ],
    );
  }
}
