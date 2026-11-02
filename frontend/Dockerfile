# Contexte de build = racine du projet, pour copier frontend/ et nginx/.
FROM nginx:alpine

# En production un montage root:root remplace ce répertoire pour passer en TLS.
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

COPY frontend/index.html frontend/style.css frontend/app.js frontend/favicon.svg \
     /usr/share/nginx/html/

EXPOSE 80
EXPOSE 443
