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

# Stage sqlite3 under a fixed path so the COPY below is arch-neutral.
# dpkg-architecture resolves the multiarch tuple (x86_64-linux-gnu / aarch64-linux-gnu / …).
RUN ARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH) && \
    mkdir -p /sqlite3-out/usr/lib/$ARCH && \
    cp -a /usr/lib/$ARCH/libsqlite3.so* /sqlite3-out/usr/lib/$ARCH/

# distroless instead of scratch — libc needed for sqlite3
FROM gcr.io/distroless/cc-debian12
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/server
COPY --from=build /sqlite3-out/ /

VOLUME ["/data"]
EXPOSE 8080
ENV DURAK_DB_PATH=/data/durak.db
ENV DURAK_AVATARS_DIR=/data/avatars
ENTRYPOINT ["/app/server"]
