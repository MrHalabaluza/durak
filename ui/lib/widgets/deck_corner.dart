import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';
import '../card_widget.dart';

class DeckCorner extends StatelessWidget {
  final int deckSize;
  final Card? trumpCard;
  final GlobalKey deckKey;

  const DeckCorner({
    super.key,
    required this.deckSize,
    required this.trumpCard,
    required this.deckKey,
  });

  @override
  Widget build(BuildContext context) {
    if (deckSize == 0) return SizedBox(key: deckKey, width: kCardWidth);
    return SizedBox(
      key: deckKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: kCardWidth,
            height: kCardHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (trumpCard != null)
                  Positioned(
                    left: kCardWidth / 2,
                    top: (kCardHeight - kCardWidth) / 2,
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: CardWidget(
                        card: trumpCard,
                        faceUp: true,
                        width: kCardWidth,
                      ),
                    ),
                  ),
                const CardWidget(faceUp: false, width: kCardWidth),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$deckSize',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
