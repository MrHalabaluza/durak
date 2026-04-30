import 'dart:math';
import 'room.dart';
import 'db/stats_dao.dart';

class RoomManager {
  static late RoomManager instance;

  static void init(StatsDao stats) {
    instance = RoomManager._(stats);
  }

  final StatsDao _stats;
  final Map<String, Room> _rooms = {};
  final Random _rng = Random();

  RoomManager._(this._stats);

  Room create() {
    String id;
    do {
      id = _generateId();
    } while (_rooms.containsKey(id));
    return _rooms[id] = Room(id, _stats);
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
