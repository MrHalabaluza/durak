import 'dart:math';
import 'card.dart';
import 'deck_config.dart';

class Deck {
  final List<Card> _cards;

  Deck._() : _cards = [];

  factory Deck.standard([DeckConfig config = const DeckConfig()]) {
    final deck = Deck._();
    for (final suit in Suit.values) {
      if (!config.suits.contains(suit)) continue;
      for (final rank in Rank.values) {
        if (rank.index >= config.minRank.index) {
          deck._cards.add(Card(suit, rank));
        }
      }
    }
    return deck;
  }

  int get size => _cards.length;
  bool get isEmpty => _cards.isEmpty;
  bool get isNotEmpty => _cards.isNotEmpty;

  /// Top card determines trump; not removed until drawn.
  Card? get topCard => _cards.isEmpty ? null : _cards.last;

  void shuffle([Random? random]) => _cards.shuffle(random ?? Random());

  Card? draw() => isEmpty ? null : _cards.removeLast();

  List<Card> drawMany(int count) {
    final result = <Card>[];
    for (var i = 0; i < count && isNotEmpty; i++) {
      result.add(_cards.removeLast());
    }
    return result;
  }
}
