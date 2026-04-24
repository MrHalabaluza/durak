enum Suit { diamonds, hearts, clubs, spades }

enum Rank { two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace }

class Card {
  static int _nextId = 0;

  final int id;
  final Suit suit;
  final Rank rank;

  Card(this.suit, this.rank) : id = _nextId++;

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
