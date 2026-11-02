"""Tests automatisés de l'API Task Manager."""

import pytest


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_list_tasks_is_empty_at_start(client):
    response = client.get("/tasks")
    assert response.status_code == 200
    assert response.json() == []


def test_create_task(client):
    response = client.post("/tasks", json={"title": "Acheter du pain"})
    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "Acheter du pain"
    assert isinstance(body["id"], int)


def test_created_task_appears_in_list(client):
    client.post("/tasks", json={"title": "Ecrire le Dockerfile"})
    response = client.get("/tasks")
    assert response.status_code == 200
    assert [task["title"] for task in response.json()] == ["Ecrire le Dockerfile"]


def test_tasks_are_listed_most_recent_first(client):
    for title in ["Premiere", "Deuxieme", "Troisieme"]:
        client.post("/tasks", json={"title": title})

    titles = [task["title"] for task in client.get("/tasks").json()]
    assert titles == ["Troisieme", "Deuxieme", "Premiere"]


def test_create_task_trims_whitespace(client):
    response = client.post("/tasks", json={"title": "  Relire le README  "})
    assert response.status_code == 201
    assert response.json()["title"] == "Relire le README"


@pytest.mark.parametrize("title", ["", "   ", "x" * 201])
def test_create_task_rejects_invalid_title(client, title):
    response = client.post("/tasks", json={"title": title})
    assert response.status_code == 422


def test_create_task_rejects_missing_title(client):
    response = client.post("/tasks", json={})
    assert response.status_code == 422


def test_delete_task(client):
    task_id = client.post("/tasks", json={"title": "A supprimer"}).json()["id"]

    response = client.delete(f"/tasks/{task_id}")
    assert response.status_code == 204

    assert client.get("/tasks").json() == []


def test_delete_unknown_task_returns_404(client):
    response = client.delete("/tasks/999")
    assert response.status_code == 404


def test_identifiers_are_not_reused_after_delete(client):
    first_id = client.post("/tasks", json={"title": "Premiere"}).json()["id"]
    client.delete(f"/tasks/{first_id}")

    second_id = client.post("/tasks", json={"title": "Deuxieme"}).json()["id"]
    assert second_id != first_id
