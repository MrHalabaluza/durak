import 'dart:collection';
import 'dart:math';
import 'card.dart';

HashMap<Card, int> _newCardMap() => HashMap<Card, int>(
      equals: (a, b) => a.suit == b.suit && a.rank == b.rank,
      hashCode: (c) => Object.hash(c.suit, c.rank),
    );

class DeckConfig {
  /// Number of copies of each card. Cards absent from the map are not included.
  /// Keyed by suit+rank (multiple Card instances with the same suit+rank are treated as one key).
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
    final m = _newCardMap();
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
    final m = _newCardMap()..addAll(counts);
    m.removeWhere((_, v) => v <= 0);
    return DeckConfig._(m);
  }

  /// Random deck: [totalCount] cards drawn uniformly (with replacement) from
  /// the pool of all cards with rank >= [minRank]. Each draw is independent,
  /// so some cards may appear multiple times and others not at all.
  factory DeckConfig.random(Rank minRank, int totalCount, Random rng) {
    if (totalCount <= 0) return DeckConfig._(_newCardMap());
    final pool = [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (rank.index >= minRank.index) Card(suit, rank),
    ];
    final m = _newCardMap();
    for (var i = 0; i < totalCount; i++) {
      final card = pool[rng.nextInt(pool.length)];
      m[card] = (m[card] ?? 0) + 1;
    }
    return DeckConfig._(m);
  }

  int get cardCount => counts.values.fold(0, (a, b) => a + b);

  /// Returns a new config with [card] set to [count] copies (0 removes it).
  DeckConfig withCount(Card card, int count) {
    final m = _newCardMap()..addAll(counts);
    if (count <= 0) {
      m.remove(card);
    } else {
      m[card] = count;
    }
    return DeckConfig._(m);
  }
}
