#!/usr/bin/env bash
# Script de déploiement privilégié, installé par Ansible dans
# /usr/local/sbin/task-manager-deploy (root:root, mode 0755) et lancé par
# gha-runner via « sudo -n ». Cette copie du dépôt n'est qu'une source
# versionnée : le runner ne l'exécute jamais, sinon il pourrait modifier le
# code tournant en root.
#
# Règle : ce script ne doit lire aucun fichier modifiable par gha-runner. Un
# fichier Compose équivaut à une exécution root arbitraire (privileged,
# montage de /, ...), d'où les contrôles ci-dessous.
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 022

COMPOSE_DIR=/opt/task-manager
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.prod.yml"
ENV_FILE="$COMPOSE_DIR/.env"
NGINX_DIR="$COMPOSE_DIR/nginx"
# Servie en clair même sous HTTPS : le reste du port 80 répond 301.
HEALTH_URL=http://localhost/healthz
CONTAINERS=(task-manager-db task-manager-backend task-manager-frontend)
MAX_ATTEMPTS=20
DELAY=5

fail() {
  echo "ERREUR: $*" >&2
  exit 1
}

# On n'accepte qu'un SHA Git complet, jamais une chaîne arbitraire qui
# désignerait une image non construite par la pipeline.
[ $# -eq 1 ] || fail "usage: $(basename "$0") <sha-git-40-hex>"
IMAGE_TAG=$1
[[ $IMAGE_TAG =~ ^[0-9a-f]{40}$ ]] || fail "tag invalide: attendu 40 caractères hexadécimaux"

# Un seul de ces chemins inscriptible par gha-runner, et c'est un root complet.
# Le répertoire nginx en fait partie : il est monté dans le conteneur frontend.
for path in "$COMPOSE_DIR" "$COMPOSE_FILE" "$ENV_FILE" "$NGINX_DIR"; do
  [ -e "$path" ] || fail "$path est absent"
  if [ -n "$(find "$path" -maxdepth 0 \( ! -user root -o -perm /022 \))" ]; then
    fail "$path doit être root:root et non inscriptible par groupe/autres"
  fi
done

echo "Déploiement du tag $IMAGE_TAG"
# Exporté plutôt qu'écrit dans .env : l'environnement l'emporte sur le fichier.
export IMAGE_TAG

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

compose pull
# Ni « down » ni « -v » : les conteneurs sont recréés en place et le volume
# task-manager_db-data est conservé. --no-build garantit qu'un ajout ultérieur
# de section build: ne déclencherait pas de compilation en root.
compose up -d --no-build --remove-orphans

# Healthchecks Docker des trois conteneurs ET réponse HTTP à travers Nginx :
# le backend n'expose pas 8000, localhost:8000 serait injoignable depuis l'hôte.
echo "Vérification des conteneurs et de $HEALTH_URL"
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  healthy=1

  for container in "${CONTAINERS[@]}"; do
    status=$(docker inspect \
      -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}sans-healthcheck{{end}}' \
      "$container" 2>/dev/null || echo absent)
    if [ "$status" != healthy ]; then
      echo "  $container : $status"
      healthy=0
    fi
  done

  if [ "$healthy" -eq 1 ] && curl -fsS --max-time 5 "$HEALTH_URL" > /dev/null; then
    echo "Déploiement réussi (tentative $attempt/$MAX_ATTEMPTS)."
    compose ps
    docker image prune -f
    exit 0
  fi

  echo "Tentative $attempt/$MAX_ATTEMPTS sans succès, nouvel essai dans ${DELAY}s."
  sleep "$DELAY"
done

echo "Healthcheck en échec après $MAX_ATTEMPTS tentatives." >&2
compose ps
compose logs --tail 50
exit 1
