import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:durak_logic/durak_logic.dart';
import 'package:durak_protocol/durak_protocol.dart';
import 'lobby_screen.dart';
import 'widgets/actions_bar.dart';
import 'widgets/card_overlay.dart';
import 'widgets/deck_corner.dart';
import 'widgets/discard_corner.dart';
import 'widgets/log_panel.dart';
import 'widgets/my_hand.dart';
import 'widgets/table_area.dart';

class OnlineGameScreen extends StatefulWidget {
  /// Used only for sending messages to the server.
  final WebSocketChannel socket;

  /// Broadcast stream of parsed server messages — created in LobbyScreen.
  final Stream<Map<String, dynamic>> messageStream;

  final String myPlayerId;

  /// First game_state received in the lobby — displayed immediately.
  final Map<String, dynamic>? initialState;

  // Server connection params — used to navigate back to lobby after game ends.
  final String host;
  final int port;
  final bool tls;
  final String token;
  final DeckConfig deckConfig;

  const OnlineGameScreen({
    super.key,
    required this.socket,
    required this.messageStream,
    required this.myPlayerId,
    this.initialState,
    required this.host,
    required this.port,
    required this.tls,
    required this.token,
    required this.deckConfig,
  });

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen>
    with WidgetsBindingObserver {
  StreamSubscription? _sub;
  GameStateView? _gs;
  String? _error;
  bool _returningToLobby = false;
  String? _postGameRoomId;
  String? _postGameOwnerId;
  List<({String id, String nickname, bool isBot})> _postGamePlayers = [];

  final Set<int> _selectedCardIds = {};
  Card? _selectedAttackCard;

  final List<LogEntry> _log = [];

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
  // ключи на конкретные слоты руки (по card.id, лениво)
  final Map<int, GlobalKey> _handSlotKeys = {};
  GlobalKey _handSlotKey(int cardId) =>
      _handSlotKeys.putIfAbsent(cardId, () => GlobalKey());

  // Overlay-анимация
  final _flying     = <FlyingCard>[];
  int  _nextFlyId   = 0;
  bool _animating   = false;
  int  _animGeneration = 0;
  // card.id карты, перенесённой drag-and-drop — её анимация пропускается.
  int? _lastDraggedCardId;
  // card.id карт, которые сейчас в полёте — статичный слой их скрывает.
  final Set<int> _hiddenCardIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (widget.initialState != null) {
      final next = GameStateView.fromJson(widget.initialState!);
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
  static GameStateView _preDealState(GameStateView next) {
    final inHands = next.players.fold<int>(0, (s, p) => s + p.handSize);
    final onTable = next.table
        .fold<int>(0, (s, e) => s + 1 + (e.defense != null ? 1 : 0));
    return GameStateView(
      phase: next.phase,
      trump: next.trump,
      trumpCard: next.trumpCard,
      deckSize: next.deckSize + inHands + next.discardSize + onTable,
      discardSize: 0,
      attackerIndex: next.attackerIndex,
      defenderIndex: next.defenderIndex,
      currentAdderIndex: next.currentAdderIndex,
      isFirstTurn: next.isFirstTurn,
      addingPlayerIds: const [],
      hand: const [],
      players: next.players
          .map((p) => PlayerView(p.id, p.nickname, 0, p.hasLeft))
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
    if (!_returningToLobby) widget.socket.sink.close();
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
      final next = GameStateView.fromJson(map);
      if (prev != null) _diffAndLog(prev, next);

      // Снимок позиций уходящих карт ДО setState — после применения next
      // соответствующие слоты руки/ячейки могут исчезнуть из layout
      // (карта сыграна, стол очищен и т.п.), и якорь будет недоступен.
      final prevHandPositions = <int, Offset>{};
      final prevTableCellPositions = <int, Offset>{};
      if (prev != null) {
        for (final card in prev.hand) {
          final key = _handSlotKeys[card.id];
          if (key?.currentContext != null) {
            prevHandPositions[card.id] = _anchorOf(key!);
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
    } else if (type == 'room_state') {
      if (_gs?.phase != GamePhase.finished) return;
      final roomId = map['roomId'] as String;
      final ownerId = map['ownerId'] as String?;
      final players = (map['players'] as List).map((e) {
        final p = e as Map<String, dynamic>;
        return (
          id: p['id'] as String,
          nickname: p['nickname'] as String? ?? '',
          isBot: p['isBot'] as bool? ?? false,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _postGameRoomId = roomId;
          _postGameOwnerId = ownerId;
          _postGamePlayers = players;
        });
      }
    } else if (type == 'error') {
      setState(() => _error = map['message'] as String);
    }
  }

  void _diffAndLog(GameStateView prev, GameStateView next) {
    if (prev.phase == GamePhase.finished) {
      _log.clear();
      return;
    }

    String nick(PlayerView p) => p.nickname.isEmpty ? 'Игрок' : p.nickname;

    // Подключение / отключение игроков
    final minLen = prev.players.length < next.players.length
        ? prev.players.length
        : next.players.length;
    for (var i = 0; i < minLen; i++) {
      final pp = prev.players[i];
      final np = next.players[i];
      if (!pp.hasLeft && np.hasLeft) {
        _log.add(LogEntry(
            timestamp: DateTime.now(),
            actorNickname: nick(pp),
            type: 'disconnected'));
      } else if (pp.hasLeft && !np.hasLeft) {
        _log.add(LogEntry(
            timestamp: DateTime.now(),
            actorNickname: nick(np),
            type: 'connected'));
      }
    }

    final prevAttacks = prev.table.map((e) => e.attack).toSet();
    final nextAttacks = next.table.map((e) => e.attack).toSet();

    // Table cleared
    if (prev.table.isNotEmpty && next.table.isEmpty) {
      if (next.discardSize > prev.discardSize) {
        _log.add(LogEntry(timestamp: DateTime.now(), actorNickname: '', type: 'beat'));
      } else {
        _log.add(LogEntry(
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
      _log.add(LogEntry(
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
        _log.add(LogEntry(
          timestamp: DateTime.now(),
          actorNickname: nick(next.players[next.attackerIndex]),
          type: 'attack',
          cards: newAttacks.toList(),
        ));
      } else {
        _log.add(LogEntry(
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
        _log.add(LogEntry(
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
    required Offset to,
    Duration duration = const Duration(milliseconds: 200),
    Duration startDelay = Duration.zero,
  }) {
    final gen = _animGeneration;
    Future.delayed(startDelay, () {
      if (!mounted || gen != _animGeneration) return;
      final id = _nextFlyId++;
      final cid = card?.id;
      setState(() {
        _flying.add(FlyingCard(
          id: id,
          card: card,
          faceUp: faceUp,
          from: from,
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
  bool _willAnimate(GameStateView prev, GameStateView next) {
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
  void _animateChanges(GameStateView prev, GameStateView next,
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
    /// Если слот не смонтирован (карта была скрыта или ещё не появилась),
    /// fallback на общий handPos.
    Offset handSlotPos(int cardId) {
      final key = _handSlotKeys[cardId];
      if (key?.currentContext != null) {
        final p = _anchorOf(key!);
        if (p != Offset.zero) return p;
      }
      return handPos;
    }

    /// Источник для карты, уходящей из руки конкретного игрока.
    /// Если это я и снапшот есть — точка слота из prev; иначе — seat/hand.
    Offset srcFromPlayer(Card card, int pi) {
      if (pi == myIndex) {
        final p = prevHandPositions[card.id];
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
        _fly(card: e.attack, faceUp: true,
            from: prevTableSrc(i), to: discardPos,
            startDelay: step * seq++);
        if (e.defense != null) {
          _fly(card: e.defense, faceUp: true,
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
      final isMine = prev.defenderIndex == myIndex;
      final dest = isMine ? handPos : seatPos(prev.defenderIndex);
      for (int i = 0; i < prev.table.length; i++) {
        final e = prev.table[i];
        _fly(card: e.attack, faceUp: isMine,
            from: prevTableSrc(i), to: dest,
            startDelay: step * seq++);
        if (e.defense != null) {
          _fly(card: e.defense, faceUp: isMine,
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
          if (card.id == draggedId) continue;
          _fly(card: card, faceUp: true,
              from: srcFromPlayer(card, prev.defenderIndex),
              to: tableDest(card),
              startDelay: step * seq++);
        }
      } else {
        // TRANSIT: козырь нужного ранга показан и остаётся в руке.
        // Визуально — карта вылетает из руки/посадки бывшего защитника
        // в сторону нового и исчезает; в статике она вернётся в руку,
        // т.к. _hiddenCardIds сбросится по завершении полёта.
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

        _fly(card: showCard, faceUp: faceUp,
            from: from, to: to,
            duration: const Duration(milliseconds: 300),
            startDelay: step * seq++);
      }
    }

    // ATTACK / ADD_ATTACK (только если не было transfer).
    // Инвариант: addAttack в logic/game.dart не меняет currentAdderIndex,
    // pass меняет, но карт на столе не добавляет. Значит prev.currentAdderIndex
    // в этой ветке — игрок, который только что подкинул карту.
    if (prev.defenderIndex == next.defenderIndex) {
      for (final card in nextAttacks.difference(prevAttacks)) {
        if (card.id == draggedId) continue;
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
      if (ne.defense!.id == draggedId) continue;
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
              .map((c) => c.id)
              .toSet()
          : const <int>{};

      final prevHandIds = prev.hand.map((c) => c.id).toSet();
      for (final card in next.hand) {
        if (!prevHandIds.contains(card.id) && !takenIds.contains(card.id)) {
          _fly(card: card, faceUp: true,
              from: deckPos, to: handSlotPos(card.id),
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Card> get _selectedCards => _gs!.hand
      .where((c) => _selectedCardIds.contains(c.id))
      .toList();

  bool get _imAttacker =>
      _gs!.players[_gs!.attackerIndex].id == widget.myPlayerId;
  bool get _imDefender =>
      _gs!.players[_gs!.defenderIndex].id == widget.myPlayerId;
  bool get _canAdd => _gs!.addingPlayerIds.contains(widget.myPlayerId);
  bool get _isTokenHolder =>
      _gs!.players[_gs!.currentAdderIndex].id == widget.myPlayerId;

  // ── Actions ───────────────────────────────────────────────────────────────

  void _doAction(Map<String, dynamic> msg) {
    if (_animating) return;
    _send(msg);
    setState(() {
      _selectedCardIds.clear();
      _selectedAttackCard = null;
    });
  }

  void _attack() => _doAction(AttackMsg(_selectedCards).toJson());

  void _defend() {
    if (_selectedAttackCard == null || _selectedCards.length != 1) return;
    _doAction(DefendMsg(_selectedAttackCard!, _selectedCards.first).toJson());
  }

  void _transfer() => _doAction(TransferMsg(_selectedCards).toJson());

  void _transit() {
    if (_selectedCards.length != 1) return;
    _doAction(TransitMsg(_selectedCards.first).toJson());
  }

  void _addAttack() => _doAction(AddAttackMsg(_selectedCards).toJson());

  void _pass() => _doAction(const PassMsg().toJson());

  void _take() => _doAction(const TakeMsg().toJson());

  Card? _cardById(GameStateView gs, int id) =>
      gs.hand.where((c) => c.id == id).firstOrNull;

  void _attackByDrag(GameStateView gs, int cardId) {
    final dragged = _cardById(gs, cardId);
    if (dragged == null) return;
    final cards =
        _selectedCardIds.contains(cardId) && _selectedCardIds.isNotEmpty
            ? _selectedCards
            : [dragged];
    final isAdding =
        gs.phase == GamePhase.adding || gs.phase == GamePhase.taking;
    _lastDraggedCardId = cardId;
    _doAction(isAdding
        ? AddAttackMsg(cards).toJson()
        : AttackMsg(cards).toJson());
  }

  void _defendByDrag(Card attackCard, int cardId) {
    final defense = _cardById(_gs!, cardId);
    if (defense == null) return;
    _lastDraggedCardId = cardId;
    _doAction(DefendMsg(attackCard, defense).toJson());
  }

  void _transferByDrag(GameStateView gs, int cardId) {
    final dragged = _cardById(gs, cardId);
    if (dragged == null) return;
    final cards = _selectedCardIds.contains(cardId) && _selectedCardIds.isNotEmpty
        ? _selectedCards
        : [dragged];
    _lastDraggedCardId = cardId;
    _doAction(TransferMsg(cards).toJson());
  }

  // ── Layout constant ───────────────────────────────────────────────────────

  static const double _handHeight = 116.0;

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

    final myIndex = gs.players.indexWhere((p) => p.id == widget.myPlayerId);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                if (_error != null) _buildErrorBanner(),
                _buildStatusBar(gs),
                Expanded(
                  child: TableArea(
                    gs: gs,
                    myIndex: myIndex,
                    hiddenCardIds: _hiddenCardIds,
                    animating: _animating,
                    selectedAttackCard: _selectedAttackCard,
                    imAttacker: _imAttacker,
                    imDefender: _imDefender,
                    canAdd: _canAdd,
                    isTokenHolder: _isTokenHolder,
                    tableKey: _tableKey,
                    seatKeys: _seatKeys,
                    tableCellKeys: _tableCellKeys,
                    onAttackByDrag: (id) => _attackByDrag(gs, id),
                    onDefendByDrag: _defendByDrag,
                    onTransferByDrag: (id) => _transferByDrag(gs, id),
                    onSelectAttackCard: (c) =>
                        setState(() => _selectedAttackCard = c),
                    onTake: _take,
                    onPass: _pass,
                  ),
                ),
                ActionsBar(
                  phase: gs.phase,
                  imAttacker: _imAttacker,
                  imDefender: _imDefender,
                  canAdd: _canAdd,
                  selectedCards: _selectedCards,
                  selectedAttackCard: _selectedAttackCard,
                  onAttack: _attack,
                  onDefend: _defend,
                  onTransfer: _transfer,
                  onTransit: _transit,
                  onAddAttack: _addAttack,
                ),
                LogPanel(log: _log),
                SizedBox(
                  height: _handHeight,
                  child: MyHand(
                    gs: gs,
                    hiddenCardIds: _hiddenCardIds,
                    animating: _animating,
                    selectedCardIds: _selectedCardIds,
                    handKey: _handKey,
                    handSlotKey: _handSlotKey,
                    onCardTap: (id) => setState(() {
                      if (_selectedCardIds.contains(id)) {
                        _selectedCardIds.remove(id);
                      } else {
                        _selectedCardIds.add(id);
                      }
                    }),
                  ),
                ),
              ],
            ),
          ),
          CardOverlay(flying: _flying, overlayKey: _overlayKey),
        ],
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────

  Widget _buildStatusBar(GameStateView gs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeckCorner(
            deckSize: gs.deckSize,
            trumpCard: gs.trumpCard,
            deckKey: _deckKey,
          ),
          Expanded(child: _buildStatusText(gs)),
          DiscardCorner(
            discardSize: gs.discardSize,
            discardKey: _discardKey,
          ),
        ],
      ),
    );
  }

  String _playerName(GameStateView gs, int index) {
    final p = gs.players[index];
    return p.nickname.isEmpty ? 'Игрок ${index + 1}' : p.nickname;
  }

  Widget _buildStatusText(GameStateView gs) {
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

  // ── Game over ─────────────────────────────────────────────────────────────

  Widget _buildGameOver(GameStateView gs) {
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
              onPressed: () {
                _returningToLobby = true;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LobbyScreen(
                      host: widget.host,
                      port: widget.port,
                      tls: widget.tls,
                      token: widget.token,
                      resumeSocket: widget.socket,
                      resumeStream: widget.messageStream,
                      resumePlayerId: widget.myPlayerId,
                      resumeRoomId: _postGameRoomId,
                      resumeOwnerId: _postGameOwnerId,
                      resumePlayers: _postGamePlayers,
                      resumeDeckConfig: widget.deckConfig,
                    ),
                  ),
                );
              },
              child: const Text('В лобби'),
            ),
          ],
        ),
      ),
    );
  }
}
