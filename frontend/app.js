// Chemin relatif : Nginx redirige /api/ vers le backend FastAPI.
const API_URL = "/api";

const form = document.getElementById("task-form");
const input = document.getElementById("task-title");
const submitButton = form.querySelector("button[type=submit]");
const list = document.getElementById("task-list");
const message = document.getElementById("message");
const counter = document.getElementById("task-counter");

let messageTimer;

function showMessage(text, isSuccess = false) {
  window.clearTimeout(messageTimer);
  message.textContent = text;
  message.classList.toggle("is-success", isSuccess && text !== "");

  // Une confirmation n'a pas à rester à l'écran, contrairement à une erreur
  // que l'utilisateur doit pouvoir relire.
  if (isSuccess && text !== "") {
    messageTimer = window.setTimeout(() => showMessage(""), 2500);
  }
}

function updateCounter(count) {
  if (count === null) {
    counter.textContent = "";
    return;
  }

  counter.textContent = count === 1 ? "1 tâche" : `${count} tâches`;
}

function buildTaskItem(task) {
  const item = document.createElement("li");

  const title = document.createElement("span");
  title.className = "task-title";
  title.textContent = task.title; // textContent, et non innerHTML : évite les injections
  item.appendChild(title);

  const button = document.createElement("button");
  button.type = "button";
  button.className = "delete";
  button.textContent = "Supprimer";
  button.setAttribute("aria-label", `Supprimer la tâche ${task.title}`);
  button.addEventListener("click", () => deleteTask(task.id, button));
  item.appendChild(button);

  return item;
}

function renderPlaceholder(text) {
  // Un <ul> ne doit contenir que des <li>, d'où ce <li> plutôt qu'un <p>.
  const item = document.createElement("li");
  item.className = "empty";
  item.textContent = text;
  list.replaceChildren(item);
}

async function loadTasks() {
  try {
    const response = await fetch(`${API_URL}/tasks`);
    if (!response.ok) {
      throw new Error("Chargement impossible");
    }

    const tasks = await response.json();
    updateCounter(tasks.length);

    if (tasks.length === 0) {
      renderPlaceholder("Aucune tâche pour le moment.");
      return;
    }

    list.replaceChildren(...tasks.map(buildTaskItem));
  } catch (error) {
    updateCounter(null);
    renderPlaceholder("");
    showMessage("Impossible de contacter l'API.");
  }
}

async function createTask(title) {
  const response = await fetch(`${API_URL}/tasks`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title }),
  });

  if (response.status === 422) {
    throw new Error("Titre invalide (1 à 200 caractères).");
  }
  if (!response.ok) {
    throw new Error("Ajout impossible.");
  }
}

async function deleteTask(taskId, button) {
  button.disabled = true;
  try {
    const response = await fetch(`${API_URL}/tasks/${taskId}`, {
      method: "DELETE",
    });
    if (!response.ok) {
      throw new Error("Suppression impossible");
    }
    showMessage("Tâche supprimée.", true);
    await loadTasks();
  } catch (error) {
    button.disabled = false;
    showMessage("Suppression impossible.");
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  // Contrôle de confort uniquement : le backend revalide systématiquement.
  const title = input.value.trim();
  if (title === "") {
    showMessage("Le titre ne peut pas être vide.");
    return;
  }

  submitButton.disabled = true;
  try {
    await createTask(title);
    input.value = "";
    showMessage("Tâche ajoutée.", true);
    await loadTasks();
  } catch (error) {
    showMessage(error.message);
  } finally {
    submitButton.disabled = false;
    input.focus();
  }
});

renderPlaceholder("Chargement...");
loadTasks();
