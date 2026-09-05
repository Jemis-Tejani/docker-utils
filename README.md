# docker-utils

Local Docker Compose stack for Spark Connect, Redis, a private registry, Postgres (pgvector), ChromaDB, Keycloak, and an ngrok tunnel to host Ollama.

## Prerequisites

- Docker and Docker Compose
- Ollama running on the host at `localhost:11434` (used by ngrok)

## Start

Use `docker compose` (Compose V2 plugin). `docker-compose` is the old CLI and is not needed.

Foreground with logs:

```bash
docker compose up
```

Single service:

```bash
docker compose up redis
```

Stop: `Ctrl+C`. Then optionally:

```bash
docker compose down
```

## Services

| Service | Image | Host port | Data dir |
| --- | --- | --- | --- |
| spark | `apache/spark:4.0.0` | `15002` (Connect), `4040` (UI) | `./spark-data` |
| redis | `redis:8.8.0` | `6379` | `./redis-data` |
| registry | `registry:2` | `5001` | `./registry-data` |
| pgvector | `pgvector/pgvector:pg16` | `5432` | `./postgres-data` |
| chromadb | `chromadb/chroma:1.5.3` | `8000` | `./chromadb-data` |
| keycloak | `harbor-registry.dataphion.com/iidrak/keycloak:1.1.4-arm64` | `8080` | `./keycloak-data` |
| ngrok | `ngrok/ngrok:latest` | `4041` (inspector) | `./ngrok-data` |

### Spark Connect

- Endpoint: `sc://localhost:15002`
- UI: http://localhost:4040
- Persists warehouse, local scratch, and Ivy cache under `./spark-data`
- Also mounts host `/var/folders` so Spark can read macOS temp files

### Redis

- `localhost:6379`
- AOF enabled (`--appendonly yes`)

### Registry

- `localhost:5001`
- Image delete enabled (`REGISTRY_STORAGE_DELETE_ENABLED=true`)

### Postgres / pgvector

- Host: `localhost:5432`
- User / password / db: `postgres` / `postgres` / `postgres`
- `vector` extension is created on first init via `init-scripts/postgres/01-create-extensions.sql`

Init scripts only run when `./postgres-data` is empty.

### ChromaDB

- http://localhost:8000

### Keycloak

- http://localhost:8080
- Admin: `admin` / `admin`

### ngrok

Tunnels host Ollama (`host.docker.internal:11434`) on a reserved domain:

- Public: https://micrometrical-patronymically-jarvis.ngrok-free.dev/v1
- Inspector: http://localhost:4041

Auth token is set on the `ngrok` service in `docker-compose.yml`.

## Persistence

Bind mounts (created on first start):

```
./spark-data
./redis-data
./registry-data
./postgres-data
./chromadb-data
./keycloak-data
./ngrok-data
```

`docker compose down` keeps these. Remove a data dir only if you want that service to start fresh.
