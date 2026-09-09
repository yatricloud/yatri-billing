import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

enum CbButtonVariant { primary, secondary, tertiary, outlineDark, hero }

class CbButton extends StatefulWidget {
  const CbButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = CbButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.hero = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final CbButtonVariant variant;
  final bool loading;
  final IconData? icon;
  final bool expand;
  final bool hero;

  @override
  State<CbButton> createState() => _CbButtonState();
}

class _CbButtonState extends State<CbButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final height = widget.hero ? 56.0 : 44.0;
    final hPad = widget.hero ? 32.0 : 20.0;

    Color bg;
    Color fg;
    BorderSide? border;

    switch (widget.variant) {
      case CbButtonVariant.primary:
      case CbButtonVariant.hero:
        bg = enabled
            ? (_pressed ? CbTokens.primaryActive : CbTokens.primary)
            : CbTokens.primaryDisabled;
        fg = CbTokens.onPrimary;
      case CbButtonVariant.secondary:
        bg = CbTokens.surfaceSoft;
        fg = CbTokens.ink;
        border = const BorderSide(color: CbTokens.hairline, width: 1);
      case CbButtonVariant.tertiary:
        bg = Colors.transparent;
        fg = CbTokens.primary;
      case CbButtonVariant.outlineDark:
        bg = Colors.transparent;
        fg = CbTokens.onDark;
        border = const BorderSide(color: CbTokens.onDark, width: 1);
    }

    final child = AnimatedContainer(
      duration: CbTokens.durationFast,
      curve: CbTokens.curveDefault,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CbTokens.radiusLg),
        border: border != null ? Border.fromBorderSide(border) : null,
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.loading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
              ),
            )
          else ...[
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              style: AppTypography.button(fg),
            ),
          ],
        ],
      ),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: CbTokens.durationFast,
          curve: CbTokens.curveDefault,
          child: widget.expand ? SizedBox(width: double.infinity, child: child) : child,
        ),
      ),
    );
  }
}
