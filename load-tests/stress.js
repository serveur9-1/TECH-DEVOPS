import { sleep } from "k6";
import { checkHealth, checkTasks, errorThreshold } from "./common.js";

// Charge élevée : 30 utilisateurs virtuels pendant 1 minute.
// Objectif : trouver le point de dégradation, pas valider une performance.
// Le seuil de latence est volontairement plus permissif que sur la charge
// nominale, car le backend tourne avec un seul worker Uvicorn devant un pool
// de dix connexions PostgreSQL. En revanche le taux d'erreur reste exigeant :
// l'application doit ralentir, jamais renvoyer d'erreurs.
export const options = {
  vus: 30,
  duration: "1m",
  thresholds: {
    ...errorThreshold,
    http_req_duration: ["p(95)<1500"],
  },
};

export default function () {
  checkHealth();
  checkTasks();
  sleep(1);
}
