import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

/// Compact icon action button for list rows and toolbars.
class CbIconAction extends StatefulWidget {
  const CbIconAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  State<CbIconAction> createState() => _CbIconActionState();
}

class _CbIconActionState extends State<CbIconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? CbTokens.mutedSoft
        : widget.destructive
            ? CbTokens.semanticDown
            : CbTokens.primary;

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: CbTokens.durationFast,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered && enabled
                  ? color.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(CbTokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: color),
                if (_hovered && enabled) ...[
                  const SizedBox(width: 4),
                  Text(widget.label, style: AppTypography.captionStrong(color)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
