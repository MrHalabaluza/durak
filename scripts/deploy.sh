#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

if [ -f "$ROOT/.env" ]; then
  set -a; source "$ROOT/.env"; set +a
fi

: "${REMOTE_HOST:?REMOTE_HOST is not set — add it to .env}"
: "${REMOTE_DIR:=~/durak}"
: "${PORT:=8080}"

echo "→ Syncing logic/ and server/ to $REMOTE_HOST:$SSH_PORT:$REMOTE_DIR ..."
rsync -e "ssh -p $SSH_PORT" -az --delete \
  --exclude='.git' --exclude='.dart_tool' --exclude='build' \
  "$ROOT/logic/"  "$REMOTE_HOST:$REMOTE_DIR/logic/"
rsync -e "ssh -p $SSH_PORT" -az --delete \
  --exclude='.git' --exclude='.dart_tool' --exclude='build' \
  "$ROOT/server/" "$REMOTE_HOST:$REMOTE_DIR/server/"

echo "→ Building and restarting Docker container on $REMOTE_HOST ..."
ssh -p "$SSH_PORT" "$REMOTE_HOST" bash <<EOF
  set -e
  cd "$REMOTE_DIR"
  docker build -f server/Dockerfile -t durak-server .
  docker rm -f durak-server 2>/dev/null || true
  docker run -d --restart=unless-stopped -p 127.0.0.1:$PORT:8080 --name durak-server durak-server
  echo "Container started, accessible on port $PORT"
EOF

echo "✓ Done."
