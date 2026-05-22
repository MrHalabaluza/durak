import 'package:flutter/material.dart' hide Card;
import '../card_widget.dart';
import 'flying_card.dart';

class CardOverlay extends StatelessWidget {
  final List<FlyingCard> flying;
  final GlobalKey overlayKey;

  const CardOverlay({
    super.key,
    required this.flying,
    required this.overlayKey,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: overlayKey,
      children: [
        for (final fly in flying)
          TweenAnimationBuilder<Offset>(
            key: ValueKey(fly.id),
            tween: Tween(begin: fly.from, end: fly.to),
            duration: fly.duration,
            curve: Curves.easeInOut,
            builder: (_, offset, child) =>
                Positioned(left: offset.dx, top: offset.dy, child: child!),
            child: IgnorePointer(
              child: CardWidget(
                card: fly.card,
                faceUp: fly.faceUp,
                width: kCardWidth,
              ),
            ),
          ),
      ],
    );
  }
}
