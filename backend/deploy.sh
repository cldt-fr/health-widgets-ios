#!/bin/sh
# Optional helper: deploy (or update) the server on a remote machine over SSH.
#
#   DEPLOY_HOST=user@my-server DEPLOY_DIR=/opt/health-widgets ./deploy.sh
#
# The values can also live in a git-ignored `.deploy.env` next to this script.
# Sources are copied with rsync, then the image is rebuilt and the container restarted.
# On the remote machine, `.env`, `data/` and `docker-compose.override.yml` (your own
# reverse-proxy network, ports...) are never touched.
#
# To pick up a new python-garminconnect release first:
#   uv lock --upgrade-package garminconnect && uv run pytest && ./deploy.sh
set -eu

cd "$(dirname "$0")"
[ -f .deploy.env ] && . ./.deploy.env
: "${DEPLOY_HOST:?Set DEPLOY_HOST (e.g. user@my-server)}"
: "${DEPLOY_DIR:?Set DEPLOY_DIR (e.g. /opt/health-widgets)}"

echo "→ Copying sources to $DEPLOY_HOST:$DEPLOY_DIR"
ssh "$DEPLOY_HOST" "mkdir -p '$DEPLOY_DIR'"
rsync -az --delete \
  --exclude '.venv/' --exclude 'data/' --exclude '.env' --exclude '.deploy.env' \
  --exclude 'docker-compose.override.yml' \
  --exclude '.pytest_cache/' --exclude '.ruff_cache/' --exclude '__pycache__/' \
  ./ "$DEPLOY_HOST:$DEPLOY_DIR/"

echo "→ Building and restarting"
ssh "$DEPLOY_HOST" "cd '$DEPLOY_DIR' && docker compose up -d --build && docker image prune -f >/dev/null"

echo "→ Health check"
sleep 5
ssh "$DEPLOY_HOST" "cd '$DEPLOY_DIR' && docker compose exec -T api python -c \
  \"import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health').read().decode())\""
