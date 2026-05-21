import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';
import 'package:durak_protocol/durak_protocol.dart';
import '../card_widget.dart';
import 'actions_bar.dart';
import 'player_seat.dart';

class TableArea extends StatelessWidget {
  final GameStateView gs;
  final int myIndex;
  final Set<int> hiddenCardIds;
  final bool animating;
  final Card? selectedAttackCard;
  final bool imAttacker;
  final bool imDefender;
  final bool canAdd;
  final bool isTokenHolder;
  final GlobalKey tableKey;
  final List<GlobalKey> seatKeys;
  final List<GlobalKey> tableCellKeys;
  final void Function(int cardId) onAttackByDrag;
  final void Function(Card attackCard, int cardId) onDefendByDrag;
  final void Function(int cardId) onTransferByDrag;
  final void Function(Card?) onSelectAttackCard;
  final VoidCallback onTake;
  final VoidCallback onPass;

  const TableArea({
    super.key,
    required this.gs,
    required this.myIndex,
    required this.hiddenCardIds,
    required this.animating,
    required this.selectedAttackCard,
    required this.imAttacker,
    required this.imDefender,
    required this.canAdd,
    required this.isTokenHolder,
    required this.tableKey,
    required this.seatKeys,
    required this.tableCellKeys,
    required this.onAttackByDrag,
    required this.onDefendByDrag,
    required this.onTransferByDrag,
    required this.onSelectAttackCard,
    required this.onTake,
    required this.onPass,
  });

  static List<Alignment> _seatPositions(int count) => switch (count) {
        2 => const [Alignment(0.00, -0.72)],
        3 => const [Alignment(-0.50, -0.72), Alignment(0.50, -0.72)],
        4 => const [
            Alignment(-0.88, 0.15),
            Alignment(0.00, -0.72),
            Alignment(0.88, 0.15),
          ],
        5 => const [
            Alignment(-0.88, 0.15),
            Alignment(-0.45, -0.72),
            Alignment(0.45, -0.72),
            Alignment(0.88, 0.15),
          ],
        6 => const [
            Alignment(-0.88, 0.15),
            Alignment(-0.55, -0.72),
            Alignment(0.55, -0.72),
            Alignment(0.88, 0.15),
          ],
        _ => const [],
      };

  static EdgeInsets _tablePadding(int playerCount) =>
      playerCount <= 3
          ? const EdgeInsets.fromLTRB(8, 140, 8, 8)
          : const EdgeInsets.fromLTRB(80, 140, 80, 8);

  int get _actorIndex => switch (gs.phase) {
        GamePhase.attacking => gs.attackerIndex,
        GamePhase.defending => gs.defenderIndex,
        _ => gs.currentAdderIndex,
      };

  @override
  Widget build(BuildContext context) {
    final count = gs.players.length;
    final positions = _seatPositions(count);

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: _tablePadding(count),
            child: _buildTableGrid(),
          ),
        ),
        for (int si = 1; si < count; si++)
          Align(
            alignment: positions[si - 1],
            child: FractionalTranslation(
              translation: positions[si - 1].y < 0
                  ? const Offset(0, -0.15)
                  : Offset.zero,
              child: _buildPlayerSeat((myIndex + si) % count),
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: GameFab(
            gs: gs,
            imDefender: imDefender,
            isTokenHolder: isTokenHolder,
            onTake: onTake,
            onPass: onPass,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerSeat(int playerIndex) {
    return PlayerSeat(
      player: gs.players[playerIndex],
      isActor: playerIndex == _actorIndex,
      isDefender: playerIndex == gs.defenderIndex,
      seatKey: seatKeys[playerIndex],
    );
  }

  Widget _buildTableGrid() {
    return Center(
      key: tableKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int row = 0; row < 3; row++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int col = 0; col < 3; col++)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      key: tableCellKeys[row * 3 + col],
                      width: 72,
                      height: 96,
                      child: _tableCell(row * 3 + col),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tableCell(int i) {
    if (i >= gs.table.length) return _buildEmptyTableCell();
    final entry = gs.table[i];
    if (hiddenCardIds.contains(entry.attack.id)) return _buildEmptyTableCell();
    return _buildTableEntry(entry);
  }

  Widget _buildEmptyTableCell() {
    final isTransfer = imDefender && gs.phase == GamePhase.defending;
    final canDrop = isTransfer ||
        (imAttacker && gs.phase == GamePhase.attacking) ||
        (canAdd &&
            (gs.phase == GamePhase.adding || gs.phase == GamePhase.taking));

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => canDrop && !animating,
      onAcceptWithDetails: (d) => isTransfer
          ? onTransferByDrag(d.data)
          : onAttackByDrag(d.data),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: Border.all(
              color: hovering ? Colors.orange.withAlpha(160) : Colors.white12,
              width: hovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: hovering
              ? Center(
                  child: Text(
                    isTransfer ? 'Перевести' : 'Бросить',
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildTableEntry(TableEntryView entry) {
    final canDefend =
        imDefender && gs.phase == GamePhase.defending && entry.defense == null;
    final isSelected = selectedAttackCard == entry.attack;

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => canDefend && !animating,
      onAcceptWithDetails: (d) => onDefendByDrag(entry.attack, d.data),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: canDefend
              ? () => onSelectAttackCard(isSelected ? null : entry.attack)
              : null,
          child: SizedBox(
            width: 72,
            height: 96,
            child: Stack(
              children: [
                CardWidget(
                  card: entry.attack,
                  selected: isSelected || hovering,
                  highlighted: canDefend && !isSelected && !hovering,
                ),
                if (entry.defense != null &&
                    !hiddenCardIds.contains(entry.defense!.id))
                  Positioned(
                    top: 16,
                    left: 16,
                    child: CardWidget(card: entry.defense!),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
