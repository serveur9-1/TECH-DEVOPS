#!/usr/bin/env bash
# Exécuté sur l'EC2 par GitHub Actions. Ne pas tracer les secrets.
set -euo pipefail
set +x

APP_DIR=/opt/task-manager
IMAGE_TAG=${IMAGE_TAG:?IMAGE_TAG manquant}
REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:?REGISTRY_NAMESPACE manquant}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:?POSTGRES_PASSWORD manquant}

umask 077
sudo mkdir -p "$APP_DIR/nginx"
sudo chown -R ubuntu:ubuntu "$APP_DIR"

if [ ! -f "$APP_DIR/.env" ]; then
  cat > "$APP_DIR/.env" <<EOF
POSTGRES_DB=tasks
POSTGRES_USER=tasks
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
BACKEND_IMAGE=${REGISTRY_NAMESPACE}/task-manager-backend
FRONTEND_IMAGE=${REGISTRY_NAMESPACE}/task-manager-frontend
IMAGE_TAG=${IMAGE_TAG}
EOF
  chmod 600 "$APP_DIR/.env"
fi

PREVIOUS_TAG=""
if [ -f "$APP_DIR/.current_tag" ]; then
  PREVIOUS_TAG=$(cat "$APP_DIR/.current_tag")
fi

cd "$APP_DIR"
export IMAGE_TAG
export POSTGRES_DB=tasks
export POSTGRES_USER=tasks
export POSTGRES_PASSWORD
export BACKEND_IMAGE="${REGISTRY_NAMESPACE}/task-manager-backend"
export FRONTEND_IMAGE="${REGISTRY_NAMESPACE}/task-manager-frontend"

echo "$DOCKERHUB_TOKEN" | sudo docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null

sudo docker compose -f docker-compose.prod.yml pull
sudo docker compose -f docker-compose.prod.yml up -d --no-build --remove-orphans

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
    export IMAGE_TAG="$PREVIOUS_TAG"
    sudo docker compose -f docker-compose.prod.yml up -d --no-build --remove-orphans
  fi
  sudo docker compose -f docker-compose.prod.yml ps >&2
  sudo docker compose -f docker-compose.prod.yml logs --tail 50 >&2
  exit 1
fi

printf '%s\n' "$IMAGE_TAG" > "$APP_DIR/.current_tag"
sudo docker image prune -f >/dev/null
echo "Déploiement OK $IMAGE_TAG"
