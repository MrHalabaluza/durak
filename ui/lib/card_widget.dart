import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';

const double kCardWidth = 56;
const double kCardHeight = 80;
const double kCardAspectRatio = kCardWidth / kCardHeight;

class CardWidget extends StatelessWidget {
  final Card? card;
  final bool faceUp;
  final String backSkinId;
  final double? width;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;

  const CardWidget({
    super.key,
    this.card,
    this.faceUp = true,
    this.backSkinId = 'default',
    this.width,
    this.selected = false,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? kCardWidth;
    final h = w / kCardAspectRatio;

    Color borderColor = Colors.grey.shade600;
    double borderWidth = 1.5;
    if (selected) {
      borderColor = Colors.amber;
      borderWidth = 3;
    } else if (highlighted) {
      borderColor = Colors.lightBlueAccent;
      borderWidth = 3;
    }

    final assetPath = faceUp && card != null
        ? 'assets/cards/${card!.suit.name}_${card!.rank.name}.png'
        : 'assets/backs/$backSkinId.png';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6 * w / kCardWidth),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5 * w / kCardWidth),
          child: Image.asset(
            assetPath,
            width: w,
            height: h,
            fit: BoxFit.fill,
          ),
        ),
      ),
    );
  }
}
