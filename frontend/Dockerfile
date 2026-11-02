# Contexte de build = racine du projet, pour copier frontend/ et nginx/.
FROM nginx:alpine

# Configuration HTTP par défaut. En production, un montage root:root place sa
# variante HTTPS par-dessus ce répertoire sans reconstruire l'image.
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

COPY frontend/index.html frontend/style.css frontend/app.js frontend/favicon.svg \
     /usr/share/nginx/html/

EXPOSE 80
EXPOSE 443
