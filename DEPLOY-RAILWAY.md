# Déploiement Railway

Déploiement d'AppFlowy auto-hébergé sur Railway, à partir du snapshot AGPL-3.0
de ce dépôt — pas des images commerciales `appflowyinc/*`, qui appliquent la
limite du Free Tier (1 siège payant + 3 invités).

## Pourquoi ce dépôt et pas l'upstream

`AppFlowy-IO/AppFlowy-Cloud` a été archivé le 11 septembre 2026. L'auto-hébergement
officiel vit désormais dans `AppFlowy-SelfHost-Commercial`, sous licence
propriétaire. Ce dépôt est un snapshot du dernier état public AGPL, dont le
code ne contient aucun contrôle de sièges. En contrepartie : plus de mises à
jour amont, et les versions récentes du client Flutter/Web peuvent exiger des
fonctions serveur absentes ici.

## Architecture déployée

Railway ne lit pas `docker-compose.yml` : chaque conteneur est un service.

| Service | Image | Port | Rôle |
|---|---|---|---|
| `edge` | `ghcr.io/thioye97/appflowy-edge` | 80 | Seul service public. Route `/api`, `/ws`, `/gotrue`, `/console`, et le reste vers le SPA |
| `appflowy-web` | `ghcr.io/thioye97/appflowy-web` | 80 | SPA React |
| `appflowy-cloud` | `ghcr.io/thioye97/appflowy-cloud` | 8000 | Serveur Rust (API + WebSocket collab) |
| `appflowy-worker` | `ghcr.io/thioye97/appflowy-worker` | — | Tâches de fond (imports, mails) |
| `admin-frontend` | `ghcr.io/thioye97/appflowy-admin` | 3000 | Console d'administration sous `/console` |
| `gotrue` | `appflowyinc/gotrue:0.9.64` | 9999 | Authentification (fork Supabase, sans logique de sièges) |
| `postgres` | `pgvector/pgvector:pg16` | 5432 | Base — extensions `vector` et `uuid-ossp` requises |
| `redis` | `redis:7-alpine` | 6379 | Cache et flux collaboratifs |
| `appflowy-storage` | Bucket Railway | — | Stockage objet S3, remplace MinIO |

Services volontairement écartés : `minio` (remplacé par le bucket Railway),
`ai` et `appflowy_search` (absents de cette version du code, ou dépendants
d'une clé OpenAI), `pgadmin`.

Compte Railway : `app@danapay.com`, workspace « danapay's Projects », projet
`appflowy-maison` (`4590bbda-717d-404e-be06-e74754f99f73`). Les services sont
en `europe-west4` et le bucket en `ams`.

## Contraintes à connaître

**Railway injecte `PORT=8080`.** L'edge le respecterait et écouterait sur 8080,
alors que le domaine route vers 80 — d'où un 502 sur toutes les routes. On fixe
donc `PORT=80` explicitement sur le service `edge`.

**Le réseau privé est résolu en IPv6** (`fd12::10`). Tout service joignable par
l'edge doit écouter en IPv6 : `APPFLOWY_APPLICATION_HOST=[::]`,
`ADMIN_FRONTEND_HOST=[::]`, et `listen [::]:80` dans `docker/web/nginx.conf`.
GoTrue écoute sur `:9999`, ce qui est dual-stack en Go.

**Le stockage Tigris accepte le path-style.** Vérifié : écriture puis relecture
d'un blob via `PUT`/`GET /api/file_storage/{ws}/blob/{id}` rendent le contenu
exact. C'était le point le plus incertain de la configuration, puisque le code
force `force_path_style(true)` alors que Railway annonce ses buckets en
virtual-host.

**Pièges du CLI en non-interactif.** `railway volume add` plante
(`Option::unwrap()` sur `None`) si aucun service n'est lié : faire
`railway service <nom>` d'abord. `railway bucket create` exige `--region`.

**L'URL publique est figée dans l'image web.** Vite résout `import.meta.env` au
build, donc `AF_BASE_URL` / `AF_GOTRUE_URL` / `AF_WS_URL` sont des build-args.
Changer le domaine Railway impose de relancer le workflow avec le nouveau
`public_host` et de redéployer `appflowy-web`.

**WebSocket en `/ws/v1`.** Le `deploy.env` du dépôt indique `/ws/v2`, mais il
provient d'une version plus récente que le code ici présent. Le commit web
épinglé (`db92f1d`, 22 juillet 2025) parle `v1`. Ne pas « corriger » en v2.

**`PGDATA` en sous-dossier.** Le volume Railway monté sur
`/var/lib/postgresql/data` contient un `lost+found`, ce qui fait échouer
l'initialisation de Postgres. D'où `PGDATA=/var/lib/postgresql/data/pgdata`.

**Pas de SMTP configuré.** `GOTRUE_MAILER_AUTOCONFIRM=true` est obligatoire :
sans serveur mail, personne ne peut confirmer son adresse, donc personne ne
peut se connecter. Renseigner les variables `GOTRUE_SMTP_*` pour revenir à une
confirmation par mail.

**Stockage objet.** Le code force `force_path_style(true)` et n'applique
l'endpoint personnalisé que si `APPFLOWY_S3_USE_MINIO=true`. On met donc le
bucket Railway en « mode MinIO » avec son endpoint public, et
`APPFLOWY_S3_CREATE_BUCKET=false` puisque le bucket est créé par Railway.

## Construire les images

Les images sont construites par GitHub Actions (`.github/workflows/build-images.yml`),
jamais en local : ce sont trois compilations Rust complètes via `cargo-chef`.

```bash
gh workflow run build-images.yml \
  -f public_host=https://<ton-domaine>.up.railway.app \
  -f tag=v2025.07-1
```

Seule l'image web dépend du domaine. Après un changement d'URL, inutile de
relancer les trois compilations Rust — l'entrée `only` restreint le run :

```bash
gh workflow run build-images.yml -f public_host=https://<nouvelle-url> -f only=web
```

Les paquets GHCR doivent ensuite être rendus **publics**, sinon Railway ne peut
pas les tirer (les identifiants de registre privé se configurent uniquement
depuis le tableau de bord Railway).

## État actuel

Le compte propriétaire est créé et `GOTRUE_DISABLE_SIGNUP=true` est actif : une
tentative d'inscription renvoie `signup_disabled`. Pour ajouter quelqu'un, il
faut repasser temporairement la variable à `false`, ou inviter depuis l'espace
de travail.

Les identifiants vivent dans `~/.config/appflowy-maison/secrets.env`, **hors du
dépôt**. Un `.gitignore` ne suffisait pas : l'outil d'instantanés local forçait
l'ajout du fichier et le capturait malgré tout. Les hors-dépôt, il ne peut plus
l'atteindre. Aucun secret n'est présent dans l'historique.

```bash
set -a; . ~/.config/appflowy-maison/secrets.env; set +a
```
