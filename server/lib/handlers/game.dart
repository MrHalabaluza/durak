import '../connection.dart';
import '../protocol.dart';

void handleGame(Connection conn, ClientMessage msg) {
  final room = conn.room;
  if (room == null || !room.isStarted) {
    conn.send(errorMsg('No active game'));
    return;
  }
  switch (msg) {
    case AttackMsg(:final cards):
      room.handleAttack(conn, cards);
    case DefendMsg(:final attackCard, :final defenseCard):
      room.handleDefend(conn, attackCard, defenseCard);
    case TransferMsg(:final cards):
      room.handleTransfer(conn, cards);
    case TransitMsg(:final card):
      room.handleTransit(conn, card);
    case AddAttackMsg(:final cards):
      room.handleAddAttack(conn, cards);
    case PassMsg():
      room.handlePass(conn);
    case TakeMsg():
      room.handleTake(conn);
    default:
  }
}
