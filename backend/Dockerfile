FROM python:3.12-slim

# Logs non bufferisés, sinon ils n'apparaissent pas dans `docker logs`.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copié seul : la couche pip reste en cache tant que les dépendances ne bougent pas.
# requirements.txt ne contient que l'exécution, pas pytest : l'image embarque
# le strict nécessaire, ce qui réduit d'autant la surface analysée par Trivy.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py ./

# Plus de volume à préparer depuis que les données vivent dans PostgreSQL :
# l'application n'écrit plus rien sur son propre système de fichiers.
RUN useradd --create-home --uid 1000 appuser \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

# 0.0.0.0 et non 127.0.0.1, sinon le conteneur est injoignable de l'extérieur.
# --proxy-headers : l'application est derrière Nginx, c'est X-Forwarded-Proto
# qui porte le vrai schéma une fois HTTPS activé. L'adresse de confiance est
# ouverte car le port 8000 n'est joignable que sur le réseau privé Compose.
CMD ["uvicorn", "main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]
