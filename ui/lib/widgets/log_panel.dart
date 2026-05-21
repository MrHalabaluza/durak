import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';

String _cardStr(Card c) {
  const suits = {
    Suit.diamonds: '♦', Suit.hearts: '♥', Suit.clubs: '♣', Suit.spades: '♠',
  };
  const ranks = {
    Rank.two: '2', Rank.three: '3', Rank.four: '4', Rank.five: '5',
    Rank.six: '6', Rank.seven: '7', Rank.eight: '8', Rank.nine: '9',
    Rank.ten: '10', Rank.jack: 'В', Rank.queen: 'Д', Rank.king: 'К',
    Rank.ace: 'Т',
  };
  return '${suits[c.suit]}${ranks[c.rank]}';
}

class LogEntry {
  final DateTime timestamp;
  final String actorNickname;
  final String type;
  final List<Card> cards;

  const LogEntry({
    required this.timestamp,
    required this.actorNickname,
    required this.type,
    this.cards = const [],
  });

  String get text {
    final cStr = cards.isEmpty ? '' : ' ${cards.map(_cardStr).join(' ')}';
    final a = actorNickname.isEmpty ? '' : '$actorNickname ';
    return switch (type) {
      'attack'       => '$aатаковал$cStr',
      'add_attack'   => '$aподкинул$cStr',
      'defend'       => '$aотбил$cStr',
      'transfer'     => '$aперевёл$cStr',
      'take'         => '$aвзял карты',
      'beat'         => 'Бито',
      'connected'    => '${actorNickname.isEmpty ? 'Игрок' : actorNickname} подключился',
      'disconnected' => '${actorNickname.isEmpty ? 'Игрок' : actorNickname} отключился',
      _              => '$a$type$cStr',
    };
  }
}

class LogPanel extends StatelessWidget {
  final List<LogEntry> log;
  const LogPanel({required this.log, super.key});

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('История партии',
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          Expanded(
            child: log.isEmpty
                ? const Center(
                    child: Text('Нет действий',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    reverse: true,
                    itemCount: log.length,
                    itemBuilder: (ctx, i) {
                      final e = log[log.length - 1 - i];
                      final t = e.timestamp;
                      final ts =
                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
                      return ListTile(
                        dense: true,
                        leading: Text(ts,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                        title: Text(e.text,
                            style: const TextStyle(fontSize: 13)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = log.isEmpty ? null : log.last;
    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Container(
        width: double.infinity,
        color: Colors.black38,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.history, size: 13, color: Colors.white54),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                last?.text ?? 'Лог действий',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_less, size: 13, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
