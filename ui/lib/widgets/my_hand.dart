import 'package:flutter/material.dart' hide Card;
import 'package:durak_protocol/durak_protocol.dart';
import '../card_widget.dart';
import '../sort_hand.dart';

class MyHand extends StatelessWidget {
  final GameStateView gs;
  final Set<int> hiddenCardIds;
  final bool animating;
  final Set<int> selectedCardIds;
  final GlobalKey handKey;
  final GlobalKey Function(int cardId) handSlotKey;
  final void Function(int cardId) onCardTap;

  const MyHand({
    super.key,
    required this.gs,
    required this.hiddenCardIds,
    required this.animating,
    required this.selectedCardIds,
    required this.handKey,
    required this.handSlotKey,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    if (gs.hand.isEmpty) {
      return SizedBox(
        key: handKey,
        child: const Center(
          child: Text('Нет карт', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    final sorted = sortHand(gs.hand, gs.trump);
    return SizedBox(
      key: handKey,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            for (final card in sorted)
              Padding(
                key: handSlotKey(card.id),
                padding: const EdgeInsets.only(right: 6),
                child: Visibility(
                  visible: !hiddenCardIds.contains(card.id),
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Draggable<int>(
                    data: card.id,
                    maxSimultaneousDrags: animating ? 0 : 1,
                    feedback: Material(
                      color: Colors.transparent,
                      child: Transform.scale(
                        scale: 1.1,
                        child: CardWidget(card: card, selected: true),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: CardWidget(card: card),
                    ),
                    child: CardWidget(
                      card: card,
                      selected: selectedCardIds.contains(card.id),
                      onTap: animating ? null : () => onCardTap(card.id),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
