import 'card.dart';

class DeckConfig {
  final Rank minRank;
  final Set<Suit> suits;

  const DeckConfig({
    this.minRank = Rank.six,
    this.suits = const {Suit.diamonds, Suit.hearts, Suit.clubs, Suit.spades},
  });

  int get cardCount =>
      (Rank.values.length - minRank.index) * suits.length;
}
