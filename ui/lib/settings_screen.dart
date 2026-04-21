import 'package:flutter/material.dart';
import 'package:durak_logic/durak_logic.dart';

class SettingsScreen extends StatefulWidget {
  final DeckConfig initial;
  const SettingsScreen({super.key, required this.initial});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Rank _minRank;
  late Set<Suit> _suits;

  static const _rankLabel = {
    Rank.two: '2', Rank.three: '3', Rank.four: '4', Rank.five: '5',
    Rank.six: '6', Rank.seven: '7', Rank.eight: '8', Rank.nine: '9',
    Rank.ten: '10', Rank.jack: 'В', Rank.queen: 'Д', Rank.king: 'К',
  };

  static const _suitLabel = {
    Suit.spades: '♠ Пики',
    Suit.hearts: '♥ Черви',
    Suit.diamonds: '♦ Бубны',
    Suit.clubs: '♣ Крести',
  };

  @override
  void initState() {
    super.initState();
    _minRank = widget.initial.minRank;
    _suits = Set.from(widget.initial.suits);
  }

  DeckConfig get _config => DeckConfig(minRank: _minRank, suits: Set.unmodifiable(_suits));

  bool get _valid => _suits.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cardCount = _config.cardCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки колоды'),
        actions: [
          TextButton(
            onPressed: _valid ? () => Navigator.pop(context, _config) : null,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Deck size indicator ───────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.style, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Карт в колоде: $cardCount',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Min rank ─────────────────────────────────────────────────────
          const Text('Минимальный ранг',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _rankLabel.entries.map((e) {
              final selected = e.key == _minRank;
              return ChoiceChip(
                label: Text(e.value),
                selected: selected,
                onSelected: (_) => setState(() => _minRank = e.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // ── Suits ─────────────────────────────────────────────────────────
          const Text('Масти',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suitLabel.entries.map((e) {
              final selected = _suits.contains(e.key);
              return FilterChip(
                label: Text(e.value),
                selected: selected,
                onSelected: (on) {
                  setState(() {
                    if (on) {
                      _suits.add(e.key);
                    } else if (_suits.length > 1) {
                      _suits.remove(e.key);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
