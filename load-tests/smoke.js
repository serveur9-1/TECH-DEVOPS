import { sleep } from "k6";
import { checkHealth, checkTasks, errorThreshold } from "./common.js";

// Smoke test : 1 utilisateur virtuel pendant 30 s. Ne cherche pas à charger
// l'application, seulement à confirmer que les routes répondent avant
// d'enchaîner sur une vraie montée en charge.
export const options = {
  vus: 1,
  duration: "30s",
  thresholds: {
    ...errorThreshold,
    http_req_duration: ["p(95)<500"],
  },
};

export default function () {
  checkHealth();
  checkTasks();
  sleep(1);
}
