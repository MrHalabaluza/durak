import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';

class CardWidget extends StatelessWidget {
  final Card card;
  final Suit trump;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;

  const CardWidget({
    super.key,
    required this.card,
    required this.trump,
    this.selected = false,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTrump = card.suit == trump;
    final isRed = card.suit == Suit.hearts || card.suit == Suit.diamonds;

    final suitSymbol = switch (card.suit) {
      Suit.diamonds => '♦',
      Suit.hearts => '♥',
      Suit.clubs => '♣',
      Suit.spades => '♠',
    };

    final rankLabel = switch (card.rank) {
      Rank.six => '6',
      Rank.seven => '7',
      Rank.eight => '8',
      Rank.nine => '9',
      Rank.ten => '10',
      Rank.jack => 'В',
      Rank.queen => 'Д',
      Rank.king => 'К',
      Rank.ace => 'Т',
    };

    Color bg = Colors.white;
    Color border = Colors.grey.shade400;
    if (selected) border = Colors.yellow;
    if (highlighted) border = Colors.lightBlue;
    if (isTrump) bg = const Color(0xFFFFF9C4);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 56,
        height: 80,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: border,
            width: selected || highlighted ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [const BoxShadow(color: Colors.yellow, blurRadius: 6)]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rankLabel,
                style: TextStyle(
                  color: isRed ? Colors.red : Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              Text(
                suitSymbol,
                style: TextStyle(
                  color: isRed ? Colors.red : Colors.black,
                  fontSize: 14,
                  height: 1,
                ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  suitSymbol,
                  style: TextStyle(
                    color: isRed ? Colors.red : Colors.black,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
