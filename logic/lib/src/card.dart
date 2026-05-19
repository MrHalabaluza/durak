enum Suit { diamonds, hearts, clubs, spades }

enum Rank { two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace }

class Card {
  static int _nextId = 0;

  final int id;
  final Suit suit;
  final Rank rank;

  Card(this.suit, this.rank) : id = _nextId++;

  Card.withId(this.id, this.suit, this.rank);

  /// Returns true if this card beats [other] given [trump] suit.
  bool beats(Card other, Suit trump) {
    if (suit == trump && other.suit != trump) return true;
    if (suit == other.suit) return rank.index > other.rank.index;
    return false;
  }

  bool sameValue(Card other) => suit == other.suit && rank == other.rank;

  @override
  bool operator ==(Object other) => other is Card && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '${rank.name}_of_${suit.name}[$id]';
}
