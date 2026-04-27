import 'dart:math';
import 'card.dart';
import 'deck_config.dart';

class Deck {
  final List<Card> _cards;

  Deck._() : _cards = [];

  factory Deck.standard([DeckConfig? config]) {
    final cfg = config ?? DeckConfig();
    final deck = Deck._();
    for (final entry in cfg.counts.entries) {
      for (var i = 0; i < entry.value; i++) {
        deck._cards.add(Card(entry.key.suit, entry.key.rank));
      }
    }
    return deck;
  }

  int get size => _cards.length;
  bool get isEmpty => _cards.isEmpty;
  bool get isNotEmpty => _cards.isNotEmpty;

  /// The face-up trump card placed at the very bottom — drawn last.
  Card? get bottomCard => _cards.isEmpty ? null : _cards.first;

  void shuffle([Random? random]) => _cards.shuffle(random ?? Random());

  Card? draw() => isEmpty ? null : _cards.removeLast();

  /// Finds the first non-ace from the top of the deck, removes it from its
  /// current position, places it at the bottom (drawn last), and returns it.
  /// Returns null if all remaining cards are aces (degenerate edge case).
  Card? pullTrumpCard() {
    for (var i = _cards.length - 1; i >= 0; i--) {
      if (_cards[i].rank != Rank.ace) {
        final card = _cards.removeAt(i);
        _cards.insert(0, card);
        return card;
      }
    }
    return null;
  }

  List<Card> drawMany(int count) {
    final result = <Card>[];
    for (var i = 0; i < count && isNotEmpty; i++) {
      result.add(_cards.removeLast());
    }
    return result;
  }
}
