# Build from repo root:
#   docker build -f server/Dockerfile -t durak-server .

FROM dart:stable AS build

WORKDIR /app/server

# logic/ is a local path dependency — must be available during pub get
COPY logic/ /app/logic/

COPY server/pubspec.yaml server/pubspec.lock* ./
RUN dart pub get --no-example

COPY server/ ./
RUN dart compile exe bin/server.dart -o bin/server

# Minimal runtime image (scratch + Dart shared libs)
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/server

EXPOSE 8080
CMD ["/app/server"]
