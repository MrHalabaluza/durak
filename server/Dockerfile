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

# distroless instead of scratch — libc needed for sqlite3
FROM gcr.io/distroless/cc-debian12
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/server
COPY --from=build /usr/lib/x86_64-linux-gnu/libsqlite3.so* /usr/lib/x86_64-linux-gnu/

VOLUME ["/data"]
EXPOSE 8080
ENV DURAK_DB_PATH=/data/durak.db
ENV DURAK_AVATARS_DIR=/data/avatars
ENTRYPOINT ["/app/server"]
