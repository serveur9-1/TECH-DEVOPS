FROM python:3.12-slim

# Logs non bufferisés, sinon ils n'apparaissent pas dans `docker logs`.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copié seul : la couche pip reste en cache tant que les dépendances ne bougent pas.
# requirements.txt ne contient que l'exécution, ni pytest ni Ruff.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py ./

RUN useradd --create-home --uid 1000 appuser \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

# 0.0.0.0 et non 127.0.0.1, sinon le conteneur est injoignable de l'extérieur.
# --proxy-headers : X-Forwarded-Proto porte le vrai schéma une fois HTTPS actif.
CMD ["uvicorn", "main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]
