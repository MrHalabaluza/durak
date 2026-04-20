import 'card.dart';

class TableEntry {
  final Card attack;
  Card? defense;

  TableEntry(this.attack);

  bool get isDefended => defense != null;
  bool get isUndefended => defense == null;
}

class TableState {
  final List<TableEntry> entries = [];

  int get size => entries.length;
  bool get isEmpty => entries.isEmpty;
  bool get isAllDefended => entries.every((e) => e.isDefended);
  bool get hasUndefended => entries.any((e) => e.isUndefended);

  List<Card> get allCards => [
        for (final e in entries) ...[
          e.attack,
          if (e.defense != null) e.defense!,
        ],
      ];

  Set<Rank> get presentRanks => {
        for (final e in entries) ...[
          e.attack.rank,
          if (e.defense != null) e.defense!.rank,
        ],
      };

  void addAttack(Card card) => entries.add(TableEntry(card));

  /// Assigns [defenseCard] to the undefended entry matching [attackCard].
  /// Returns false if no such entry exists.
  bool defend(Card attackCard, Card defenseCard) {
    final entry = entries
        .where((e) => e.attack == attackCard && e.isUndefended)
        .firstOrNull;
    if (entry == null) return false;
    entry.defense = defenseCard;
    return true;
  }

  List<Card> takeAll() {
    final all = allCards;
    entries.clear();
    return all;
  }
}
