#!/usr/bin/env bash
# Exécuté sur l'EC2 par le runner self-hosted. Pas de build, pas de tests.
set -euo pipefail
set +x

APP_DIR=/opt/task-manager
SRC=${GITHUB_WORKSPACE:-.}
IMAGE_TAG=${IMAGE_TAG:?IMAGE_TAG manquant}

umask 077
sudo mkdir -p "$APP_DIR/nginx"

if [ ! -f "$APP_DIR/.env" ]; then
  echo "/opt/task-manager/.env introuvable." >&2
  echo "Le premier déploiement manuel doit déjà l'avoir créé. On ne l'écrase pas." >&2
  exit 1
fi

install -m 644 "$SRC/docker-compose.prod.yml" "$APP_DIR/docker-compose.prod.yml"
install -m 644 "$SRC/nginx/default.conf" "$APP_DIR/nginx/default.conf"

PREVIOUS_TAG=""
if [ -f "$APP_DIR/.current_tag" ]; then
  PREVIOUS_TAG=$(cat "$APP_DIR/.current_tag")
fi

cd "$APP_DIR"

if [ -n "${DOCKERHUB_TOKEN:-}" ] && [ -n "${DOCKERHUB_USERNAME:-}" ]; then
  echo "$DOCKERHUB_TOKEN" | sudo docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null
fi

compose() {
  sudo env IMAGE_TAG="$IMAGE_TAG" docker compose --env-file "$APP_DIR/.env" -f docker-compose.prod.yml "$@"
}

compose pull
# --no-build : les images viennent de Docker Hub, pas de build local (1 Gio RAM).
# Pas de down, pas de -v : le volume PostgreSQL et .env restent.
compose up -d --no-build --remove-orphans

ok=0
for _ in $(seq 1 20); do
  if curl -fsS --max-time 5 http://127.0.0.1/healthz >/dev/null \
    && curl -fsS --max-time 5 http://127.0.0.1/api/health >/dev/null \
    && curl -fsS --max-time 5 http://127.0.0.1/api/ready >/dev/null; then
    ok=1
    break
  fi
  sleep 5
done

if [ "$ok" -ne 1 ]; then
  echo "Healthcheck en échec (healthz / api/health / api/ready)." >&2
  if [ -n "$PREVIOUS_TAG" ] && [ "$PREVIOUS_TAG" != "$IMAGE_TAG" ]; then
    echo "Rollback vers $PREVIOUS_TAG"
    IMAGE_TAG="$PREVIOUS_TAG"
    compose up -d --no-build --remove-orphans
  fi
  compose ps >&2
  sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' >&2
  compose logs --tail 50 >&2
  exit 1
fi

printf '%s\n' "$IMAGE_TAG" > "$APP_DIR/.current_tag"
sudo docker image prune -f >/dev/null
echo "Déploiement OK $IMAGE_TAG"
