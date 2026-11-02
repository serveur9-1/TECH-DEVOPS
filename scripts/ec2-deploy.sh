#!/usr/bin/env bash
# Exécuté sur l'EC2 par GitHub Actions. Ne pas tracer les secrets.
set -euo pipefail
set +x

APP_DIR=/opt/task-manager
IMAGE_TAG=${IMAGE_TAG:?IMAGE_TAG manquant}
REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:?REGISTRY_NAMESPACE manquant}

umask 077
sudo mkdir -p "$APP_DIR/nginx"
sudo chown -R ubuntu:ubuntu "$APP_DIR"

if [ ! -f "$APP_DIR/.env" ]; then
  password=$(openssl rand -hex 24)
  cat > "$APP_DIR/.env" <<EOF
POSTGRES_DB=tasks
POSTGRES_USER=tasks
POSTGRES_PASSWORD=${password}
BACKEND_IMAGE=${REGISTRY_NAMESPACE}/task-manager-backend
FRONTEND_IMAGE=${REGISTRY_NAMESPACE}/task-manager-frontend
EOF
  chmod 600 "$APP_DIR/.env"
  unset password
fi

PREVIOUS_TAG=""
if [ -f "$APP_DIR/.current_tag" ]; then
  PREVIOUS_TAG=$(cat "$APP_DIR/.current_tag")
fi

cd "$APP_DIR"

echo "$DOCKERHUB_TOKEN" | sudo docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null

compose() {
  sudo env IMAGE_TAG="$IMAGE_TAG" docker compose --env-file "$APP_DIR/.env" -f docker-compose.prod.yml "$@"
}

compose pull
compose up -d --no-build --remove-orphans

ok=0
for _ in $(seq 1 20); do
  if curl -fsS --max-time 5 http://127.0.0.1/healthz >/dev/null \
    && curl -fsS --max-time 5 http://127.0.0.1/api/health >/dev/null; then
    ok=1
    break
  fi
  sleep 5
done

if [ "$ok" -ne 1 ]; then
  echo "Healthcheck en échec." >&2
  if [ -n "$PREVIOUS_TAG" ] && [ "$PREVIOUS_TAG" != "$IMAGE_TAG" ]; then
    echo "Rollback vers $PREVIOUS_TAG"
    IMAGE_TAG="$PREVIOUS_TAG"
    compose up -d --no-build --remove-orphans
  fi
  compose ps >&2
  compose logs --tail 50 >&2
  exit 1
fi

printf '%s\n' "$IMAGE_TAG" > "$APP_DIR/.current_tag"
sudo docker image prune -f >/dev/null
echo "Déploiement OK $IMAGE_TAG"
