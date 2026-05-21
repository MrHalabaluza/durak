import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';
import 'package:durak_protocol/durak_protocol.dart';

class ActionsBar extends StatelessWidget {
  final GamePhase phase;
  final bool imAttacker;
  final bool imDefender;
  final bool canAdd;
  final List<Card> selectedCards;
  final Card? selectedAttackCard;
  final VoidCallback onAttack;
  final VoidCallback onDefend;
  final VoidCallback onTransfer;
  final VoidCallback onTransit;
  final VoidCallback onAddAttack;

  const ActionsBar({
    super.key,
    required this.phase,
    required this.imAttacker,
    required this.imDefender,
    required this.canAdd,
    required this.selectedCards,
    required this.selectedAttackCard,
    required this.onAttack,
    required this.onDefend,
    required this.onTransfer,
    required this.onTransit,
    required this.onAddAttack,
  });

  @override
  Widget build(BuildContext context) {
    final hasSel = selectedCards.isNotEmpty;
    final hasSingle = selectedCards.length == 1;
    final hasTarget = selectedAttackCard != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (phase == GamePhase.attacking)
            FilledButton(
              onPressed: imAttacker && hasSel ? onAttack : null,
              child: const Text('Атаковать'),
            ),
          if (phase == GamePhase.defending) ...[
            FilledButton(
              onPressed: imDefender && hasTarget && hasSingle ? onDefend : null,
              child: const Text('Отбить'),
            ),
            OutlinedButton(
              onPressed: imDefender && hasSel ? onTransfer : null,
              child: const Text('Перевести'),
            ),
            OutlinedButton(
              onPressed: imDefender && hasSingle ? onTransit : null,
              child: const Text('Проездной'),
            ),
          ],
          if (phase == GamePhase.adding || phase == GamePhase.taking)
            FilledButton(
              onPressed: canAdd && hasSel ? onAddAttack : null,
              child: const Text('Подкинуть'),
            ),
        ],
      ),
    );
  }
}

class GameFab extends StatelessWidget {
  final GameStateView gs;
  final bool imDefender;
  final bool isTokenHolder;
  final VoidCallback onTake;
  final VoidCallback onPass;

  const GameFab({
    super.key,
    required this.gs,
    required this.imDefender,
    required this.isTokenHolder,
    required this.onTake,
    required this.onPass,
  });

  @override
  Widget build(BuildContext context) {
    final phase = gs.phase;
    if (imDefender &&
        (phase == GamePhase.defending || phase == GamePhase.adding)) {
      return FloatingActionButton.extended(
        heroTag: 'take_fab',
        onPressed: onTake,
        label: const Text('Взять'),
        icon: const Icon(Icons.download_rounded, size: 18),
        backgroundColor: Colors.red.shade700,
      );
    }
    if (isTokenHolder &&
        (phase == GamePhase.adding || phase == GamePhase.taking)) {
      return FloatingActionButton.extended(
        heroTag: 'pass_fab',
        onPressed: onPass,
        label: const Text('Пас'),
        icon: const Icon(Icons.skip_next_rounded, size: 18),
      );
    }
    return const SizedBox.shrink();
  }
}
