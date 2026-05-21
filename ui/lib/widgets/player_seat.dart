import 'package:flutter/material.dart' hide Card;
import 'package:durak_protocol/durak_protocol.dart';
import '../card_widget.dart';

class PlayerSeat extends StatelessWidget {
  final PlayerView player;
  final bool isActor;
  final bool isDefender;
  final GlobalKey seatKey;

  const PlayerSeat({
    super.key,
    required this.player,
    required this.isActor,
    required this.isDefender,
    required this.seatKey,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isActor
        ? (isDefender ? Colors.lightBlue : Colors.orange)
        : Colors.grey.shade700;
    final borderWidth = isActor ? 2.5 : 1.0;

    return Container(
      key: seatKey,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      constraints: const BoxConstraints(maxWidth: 96),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCardFan(player.handSize),
          const SizedBox(height: 3),
          Text(
            player.hasLeft ? '—' : (player.nickname.isEmpty ? '?' : player.nickname),
            style: const TextStyle(fontSize: 10, color: Colors.white70),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style, size: 9, color: Colors.grey),
              const SizedBox(width: 2),
              Text(
                '${player.handSize}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardFan(int count) {
    final shown = count.clamp(0, 5);
    if (shown == 0) {
      return const SizedBox(width: kCardWidth, height: kCardHeight);
    }
    const step = 8.0;
    return SizedBox(
      width: kCardWidth + (shown - 1) * step,
      height: kCardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < shown; i++)
            Positioned(
              left: i * step,
              child: Transform.rotate(
                angle: (i - (shown - 1) / 2) * 0.12,
                child: const CardWidget(faceUp: false, width: kCardWidth),
              ),
            ),
        ],
      ),
    );
  }
}
