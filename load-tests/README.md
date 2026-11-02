# Tests de charge k6

Tests de performance de l'API Task Manager. Ils sont **lancés à la main** :
aucun job CI/CD ne les déclenche automatiquement.

## Scénarios

| Fichier | Utilisateurs | Durée | Objectif | Seuil de latence |
|---|---|---|---|---|
| `smoke.js` | 1 | 30 s | Vérifier que les routes répondent | p95 < 500 ms |
| `load.js` | 10 | 1 min | Charge nominale, scénario de référence | p95 < 500 ms |
| `stress.js` | 30 | 1 min | Trouver le point de dégradation | p95 < 1500 ms |

Les trois scénarios exigent un **taux d'erreur HTTP inférieur à 1 %**
(`http_req_failed: rate<0.01`).

`common.js` regroupe la configuration et les requêtes communes aux trois
scénarios.

## Endpoints testés

Uniquement des `GET`, sur les routes réelles du projet :

- `GET /api/health` — on vérifie le statut 200 et que le corps contient
  `status: "ok"`.
- `GET /api/tasks` — on vérifie le statut 200 et que la réponse est bien un
  tableau JSON.

Aucun `POST` ni `DELETE` n'est effectué : **les tests ne modifient jamais la
base de données** de l'environnement visé.

## Lancer les tests avec Docker (sans installer k6)

Depuis la racine du dépôt, sur le serveur :

```bash
docker run --rm --network host \
  -v "$PWD/load-tests:/scripts:ro" \
  grafana/k6:latest run /scripts/smoke.js
```

Remplacez `smoke.js` par `load.js` ou `stress.js` selon le scénario.

`--network host` permet d'atteindre `http://localhost` depuis le conteneur.
Si vous préférez ne pas l'utiliser, rejoignez directement le réseau Compose et
visez le service Nginx par son nom :

```bash
docker run --rm --network task-manager_default \
  -e BASE_URL=http://frontend/api \
  -v "$PWD/load-tests:/scripts:ro" \
  grafana/k6:latest run /scripts/load.js
```

Épinglez une version de l'image (`grafana/k6:<version>`) plutôt que `latest`
si vous voulez des résultats comparables dans le temps.

## Changer la cible

`BASE_URL` désigne la racine de l'API et vaut `http://localhost/api` par
défaut.

```bash
# Avec Docker
docker run --rm --network host -e BASE_URL=https://exemple.fr/api \
  -v "$PWD/load-tests:/scripts:ro" grafana/k6:latest run /scripts/load.js

# Avec k6 installé localement
k6 run -e BASE_URL=https://exemple.fr/api load-tests/load.js
```

## Lire les résultats

k6 sort en **code 0 si tous les seuils sont respectés**, et en code 99 si au
moins un seuil est dépassé. C'est ce code retour qui fait foi.

```
█ THRESHOLDS
  http_req_duration
  ✓ 'p(95)<500' p(95)=24.43ms
  http_req_failed
  ✓ 'rate<0.01' rate=0.00%
```

Les métriques à regarder en priorité :

- **`http_req_failed`** — le taux de requêtes en échec. C'est l'indicateur le
  plus important : une application peut ralentir, elle ne doit pas renvoyer
  d'erreurs. Au-delà de 1 %, le test échoue.
- **`checks_succeeded`** — le pourcentage d'assertions validées. Il peut être
  inférieur à 100 % alors que `http_req_failed` est à 0 %, par exemple si
  l'API répond 200 avec un corps inattendu. Les deux sont complémentaires.
- **`http_req_duration` p(95)** — 95 % des requêtes sont plus rapides que
  cette valeur. On utilise le p95 plutôt que la moyenne, car une moyenne
  basse peut masquer des requêtes très lentes pour une partie des
  utilisateurs.
- **`{ endpoint:health }` et `{ endpoint:tasks }`** — le même p95, détaillé
  par route. C'est ce qui permet de savoir laquelle des deux dégrade le
  résultat global. `load.js` pose un seuil sur chacune.
- **`iterations`** et **`http_reqs`** — le volume réellement produit, utile
  pour vérifier que le test a bien généré la charge attendue.

### Quand un seuil est dépassé

Si `stress.js` échoue mais que `load.js` passe, c'est le comportement normal
d'un test de charge élevée : vous avez trouvé le point de saturation. Le
backend tourne avec un seul worker Uvicorn devant un pool de dix connexions
PostgreSQL, donc la latence augmente — les requêtes attendent une connexion
libre — avant que les erreurs n'apparaissent. C'est pour cela que le seuil
de `stress.js` est
plus permissif que celui de `load.js`.

Si `load.js` échoue, en revanche, c'est une régression à investiguer :
regardez d'abord le p95 par endpoint pour isoler la route concernée, puis les
logs avec `docker compose logs backend`.
