import 'dart:math';
import 'room.dart';

class RoomManager {
  static final RoomManager instance = RoomManager._();
  RoomManager._();

  final Map<String, Room> _rooms = {};
  final Random _rng = Random();

  Room create() {
    String id;
    do {
      id = _generateId();
    } while (_rooms.containsKey(id));
    return _rooms[id] = Room(id);
  }

  Room? find(String id) => _rooms[id];

  void removeIfEmpty(String id) {
    if (_rooms[id]?.isEmpty ?? false) _rooms.remove(id);
  }

  String _generateId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
  }
}
