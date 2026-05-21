import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';
import '../card_widget.dart';

class FlyingCard {
  final int id;
  final Card? card;
  final bool faceUp;
  final Offset from;
  final Offset to;
  final Duration duration;

  const FlyingCard({
    required this.id,
    required this.card,
    required this.faceUp,
    required this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 200),
  });
}

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
