import 'card.dart';

class DeckConfig {
  /// Number of copies of each card. Cards absent from the map are not included.
  final Map<Card, int> counts;

  DeckConfig._(Map<Card, int> counts)
      : counts = Map.unmodifiable(counts);

  /// Standard 36-card deck (6–Ace, all four suits, 1 copy each).
  factory DeckConfig() => DeckConfig.preset(Rank.six);

  /// Generates 1 copy of every card with rank >= [minRank] in [suits].
  factory DeckConfig.preset(
    Rank minRank, [
    Set<Suit> suits = const {
      Suit.diamonds,
      Suit.hearts,
      Suit.clubs,
      Suit.spades,
    },
  ]) {
    final m = <Card, int>{};
    for (final suit in Suit.values) {
      if (!suits.contains(suit)) continue;
      for (final rank in Rank.values) {
        if (rank.index >= minRank.index) m[Card(suit, rank)] = 1;
      }
    }
    return DeckConfig._(m);
  }

  /// Arbitrary deck: provide any [Card] → copy-count mapping.
  /// Entries with count ≤ 0 are ignored.
  factory DeckConfig.custom(Map<Card, int> counts) {
    final m = Map<Card, int>.from(counts)
      ..removeWhere((_, v) => v <= 0);
    return DeckConfig._(m);
  }

  int get cardCount => counts.values.fold(0, (a, b) => a + b);

  /// Returns a new config with [card] set to [count] copies (0 removes it).
  DeckConfig withCount(Card card, int count) {
    final m = Map<Card, int>.from(counts);
    if (count <= 0) {
      m.remove(card);
    } else {
      m[card] = count;
    }
    return DeckConfig._(m);
  }
}
