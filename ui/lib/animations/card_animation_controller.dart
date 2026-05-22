import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';
import 'package:durak_protocol/durak_protocol.dart';
import 'flying_card.dart';

class CardAnimationController {
  final void Function(void Function()) _setState;
  final bool Function() _isMounted;

  // GlobalKeys — owned here, passed to the widget tree via build
  final deckKey    = GlobalKey();
  final discardKey = GlobalKey();
  final tableKey   = GlobalKey();
  final handKey    = GlobalKey();
  final overlayKey = GlobalKey();
  final seatKeys      = List.generate(6, (_) => GlobalKey());
  final tableCellKeys = List.generate(9, (_) => GlobalKey());
  final Map<int, GlobalKey> handSlotKeys = {};

  // Mutable animation state — read by the screen's build method
  final List<FlyingCard> flying = [];
  bool animating = false;
  final Set<int> hiddenCardIds = {};
  int? lastDraggedCardId;

  int _nextFlyId = 0;
  int _animGeneration = 0;

  CardAnimationController({
    required void Function(void Function()) setState,
    required bool Function() isMounted,
  })  : _setState = setState,
        _isMounted = isMounted;

  GlobalKey handSlotKey(int cardId) =>
      handSlotKeys.putIfAbsent(cardId, () => GlobalKey());

  // ── Position helpers ───────────────────────────────────────────────────────

  Offset anchorOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    final global = box.localToGlobal(Offset.zero);
    final overlayBox =
        overlayKey.currentContext?.findRenderObject() as RenderBox?;
    return overlayBox != null ? overlayBox.globalToLocal(global) : global;
  }

  // ── Core animation primitives ──────────────────────────────────────────────

  void fly({
    required Card? card,
    required bool faceUp,
    required Offset from,
    required Offset to,
    Duration duration = const Duration(milliseconds: 200),
    Duration startDelay = Duration.zero,
  }) {
    final gen = _animGeneration;
    Future.delayed(startDelay, () {
      if (!_isMounted() || gen != _animGeneration) return;
      final id = _nextFlyId++;
      final cid = card?.id;
      _setState(() {
        flying.add(FlyingCard(
          id: id,
          card: card,
          faceUp: faceUp,
          from: from,
          to: to,
          duration: duration,
        ));
        if (cid != null) hiddenCardIds.add(cid);
      });
      // Wait for the tween's first frame before starting the removal timer —
      // otherwise Future.delayed(duration) fires ~16 ms before the first
      // animation frame and the card disappears before reaching `to`.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;
        Future.delayed(duration, () {
          if (!_isMounted() || gen != _animGeneration) return;
          _setState(() {
            flying.removeWhere((f) => f.id == id);
            if (cid != null) hiddenCardIds.remove(cid);
            if (flying.isEmpty) animating = false;
          });
        });
      });
    });
  }

  void cancelAnimations() {
    _animGeneration++;
    _setState(() {
      flying.clear();
      hiddenCardIds.clear();
      animating = false;
    });
  }

  // ── Diff helpers ───────────────────────────────────────────────────────────

  bool willAnimate(GameStateView prev, GameStateView next) {
    if (prev.table.isNotEmpty && next.table.isEmpty) return true;
    if (prev.defenderIndex != next.defenderIndex && prev.table.isNotEmpty) {
      return true;
    }
    if (next.deckSize < prev.deckSize) return true;
    final pa = prev.table.map((e) => e.attack).toSet();
    final na = next.table.map((e) => e.attack).toSet();
    if (na.difference(pa).isNotEmpty) return true;
    for (final ne in next.table) {
      if (ne.defense == null) continue;
      final pe = prev.table.where((e) => e.attack == ne.attack).firstOrNull;
      if (pe != null && pe.defense == null) return true;
    }
    return false;
  }

  // ── Sequence orchestration ─────────────────────────────────────────────────

  void animateChanges(
    GameStateView prev,
    GameStateView next,
    String myPlayerId, {
    Duration step = const Duration(milliseconds: 150),
    Map<int, Offset> prevHandPositions = const {},
    Map<int, Offset> prevTableCellPositions = const {},
  }) {
    final draggedId = lastDraggedCardId;
    lastDraggedCardId = null;
    int seq = 0;

    final myIndex = next.players.indexWhere((p) => p.id == myPlayerId);
    final deckPos    = anchorOf(deckKey);
    final discardPos = anchorOf(discardKey);
    final tablePos   = anchorOf(tableKey);
    final handPos    = anchorOf(handKey);

    Offset seatPos(int pi) => anchorOf(seatKeys[pi]);

    Offset handSlotPos(int cardId) {
      final key = handSlotKeys[cardId];
      if (key?.currentContext != null) {
        final p = anchorOf(key!);
        if (p != Offset.zero) return p;
      }
      return handPos;
    }

    Offset srcFromPlayer(Card card, int pi) {
      if (pi == myIndex) {
        final p = prevHandPositions[card.id];
        if (p != null) return p;
        return handPos;
      }
      return seatPos(pi);
    }

    Offset prevTableSrc(int prevIdx, {Offset shift = Offset.zero}) =>
        (prevTableCellPositions[prevIdx] ?? tablePos) + shift;

    Offset tableDest(Card card, {Offset shift = Offset.zero}) {
      final i = next.table.indexWhere(
          (e) => e.attack == card || e.defense == card);
      if (i >= 0 && i < tableCellKeys.length) {
        final p = anchorOf(tableCellKeys[i]);
        if (p != Offset.zero) return p + shift;
      }
      return tablePos + shift;
    }

    final prevAttacks = prev.table.map((e) => e.attack).toSet();
    final nextAttacks = next.table.map((e) => e.attack).toSet();

    // BEAT: table → discard
    if (prev.table.isNotEmpty &&
        next.table.isEmpty &&
        next.discardSize > prev.discardSize) {
      for (int i = 0; i < prev.table.length; i++) {
        final e = prev.table[i];
        fly(card: e.attack, faceUp: true,
            from: prevTableSrc(i), to: discardPos,
            startDelay: step * seq++);
        if (e.defense != null) {
          fly(card: e.defense, faceUp: true,
              from: prevTableSrc(i, shift: const Offset(16, 16)),
              to: discardPos,
              startDelay: step * seq++);
        }
      }
    }

    // TAKE: table → defender's hand
    if (prev.table.isNotEmpty &&
        next.table.isEmpty &&
        next.discardSize == prev.discardSize) {
      final isMine = prev.defenderIndex == myIndex;
      final dest = isMine ? handPos : seatPos(prev.defenderIndex);
      for (int i = 0; i < prev.table.length; i++) {
        final e = prev.table[i];
        fly(card: e.attack, faceUp: isMine,
            from: prevTableSrc(i), to: dest,
            startDelay: step * seq++);
        if (e.defense != null) {
          fly(card: e.defense, faceUp: isMine,
              from: prevTableSrc(i, shift: const Offset(16, 16)),
              to: dest,
              startDelay: step * seq++);
        }
      }
    }

    // TRANSFER / TRANSIT: defender changed mid-turn
    if (prev.defenderIndex != next.defenderIndex && prev.table.isNotEmpty) {
      final newCards = nextAttacks.difference(prevAttacks);
      if (newCards.isNotEmpty) {
        // TRANSFER: new card(s) placed on table
        for (final card in newCards) {
          if (card.id == draggedId) continue;
          fly(card: card, faceUp: true,
              from: srcFromPlayer(card, prev.defenderIndex),
              to: tableDest(card),
              startDelay: step * seq++);
        }
      } else {
        // TRANSIT: trump of required rank shown and stays in hand;
        // visually it flies from old defender toward new defender.
        final fromIdx = prev.defenderIndex;
        final toIdx = next.defenderIndex;
        final from = fromIdx == myIndex ? handPos : seatPos(fromIdx);
        final to = toIdx == myIndex ? handPos : seatPos(toIdx);

        Card? showCard;
        bool faceUp = false;
        if (fromIdx == myIndex) {
          final uncoveredRanks = next.table
              .where((e) => e.defense == null)
              .map((e) => e.attack.rank)
              .toSet();
          showCard = next.hand
              .where((c) =>
                  c.suit == next.trump && uncoveredRanks.contains(c.rank))
              .firstOrNull;
          faceUp = showCard != null;
        }

        fly(card: showCard, faceUp: faceUp,
            from: from, to: to,
            duration: const Duration(milliseconds: 300),
            startDelay: step * seq++);
      }
    }

    // ATTACK / ADD_ATTACK (only when no transfer)
    if (prev.defenderIndex == next.defenderIndex) {
      for (final card in nextAttacks.difference(prevAttacks)) {
        if (card.id == draggedId) continue;
        final srcIndex =
            prev.table.isEmpty ? next.attackerIndex : prev.currentAdderIndex;
        fly(card: card, faceUp: true,
            from: srcFromPlayer(card, srcIndex),
            to: tableDest(card),
            startDelay: step * seq++);
      }
    }

    // DEFEND: defense card from hand to table
    for (final ne in next.table) {
      if (ne.defense == null) continue;
      if (ne.defense!.id == draggedId) continue;
      final pe = prev.table.where((e) => e.attack == ne.attack).firstOrNull;
      if (pe != null && pe.defense == null) {
        fly(card: ne.defense, faceUp: true,
            from: srcFromPlayer(ne.defense!, prev.defenderIndex),
            to: tableDest(ne.defense!, shift: const Offset(16, 16)),
            startDelay: step * seq++);
      }
    }

    // DEAL / REFILL: deck → hands
    if (next.deckSize < prev.deckSize) {
      final isTake = prev.table.isNotEmpty &&
          next.table.isEmpty &&
          next.discardSize == prev.discardSize;
      final takenIds = isTake
          ? prev.table
              .expand<Card>((e) => [e.attack, if (e.defense != null) e.defense!])
              .map((c) => c.id)
              .toSet()
          : const <int>{};

      final prevHandIds = prev.hand.map((c) => c.id).toSet();
      for (final card in next.hand) {
        if (!prevHandIds.contains(card.id) && !takenIds.contains(card.id)) {
          fly(card: card, faceUp: true,
              from: deckPos, to: handSlotPos(card.id),
              startDelay: step * seq++);
        }
      }
      for (int i = 0; i < next.players.length; i++) {
        if (i == myIndex) continue;
        final rawDelta = next.players[i].handSize - prev.players[i].handSize;
        final tableOffset =
            isTake && i == prev.defenderIndex ? takenIds.length : 0;
        final delta = rawDelta - tableOffset;
        for (int k = 0; k < delta; k++) {
          fly(card: null, faceUp: false, from: deckPos, to: seatPos(i),
              startDelay: step * seq++);
        }
      }
    }

      if (seq == 0) _setState(() => animating = false);
  }

  // ── Convenience: schedule animateChanges via postFrameCallback ─────────────

  void scheduleAnimateChanges(
    GameStateView prev,
    GameStateView next,
    String myPlayerId, {
    Duration step = const Duration(milliseconds: 150),
    Map<int, Offset> prevHandPositions = const {},
    Map<int, Offset> prevTableCellPositions = const {},
  }) {
    animating = true;
    final gen = _animGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) return;
      if (gen == _animGeneration) {
        animateChanges(prev, next, myPlayerId,
            step: step,
            prevHandPositions: prevHandPositions,
            prevTableCellPositions: prevTableCellPositions);
      } else if (animating) {
        _setState(() => animating = false);
      }
    });
  }
}
