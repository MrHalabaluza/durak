# Build from repo root:
#   docker build -f server/Dockerfile -t durak-server .

FROM dart:stable AS build

WORKDIR /app/server

# logic/ and protocol/ are local path dependencies — must be available during pub get
COPY logic/ /app/logic/
COPY protocol/ /app/protocol/

COPY server/pubspec.yaml server/pubspec.lock* ./
RUN dart pub get --no-example

COPY server/ ./
RUN dart compile exe bin/server.dart -o bin/server

# Stage sqlite3 under a fixed path so the COPY below is arch-neutral.
# dart:stable has no dpkg-architecture; resolve the lib dir via find instead.
RUN LIB_DIR=$(dirname "$(find /usr/lib -name 'libsqlite3.so.0' | head -1)") && \
    mkdir -p "/sqlite3-out${LIB_DIR}" && \
    cp -a "${LIB_DIR}"/libsqlite3.so* "/sqlite3-out${LIB_DIR}/" && \
    ln -sf libsqlite3.so.0 "/sqlite3-out${LIB_DIR}/libsqlite3.so"

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
