"""Task Manager API - FastAPI + PostgreSQL (psycopg 3)."""

import os
import time
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, HTTPException
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout
from pydantic import BaseModel, Field

DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/tasks"

TITLE_MAX_LENGTH = 200

# Le conteneur backend peut démarrer avant que PostgreSQL n'accepte les
# connexions. Compose attend déjà son healthcheck, mais une base distante ou un
# redémarrage du serveur ne passent pas par là.
STARTUP_ATTEMPTS = 30
STARTUP_DELAY_SECONDS = 1

# Délai court sur /ready : un readiness probe doit répondre vite, quitte à
# déclarer le service indisponible.
READY_TIMEOUT_SECONDS = 2

SCHEMA = f"""
CREATE TABLE IF NOT EXISTS tasks (
    id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title TEXT NOT NULL
          CHECK (char_length(title) BETWEEN 1 AND {TITLE_MAX_LENGTH})
)
"""

_pool: ConnectionPool | None = None


def database_url():
    # Relu à chaque appel, pour que les tests puissent surcharger DATABASE_URL.
    return os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL)


def get_pool():
    if _pool is None:
        raise RuntimeError("pool de connexions non initialisé")
    return _pool


class TaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=TITLE_MAX_LENGTH)


class Task(BaseModel):
    id: int
    title: str


def create_pool():
    return ConnectionPool(
        conninfo=database_url(),
        min_size=1,
        max_size=10,
        # dict_row : les lignes arrivent en dictionnaires, comme sqlite3.Row.
        # autocommit : toutes les requêtes de cette API tiennent en un seul
        # ordre SQL, inutile d'ouvrir une transaction et de garder une
        # connexion « idle in transaction » le temps du rendu de la réponse.
        kwargs={"autocommit": True, "row_factory": dict_row},
        open=False,
    )


def wait_for_database(pool):
    """Boucle jusqu'à ce que PostgreSQL réponde, ou abandonne le démarrage."""
    last_error = None
    for _ in range(STARTUP_ATTEMPTS):
        try:
            with pool.connection(timeout=STARTUP_DELAY_SECONDS) as connection:
                connection.execute("SELECT 1")
            return
        except (psycopg.Error, PoolTimeout) as error:
            last_error = error
            time.sleep(STARTUP_DELAY_SECONDS)

    raise RuntimeError(
        f"base de données injoignable après {STARTUP_ATTEMPTS} tentatives"
    ) from last_error


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global _pool

    _pool = create_pool()
    _pool.open()
    wait_for_database(_pool)
    # Schéma créé au démarrage : le projet n'utilise pas d'outil de migration.
    with _pool.connection() as connection:
        connection.execute(SCHEMA)

    yield

    _pool.close()
    _pool = None


app = FastAPI(title="Task Manager API", version="2.0.0", lifespan=lifespan)


@app.get("/health")
def health():
    """Liveness : l'application répond."""
    return {"status": "ok"}


@app.get("/ready")
def ready():
    """Readiness : la base de données est accessible."""
    try:
        with get_pool().connection(timeout=READY_TIMEOUT_SECONDS) as connection:
            connection.execute("SELECT 1")
    except (psycopg.Error, PoolTimeout) as error:
        raise HTTPException(status_code=503, detail="database unavailable") from error
    return {"status": "ready"}


@app.get("/tasks", response_model=list[Task])
def list_tasks():
    """Liste les tâches, la plus récente en premier."""
    with get_pool().connection() as connection:
        return connection.execute(
            "SELECT id, title FROM tasks ORDER BY id DESC"
        ).fetchall()


@app.post("/tasks", response_model=Task, status_code=201)
def create_task(task: TaskIn):
    """Crée une tâche ; le titre est débarrassé des espaces superflus."""
    title = task.title.strip()
    # min_length=1 laisse passer un titre composé uniquement d'espaces.
    if not title:
        raise HTTPException(status_code=422, detail="title must not be empty")

    with get_pool().connection() as connection:
        # RETURNING plutôt qu'un lastrowid : PostgreSQL rend l'identifiant
        # attribué dans la même requête, sans aller-retour supplémentaire.
        return connection.execute(
            "INSERT INTO tasks (title) VALUES (%s) RETURNING id, title", (title,)
        ).fetchone()


@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int):
    """Supprime une tâche, 404 si elle n'existe pas."""
    with get_pool().connection() as connection:
        cursor = connection.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="task not found")
