# Contexte de build = racine du projet, pour copier frontend/ et nginx/.
FROM nginx:alpine

# nginx:alpine embarque des paquets OS (brotli, curl) dont les CVE ont déjà
# un correctif dans Alpine. Sans upgrade, Trivy bloque la publication.
RUN apk upgrade --no-cache

# En production un montage root:root remplace ce répertoire pour passer en TLS.
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

COPY frontend/index.html frontend/style.css frontend/app.js frontend/favicon.svg \
     /usr/share/nginx/html/

EXPOSE 80
EXPOSE 443
