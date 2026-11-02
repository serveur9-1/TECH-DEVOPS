import { sleep } from "k6";
import { checkHealth, checkTasks, errorThreshold } from "./common.js";

// Charge nominale : 10 utilisateurs virtuels pendant 1 minute.
// C'est le scénario de référence du projet, celui dont les seuils doivent
// rester verts avant toute mise en production.
export const options = {
  vus: 10,
  duration: "1m",
  thresholds: {
    ...errorThreshold,
    http_req_duration: ["p(95)<500"],
    // Seuils par endpoint : permet de savoir laquelle des deux routes
    // dégrade le p95 global.
    "http_req_duration{endpoint:health}": ["p(95)<500"],
    "http_req_duration{endpoint:tasks}": ["p(95)<500"],
  },
};

export default function () {
  checkHealth();
  checkTasks();
  sleep(1);
}
