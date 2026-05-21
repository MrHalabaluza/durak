# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DTFool — карточная игра «Двойной переводной дурак». Платформы: iOS, Android, Desktop. Стек: Flutter + Dart.

Три независимых модуля в монорепо:
- `logic/` — чистая Dart-библиотека, игровые правила и состояние (без I/O и Flutter-зависимостей)
- `server/` — WebSocket-сервер мультиплеера, зависит от `logic/`
- `ui/` — Flutter-приложение, зависит от `logic/`

## Commands

```bash
# UI (Flutter)
cd ui && flutter pub get && flutter run

# Server
cd server && dart pub get && dart run bin/server.dart  # PORT=8080 по умолчанию

# Docker (из корня репо)
docker build -f server/Dockerfile -t durak-server .
docker run -p 8080:8080 durak-server

# Тесты logic
cd logic && dart pub get && dart test
```

## Architecture

### Module dependencies

```
logic/ (pure Dart, no deps)
   ▲           ▲
server/     ui/
```

`ui/pubspec.yaml` и `server/pubspec.yaml` подключают `logic/` через `path: ../logic`.

### Game state machine (`logic/lib/src/game.dart`)

`Game` — центральный класс, реализующий конечный автомат. Точка входа: `Game.start(playerIds, {random?, config?})`.

Публичные действия: `attack`, `defend`, `transfer`, `transit`, `addAttack`, `pass`, `take`. Каждое действие бросает `GameException` при нарушении правил (неверная фаза, не тот игрок, недопустимая карта).

`GameState` — иммутабельный снимок состояния (игроки, колода, козырь, стол, фаза, индексы).

`GamePhase` enum: `attacking → defending → adding → taking → finished`.

### Networking (`server/lib/protocol.dart`)

Sealed-классы `ClientMessage` описывают все сообщения клиента. `ClientMessage.parse(json)` десериализует входящее сообщение. Сервер отправляет ответы через хелперы `roomJoinedMsg`, `gameStateMsg`, `errorMsg` и т.д.

Сервер назначает каждому клиенту уникальный `playerId` (8-байтовый hex). Клиент не выбирает его сам.

### UI flow (`ui/lib/`)

```
SetupScreen (main.dart)
└── LobbyScreen → OnlineGameScreen — WebSocket, broadcast stream
```

Локального оффлайн-режима нет. `OnlineGameScreen` подписывается на broadcast stream WebSocket; состояние игры приходит как `_RemoteGS` (только своя рука, размеры рук других).

`CardWidget` поддерживает tap для выбора и drag для размещения карт.

## Game Rules Key Points (full spec in `logic/CLAUDE.md`)

- 2–6 игроков; карты 6–Туз, четыре масти; козырь — масть верхней карты колоды
- Раздаётся 9 карт; добирают до 9 после хода
- **transfer** — перевод: отбивающийся кладёт карты того же номинала, следующий становится отбивающимся
- **transit** — транзит: козырная карта нужного номинала; передаётся без размещения на столе
- **defend** — покрытие: старшей картой той же масти или любой козырной
- **take** — взять: отбивающийся забирает все карты стола
- Проигравший — последний с картами; ничья — колода пуста и все карты биты
- Первый ход нельзя перевести/транзитить (`isFirstTurn` guard в `Game`)
- Максимальное количество карт для отбития на столе 9; если отбитых карт ещё нет, то 5
- Подкидывать карты могут только игроки рядом с отбивающимся
- Игроки рядом с отбивающимся подкидывают по очереди по одной или несколько карт, если оба пасуют подряд (без подкидок между пасами), то ход заканчивается
- Карты из колоды игроки добирают по очереди начиная со следующего от последнего отбивающегося игрока 
