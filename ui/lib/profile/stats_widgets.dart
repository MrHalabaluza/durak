import 'package:flutter/material.dart';

class StatsCardGrid extends StatelessWidget {
  final int games;
  final int wins;
  final int losses;
  final int draws;
  final double? winrate;

  const StatsCardGrid({
    super.key,
    required this.games,
    required this.wins,
    required this.losses,
    required this.draws,
    this.winrate,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: [
        _StatTile(label: 'Партий', value: '$games'),
        _StatTile(label: 'Побед', value: '$wins', color: Colors.greenAccent),
        _StatTile(label: 'Поражений', value: '$losses', color: Colors.redAccent),
        _StatTile(label: 'Ничьих', value: '$draws', color: Colors.grey),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatTile({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class WinrateBadge extends StatelessWidget {
  final double? winrate;
  const WinrateBadge({super.key, this.winrate});

  @override
  Widget build(BuildContext context) {
    final text = winrate == null ? '—' : '${(winrate! * 100).toStringAsFixed(1)}%';
    return Text(text,
        style: const TextStyle(fontSize: 14, color: Colors.grey));
  }
}

Map<String, dynamic> statsFromJson(Map<String, dynamic> json) => json;

int statsGames(Map<String, dynamic> s) => s['games_played'] as int? ?? 0;
int statsWins(Map<String, dynamic> s) => s['wins'] as int? ?? 0;
int statsLosses(Map<String, dynamic> s) => s['losses'] as int? ?? 0;
int statsDraws(Map<String, dynamic> s) => s['draws'] as int? ?? 0;
double? statsWinrate(Map<String, dynamic> s) => (s['winrate'] as num?)?.toDouble();
