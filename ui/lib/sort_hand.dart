import 'package:durak_logic/durak_logic.dart';

/// Suit display order: ♣ ♦ ♥ ♠, with [trump] moved to the end.
const _suitOrder = [Suit.clubs, Suit.diamonds, Suit.hearts, Suit.spades];

/// Returns [hand] sorted for display: non-trump suits in [♣,♦,♥,♠] order,
/// trump suit last; within each suit ascending by rank.
List<Card> sortHand(List<Card> hand, Suit trump) {
  final order = [
    ..._suitOrder.where((s) => s != trump),
    trump,
  ];
  final result = List<Card>.from(hand);
  result.sort((a, b) {
    final suitCmp = order.indexOf(a.suit).compareTo(order.indexOf(b.suit));
    if (suitCmp != 0) return suitCmp;
    return a.rank.index.compareTo(b.rank.index);
  });
  return result;
}
