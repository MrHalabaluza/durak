import 'package:flutter/material.dart' hide Card;
import '../card_widget.dart';

class DiscardCorner extends StatelessWidget {
  final int discardSize;
  final GlobalKey discardKey;

  const DiscardCorner({
    super.key,
    required this.discardSize,
    required this.discardKey,
  });

  @override
  Widget build(BuildContext context) {
    if (discardSize == 0) return SizedBox(key: discardKey, width: kCardWidth);
    return SizedBox(
      key: discardKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: 0.12,
            child: const CardWidget(faceUp: false, width: kCardWidth),
          ),
          const SizedBox(height: 3),
          Text(
            '$discardSize',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
