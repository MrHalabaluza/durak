import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:durak_logic/durak_logic.dart';
import 'protocol.dart';
import 'room.dart';

typedef MessageHandler = void Function(Connection conn, ClientMessage msg);
typedef CloseHandler = void Function(Connection conn);

class Connection {
  final WebSocket _socket;
  String? playerId;
  String? username;
  bool authed = false;
  Room? room;
  String nickname = '';
  Timer? _authTimer;
  /// The user's saved deck config, loaded from DB on auth and updated by save_deck.
  DeckConfig savedDeckConfig = DeckConfig();

  Connection({
    required WebSocket socket,
    required MessageHandler onMessage,
    required CloseHandler onClose,
  }) : _socket = socket {
    _authTimer = Timer(const Duration(seconds: 5), () {
      if (!authed) {
        send(errorMsg('auth_timeout'));
        close();
      }
    });
    socket.listen(
      (data) {
        if (data is! String) return;
        try {
          onMessage(this, ClientMessage.parse(data));
        } catch (e) {
          send(errorMsg('Bad message: $e'));
        }
      },
      onDone: () {
        _authTimer?.cancel();
        onClose(this);
      },
      onError: (_) {
        _authTimer?.cancel();
        onClose(this);
      },
      cancelOnError: false,
    );
  }

  void markAuthed(int userId, String uname) {
    _authTimer?.cancel();
    authed = true;
    playerId = userId.toString();
    username = uname;
    nickname = uname;
  }

  void send(Map<String, dynamic> message) {
    try {
      _socket.add(jsonEncode(message));
    } catch (_) {}
  }

  void close() => _socket.close();
}
