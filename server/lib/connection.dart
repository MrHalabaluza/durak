import 'dart:io';
import 'dart:convert';
import 'protocol.dart';
import 'room.dart';

typedef MessageHandler = void Function(Connection conn, ClientMessage msg);
typedef CloseHandler = void Function(Connection conn);

class Connection {
  final String playerId;
  final WebSocket _socket;
  Room? room;

  Connection({
    required this.playerId,
    required WebSocket socket,
    required MessageHandler onMessage,
    required CloseHandler onClose,
  }) : _socket = socket {
    socket.listen(
      (data) {
        if (data is! String) return;
        try {
          onMessage(this, ClientMessage.parse(data));
        } catch (e) {
          send(errorMsg('Bad message: $e'));
        }
      },
      onDone: () => onClose(this),
      onError: (_) => onClose(this),
      cancelOnError: false,
    );
  }

  void send(Map<String, dynamic> message) {
    try {
      _socket.add(jsonEncode(message));
    } catch (_) {}
  }

  void close() => _socket.close();
}
