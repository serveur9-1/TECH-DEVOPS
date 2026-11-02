# Task Manager

Application de gestion de tâches servant de support à une chaîne DevOps
complète : API FastAPI, base PostgreSQL, interface en JavaScript natif, le tout
conteneurisé, provisionné par Terraform, configuré par Ansible et déployé à
chaque push.

Pas d'ORM, pas de framework frontend, pas d'étape de build côté navigateur.

## Technologies

| Brique | Choix |
|---|---|
| API | FastAPI + Uvicorn |
| Base de données | PostgreSQL 17, pilote psycopg 3 |
| Frontend | HTML/CSS/JavaScript natif |
| Serveur web | Nginx (`nginx:alpine`) |
| Conteneurs | Docker Compose |
| Infrastructure | Terraform (AWS) |
| Configuration | Ansible |
| CI/CD | GitHub Actions |
| Sécurité | Trivy |
| Certificats | Let's Encrypt (certbot) |
| Tests | pytest, k6 |

## Architecture

Trois outils se partagent le travail. Terraform crée le réseau et la machine.
Ansible configure le serveur. GitHub Actions ne fait que remplacer des images.

```
Terraform ──► VPC public + IGW + EC2 + SG + IP fixe (EIP)
                   │
Ansible ──────────►│ Docker, /opt/task-manager, secrets, certificat TLS
                   │
GitHub Actions ───►│ docker compose pull && up -d
```

Le réseau AWS, créé même sur un compte sans VPC par défaut :

```
 Internet
    │  80/443 ouverts ; 22 limité à ssh_allowed_cidrs
    ▼
 EIP (IP publique fixe)
    │
 Internet Gateway
    │
 VPC 10.0.0.0/16
    └── subnet public 10.0.1.0/24 ──► route 0.0.0.0/0 → IGW
            │
            └── EC2 Ubuntu 24.04  t3.micro  IMDSv2  disque gp3 chiffré
```

L'application sur cette instance :

```
                         Navigateur
                             │
                             │  80 (HTTP) ou 443 (HTTPS, le 80 redirige)
                             ▼
 ┌─── EC2 Ubuntu 24.04 ──────────────────────────────────────┐
 │                                                           │
 │  ┌──────────────────┐         ┌──────────────────────┐    │
 │  │ frontend         │  /api/  │ backend              │    │
 │  │ nginx:alpine     │────────►│ FastAPI + Uvicorn    │    │
 │  │ 80 et 443        │  proxy  │ port 8000 non publié │    │
 │  │ HTML / CSS / JS  │         │ utilisateur non-root │    │
 │  └──────────────────┘         └──────────┬───────────┘    │
 │        réseau privé Docker Compose       │ psycopg        │
 │                                          ▼                │
 │                            ┌─────────────────────────┐    │
 │                            │ db — postgres:17-alpine │    │
 │                            │ port 5432 non publié    │    │
 │                            │ volume nommé            │    │
 │                            └─────────────────────────┘    │
 └───────────────────────────────────────────────────────────┘
```

Seul Nginx est joignable depuis Internet. Le backend et PostgreSQL sont
déclarés avec `expose` et non `ports` : ils n'existent que sur le réseau privé
Compose.

Le JavaScript appelle `/api/tasks` en chemin relatif. Nginx reconnaît le
préfixe `/api/` et le **retire** avant de transmettre, donc FastAPI reçoit
`/tasks`. Une seule origine côté navigateur, donc pas de CORS à configurer et
aucune URL d'API codée en dur dans le frontend.

### Structure

```
backend/        main.py, conftest.py, test_main.py (14 tests), Dockerfile
frontend/       index.html, style.css, app.js, Dockerfile Nginx
nginx/          default.conf — reverse proxy et en-têtes de sécurité
terraform/      VPC public, EC2, groupe de sécurité, IP fixe
ansible/        playbook de configuration et gabarits
deploy/         script de déploiement privilégié et règle sudoers
load-tests/     scripts k6
docker-compose.yml       développement local, construit les images
docker-compose.prod.yml  production, utilise les images publiées
.github/workflows/ci-cd.yml
```

Le fichier Compose de production vit sur le serveur, dans
`/opt/task-manager`, et appartient à root.

## Lancer en local

```bash
docker compose up --build
```

L'application répond sur <http://localhost>. Aucune configuration préalable :
`docker-compose.yml` fournit des valeurs de repli pour la base. Copiez
`.env.example` en `.env` pour les changer.

`docker compose down` conserve les tâches, `down -v` les supprime.

Sans Docker, il faut un PostgreSQL joignable :

```bash
cd backend
pip install -r requirements-dev.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/tasks
uvicorn main:app --reload --port 8000
```

### Endpoints

Préfixés par `/api` lorsqu'on passe par Nginx.

| Méthode | Route | Rôle |
|---|---|---|
| GET | `/health` | l'application répond |
| GET | `/ready` | la base est accessible |
| GET | `/tasks` | liste, les plus récentes d'abord |
| POST | `/tasks` | crée une tâche, titre de 1 à 200 caractères |
| DELETE | `/tasks/{id}` | supprime, 404 si inconnue |

```bash
curl http://localhost/api/health
curl -X POST http://localhost/api/tasks \
  -H 'Content-Type: application/json' -d '{"title":"Ma tâche"}'
```

Requêtes SQL paramétrées. Les titres sont validés deux fois, par Pydantic puis
par une contrainte `CHECK` en base : un titre vide ou composé uniquement
d'espaces repart en 422.

## Tests

14 tests pytest, exécutés contre un vrai PostgreSQL plutôt qu'un substitut, de
sorte que le SQL testé soit celui qui part en production. Chaque test démarre
sur une table vide.

```bash
cd backend
pip install -r requirements-dev.txt
python -m pytest -v
```

La base de test est créée au premier lancement. `TEST_DATABASE_URL` permet de
viser un autre serveur.

Trois scénarios k6 dans `load-tests/`, détaillés dans le README de ce
répertoire. Ils ne font que des `GET`.

## Déployer

### Provisionner

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # puis renseigner votre IP
terraform init
terraform apply
```

Une instance Ubuntu 24.04 dans un VPC créé par Terraform (subnet public +
Internet Gateway), une IP fixe, et un groupe de sécurité qui n'ouvre que 80,
443 et 22. Ce dernier est limité à vos adresses :
une règle de validation refuse `0.0.0.0/0`. Disque racine chiffré, IMDSv2
obligatoire, AMI résolue dynamiquement auprès de Canonical.

### Configurer

```bash
cd ansible
cp inventory.ini.example inventory.ini   # y mettre la sortie public_ip
ansible-playbook playbook.yml
```

Le playbook installe Docker depuis le dépôt officiel, crée `/opt/task-manager`
en root:root, tire un mot de passe PostgreSQL aléatoire au premier passage,
dépose le fichier Compose, installe le script de déploiement et démarre la
pile. Il n'utilise que des modules d'`ansible-core` et il est idempotent.

### Activer HTTPS

Prérequis : un enregistrement DNS A pointant déjà vers l'IP de la VM. Sans
lui, la validation échoue et l'application reste en HTTP, ce qui est le
comportement par défaut.

```bash
ansible-playbook playbook.yml \
  -e domain=exemple.fr -e letsencrypt_email=vous@exemple.fr
```

Le certificat est demandé en mode webroot, pas standalone : Nginx garde le
port 80 et le service n'est pas coupé pendant la validation. Le playbook
bascule ensuite la configuration, ajoute HSTS, et pose une tâche cron qui
renouvelle le certificat deux fois par jour puis recharge Nginx.

### Brancher le déploiement continu

Le déploiement tourne sur un runner GitHub Actions auto-hébergé installé sur la
VM, labels `self-hosted, Linux, X64, app-deploy`. C'est lui qui sort vers
GitHub, donc aucun port entrant à ouvrir pour la CI.

À configurer dans le dépôt :

| Type | Nom |
|---|---|
| Variable | `REGISTRY_NAMESPACE` |
| Variable | `DEPLOY_ENABLED` (`true` pour activer) |
| Secret | `DOCKERHUB_USERNAME` |
| Secret | `DOCKERHUB_TOKEN` |

Tant que `DEPLOY_ENABLED` est absente, le job est ignoré sans faire échouer la
pipeline.

## CI/CD

```
 git push
    │
    ├── Pull Request ──► lint ─┐
    │                   tests ─┼─► build ──► Trivy image ──► fin
    │                   Trivy ─┘   (rien n'est publié, aucun secret)
    │
    └── push main ─────► lint, tests, Trivy ──► build ──► Trivy image
                                                    │
                                     registre ◄─────┤  latest + SHA
                                                    │
                                     runner ◄───────┘
                              compose pull, up -d, healthchecks
```

Le job `lint` passe Ruff sur le Python, Hadolint sur les deux Dockerfile,
`terraform fmt` et `terraform validate`, et un contrôle syntaxique du playbook.
Le job `test` démarre un service PostgreSQL et joue les 14 tests.

Le job `security` lance Trivy sur tout le dépôt avec ses trois analyseurs :
dépendances, secrets, et mauvaises configurations dans les Dockerfile, les
fichiers Compose et le code Terraform. Le rapport part dans l'onglet Security
au format SARIF. La pipeline n'échoue que sur une vulnérabilité critique
disposant d'un correctif : sans correctif publié, l'alerte n'est pas
actionnable et bloquerait toutes les livraisons.

Chaque image est ensuite construite, chargée localement, analysée par Trivy,
et publiée seulement si l'analyse passe. Le cache de build est réutilisé entre
les deux étapes, donc l'image publiée est exactement celle qui a été analysée.

Le déploiement utilise le tag SHA, jamais `latest`. Un retour arrière consiste
à redéployer un SHA antérieur.

## Sécurité

Le compte qui déploie, `gha-runner`, n'appartient pas au groupe `docker` :
en faire partie équivaut à un accès root. Il ne dispose que d'une règle
sudoers autorisant une seule commande, `/usr/local/sbin/task-manager-deploy`.

Ce script se protège lui-même. Il refuse de démarrer si le fichier Compose de
production, le fichier d'environnement ou le répertoire de configuration Nginx
n'appartiennent pas à root, ou s'ils sont modifiables par quelqu'un d'autre :
un fichier Compose équivaut à une exécution root arbitraire. Son seul argument
doit être un SHA de 40 caractères hexadécimaux, ce qui interdit de déployer une
image venue d'ailleurs que du pipeline. Le job de déploiement ne fait d'ailleurs
aucun `checkout`.

Le reste tient en quelques points :

- Mot de passe PostgreSQL généré sur le serveur, dans `/opt/task-manager/.env`
  en mode 0600. Aucun secret dans le dépôt.
- Backend non-root, `cap_drop: ALL` et `no-new-privileges`.
- Nginx masque sa version et pose `X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, `Permissions-Policy` et une CSP stricte, possible parce
  que la page n'a ni script ni style en ligne. HSTS s'y ajoute en HTTPS.
- Corps de requête plafonné à 64 ko.
- Dépendances Python épinglées à la version exacte ; `requirements.txt` ne
  contient que l'exécution, donc ni pytest ni Ruff ne partent en production.
- `.gitignore` exclut les états Terraform, l'inventaire Ansible, les clés
  privées et les certificats.

## Notes sur la migration vers PostgreSQL

Le portage depuis SQLite a demandé plus qu'un changement de pilote :
placeholders `%s` au lieu de `?`, `GENERATED ALWAYS AS IDENTITY` au lieu de
`AUTOINCREMENT`, et surtout `INSERT ... RETURNING id` au lieu de
`cursor.lastrowid`.

Le pool tourne en autocommit. Toutes les requêtes tiennent en un seul ordre
SQL, donc ouvrir une transaction reviendrait à garder une connexion « idle in
transaction » pendant le rendu de la réponse.

Compose attend le healthcheck `pg_isready` avant de démarrer le backend, mais
une base distante ou un redémarrage du serveur ne passent pas par là :
l'application réessaie pendant trente secondes avant d'abandonner.

## Limites connues

- Une seule instance, pas de haute disponibilité.
- Pas de sauvegarde automatisée du volume PostgreSQL. C'est la première chose
  à ajouter avant un usage réel.
- Logs consultés avec `docker logs`, sans centralisation.
- Schéma créé par un `CREATE TABLE IF NOT EXISTS` au démarrage. Suffisant pour
  une table, à remplacer par Alembic dès la première évolution.
- Pas de rollback automatique : un healthcheck en échec arrête le déploiement
  et laisse l'ancienne version en place, mais sans revenir au SHA précédent.
