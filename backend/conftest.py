"""Base PostgreSQL dédiée aux tests, vidée entre chaque test."""

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict

import main

# Jamais la base de l'application. La CI surcharge cette variable.
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/tasks_test",
)


def _ensure_test_database():
    params = conninfo_to_dict(TEST_DATABASE_URL)
    dbname = params.pop("dbname", None)
    if not dbname:
        raise RuntimeError("TEST_DATABASE_URL doit nommer une base de données")

    with psycopg.connect(**params, dbname="postgres", autocommit=True) as connection:
        exists = connection.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (dbname,)
        ).fetchone()
        if not exists:
            # Un nom d'objet ne peut pas être un paramètre lié.
            connection.execute(
                sql.SQL("CREATE DATABASE {}").format(sql.Identifier(dbname))
            )


@pytest.fixture(scope="session")
def _api(monkeypatch_session):
    _ensure_test_database()
    monkeypatch_session.setenv("DATABASE_URL", TEST_DATABASE_URL)
    with TestClient(main.app) as test_client:
        yield test_client


@pytest.fixture(scope="session")
def monkeypatch_session():
    """`monkeypatch` est limité à la portée fonction, il en faut un ici qui
    vive aussi longtemps que l'application de test."""
    patcher = pytest.MonkeyPatch()
    yield patcher
    patcher.undo()


@pytest.fixture
def client(_api):
    """TRUNCATE plutôt qu'une base jetable par test : même isolation, pour une
    fraction du coût."""
    with psycopg.connect(TEST_DATABASE_URL, autocommit=True) as connection:
        connection.execute("TRUNCATE tasks RESTART IDENTITY")
    return _api
