import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:durak_logic/durak_logic.dart';
import 'card_widget.dart';
import 'sort_hand.dart';

// ── Card string helper ────────────────────────────────────────────────────────

String _cardStr(Card c) {
  const suits = {
    Suit.diamonds: '♦', Suit.hearts: '♥', Suit.clubs: '♣', Suit.spades: '♠',
  };
  const ranks = {
    Rank.two: '2', Rank.three: '3', Rank.four: '4', Rank.five: '5',
    Rank.six: '6', Rank.seven: '7', Rank.eight: '8', Rank.nine: '9',
    Rank.ten: '10', Rank.jack: 'В', Rank.queen: 'Д', Rank.king: 'К', Rank.ace: 'Т',
  };
  return '${suits[c.suit]}${ranks[c.rank]}';
}

// ── Log entry ─────────────────────────────────────────────────────────────────

class _LogEntry {
  final DateTime timestamp;
  final String actorNickname;
  final String type; // 'attack','add_attack','defend','transfer','take','beat'
  final List<Card> cards;

  const _LogEntry({
    required this.timestamp,
    required this.actorNickname,
    required this.type,
    this.cards = const [],
  });

  String get text {
    final cStr = cards.isEmpty ? '' : ' ${cards.map(_cardStr).join(' ')}';
    final a = actorNickname.isEmpty ? '' : '$actorNickname ';
    return switch (type) {
      'attack'     => '$aатаковал$cStr',
      'add_attack' => '$aподкинул$cStr',
      'defend'     => '$aотбил$cStr',
      'transfer'   => '$aперевёл$cStr',
      'take'       => '$aвзял карты',
      'beat'       => 'Бито',
      _            => '$a$type$cStr',
    };
  }
}

// ── Deserialization ───────────────────────────────────────────────────────────

Card _parseCard(Map<String, dynamic> m) => Card(
      Suit.values.byName(m['suit'] as String),
      Rank.values.byName(m['rank'] as String),
    );

Map<String, String> _serCard(Card c) =>
    {'suit': c.suit.name, 'rank': c.rank.name};

// ── Remote state model ────────────────────────────────────────────────────────

class _RemotePlayer {
  final String id;
  final String nickname;
  final int handSize;
  final bool hasLeft;
  const _RemotePlayer(this.id, this.nickname, this.handSize, this.hasLeft);
}

class _RemoteEntry {
  final Card attack;
  final Card? defense;
  const _RemoteEntry(this.attack, this.defense);
}

class _RemoteGS {
  final GamePhase phase;
  final Suit trump;
  final Card? trumpCard;
  final int deckSize;
  final int discardSize;
  final int attackerIndex;
  final int defenderIndex;
  final int currentAdderIndex;
  final List<String> addingPlayerIds;
  final List<Card> hand;
  final List<_RemotePlayer> players;
  final List<_RemoteEntry> table;
  final String? loserId;

  const _RemoteGS({
    required this.phase,
    required this.trump,
    this.trumpCard,
    required this.deckSize,
    required this.discardSize,
    required this.attackerIndex,
    required this.defenderIndex,
    required this.currentAdderIndex,
    required this.addingPlayerIds,
    required this.hand,
    required this.players,
    required this.table,
    this.loserId,
  });

  factory _RemoteGS.fromJson(Map<String, dynamic> m) => _RemoteGS(
        phase: GamePhase.values.byName(m['phase'] as String),
        trump: Suit.values.byName(m['trump'] as String),
        trumpCard: m['trumpCard'] != null
            ? _parseCard(m['trumpCard'] as Map<String, dynamic>)
            : null,
        deckSize: m['deckSize'] as int,
        discardSize: m['discardSize'] as int,
        attackerIndex: m['attackerIndex'] as int,
        defenderIndex: m['defenderIndex'] as int,
        currentAdderIndex: m['currentAdderIndex'] as int,
        addingPlayerIds: List<String>.from(m['addingPlayerIds'] as List),
        hand: (m['hand'] as List)
            .map((e) => _parseCard(e as Map<String, dynamic>))
            .toList(),
        players: (m['players'] as List).map((e) {
          final p = e as Map<String, dynamic>;
          return _RemotePlayer(
            p['id'] as String,
            p['nickname'] as String? ?? '',
            p['handSize'] as int,
            p['hasLeft'] as bool,
          );
        }).toList(),
        table: (m['table'] as List).map((e) {
          final t = e as Map<String, dynamic>;
          return _RemoteEntry(
            _parseCard(t['attack'] as Map<String, dynamic>),
            t['defense'] != null
                ? _parseCard(t['defense'] as Map<String, dynamic>)
                : null,
          );
        }).toList(),
        loserId: m['loserId'] as String?,
      );
}

// ── Flying card ───────────────────────────────────────────────────────────────

class _FlyingCard {
  final int id;
  final Card? card;
  final bool faceUp;
  final Offset from;
  final Offset? via;
  final Offset to;
  final Duration duration;
  const _FlyingCard({
    required this.id,
    required this.card,
    required this.faceUp,
    required this.from,
    this.via,
    required this.to,
    this.duration = const Duration(milliseconds: 200),
  });
}

// ── Widget ────────────────────────────────────────────────────────────────────

class OnlineGameScreen extends StatefulWidget {
  /// Used only for sending messages to the server.
  final WebSocketChannel socket;

  /// Broadcast stream of parsed server messages — created in LobbyScreen.
  final Stream<Map<String, dynamic>> messageStream;

  final String myPlayerId;

  /// First game_state received in the lobby — displayed immediately.
  final Map<String, dynamic>? initialState;

  const OnlineGameScreen({
    super.key,
    required this.socket,
    required this.messageStream,
    required this.myPlayerId,
    this.initialState,
  });

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen>
    with WidgetsBindingObserver {
  StreamSubscription? _sub;
  _RemoteGS? _gs;
  String? _error;

  final Set<int> _selectedCardIds = {};
  Card? _selectedAttackCard;

  final List<_LogEntry> _log = [];

  // GlobalKey-якоря для вычисления позиций анимации
  final _deckKey    = GlobalKey();
  final _discardKey = GlobalKey();
  final _tableKey   = GlobalKey();
  final _handKey    = GlobalKey();
  final _overlayKey = GlobalKey();
  // один ключ на слот игрока (по playerIndex, 0..5)
  final _seatKeys      = List.generate(6, (_) => GlobalKey());
  // ключи на каждую из 9 ячеек грида стола (по индексу 0..8)
  final _tableCellKeys = List.generate(9, (_) => GlobalKey());
  // ключи на слоты руки (по sortedIndex — всегда уникален, безопасен при дублях карт)
  final Map<int, GlobalKey> _handSlotKeys = {};
  GlobalKey _handSlotKey(int index) =>
      _handSlotKeys.putIfAbsent(index, () => GlobalKey());

  // Overlay-анимация
  final _flying     = <_FlyingCard>[];
  int  _nextFlyId   = 0;
  bool _animating   = false;
  int  _animGeneration = 0;
  // displayId карты, перенесённой drag-and-drop — её анимация пропускается,
  // так как пользователь уже видел перемещение во время drag.
  int? _lastDraggedCardId;
  // displayId карт, которые сейчас в полёте — статичный слой их скрывает,
  // чтобы карта не была одновременно видна и в overlay, и в hand/table.
  final Set<int> _hiddenCardIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (widget.initialState != null) {
      final next = _RemoteGS.fromJson(widget.initialState!);
      _gs = next;
      if (next.players.any((p) => p.handSize > 0)) {
        final prev = _preDealState(next);
        _animating = true;
        final initGen = _animGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && initGen == _animGeneration) {
            _animateChanges(prev, next,
                step: const Duration(milliseconds: 40));
          }
        });
      }
    }
    _sub = widget.messageStream
        .listen(_onData, onDone: _onDone, onError: _onError);
  }

  /// Синтезирует пре-раздачное состояние: пустые руки, полная колода,
  /// пустой стол и бита. Нужно как `prev` для анимации первой раздачи.
  static _RemoteGS _preDealState(_RemoteGS next) {
    final inHands = next.players.fold<int>(0, (s, p) => s + p.handSize);
    final onTable = next.table
        .fold<int>(0, (s, e) => s + 1 + (e.defense != null ? 1 : 0));
    return _RemoteGS(
      phase: next.phase,
      trump: next.trump,
      trumpCard: next.trumpCard,
      deckSize: next.deckSize + inHands + next.discardSize + onTable,
      discardSize: 0,
      attackerIndex: next.attackerIndex,
      defenderIndex: next.defenderIndex,
      currentAdderIndex: next.currentAdderIndex,
      addingPlayerIds: const [],
      hand: const [],
      players: next.players
          .map((p) => _RemotePlayer(p.id, p.nickname, 0, p.hasLeft))
          .toList(),
      table: const [],
      loserId: null,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _sub?.cancel();
    widget.socket.sink.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (mounted) _cancelAnimations();
    } else if (state == AppLifecycleState.resumed && mounted) {
      // Bump generation to invalidate any postFrameCallbacks queued while inactive.
      _cancelAnimations();
    }
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  void _onData(Map<String, dynamic> map) {
    final type = map['type'] as String;
    if (type == 'game_state') {
      final prev = _gs;
      final next = _RemoteGS.fromJson(map);
      if (prev != null) _diffAndLog(prev, next);

      // Снимок позиций уходящих карт ДО setState — после применения next
      // соответствующие слоты руки/ячейки могут исчезнуть из layout
      // (карта сыграна, стол очищен и т.п.), и якорь будет недоступен.
      final prevHandPositions = <int, Offset>{};
      final prevTableCellPositions = <int, Offset>{};
      if (prev != null) {
        final prevSorted = sortHand(prev.hand, prev.trump);
        for (int i = 0; i < prevSorted.length; i++) {
          final id = cardDisplayId(prevSorted[i]);
          final key = _handSlotKeys[i];
          if (key?.currentContext != null) {
            prevHandPositions[id] = _anchorOf(key!);
          }
        }
        for (int i = 0;
            i < prev.table.length && i < _tableCellKeys.length;
            i++) {
          prevTableCellPositions[i] = _anchorOf(_tableCellKeys[i]);
        }
      }

      setState(() {
        _gs = next;
        _selectedCardIds.clear();
        _selectedAttackCard = null;
        _error = null;
      });
      if (prev != null && _willAnimate(prev, next)) {
        // Флаг устанавливается до postFrameCallback, чтобы build уже видел его
        _animating = true;
        final animGen = _animGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && animGen == _animGeneration) {
            _animateChanges(prev, next,
                prevHandPositions: prevHandPositions,
                prevTableCellPositions: prevTableCellPositions);
          } else if (mounted && _animating) {
            setState(() => _animating = false);
          }
        });
      }
    } else if (type == 'error') {
      setState(() => _error = map['message'] as String);
    }
  }

  void _diffAndLog(_RemoteGS prev, _RemoteGS next) {
    if (prev.phase == GamePhase.finished) {
      _log.clear();
      return;
    }

    String nick(_RemotePlayer p) => p.nickname.isEmpty ? 'Игрок' : p.nickname;

    final prevAttacks = prev.table.map((e) => e.attack).toSet();
    final nextAttacks = next.table.map((e) => e.attack).toSet();

    // Table cleared
    if (prev.table.isNotEmpty && next.table.isEmpty) {
      if (next.discardSize > prev.discardSize) {
        _log.add(_LogEntry(timestamp: DateTime.now(), actorNickname: '', type: 'beat'));
      } else {
        _log.add(_LogEntry(
          timestamp: DateTime.now(),
          actorNickname: nick(prev.players[prev.defenderIndex]),
          type: 'take',
        ));
      }
      return;
    }

    // Defender changed → transfer/transit
    if (prev.defenderIndex != next.defenderIndex && prev.table.isNotEmpty) {
      final newCards = nextAttacks.difference(prevAttacks).toList();
      _log.add(_LogEntry(
        timestamp: DateTime.now(),
        actorNickname: nick(prev.players[prev.defenderIndex]),
        type: 'transfer',
        cards: newCards,
      ));
      return;
    }

    // New attack cards appeared
    final newAttacks = nextAttacks.difference(prevAttacks);
    if (newAttacks.isNotEmpty) {
      if (prev.table.isEmpty) {
        _log.add(_LogEntry(
          timestamp: DateTime.now(),
          actorNickname: nick(next.players[next.attackerIndex]),
          type: 'attack',
          cards: newAttacks.toList(),
        ));
      } else {
        _log.add(_LogEntry(
          timestamp: DateTime.now(),
          actorNickname: nick(prev.players[prev.currentAdderIndex]),
          type: 'add_attack',
          cards: newAttacks.toList(),
        ));
      }
    }

    // New defense cards appeared
    for (final nextEntry in next.table) {
      if (nextEntry.defense == null) continue;
      final prevEntry =
          prev.table.where((e) => e.attack == nextEntry.attack).firstOrNull;
      if (prevEntry != null && prevEntry.defense == null) {
        _log.add(_LogEntry(
          timestamp: DateTime.now(),
          actorNickname: nick(prev.players[prev.defenderIndex]),
          type: 'defend',
          cards: [nextEntry.defense!],
        ));
      }
    }
  }

  void _onDone() {
    if (mounted) setState(() => _error = 'Соединение разорвано');
  }

  void _onError(Object e) {
    if (mounted) setState(() => _error = e.toString());
  }

  void _send(Map<String, dynamic> msg) =>
      widget.socket.sink.add(jsonEncode(msg));

  // ── Animation ─────────────────────────────────────────────────────────────

  /// Позиция виджета [key] в системе координат overlay-стека.
  Offset _anchorOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    final global = box.localToGlobal(Offset.zero);
    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    return overlayBox != null ? overlayBox.globalToLocal(global) : global;
  }

  /// Запускает анимацию одной «летящей» карты из [from] в [to].
  void _fly({
    required Card? card,
    required bool faceUp,
    required Offset from,
    Offset? via,
    required Offset to,
    Duration duration = const Duration(milliseconds: 200),
    Duration startDelay = Duration.zero,
  }) {
    final gen = _animGeneration;
    Future.delayed(startDelay, () {
      if (!mounted || gen != _animGeneration) return;
      final id = _nextFlyId++;
      final cid = card != null ? cardDisplayId(card) : null;
      setState(() {
        _flying.add(_FlyingCard(
          id: id,
          card: card,
          faceUp: faceUp,
          from: from,
          via: via,
          to: to,
          duration: duration,
        ));
        if (cid != null) _hiddenCardIds.add(cid);
      });
      // Запускаем таймер удаления только ПОСЛЕ первого кадра твина —
      // иначе Future.delayed(duration) начался бы примерно на ~16 мс
      // раньше первого кадра анимации и карта снималась бы до того,
      // как доедет до to.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(duration, () {
          if (!mounted || gen != _animGeneration) return;
          setState(() {
            _flying.removeWhere((f) => f.id == id);
            if (cid != null) _hiddenCardIds.remove(cid);
            if (_flying.isEmpty) _animating = false;
          });
        });
      });
    });
  }

  void _cancelAnimations() {
    _animGeneration++;
    setState(() {
      _flying.clear();
      _hiddenCardIds.clear();
      _animating = false;
    });
  }

  /// Быстрая проверка: нужна ли анимация между [prev] и [next].
  bool _willAnimate(_RemoteGS prev, _RemoteGS next) {
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

  /// Вычисляет diff между [prev] и [next] и запускает _fly() для каждой карты.
  /// Вызывается из postFrameCallback (GlobalKeys уже привязаны к новому layout).
  /// [step] — задержка между запусками соседних карт; для раздачи имеет смысл
  /// сделать заметно меньше дефолта, иначе при 4–6 игроках вся последовательность
  /// растянется на 5+ секунд.
  /// [prevHandPositions] / [prevTableCellPositions] — снапшоты позиций
  /// уходящих карт, снятые ДО `setState(_gs = next)`. После применения next
  /// слоты могут исчезнуть из layout, и якорь возвращает Offset.zero.
  void _animateChanges(_RemoteGS prev, _RemoteGS next,
      {Duration step = const Duration(milliseconds: 150),
      Map<int, Offset> prevHandPositions = const {},
      Map<int, Offset> prevTableCellPositions = const {}}) {
    final draggedId = _lastDraggedCardId;
    _lastDraggedCardId = null;
    int seq = 0;

    final myIndex = next.players.indexWhere((p) => p.id == widget.myPlayerId);
    final deckPos    = _anchorOf(_deckKey);
    final discardPos = _anchorOf(_discardKey);
    final tablePos   = _anchorOf(_tableKey);
    final handPos    = _anchorOf(_handKey);

    Offset seatPos(int pi) => _anchorOf(_seatKeys[pi]);

    /// Текущая позиция слота руки (для целей DEAL/TAKE-в-мою-руку).
    /// Ищет первый слот с совпадающим displayId в отсортированной руке.
    /// Fallback на общий handPos, если слот не смонтирован.
    Offset handSlotPos(int displayId) {
      final sorted = sortHand(next.hand, next.trump);
      final idx = sorted.indexWhere((c) => cardDisplayId(c) == displayId);
      if (idx >= 0) {
        final key = _handSlotKeys[idx];
        if (key?.currentContext != null) {
          final p = _anchorOf(key!);
          if (p != Offset.zero) return p;
        }
      }
      return handPos;
    }

    /// Источник для карты, уходящей из руки конкретного игрока.
    /// Если это я и снапшот есть — точка слота из prev; иначе — seat/hand.
    Offset srcFromPlayer(Card card, int pi) {
      if (pi == myIndex) {
        final p = prevHandPositions[cardDisplayId(card)];
        if (p != null) return p;
        return handPos;
      }
      return seatPos(pi);
    }

    /// Источник для карты, уходящей из ячейки стола в prev.
    Offset prevTableSrc(int prevIdx, {Offset shift = Offset.zero}) =>
        (prevTableCellPositions[prevIdx] ?? tablePos) + shift;

    /// Цель — конкретная ячейка стола, где карта живёт в next.
    Offset tableDest(Card card, {Offset shift = Offset.zero}) {
      final i = next.table.indexWhere(
          (e) => e.attack == card || e.defense == card);
      if (i >= 0 && i < _tableCellKeys.length) {
        final p = _anchorOf(_tableCellKeys[i]);
        if (p != Offset.zero) return p + shift;
      }
      return tablePos + shift;
    }

    final prevAttacks = prev.table.map((e) => e.attack).toSet();
    final nextAttacks = next.table.map((e) => e.attack).toSet();

    // BEAT: стол → бита
    if (prev.table.isNotEmpty &&
        next.table.isEmpty &&
        next.discardSize > prev.discardSize) {
      for (int i = 0; i < prev.table.length; i++) {
        final e = prev.table[i];
        _fly(card: e.attack, faceUp: false,
            from: prevTableSrc(i), to: discardPos,
            startDelay: step * seq++);
        if (e.defense != null) {
          _fly(card: e.defense, faceUp: false,
              from: prevTableSrc(i, shift: const Offset(16, 16)),
              to: discardPos,
              startDelay: step * seq++);
        }
      }
    }

    // TAKE: стол → рука отбивающегося
    if (prev.table.isNotEmpty &&
        next.table.isEmpty &&
        next.discardSize == prev.discardSize) {
      final dest = prev.defenderIndex == myIndex ? handPos : seatPos(prev.defenderIndex);
      for (int i = 0; i < prev.table.length; i++) {
        final e = prev.table[i];
        _fly(card: e.attack, faceUp: false,
            from: prevTableSrc(i), to: dest,
            startDelay: step * seq++);
        if (e.defense != null) {
          _fly(card: e.defense, faceUp: false,
              from: prevTableSrc(i, shift: const Offset(16, 16)),
              to: dest,
              startDelay: step * seq++);
        }
      }
    }

    // TRANSFER / TRANSIT: защитник сменился по ходу
    if (prev.defenderIndex != next.defenderIndex && prev.table.isNotEmpty) {
      final newCards = nextAttacks.difference(prevAttacks);
      if (newCards.isNotEmpty) {
        // TRANSFER: новая карта(ы) кладётся на стол
        for (final card in newCards) {
          if (cardDisplayId(card) == draggedId) continue;
          _fly(card: card, faceUp: true,
              from: srcFromPlayer(card, prev.defenderIndex),
              to: tableDest(card),
              startDelay: step * seq++);
        }
      } else {
        // TRANSIT: козырь нужного ранга показан и остаётся в руке.
        const transitDuration = Duration(milliseconds: 700);
        final fromIdx = prev.defenderIndex;
        if (fromIdx == myIndex) {
          // Свой транзит: карты поднимаются из руки и опускаются обратно
          final uncoveredRanks = next.table
              .where((e) => e.defense == null)
              .map((e) => e.attack.rank)
              .toSet();
          final transitCards = next.hand
              .where((c) =>
                  c.suit == next.trump && uncoveredRanks.contains(c.rank))
              .toList();
          for (final card in transitCards) {
            final slotPos = handSlotPos(cardDisplayId(card));
            _fly(
              card: card, faceUp: true,
              from: slotPos,
              via: slotPos - const Offset(0, kCardHeight / 2),
              to: slotPos,
              duration: transitDuration,
              startDelay: step * seq,
            );
          }
          if (transitCards.isNotEmpty) seq++;
        } else {
          // Чужой транзит: карты рубашкой вверх появляются у посадки и исчезают
          final seat = seatPos(fromIdx);
          final count = prev.table
              .where((e) => e.defense == null)
              .length
              .clamp(1, 3);
          for (int k = 0; k < count; k++) {
            final dx = count > 1
                ? (k - (count - 1) / 2.0) * (kCardWidth + 4)
                : 0.0;
            _fly(
              card: null, faceUp: false,
              from: seat + Offset(dx, 0),
              via: seat + Offset(dx, -kCardHeight / 2),
              to: seat + Offset(dx, 0),
              duration: transitDuration,
              startDelay: step * seq,
            );
          }
          seq++;
        }
      }
    }

    // ATTACK / ADD_ATTACK (только если не было transfer).
    // Инвариант: addAttack в logic/game.dart не меняет currentAdderIndex,
    // pass меняет, но карт на столе не добавляет. Значит prev.currentAdderIndex
    // в этой ветке — игрок, который только что подкинул карту.
    if (prev.defenderIndex == next.defenderIndex) {
      for (final card in nextAttacks.difference(prevAttacks)) {
        if (cardDisplayId(card) == draggedId) continue;
        final srcIndex =
            prev.table.isEmpty ? next.attackerIndex : prev.currentAdderIndex;
        _fly(card: card, faceUp: true,
            from: srcFromPlayer(card, srcIndex),
            to: tableDest(card),
            startDelay: step * seq++);
      }
    }

    // DEFEND: карта защиты из руки на стол
    for (final ne in next.table) {
      if (ne.defense == null) continue;
      if (cardDisplayId(ne.defense!) == draggedId) continue;
      final pe = prev.table.where((e) => e.attack == ne.attack).firstOrNull;
      if (pe != null && pe.defense == null) {
        _fly(card: ne.defense, faceUp: true,
            from: srcFromPlayer(ne.defense!, prev.defenderIndex),
            to: tableDest(ne.defense!, shift: const Offset(16, 16)),
            startDelay: step * seq++);
      }
    }

    // DEAL / REFILL: колода → руки
    if (next.deckSize < prev.deckSize) {
      // При взятии карты стола уже анимированы блоком TAKE — исключаем их,
      // чтобы не анимировать повторно как добор из колоды.
      final isTake = prev.table.isNotEmpty &&
          next.table.isEmpty &&
          next.discardSize == prev.discardSize;
      final takenIds = isTake
          ? prev.table
              .expand<Card>((e) => [e.attack, if (e.defense != null) e.defense!])
              .map(cardDisplayId)
              .toSet()
          : const <int>{};

      final prevHandIds = prev.hand.map(cardDisplayId).toSet();
      for (final card in next.hand) {
        final id = cardDisplayId(card);
        if (!prevHandIds.contains(id) && !takenIds.contains(id)) {
          _fly(card: card, faceUp: false,
              from: deckPos, to: handSlotPos(id),
              startDelay: step * seq++);
        }
      }
      for (int i = 0; i < next.players.length; i++) {
        if (i == myIndex) continue;
        final rawDelta = next.players[i].handSize - prev.players[i].handSize;
        final tableOffset = isTake && i == prev.defenderIndex ? takenIds.length : 0;
        final delta = rawDelta - tableOffset;
        for (int k = 0; k < delta; k++) {
          _fly(card: null, faceUp: false, from: deckPos, to: seatPos(i),
              startDelay: step * seq++);
        }
      }
    }

    // Если ни одна анимация не запущена — сброс флага
    if (seq == 0) setState(() => _animating = false);
  }

  Widget _buildCardOverlay() {
    return Stack(
      key: _overlayKey,
      children: [
        for (final fly in _flying)
          if (fly.via != null)
            TweenAnimationBuilder<double>(
              key: ValueKey(fly.id),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: fly.duration,
              builder: (_, t, child) {
                final Offset pos;
                if (t <= 0.5) {
                  pos = Offset.lerp(
                      fly.from, fly.via!, Curves.easeOut.transform(t * 2))!;
                } else {
                  pos = Offset.lerp(
                      fly.via!, fly.to, Curves.easeIn.transform((t - 0.5) * 2))!;
                }
                return Positioned(left: pos.dx, top: pos.dy, child: child!);
              },
              child: IgnorePointer(
                child: CardWidget(
                  card: fly.card,
                  faceUp: fly.faceUp,
                  width: kCardWidth,
                ),
              ),
            )
          else
            TweenAnimationBuilder<Offset>(
              key: ValueKey(fly.id),
              tween: Tween(begin: fly.from, end: fly.to),
              duration: fly.duration,
              curve: Curves.easeInOut,
              builder: (_, offset, child) =>
                  Positioned(left: offset.dx, top: offset.dy, child: child!),
              child: IgnorePointer(
                child: CardWidget(
                  card: fly.card,
                  faceUp: fly.faceUp,
                  width: kCardWidth,
                ),
              ),
            ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Card> get _selectedCards => _gs!.hand
      .where((c) => _selectedCardIds.contains(cardDisplayId(c)))
      .toList();

  bool get _imAttacker =>
      _gs!.players[_gs!.attackerIndex].id == widget.myPlayerId;
  bool get _imDefender =>
      _gs!.players[_gs!.defenderIndex].id == widget.myPlayerId;
  bool get _canAdd => _gs!.addingPlayerIds.contains(widget.myPlayerId);
  bool get _isTokenHolder =>
      _gs!.players[_gs!.currentAdderIndex].id == widget.myPlayerId;

  int _currentActorIndex(_RemoteGS gs) => switch (gs.phase) {
        GamePhase.attacking => gs.attackerIndex,
        GamePhase.defending => gs.defenderIndex,
        _ => gs.currentAdderIndex,
      };

  // ── Actions ───────────────────────────────────────────────────────────────

  void _doAction(Map<String, dynamic> msg) {
    if (_animating) return;
    _send(msg);
    setState(() {
      _selectedCardIds.clear();
      _selectedAttackCard = null;
    });
  }

  void _attack() => _doAction({
        'type': 'attack',
        'cards': _selectedCards.map(_serCard).toList(),
      });

  void _defend() {
    if (_selectedAttackCard == null || _selectedCards.length != 1) return;
    _doAction({
      'type': 'defend',
      'attackCard': _serCard(_selectedAttackCard!),
      'defenseCard': _serCard(_selectedCards.first),
    });
  }

  void _transfer() => _doAction({
        'type': 'transfer',
        'cards': _selectedCards.map(_serCard).toList(),
      });

  void _transit() {
    if (_selectedCards.length != 1) return;
    _doAction({'type': 'transit', 'card': _serCard(_selectedCards.first)});
  }

  void _addAttack() => _doAction({
        'type': 'add_attack',
        'cards': _selectedCards.map(_serCard).toList(),
      });

  void _pass() => _doAction({'type': 'pass'});

  void _take() => _doAction({'type': 'take'});

  void _swipeUpCard(_RemoteGS gs, Card card) {
    final id = cardDisplayId(card);
    final isTransfer = _imDefender && gs.phase == GamePhase.defending;
    final canAttack = _imAttacker && gs.phase == GamePhase.attacking;
    final canAdd = _canAdd &&
        (gs.phase == GamePhase.adding || gs.phase == GamePhase.taking);
    if (isTransfer) {
      _transferByDrag(gs, id);
    } else if (canAttack || canAdd) {
      _attackByDrag(gs, id);
    }
  }

  Card? _cardByDisplayId(_RemoteGS gs, int displayId) =>
      gs.hand.where((c) => cardDisplayId(c) == displayId).firstOrNull;

  void _attackByDrag(_RemoteGS gs, int displayId) {
    final dragged = _cardByDisplayId(gs, displayId);
    if (dragged == null) return;
    final cards =
        _selectedCardIds.contains(displayId) && _selectedCardIds.isNotEmpty
            ? _selectedCards
            : [dragged];
    final isAdding =
        gs.phase == GamePhase.adding || gs.phase == GamePhase.taking;
    _lastDraggedCardId = displayId;
    _doAction({
      'type': isAdding ? 'add_attack' : 'attack',
      'cards': cards.map(_serCard).toList(),
    });
  }

  void _defendByDrag(Card attackCard, int displayId) {
    final defense = _cardByDisplayId(_gs!, displayId);
    if (defense == null) return;
    _lastDraggedCardId = displayId;
    _doAction({
      'type': 'defend',
      'attackCard': _serCard(attackCard),
      'defenseCard': _serCard(defense),
    });
  }

  void _transferByDrag(_RemoteGS gs, int displayId) {
    final dragged = _cardByDisplayId(gs, displayId);
    if (dragged == null) return;
    final cards = _selectedCardIds.contains(displayId) && _selectedCardIds.isNotEmpty
        ? _selectedCards
        : [dragged];
    _lastDraggedCardId = displayId;
    _doAction({
      'type': 'transfer',
      'cards': cards.map(_serCard).toList(),
    });
  }

  // ── Log strip ─────────────────────────────────────────────────────────────

  void _showLogSheet() {
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
            child: _log.isEmpty
                ? const Center(
                    child: Text('Нет действий',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    reverse: true,
                    itemCount: _log.length,
                    itemBuilder: (ctx, i) {
                      final e = _log[_log.length - 1 - i];
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

  Widget _buildLogStrip() {
    final last = _log.isEmpty ? null : _log.last;
    return GestureDetector(
      onTap: _showLogSheet,
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

  // ── Layout constants ──────────────────────────────────────────────────────

  static const double _handHeight = 116.0;

  // ── Seat positions ────────────────────────────────────────────────────────

  static List<Alignment> _seatPositions(int count) => switch (count) {
        2 => const [Alignment(0.00, -0.72)],
        3 => const [Alignment(-0.50, -0.72), Alignment(0.50, -0.72)],
        4 => const [
            Alignment(-0.88, 0.15),
            Alignment(0.00, -0.72),
            Alignment(0.88, 0.15),
          ],
        5 => const [
            Alignment(-0.88, 0.15),
            Alignment(-0.45, -0.72),
            Alignment(0.45, -0.72),
            Alignment(0.88, 0.15),
          ],
        6 => const [
            Alignment(-0.88, 0.15),
            Alignment(-0.55, -0.72),
            Alignment(0.00, -0.72),
            Alignment(0.55, -0.72),
            Alignment(0.88, 0.15),
          ],
        _ => const [],
      };

  static EdgeInsets _tablePadding(int playerCount) =>
      playerCount <= 3
          ? const EdgeInsets.fromLTRB(8, 140, 8, 8)
          : const EdgeInsets.fromLTRB(80, 140, 80, 8);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final gs = _gs;
    if (gs == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (gs.phase == GamePhase.finished) return _buildGameOver(gs);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                if (_error != null) _buildErrorBanner(),
                _buildStatusBar(gs),
                Expanded(child: _buildTableArea(gs)),
                _buildActionsBar(gs),
                _buildLogStrip(),
                SizedBox(height: _handHeight, child: _buildHand(gs)),
              ],
            ),
          ),
          _buildCardOverlay(),
        ],
      ),
    );
  }

  // ── Table area ────────────────────────────────────────────────────────────

  Widget _buildTableArea(_RemoteGS gs) {
    final myIndex = gs.players.indexWhere((p) => p.id == widget.myPlayerId);
    final count = gs.players.length;
    final positions = _seatPositions(count);

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: _tablePadding(count),
            child: _buildTableGrid(gs),
          ),
        ),
        for (int si = 1; si < count; si++)
          Align(
            alignment: positions[si - 1],
            child: FractionalTranslation(
              translation: positions[si - 1].y < 0
                  ? const Offset(0, -0.15)
                  : Offset.zero,
              child: _buildPlayerSeat(gs, (myIndex + si) % count),
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _buildFab(gs) ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── PlayerSeat ────────────────────────────────────────────────────────────

  Widget _buildPlayerSeat(_RemoteGS gs, int playerIndex) {
    final p = gs.players[playerIndex];
    final isActor = playerIndex == _currentActorIndex(gs);
    final isDefender = playerIndex == gs.defenderIndex;

    final borderColor = isActor
        ? (isDefender ? Colors.lightBlue : Colors.orange)
        : Colors.grey.shade700;
    final borderWidth = isActor ? 2.5 : 1.0;

    return Container(
      key: _seatKeys[playerIndex],
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      constraints: const BoxConstraints(maxWidth: 96),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCardFan(p.handSize),
          const SizedBox(height: 3),
          Text(
            p.hasLeft ? '—' : (p.nickname.isEmpty ? '?' : p.nickname),
            style: const TextStyle(fontSize: 10, color: Colors.white70),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style, size: 9, color: Colors.grey),
              const SizedBox(width: 2),
              Text(
                '${p.handSize}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardFan(int count) {
    final shown = count.clamp(0, 5);
    if (shown == 0) {
      return const SizedBox(width: kCardWidth, height: kCardHeight);
    }
    const step = 8.0;
    return SizedBox(
      width: kCardWidth + (shown - 1) * step,
      height: kCardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < shown; i++)
            Positioned(
              left: i * step,
              child: Transform.rotate(
                angle: (i - (shown - 1) / 2) * 0.12,
                child: const CardWidget(faceUp: false, width: kCardWidth),
              ),
            ),
        ],
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────

  String _playerName(_RemoteGS gs, int index) {
    final p = gs.players[index];
    return p.nickname.isEmpty ? 'Игрок ${index + 1}' : p.nickname;
  }

  Widget _buildStatusBar(_RemoteGS gs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDeckStatus(gs),
          Expanded(child: _buildStatusText(gs)),
          _buildDiscardStatus(gs),
        ],
      ),
    );
  }

  Widget _buildDeckStatus(_RemoteGS gs) {
    if (gs.deckSize == 0) return SizedBox(key: _deckKey, width: kCardWidth);
    return Column(
      key: _deckKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: kCardWidth,
          height: kCardHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (gs.trumpCard != null)
                Positioned(
                  left: kCardWidth / 2,
                  top: (kCardHeight - kCardWidth) / 2,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: CardWidget(
                      card: gs.trumpCard,
                      faceUp: true,
                      width: kCardWidth,
                    ),
                  ),
                ),
              const CardWidget(faceUp: false, width: kCardWidth),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${gs.deckSize}',
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDiscardStatus(_RemoteGS gs) {
    if (gs.discardSize == 0) return SizedBox(key: _discardKey, width: kCardWidth);
    return Column(
      key: _discardKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: 0.12,
          child: const CardWidget(faceUp: false, width: kCardWidth),
        ),
        const SizedBox(height: 3),
        Text(
          '${gs.discardSize}',
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStatusText(_RemoteGS gs) {
    final (line1, line2) = switch (gs.phase) {
      GamePhase.attacking => (
          '${_playerName(gs, gs.attackerIndex)} ходит',
          'под ${_playerName(gs, gs.defenderIndex)}',
        ),
      GamePhase.defending => (
          '${_playerName(gs, gs.defenderIndex)} отбивается',
          '',
        ),
      GamePhase.adding => (
          '${_playerName(gs, gs.currentAdderIndex)} подкидывает',
          'под ${_playerName(gs, gs.defenderIndex)}',
        ),
      GamePhase.taking => (
          '${_playerName(gs, gs.defenderIndex)} берёт',
          '',
        ),
      _ => ('', ''),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          line1,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
        if (line2.isNotEmpty)
          Text(
            line2,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
      ],
    );
  }

  // ── Error banner ──────────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Material(
      color: Colors.red.shade900,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _error = null),
            ),
          ],
        ),
      ),
    );
  }

  // ── Table grid ────────────────────────────────────────────────────────────

  Widget _buildTableGrid(_RemoteGS gs) {
    return Center(
      key: _tableKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int row = 0; row < 3; row++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int col = 0; col < 3; col++)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      key: _tableCellKeys[row * 3 + col],
                      width: 72,
                      height: 96,
                      child: _tableCell(gs, row * 3 + col),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tableCell(_RemoteGS gs, int i) {
    if (i >= gs.table.length) return _buildEmptyTableCell(gs);
    final entry = gs.table[i];
    if (_hiddenCardIds.contains(cardDisplayId(entry.attack))) {
      return _buildEmptyTableCell(gs);
    }
    return _buildTableEntry(entry, gs);
  }

  Widget _buildEmptyTableCell(_RemoteGS gs) {
    final isTransfer = _imDefender && gs.phase == GamePhase.defending;
    final canDrop = isTransfer ||
        (_imAttacker && gs.phase == GamePhase.attacking) ||
        (_canAdd &&
            (gs.phase == GamePhase.adding || gs.phase == GamePhase.taking));

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => canDrop && !_animating,
      onAcceptWithDetails: (d) => isTransfer
          ? _transferByDrag(gs, d.data)
          : _attackByDrag(gs, d.data),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: Border.all(
              color: hovering ? Colors.orange.withAlpha(160) : Colors.white12,
              width: hovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: hovering
              ? Center(
                  child: Text(
                    isTransfer ? 'Перевести' : 'Бросить',
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildTableEntry(_RemoteEntry entry, _RemoteGS gs) {
    final canDefend =
        _imDefender && gs.phase == GamePhase.defending && entry.defense == null;
    final isSelected = _selectedAttackCard == entry.attack;

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => canDefend && !_animating,
      onAcceptWithDetails: (d) => _defendByDrag(entry.attack, d.data),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: canDefend
              ? () => setState(() =>
                  _selectedAttackCard = isSelected ? null : entry.attack)
              : null,
          child: SizedBox(
            width: 72,
            height: 96,
            child: Stack(
              children: [
                CardWidget(
                  card: entry.attack,
                  selected: isSelected || hovering,
                  highlighted: canDefend && !isSelected && !hovering,
                ),
                if (entry.defense != null &&
                    !_hiddenCardIds.contains(cardDisplayId(entry.defense!)))
                  Positioned(
                    top: 16,
                    left: 16,
                    child: CardWidget(card: entry.defense!),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Hand ──────────────────────────────────────────────────────────────────

  Widget _buildHand(_RemoteGS gs) {
    if (gs.hand.isEmpty) {
      return Center(
        key: _handKey,
        child: const Text('Нет карт', style: TextStyle(color: Colors.grey)),
      );
    }
    final sorted = sortHand(gs.hand, gs.trump);
    return SingleChildScrollView(
      key: _handKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          for (final entry in sorted.asMap().entries)
            Padding(
              key: _handSlotKey(entry.key),
              padding: const EdgeInsets.only(right: 6),
              child: Visibility(
                visible: !_hiddenCardIds.contains(cardDisplayId(entry.value)),
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    final vel = details.primaryVelocity ?? 0;
                    if (vel < -500 && !_animating) _swipeUpCard(gs, entry.value);
                  },
                  child: LongPressDraggable<int>(
                    data: cardDisplayId(entry.value),
                    maxSimultaneousDrags: _animating ? 0 : 1,
                    delay: const Duration(milliseconds: 180),
                    feedback: Material(
                      color: Colors.transparent,
                      child: Transform.scale(
                        scale: 1.1,
                        child: CardWidget(card: entry.value, selected: true),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: CardWidget(card: entry.value),
                    ),
                    child: CardWidget(
                      card: entry.value,
                      selected: _selectedCardIds.contains(cardDisplayId(entry.value)),
                      onTap: _animating ? null : () => setState(() {
                        final id = cardDisplayId(entry.value);
                        if (_selectedCardIds.contains(id)) {
                          _selectedCardIds.remove(id);
                        } else {
                          _selectedCardIds.add(id);
                        }
                      }),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Actions bar ───────────────────────────────────────────────────────────

  Widget _buildActionsBar(_RemoteGS gs) {
    final sel = _selectedCards;
    final hasSel = sel.isNotEmpty;
    final hasSingle = sel.length == 1;
    final hasTarget = _selectedAttackCard != null;
    final phase = gs.phase;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (phase == GamePhase.attacking)
            FilledButton(
              onPressed: _imAttacker && hasSel ? _attack : null,
              child: const Text('Атаковать'),
            ),
          if (phase == GamePhase.defending) ...[
            FilledButton(
              onPressed: _imDefender && hasTarget && hasSingle ? _defend : null,
              child: const Text('Отбить'),
            ),
            OutlinedButton(
              onPressed: _imDefender && hasSel ? _transfer : null,
              child: const Text('Перевести'),
            ),
            OutlinedButton(
              onPressed: _imDefender && hasSingle ? _transit : null,
              child: const Text('Проездной'),
            ),
          ],
          if (phase == GamePhase.adding || phase == GamePhase.taking)
            FilledButton(
              onPressed: _canAdd && hasSel ? _addAttack : null,
              child: const Text('Подкинуть'),
            ),
        ],
      ),
    );
  }

  // ── FAB: Take / Pass ──────────────────────────────────────────────────────

  Widget? _buildFab(_RemoteGS gs) {
    final phase = gs.phase;
    if (_imDefender &&
        (phase == GamePhase.defending || phase == GamePhase.adding)) {
      return FloatingActionButton.extended(
        heroTag: 'take_fab',
        onPressed: _take,
        label: const Text('Взять'),
        icon: const Icon(Icons.download_rounded, size: 18),
        backgroundColor: Colors.red.shade700,
      );
    }
    if (_isTokenHolder &&
        (phase == GamePhase.adding || phase == GamePhase.taking)) {
      return FloatingActionButton.extended(
        heroTag: 'pass_fab',
        onPressed: _pass,
        label: const Text('Пас'),
        icon: const Icon(Icons.skip_next_rounded, size: 18),
      );
    }
    return null;
  }

  // ── Game over ─────────────────────────────────────────────────────────────

  Widget _buildGameOver(_RemoteGS gs) {
    final loserId = gs.loserId;
    final isLoser = loserId == widget.myPlayerId;
    final isDraw = loserId == null;
    final loserIdx =
        loserId != null ? gs.players.indexWhere((p) => p.id == loserId) : -1;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Конец игры'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDraw
                  ? Icons.handshake
                  : isLoser
                      ? Icons.sentiment_dissatisfied
                      : Icons.emoji_events,
              size: 80,
              color: isDraw
                  ? Colors.grey
                  : isLoser
                      ? Colors.redAccent
                      : Colors.amber,
            ),
            const SizedBox(height: 16),
            Text(
              isDraw
                  ? 'Ничья!'
                  : isLoser
                      ? 'Вы проиграли'
                      : 'Вы победили!',
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (!isDraw && loserIdx >= 0) ...[
              const SizedBox(height: 8),
              Text(
                isLoser
                    ? 'Вы — дурак'
                    : 'Дурак: ${gs.players[loserIdx].nickname.isEmpty ? 'игрок ${loserIdx + 1}' : gs.players[loserIdx].nickname}',
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('В главное меню'),
            ),
          ],
        ),
      ),
    );
  }
}
