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
