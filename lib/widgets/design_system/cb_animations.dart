import 'package:flutter/material.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

/// Fade + slide entrance animation for page sections.
class CbFadeSlideIn extends StatefulWidget {
  const CbFadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 16,
  });

  final Widget child;
  final Duration delay;
  final double offsetY;

  @override
  State<CbFadeSlideIn> createState() => _CbFadeSlideInState();
}

class _CbFadeSlideInState extends State<CbFadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CbTokens.durationSlow,
    );
    _fade = CurvedAnimation(parent: _controller, curve: CbTokens.curveDefault);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: CbTokens.curveDefault));

    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Staggered list animation wrapper.
class CbStaggeredList extends StatelessWidget {
  const CbStaggeredList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 60),
  });

  final List<Widget> children;
  final Duration itemDelay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          CbFadeSlideIn(
            delay: itemDelay * i,
            child: children[i],
          ),
      ],
    );
  }
}
