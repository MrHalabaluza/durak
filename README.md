# DTFool — Двойной переводной дурак

Карточная игра для 2–6 игроков. Локальный и онлайн-режимы. Flutter (iOS/Android/Desktop) + Dart WebSocket-сервер.

## Требования

- [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.11.5 (включает Dart ≥ 3.0)
- Для Docker: [Docker](https://docs.docker.com/get-docker/)

## Клиент (Flutter)

```bash
cd ui
flutter pub get
flutter run                        # выбор устройства интерактивно
flutter run -d linux               # или: macos, windows, chrome
```

Перед запуском онлайн-игры укажите адрес сервера в настройках приложения (шестерёнка на главном экране).

## Сервер

### Запуск напрямую

```bash
cd server
dart pub get
dart run bin/server.dart           # слушает :8080
PORT=9000 dart run bin/server.dart # другой порт
```

### Docker

```bash
# сборка (из корня репо)
docker build -f server/Dockerfile -t durak-server .

# запуск
docker run -p 8080:8080 durak-server
```

## Тесты

```bash
cd logic
dart pub get
dart test
```

## Разработка и отладка (VSCode)

### Настройка окружения

Скопируйте шаблон и заполните под свою машину:

```bash
cp .env.example .env
```

Переменные в `.env`:

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `PORT` | `8080` | Порт сервера |
| `DART_VM_PORT` | `8181` | Порт Dart VM service (отладчик) |
| `REMOTE_HOST` | — | SSH-адрес удалённого сервера (`user@host`) |
| `SSH_PORT` | `22` | SSH-порт |
| `REMOTE_DIR` | `~/durak` | Путь на удалённом сервере |

Файл `.env` не коммитится (в `.gitignore`).

### launch.json — конфигурации запуска

| Конфигурация | Описание |
|---|---|
| **Server: Launch (local)** | Запускает сервер с Dart debugger (читает `PORT` из `.env`) |
| **Server: Attach** | Подключается к уже запущенному серверу на `localhost:8181` |
| **Client 1/2/3 (web :700X)** | Flutter web на портах 7001–7003, каждый в отдельном окне Chrome |
| **Dev: Server + 1/2/3 Clients** | Compound: запускает сервер и 1–3 клиента одной кнопкой |

Для отладки удалённого сервера: пробросьте порт через SSH, затем используйте **Server: Attach**:

```bash
ssh -L 8181:localhost:8181 user@host
```

### tasks.json — вспомогательные задачи

| Задача | Описание |
|---|---|
| **pub get: all** | `dart/flutter pub get` для всех трёх модулей параллельно |
| **pub get: logic/server/ui** | То же, по отдельности |
| **deploy: remote** | Деплой сервера на удалённую машину (см. ниже) |

### Деплой на удалённый сервер

```bash
# из VSCode: Tasks → Run Task → deploy: remote
# или напрямую:
./scripts/deploy.sh
```

Скрипт синхронизирует `logic/` и `server/` через rsync, затем по SSH пересобирает Docker-образ и перезапускает контейнер. Требует заполненных `REMOTE_HOST`, `SSH_PORT`, `REMOTE_DIR` в `.env`.
