# Task Manager

Application de gestion de tâches servant de support à une chaîne DevOps
complète : API REST FastAPI, base PostgreSQL, interface HTML/CSS/JavaScript
natif, le tout conteneurisé, provisionné par Terraform, configuré par Ansible
et déployé automatiquement à chaque push.

Les choix privilégient la simplicité et la lisibilité : pas d'ORM, pas de
framework frontend, pas d'étape de build côté navigateur.

## Technologies

| Brique | Choix | Rôle |
|---|---|---|
| API | FastAPI + Uvicorn | endpoints REST, validation Pydantic |
| Base de données | PostgreSQL 17 (psycopg 3) | persistance, pool de connexions |
| Frontend | HTML/CSS/JavaScript natif | interface, sans framework |
| Serveur web | Nginx (`nginx:alpine`) | fichiers statiques, reverse proxy, TLS |
| Conteneurs | Docker Compose | orchestration des trois services |
| Infrastructure | Terraform | VM, pare-feu réseau, IP fixe |
| Configuration | Ansible | Docker, arborescence, secrets, certificat |
| CI/CD | GitHub Actions | lint, tests, sécurité, build, déploiement |
| Sécurité | Trivy | vulnérabilités, secrets, mauvaises configurations |
| Certificats | Let's Encrypt (certbot) | HTTPS et renouvellement automatique |
| Tests | pytest, k6 | unitaires et charge |

## Architecture

De l'infrastructure au code, trois outils se partagent le travail. Terraform
crée la machine et rien d'autre. Ansible la configure et dépose les fichiers
de production. GitHub Actions ne fait que remplacer des images.

```
Terraform ──► VM + pare-feu + IP fixe
                   │
Ansible ──────────►│ Docker, /opt/task-manager, secrets, certificat TLS
                   │
GitHub Actions ───►│ docker compose pull && up -d
```

Et l'application telle qu'elle tourne sur le serveur :

```
                         Navigateur
                             │
                             │  443 (HTTPS) — le 80 redirige
                             ▼
 ┌─── VM Ubuntu 24.04 ───────────────────────────────────────┐
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
 │                            │ volume task-manager_... │    │
 │                            └─────────────────────────┘    │
 └───────────────────────────────────────────────────────────┘
```

Seul Nginx est joignable depuis Internet. Le backend et PostgreSQL sont
déclarés avec `expose` et non `ports` : ils n'existent que sur le réseau privé
Compose. Les données survivent à la recréation des conteneurs grâce à un volume
Docker nommé explicitement.

### Le parcours d'une requête

Le navigateur charge la page : Nginx renvoie `index.html`, le CSS et le
JavaScript. Le JavaScript appelle ensuite `/api/tasks` en chemin relatif. Nginx
reconnaît le préfixe `/api/` et transmet la requête au backend, en **retirant
ce préfixe** au passage : FastAPI reçoit donc `/tasks`. Il interroge PostgreSQL
et renvoie le JSON, que Nginx retransmet.

Deux conséquences utiles. Le navigateur ne voit qu'une seule origine, donc
aucune configuration CORS n'est nécessaire et le frontend ne contient aucune
URL d'API codée en dur. Et le backend n'est jamais joignable depuis Internet.

### Structure du projet

```
backend/        main.py (API), conftest.py et test_main.py (14 tests), Dockerfile
frontend/       index.html, style.css, app.js, Dockerfile Nginx
nginx/          default.conf — reverse proxy /api/ et en-têtes de sécurité
terraform/      VM, groupe de sécurité, IP fixe
ansible/        playbook de configuration du serveur et gabarits
deploy/         script de déploiement privilégié et règle sudoers
load-tests/     scripts k6 : smoke, load, stress
docker-compose.yml       développement local, construit les images
docker-compose.prod.yml  production, utilise les images publiées
.github/workflows/ci-cd.yml   pipeline complète
```

Deux fichiers Compose distincts : celui de développement construit les images
localement, celui de production tire les images publiées et fixe le nom des
volumes. Le fichier de production vit sur le serveur, dans
`/opt/task-manager`, et appartient à root.

## Lancer le projet en local

Prérequis : Docker et Docker Compose. L'application est ensuite disponible sur
<http://localhost>.

```bash
docker compose up --build
```

Aucune configuration préalable n'est nécessaire : `docker-compose.yml` fournit
des valeurs de repli pour la base. Pour les personnaliser, copiez
`.env.example` en `.env`.

`docker compose down` conserve les tâches ; `docker compose down -v` supprime
le volume et donc les données.

### Sans Docker

Il faut alors un PostgreSQL joignable.

```bash
cd backend
pip install -r requirements-dev.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/tasks
uvicorn main:app --reload --port 8000
```

### Endpoints

Les routes sont préfixées par `/api` lorsqu'on passe par Nginx.

| Méthode | Route | Rôle |
|---|---|---|
| GET | `/health` | l'application répond, utilisé par le healthcheck |
| GET | `/ready` | la base de données est accessible |
| GET | `/tasks` | liste des tâches, les plus récentes d'abord |
| POST | `/tasks` | crée une tâche, titre de 1 à 200 caractères |
| DELETE | `/tasks/{id}` | supprime une tâche, 404 si elle n'existe pas |

```bash
curl http://localhost/api/health
curl -X POST http://localhost/api/tasks \
  -H 'Content-Type: application/json' -d '{"title":"Ma tâche"}'
```

Les requêtes SQL sont paramétrées et les titres validés deux fois : par
Pydantic côté application, puis par une contrainte `CHECK` côté base. Un titre
vide ou composé uniquement d'espaces est refusé avec un code 422.

## Tests

Le backend est couvert par **14 tests pytest** exécutés contre un **vrai
PostgreSQL**, et non un substitut : le SQL testé est exactement celui qui part
en production. Chaque test démarre sur une table vide, donc les tests ne
dépendent pas de l'ordre d'exécution.

```bash
cd backend
pip install -r requirements-dev.txt
python -m pytest -v
```

La base de test est créée automatiquement au premier lancement. Pour viser un
autre serveur, renseignez `TEST_DATABASE_URL`.

Trois scénarios k6 dans `load-tests/` complètent l'ensemble ; voir le README de
ce répertoire. Ils n'interrogent que des routes en lecture et ne modifient
jamais les données.

## Déployer

### 1. Provisionner la VM avec Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # puis renseigner votre IP
terraform init
terraform apply
```

Terraform crée une instance Ubuntu 24.04 dans le VPC par défaut, une IP fixe et
un groupe de sécurité qui n'ouvre que le strict nécessaire : 80 et 443 au
monde, 22 à vos seules adresses. Une règle de validation **refuse** un
`ssh_allowed_cidrs` à `0.0.0.0/0`. Le disque racine est chiffré et IMDSv2 est
obligatoire, pour qu'une éventuelle SSRF depuis l'application ne puisse pas
lire les identifiants du rôle d'instance.

L'AMI est résolue dynamiquement auprès de Canonical plutôt que codée en dur :
un identifiant d'AMI change à chaque région et à chaque publication.

### 2. Configurer le serveur avec Ansible

```bash
cd ansible
cp inventory.ini.example inventory.ini   # y mettre la sortie public_ip
ansible-playbook playbook.yml
```

Le playbook installe Docker depuis le dépôt officiel, crée l'arborescence
`/opt/task-manager` en root:root, **génère un mot de passe PostgreSQL
aléatoire** au premier passage seulement, dépose le fichier Compose de
production, installe le script de déploiement privilégié et démarre la pile.

Il n'utilise que des modules d'`ansible-core` : aucune collection à installer
au préalable. Il est idempotent — le rejouer ne réinstalle rien et ne
régénère pas le mot de passe.

### 3. Activer HTTPS

Prérequis : un nom de domaine dont l'enregistrement A pointe déjà vers l'IP
de la VM. Sans cela, la validation Let's Encrypt échoue et l'application reste
en HTTP, ce qui est le comportement par défaut.

```bash
ansible-playbook playbook.yml \
  -e domain=exemple.fr -e letsencrypt_email=vous@exemple.fr
```

Le certificat est demandé en mode **webroot** et non standalone : Nginx garde
le port 80 et le service n'est pas interrompu pendant la validation. Le
playbook bascule ensuite la configuration en HTTPS, ajoute l'en-tête HSTS et
démarre un conteneur certbot qui tente un renouvellement deux fois par jour.
Le port 80 reste ouvert pour la redirection et pour les challenges ACME
suivants.

### 4. Brancher le déploiement continu

Le déploiement s'exécute sur un **runner GitHub Actions auto-hébergé** installé
sur la VM, avec les labels `self-hosted, Linux, X64, app-deploy`. C'est lui qui
initie la connexion sortante vers GitHub, ce qui évite d'ouvrir le moindre port
entrant pour la CI/CD.

À configurer dans le dépôt :

| Type | Nom | Rôle |
|---|---|---|
| Variable | `REGISTRY_NAMESPACE` | compte du registre d'images |
| Variable | `DEPLOY_ENABLED` | `true` pour activer le job de déploiement |
| Secret | `DOCKERHUB_USERNAME` | publication des images |
| Secret | `DOCKERHUB_TOKEN` | publication des images |

Tant que `DEPLOY_ENABLED` est absente, le job de déploiement est ignoré sans
faire échouer la pipeline.

## CI/CD

```
 git push
    │
    ├── Pull Request ──► lint ─┐
    │                   tests ─┼─► build des images ──► Trivy image ──► fin
    │                   Trivy ─┘    (rien n'est publié, aucun secret)
    │
    └── push main ─────► lint, tests, Trivy ──► build ──► Trivy image
                                                    │
                                     registre ◄─────┤  latest + SHA
                                                    │
                                     runner ◄───────┘
                              compose pull, up -d, healthchecks
```

Le job **lint** passe Ruff sur le code Python, Hadolint sur les deux
Dockerfile, `terraform fmt` et `terraform validate` sur l'infrastructure, et un
contrôle syntaxique sur le playbook Ansible.

Le job **tests** démarre un service PostgreSQL et exécute les 14 tests.

Le job **sécurité** lance Trivy sur l'ensemble du dépôt avec ses trois
analyseurs : dépendances vulnérables, secrets en clair et mauvaises
configurations dans les Dockerfile, les fichiers Compose et le code Terraform.
Le rapport part dans l'onglet Security au format SARIF, et la pipeline échoue
sur toute vulnérabilité **critique disposant d'un correctif**. Sans correctif
publié, une alerte n'est pas actionnable : elle est signalée mais ne bloque pas
la livraison.

Chaque image est ensuite construite, chargée localement, **analysée par Trivy
avant toute publication**, puis publiée seulement si l'analyse passe. L'image
publiée est exactement celle qu'a vue Trivy : le cache de build est réutilisé,
rien n'est reconstruit entre les deux étapes.

Le déploiement utilise toujours le tag SHA, jamais `latest` : chaque mise en
production correspond à un commit identifiable, et un retour arrière consiste à
redéployer un SHA antérieur.

## Sécurité

**Le runner n'a pas Docker.** L'utilisateur `gha-runner` n'appartient pas au
groupe `docker`, qui équivaudrait à un accès root sur la machine. Il ne dispose
que d'une règle sudoers autorisant une unique commande :
`/usr/local/sbin/task-manager-deploy`.

**Le script de déploiement se protège lui-même.** Il refuse de démarrer si le
fichier Compose de production, le fichier d'environnement ou le répertoire de
configuration Nginx n'appartiennent pas à root, ou s'ils sont modifiables par
un autre utilisateur — un fichier Compose équivaut à une exécution root
arbitraire. Il n'accepte comme argument qu'un SHA de 40 caractères
hexadécimaux, ce qui interdit de déployer une image qui ne sort pas du
pipeline. Enfin, le job de déploiement ne fait aucun `checkout` : rien de ce
qui tourne en root n'est modifiable depuis une branche.

**Aucun secret dans le dépôt.** Le mot de passe PostgreSQL est généré sur le
serveur par Ansible et vit dans `/opt/task-manager/.env` en mode 0600. Les
identifiants du registre sont des secrets GitHub. Le `.gitignore` exclut
explicitement les états Terraform, les inventaires Ansible, les clés privées et
les certificats.

**Conteneurs restreints.** Le backend tourne en non-root, sans aucune capacité
Linux (`cap_drop: ALL`) et avec `no-new-privileges`. Il n'écrit plus rien sur
son propre système de fichiers depuis que les données sont en base.

**En-têtes HTTP.** Nginx masque sa version et pose `X-Content-Type-Options`,
`X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` et une
`Content-Security-Policy` stricte — possible parce que la page n'a ni script ni
style en ligne. En HTTPS s'y ajoute `Strict-Transport-Security`. La taille des
corps de requête est plafonnée à 64 ko, l'API n'échangeant que de petits objets
JSON.

**Images épinglées.** Les dépendances Python le sont à la version exacte, et
`requirements.txt` ne contient que l'exécution : ni pytest ni Ruff ne partent
en production, ce qui réduit d'autant la surface analysée par Trivy.

## Choix techniques notables

**PostgreSQL plutôt que SQLite.** SQLite sérialise les écritures et vit dans un
fichier : il ne survit pas proprement à plusieurs workers ni à un passage en
haute disponibilité. Le portage a demandé plus qu'un changement de pilote —
placeholders `%s` au lieu de `?`, `GENERATED ALWAYS AS IDENTITY` au lieu de
`AUTOINCREMENT`, et surtout `INSERT ... RETURNING id` au lieu de
`cursor.lastrowid`, PostgreSQL rendant l'identifiant attribué dans la même
requête.

**Un pool de connexions, en autocommit.** Toutes les requêtes de cette API
tiennent en un seul ordre SQL. L'autocommit évite de garder une connexion
« idle in transaction » pendant le rendu de la réponse.

**Le backend attend sa base.** Compose attend le healthcheck `pg_isready` de
PostgreSQL, mais une base distante ou un redémarrage du serveur ne passent pas
par là : l'application réessaie pendant trente secondes avant d'abandonner le
démarrage.

**La configuration Nginx est montée, pas reconstruite.** Activer HTTPS ne
demande donc pas de reconstruire ni de republier l'image frontend : Ansible
remplace un fichier dans un répertoire root:root monté en lecture seule.

**L'état Terraform est local.** Cela suffit pour un environnement unique piloté
par une seule personne. À plusieurs, il faudrait le déporter sur un bucket S3
avec verrouillage : l'état contient l'IP et les identifiants des ressources, il
doit être partagé sans être versionné.

## Limites connues

Le service tourne sur une seule instance, sans haute disponibilité. Le volume
PostgreSQL n'a pas de sauvegarde automatisée — c'est la première chose à
ajouter avant un usage réel, par exemple un `pg_dump` planifié vers un stockage
objet. Les logs restent consultés avec `docker logs`, sans centralisation. Le
schéma est créé au démarrage par un `CREATE TABLE IF NOT EXISTS` plutôt que par
un outil de migration : suffisant pour une table, à remplacer par Alembic dès
qu'une évolution de schéma devient nécessaire. Enfin, un rollback automatique
vers le SHA précédent en cas d'échec du healthcheck reste à écrire ; aujourd'hui
le déploiement échoue bruyamment et laisse l'ancienne version en place.
