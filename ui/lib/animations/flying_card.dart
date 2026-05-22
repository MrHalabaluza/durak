import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';

class FlyingCard {
  final int id;
  final Card? card;
  final bool faceUp;
  final Offset from;
  final Offset to;
  final Duration duration;

  const FlyingCard({
    required this.id,
    required this.card,
    required this.faceUp,
    required this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 200),
  });
}
