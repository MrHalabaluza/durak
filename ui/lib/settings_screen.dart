import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:durak_logic/durak_logic.dart';

class SettingsScreen extends StatefulWidget {
  final DeckConfig initial;
  const SettingsScreen({super.key, required this.initial});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<Card, int> _counts;

  static const _ranks = Rank.values;
  static const _suits = Suit.values;

  static const _rankLabel = [
    '2', '3', '4', '5', '6', '7', '8', '9', '10', 'В', 'Д', 'К', 'Т',
  ];

  static const _suitLabel = ['♠', '♥', '♦', '♣'];
  static const _suitColor = [
    Colors.lightBlueAccent,
    Colors.redAccent,
    Colors.redAccent,
    Colors.lightBlueAccent,
  ];

  @override
  void initState() {
    super.initState();
    _counts = Map<Card, int>.from(widget.initial.counts);
  }

  int _count(Suit suit, Rank rank) => _counts[Card(suit, rank)] ?? 0;

  int get _total => _counts.values.fold(0, (a, b) => a + b);

  void _setPreset(Rank minRank) {
    setState(() {
      _counts = Map<Card, int>.from(DeckConfig.preset(minRank).counts);
    });
  }

  void _clear() => setState(() => _counts.clear());

  Future<void> _editCell(Suit suit, Rank rank) async {
    final card = Card(suit, rank);
    final current = _counts[card] ?? 0;
    final ctrl = TextEditingController(text: '$current');

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${_rankLabel[rank.index]} ${_suitLabel[suit.index]}',
          style: TextStyle(color: _suitColor[suit.index]),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Количество копий'),
          onSubmitted: (_) {
            final v = int.tryParse(ctrl.text) ?? 0;
            Navigator.pop(ctx, v);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text) ?? 0;
              Navigator.pop(ctx, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result == null) return;
    setState(() {
      if (result <= 0) {
        _counts.remove(card);
      } else {
        _counts[card] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки колоды'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              DeckConfig.custom(_counts),
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Presets + total ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Пресеты:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                _presetChip('36 карт (6–Т)', () => _setPreset(Rank.six)),
                _presetChip('28 карт (8–Т)', () => _setPreset(Rank.eight)),
                _presetChip('52 карты (2–Т)', () => _setPreset(Rank.two)),
                _presetChip('Очистить', _clear,
                    color: Colors.red.shade700),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Карт в колоде: $_total',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
          const Divider(height: 1),

          // ── Grid ─────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: _buildGrid(),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Нажмите на ячейку, чтобы изменить количество копий',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap, {Color? color}) {
    return ActionChip(
      label: Text(label),
      backgroundColor: color,
      onPressed: onTap,
    );
  }

  Widget _buildGrid() {
    const cellW = 48.0;
    const cellH = 48.0;
    const headerW = 40.0;

    return Table(
      defaultColumnWidth: const FixedColumnWidth(cellW),
      columnWidths: const {0: FixedColumnWidth(headerW)},
      children: [
        // ── Rank header row ──────────────────────────────────────────────
        TableRow(
          children: [
            const SizedBox(height: cellH),
            for (final label in _rankLabel)
              SizedBox(
                height: cellH,
                child: Center(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
          ],
        ),
        // ── One row per suit ─────────────────────────────────────────────
        for (final suit in _suits)
          TableRow(
            children: [
              // Suit label
              SizedBox(
                height: cellH,
                child: Center(
                  child: Text(
                    _suitLabel[suit.index],
                    style: TextStyle(
                      fontSize: 20,
                      color: _suitColor[suit.index],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Count cells
              for (final rank in _ranks)
                _CountCell(
                  count: _count(suit, rank),
                  suitColor: _suitColor[suit.index],
                  size: cellH,
                  onTap: () => _editCell(suit, rank),
                ),
            ],
          ),
      ],
    );
  }
}

class _CountCell extends StatelessWidget {
  final int count;
  final Color suitColor;
  final double size;
  final VoidCallback onTap;

  const _CountCell({
    required this.count,
    required this.suitColor,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasCard = count > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: hasCard
              ? suitColor.withAlpha(40)
              : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasCard ? suitColor.withAlpha(120) : Colors.grey.shade800,
          ),
        ),
        child: Center(
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: hasCard ? suitColor : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}
