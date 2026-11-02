"""Socle commun des tests : une base PostgreSQL dédiée, vidée entre chaque test."""

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict

import main

# Base dédiée aux tests, jamais celle de l'application. La CI surcharge cette
# variable pour viser le service PostgreSQL du job.
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/tasks_test",
)


def _ensure_test_database():
    """Crée la base de test si elle manque, pour que `pytest` marche sans
    préparation manuelle sur un poste de développement."""
    params = conninfo_to_dict(TEST_DATABASE_URL)
    dbname = params.pop("dbname", None)
    if not dbname:
        raise RuntimeError("TEST_DATABASE_URL doit nommer une base de données")

    # CREATE DATABASE est interdit dans une transaction, d'où l'autocommit.
    with psycopg.connect(**params, dbname="postgres", autocommit=True) as connection:
        exists = connection.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (dbname,)
        ).fetchone()
        if not exists:
            # Un nom d'objet ne peut pas être un paramètre lié : on passe par
            # sql.Identifier, qui échappe correctement.
            connection.execute(
                sql.SQL("CREATE DATABASE {}").format(sql.Identifier(dbname))
            )


@pytest.fixture(scope="session")
def _api(monkeypatch_session):
    """Application démarrée une seule fois : le `lifespan` ouvre le pool et
    crée le schéma, inutile de le refaire à chaque test."""
    _ensure_test_database()
    monkeypatch_session.setenv("DATABASE_URL", TEST_DATABASE_URL)
    with TestClient(main.app) as test_client:
        yield test_client


@pytest.fixture(scope="session")
def monkeypatch_session():
    """`monkeypatch` est limité à la portée fonction ; il en faut un ici qui
    vive aussi longtemps que l'application de test."""
    patcher = pytest.MonkeyPatch()
    yield patcher
    patcher.undo()


@pytest.fixture
def client(_api):
    """Base vide avant chaque test. TRUNCATE plutôt qu'une base jetable par
    test : même isolation, pour une fraction du coût."""
    with psycopg.connect(TEST_DATABASE_URL, autocommit=True) as connection:
        connection.execute("TRUNCATE tasks RESTART IDENTITY")
    return _api
