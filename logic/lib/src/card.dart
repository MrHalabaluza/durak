enum Suit { diamonds, hearts, clubs, spades }

enum Rank { six, seven, eight, nine, ten, jack, queen, king, ace }

class Card {
  final Suit suit;
  final Rank rank;

  const Card(this.suit, this.rank);

  /// Returns true if this card beats [other] given [trump] suit.
  bool beats(Card other, Suit trump) {
    if (suit == trump && other.suit != trump) return true;
    if (suit == other.suit) return rank.index > other.rank.index;
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is Card && suit == other.suit && rank == other.rank;

  @override
  int get hashCode => Object.hash(suit, rank);

  @override
  String toString() => '${rank.name}_of_${suit.name}';
}
