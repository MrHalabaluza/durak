# UI TODO

Задачи на редизайн UI. Порядок отражает предлагаемую последовательность PR.

## PR1 — Ассеты и новый CardWidget

- [ ] Добавить зависимости в `pubspec.yaml`: `flutter_svg`, `flutter_animate`.
- [ ] Найти SVG-ассеты лиц карт под открытой лицензией (например, `byron-knoll/playing-cards` — public domain).
- [ ] Положить лица в `ui/assets/cards/{suit}_{rank}.svg` (52 файла).
- [ ] Положить дефолтную рубашку в `ui/assets/backs/default.svg`.
- [ ] Подключить ассеты в `pubspec.yaml`.
- [ ] Переписать `CardWidget`: параметры `faceUp`, `backSkinId`, размер карты параметризовать.
- [ ] Перенести `CardWidget`-параметры `selected` / `highlighted` (рамка пожирнее, без свечения).
- [ ] Реализовать `sortHand(List<Card> hand, Suit trump)` — порядок мастей `[♣,♦,♥,♠]` минус козырь, козырь в конец, внутри масти по `rank.index`.
- [ ] Применить `sortHand` в текущей отрисовке руки (drag-data перевести на `card.id` вместо индекса).

## PR2 — Trump card в logic + угол колоды/биты

- [ ] `GameState.trumpCard: Card?` — добавить поле.
- [ ] `Game.start`: зафиксировать `trumpCard` (нижняя/верхняя карта колоды по реализации `Deck`).
- [ ] Обнулять `trumpCard` при опустении колоды.
- [ ] `gameStateMsg`: сериализация `trumpCard`.
- [ ] `_RemoteGS.fromJson`: десериализация `trumpCard`.
- [ ] Виджет `_DeckCorner` (левый верх): закрытая карта + перпендикулярная trumpCard под ней + счётчик.
- [ ] Виджет `_DiscardCorner` (правый верх): закрытая карта со счётчиком, лёгкий наклон для эффекта стопки.

## PR3 — Никнейм

- [ ] `AppSettings.load`: если `playerName == ''` — сгенерировать `Player_<NNN>` (3 случайные цифры) и сохранить.
- [ ] `SettingsScreen`: поле «Никнейм», валидация (непустой, ≤ 20 символов).
- [ ] Сервер: `JoinRoomMsg` / `CreateRoomMsg` принимают `nickname`, хранение `playerId → nickname`, разрешение коллизий суффиксом.
- [ ] `roomStateMsg`, `gameStateMsg`: добавить `nickname` в каждого игрока.
- [ ] `LobbyScreen`: передавать `nickname` из `AppSettings`.
- [ ] `LobbyScreen` / `OnlineGameScreen`: показывать `nickname` вместо `playerId`.

## PR4 — Круговой layout + удаление локального режима

- [ ] Удалить `ui/lib/game_screen.dart`.
- [ ] `main.dart`: убрать ветку «LOCAL» и связанные элементы из `SetupScreen`.
- [ ] Реализовать `_seatPositions(int count)` для 2/3/4/5/6 игроков.
- [ ] Поворот круга: `seatIndex = (playerIndex - myIndex + count) % count` → 0 всегда снизу.
- [ ] Виджет `_PlayerSeat`: компактный «веер» закрытых карт + ник + handSize, обводка пожирнее для активного игрока.
- [ ] Виджет `_TableArea`: `Stack`, пары атака/защита (защита со смещением `(+16, +16)`).
- [ ] Виджет `_MyHand`: горизонтальный скролл, отсортированная рука, `Draggable<int>` с `card.id` в data.
- [ ] Виджет `_ActionsBar`: контекстные кнопки текущей фазы над рукой.
- [ ] FAB справа — «Взять» / «Пас».
- [ ] Перевести экран в портретную ориентацию, проверить на узких экранах (≥360px).

## PR5 — Лог действий

- [ ] Структура `_LogEntry { timestamp, actorNickname, type, cards }`.
- [ ] Diff между предыдущим и новым `game_state` → запись действий («атаковал ♥7», «отбил ♣9», «взял», «бито», «перевёл»).
- [ ] Свёрнутая полоска над рукой с последним действием.
- [ ] `BottomSheet` со всей историей текущей партии по тапу.
- [ ] Очистка лога при старте новой партии.

## PR6 — Анимации

- [ ] Виджет `_CardOverlay`: `Stack` поверх всего экрана, `AnimatedPositioned` карт по `card.id`.
- [ ] `GlobalKey` на якоря: углы колоды/биты, посадки игроков, слоты в руке.
- [ ] Helper `Offset _anchorOf(GlobalKey)` через `RenderBox.localToGlobal`.
- [ ] Diff `game_state` → последовательность анимаций:
  - [ ] раздача (deck → hands),
  - [ ] атака/подкид (hand → table),
  - [ ] защита (hand → table со смещением),
  - [ ] взять (table → hand),
  - [ ] бито (table → discard corner),
  - [ ] добор (deck → hand по одной).
- [ ] Длительность 200 мс/карта, overlap 50 мс.
- [ ] Блокировать ввод во время анимации.

## PR7 — Жест swipe-up

- [ ] `GestureDetector.onVerticalDragEnd` на карте в руке, порог velocity.
- [ ] При срабатывании — эквивалент drop на `_TableArea` (атака/подкид/перевод по фазе).
- [ ] Поддержка multi-select: если карта в выборе — свайп отправляет всю выборку.

## После всех PR

- [ ] Проверить layout на 360×640, 390×844, 428×926, десктопе и web.
- [ ] Smoke-тест всех фаз игры с 2/3/4/5/6 игроками.
- [ ] Удалить мёртвый код из старого layout (`_buildPlayersRow`, `_buildPlayerChip`, инструкции).
