import 'package:durak_logic/durak_logic.dart';

Map<String, dynamic> cardToJson(Card c) =>
    {'id': c.id, 'suit': c.suit.name, 'rank': c.rank.name};

Card cardFromJson(Map<String, dynamic> m) => Card.withId(
      m['id'] as int,
      Suit.values.byName(m['suit'] as String),
      Rank.values.byName(m['rank'] as String),
    );

List<Card> cardsFromJson(List<dynamic> list) =>
    list.map((e) => cardFromJson(e as Map<String, dynamic>)).toList();

List<Map<String, dynamic>> deckConfigToJson(DeckConfig dc) =>
    dc.counts.entries
        .where((e) => e.value > 0)
        .map((e) => {
              'suit': e.key.suit.name,
              'rank': e.key.rank.name,
              'count': e.value,
            })
        .toList();

DeckConfig deckConfigFromJson(List<dynamic> list) {
  final counts = <Card, int>{};
  for (final entry in list) {
    final m = entry as Map<String, dynamic>;
    final count = m['count'] as int;
    if (count > 0) {
      counts[Card(
        Suit.values.byName(m['suit'] as String),
        Rank.values.byName(m['rank'] as String),
      )] = count;
    }
  }
  return DeckConfig.custom(counts);
}
