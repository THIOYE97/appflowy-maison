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

## Contraintes à connaître

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

Les paquets GHCR doivent ensuite être rendus **publics**, sinon Railway ne peut
pas les tirer (les identifiants de registre privé se configurent uniquement
depuis le tableau de bord Railway).

## Après le premier déploiement

1. Créer le compte depuis la page de connexion.
2. Passer `GOTRUE_DISABLE_SIGNUP=true` sur le service `gotrue` pour fermer les
   inscriptions — l'instance est publique sur Internet.
