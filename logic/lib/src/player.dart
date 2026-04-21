import 'card.dart';

class Player {
  final String id;
  final List<Card> hand;
  bool _hasLeft = false;

  Player(this.id) : hand = [];

  bool get hasLeft => _hasLeft;
  bool get hasCards => hand.isNotEmpty;
  int get handSize => hand.length;

  void addCards(Iterable<Card> cards) => hand.addAll(cards);

  bool removeCard(Card card) => hand.remove(card);

  bool hasCard(Card card) => hand.contains(card);

  bool hasAllCards(Iterable<Card> cards) {
    final needed = <Card, int>{};
    for (final c in cards) needed[c] = (needed[c] ?? 0) + 1;
    final avail = <Card, int>{};
    for (final c in hand) avail[c] = (avail[c] ?? 0) + 1;
    return needed.entries.every((e) => (avail[e.key] ?? 0) >= e.value);
  }

  /// Called when deck is empty and player empties their hand — they are done.
  void markLeft() => _hasLeft = true;
}
