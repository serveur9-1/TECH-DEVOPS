import http from "k6/http";
import { check } from "k6";

// Racine de l'API exposée par Nginx. Surchargeable :
//   k6 run -e BASE_URL=https://exemple.fr/api load.js
// Le trailing slash est retiré pour éviter une URL en //health.
const BASE_URL = (__ENV.BASE_URL || "http://localhost/api").replace(/\/+$/, "");

// Seuil commun aux trois scénarios : moins de 1 % de requêtes HTTP en échec.
export const errorThreshold = { http_req_failed: ["rate<0.01"] };

// Les deux fonctions ci-dessous n'utilisent que des GET : aucune écriture ni
// suppression, la base de l'environnement cible reste intacte.

export function checkHealth() {
  const response = http.get(`${BASE_URL}/health`, {
    tags: { endpoint: "health" },
  });

  check(response, {
    "health: statut 200": (r) => r.status === 200,
    "health: status vaut ok": (r) => {
      try {
        return r.json("status") === "ok";
      } catch (e) {
        return false;
      }
    },
  });

  return response;
}

export function checkTasks() {
  const response = http.get(`${BASE_URL}/tasks`, {
    tags: { endpoint: "tasks" },
  });

  check(response, {
    "tasks: statut 200": (r) => r.status === 200,
    "tasks: renvoie un tableau JSON": (r) => {
      try {
        return Array.isArray(r.json());
      } catch (e) {
        return false;
      }
    },
  });

  return response;
}
