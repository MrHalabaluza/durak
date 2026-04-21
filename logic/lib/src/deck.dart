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
        deck._cards.add(entry.key);
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
