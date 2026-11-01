#!/bin/bash
# Runs ON the server: deploys one commit of the Health Widgets repository with Docker
# Compose. Designed as the forced command of a restricted SSH key used by CI, so the key
# can only ask for a deployment, never run anything else:
#
#   restrict,command="HW_APP_DIR=/opt/health-widgets /usr/local/sbin/health-widgets-deploy",from="100.64.0.0/10,fd7a:115c:a1e0::/48" ssh-ed25519 AAAA... github-actions
#
# The client picks the commit: `ssh server "deploy <40-character sha>"` (anything else
# deploys main). Sources come from the public repository, not from the client.
#
# Settings (environment): HW_APP_DIR (required): the compose project directory, where
# .env, data/ and docker-compose.override.yml are kept untouched. HW_REPO: repository to
# deploy. HW_SRC_DIR: where the repository is cloned.
set -euo pipefail

REPO="${HW_REPO:-https://github.com/cldt-fr/health-widgets-ios.git}"
APP_DIR="${HW_APP_DIR:?HW_APP_DIR is required}"
SRC_DIR="${HW_SRC_DIR:-/var/lib/health-widgets/src}"

request="${SSH_ORIGINAL_COMMAND:-${1:-}}"
target="origin/main"
if [[ "$request" =~ ^deploy\ ([0-9a-f]{40})$ ]]; then
  target="${BASH_REMATCH[1]}"
fi

exec 9>/var/lock/health-widgets-deploy.lock
flock -w 600 9

if [[ ! -d "$SRC_DIR/.git" ]]; then
  mkdir -p "$(dirname "$SRC_DIR")"
  git clone --quiet "$REPO" "$SRC_DIR"
fi
git -C "$SRC_DIR" fetch --quiet --prune origin
git -C "$SRC_DIR" checkout --quiet --force --detach "$target"
echo "→ Deploying $(git -C "$SRC_DIR" log -1 --format='%h %s')"

mkdir -p "$APP_DIR"
rsync -a --delete \
  --exclude '.venv/' --exclude 'data/' --exclude '.env' --exclude '.deploy.env' \
  --exclude 'docker-compose.override.yml' \
  --exclude '.pytest_cache/' --exclude '.ruff_cache/' --exclude '__pycache__/' \
  "$SRC_DIR/backend/" "$APP_DIR/"

cd "$APP_DIR"
docker compose up -d --build --remove-orphans
docker image prune -f >/dev/null

for _ in $(seq 1 30); do
  if docker compose exec -T api python -c \
    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)" 2>/dev/null; then
    echo "✓ API healthy"
    exit 0
  fi
  sleep 2
done
echo "✗ The API did not become healthy:"
docker compose logs --tail 40 api
exit 1
