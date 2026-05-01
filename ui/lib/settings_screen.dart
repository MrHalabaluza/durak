import 'dart:math';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:durak_logic/durak_logic.dart';
import 'app_settings.dart';

enum _CardRange { six, two }

enum _DeckType { standard, random }

class SettingsScreen extends StatefulWidget {
  final AppSettings initial;
  const SettingsScreen({super.key, required this.initial});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<Card, int> _counts;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _randomCountCtrl;
  late bool _tls;
  late _CardRange _cardRange;
  late _DeckType _deckType;

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

  Rank get _minRank => _cardRange == _CardRange.two ? Rank.two : Rank.six;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial.deckConfig;
    _counts = Map<Card, int>.from(initial.counts);
    _hostCtrl = TextEditingController(text: widget.initial.serverHost);
    _portCtrl = TextEditingController(text: '${widget.initial.serverPort}');
    _tls = widget.initial.serverTls;

    final hasLowRanks =
        _counts.keys.any((c) => c.rank.index < Rank.six.index);
    _cardRange = hasLowRanks ? _CardRange.two : _CardRange.six;

    final std = DeckConfig.preset(_minRank).counts;
    final isStandard = _counts.length == std.length &&
        _counts.entries.every((e) => std[e.key] == e.value);
    _deckType = isStandard ? _DeckType.standard : _DeckType.random;

    _randomCountCtrl =
        TextEditingController(text: '${initial.cardCount}');
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _randomCountCtrl.dispose();
    super.dispose();
  }

  int _count(Suit suit, Rank rank) => _counts[Card(suit, rank)] ?? 0;

  int get _total => _counts.values.fold(0, (a, b) => a + b);

  void _setRange(_CardRange range) {
    setState(() {
      _cardRange = range;
      if (_deckType == _DeckType.standard) {
        _counts = Map.from(DeckConfig.preset(_minRank).counts);
      } else {
        final n = int.tryParse(_randomCountCtrl.text) ?? _total;
        _applyRandom(n > 0 ? n : 36);
      }
    });
  }

  void _setDeckType(_DeckType type) {
    setState(() {
      _deckType = type;
      if (type == _DeckType.standard) {
        _counts = Map.from(DeckConfig.preset(_minRank).counts);
      }
    });
  }

  void _applyRandom(int count) {
    _counts = Map.from(DeckConfig.random(_minRank, count, Random()).counts);
  }

  void _generateRandom() {
    final n = int.tryParse(_randomCountCtrl.text) ?? 0;
    if (n <= 0) return;
    setState(() => _applyRandom(n));
  }

  AppSettings _buildSettings() {
    final port = int.tryParse(_portCtrl.text) ?? 8080;
    return AppSettings(
      deckConfig: DeckConfig.custom(_counts),
      serverHost: _hostCtrl.text.trim().isEmpty
          ? 'localhost'
          : _hostCtrl.text.trim(),
      serverPort: port > 0 && port <= 65535 ? port : 8080,
      serverTls: _tls,
    );
  }

  bool get _canSave => true;

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
      _deckType = _DeckType.random;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        actions: [
          TextButton(
            onPressed:
                _canSave ? () => Navigator.pop(context, _buildSettings()) : null,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Server settings ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Сервер',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Адрес сервера',
                      hintText: 'localhost',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _portCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Порт',
                      hintText: '8080',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 16, 12),
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: const Text('TLS (wss://)'),
              value: _tls,
              onChanged: (v) => setState(() => _tls = v),
            ),
          ),
          const Divider(height: 1),

          // ── Deck config ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Колода',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<_CardRange>(
              segments: const [
                ButtonSegment(value: _CardRange.six, label: Text('6–Т')),
                ButtonSegment(value: _CardRange.two, label: Text('2–Т')),
              ],
              selected: {_cardRange},
              onSelectionChanged: (s) => _setRange(s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<_DeckType>(
              segments: const [
                ButtonSegment(
                    value: _DeckType.standard, label: Text('Стандартная')),
                ButtonSegment(
                    value: _DeckType.random, label: Text('Проёб-колода')),
              ],
              selected: {_deckType},
              onSelectionChanged: (s) => _setDeckType(s.first),
            ),
          ),
          if (_deckType == _DeckType.random)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _randomCountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Карт в колоде',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _generateRandom,
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Сгенерировать'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Карт в колоде: $_total',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
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

  Widget _buildGrid() {
    const cellW = 48.0;
    const cellH = 48.0;
    const headerW = 40.0;

    return Table(
      defaultColumnWidth: const FixedColumnWidth(cellW),
      columnWidths: const {0: FixedColumnWidth(headerW)},
      children: [
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
        for (final suit in _suits)
          TableRow(
            children: [
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
