# docker-utils

Local Docker Compose infrastructure for the **Hermes / Iidrak Enterprise Data Platform**.

This stack provides all local backing services required for development and testing across **Hermes CMS**, **Hermes Frontend**, **AI Studio**, **Spark Connect**, and **Catalog Connectors**.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start Guide](#quick-start-guide)
  - [1. Core Services (Default)](#1-core-services-default)
  - [2. Optional Services (ChromaDB)](#2-optional-services-chromadb)
  - [3. Local Catalog Connectors](#3-local-catalog-connectors)
- [Services Matrix](#services-matrix)
- [Service Details](#service-details)
  - [Core Services](#core-services)
    - [Keycloak (SSO / IAM)](#keycloak-sso--iam)
    - [Spark Connect & Web UI](#spark-connect--web-ui)
    - [Redis (Cache & Queues)](#redis-cache--queues)
    - [Private Docker Registry](#private-docker-registry)
    - [PostgreSQL with pgvector](#postgresql-with-pgvector)
    - [ngrok Tunnel (Ollama LLM)](#ngrok-tunnel-ollama-llm)
  - [Optional Services](#optional-services)
    - [ChromaDB (Vector Database)](#chromadb-vector-database)
  - [Catalog Connectors](#catalog-connectors)
    - [MySQL 8.0](#mysql-80)
    - [MongoDB 7.0](#mongodb-70)
    - [MSSQL (Azure SQL Edge)](#mssql-azure-sql-edge)
    - [PrestoDB](#prestodb)
    - [Trino](#trino)
    - [SQLite (In-Memory)](#sqlite-in-memory)
- [Hermes Frontend GUI Connector Configuration](#hermes-frontend-gui-connector-configuration)
- [Data Persistence & Volumes](#data-persistence--volumes)
- [Maintenance & Troubleshooting](#maintenance--troubleshooting)

---

## Architecture Overview

```
                         ┌─────────────────────────────────────────┐
                         │   Hermes Frontend (React / localhost)    │
                         └────────────────────┬────────────────────┘
                                              │ API calls
                                              ▼
                         ┌─────────────────────────────────────────┐
                         │     Hermes CMS (Strapi / Koa API)       │
                         └──────┬─────────────┬─────────────┬──────┘
                                │             │             │
                ┌───────────────┘             │             └───────────────┐
                ▼                             ▼                             ▼
┌──────────────────────────────┐┌──────────────────────────┐┌──────────────────────────────┐
│        Core Services         ││      AI Infrastructure   ││      Catalog Connectors      │
│                              ││                          ││   (Profile: "connectors")    │
│ • Keycloak (Port 8080)       ││ • ngrok (Port 4041)      ││ • MySQL (Port 3307)          │
│ • Spark Connect (Port 15002) ││   └─► Ollama:11434       ││ • MongoDB (Port 27017)       │
│ • Redis (Port 6379)          ││ • ChromaDB (Port 8000)   ││ • MSSQL (Port 1433)          │
│ • Postgres+pgvector (5432)   ││   (Profile: "optional")  ││ • Presto (Port 8089)         │
│ • Local Registry (Port 5001) ││                          ││ • Trino (Port 8082)          │
│                              ││                          ││ • SQLite (In-Memory / Port 0)│
└──────────────────────────────┘└──────────────────────────┘└──────────────────────────────┘
```

---

## Prerequisites

1. **Docker Desktop** (Engine 20.10+ and Docker Compose V2 plugin).
2. **Apple Silicon (M1/M2/M3/M4) or Intel Mac / Linux** with at least 8 GB RAM allocated to Docker.
3. **Ollama** installed on the host machine running at `localhost:11434` (if testing local LLMs via ngrok).
4. Free local ports: `8080`, `15002`, `4040`, `6379`, `5001`, `5432`, `4041` (plus `3307`, `27017`, `1433`, `8089`, `8082`, `8000` when connectors/ChromaDB are started).

---

## Quick Start Guide

### 1. Core Services (Default)

Starts all core services needed for day-to-day Hermes development (**Keycloak, Spark Connect, Redis, Registry, Postgres with pgvector, and ngrok**):

```bash
# Start all core services in background
docker compose up -d

# View live logs for all core services
docker compose logs -f

# View live logs for a specific service
docker compose logs -f spark

# Stop all core services
docker compose down
```

> **Note:** Catalog connectors and ChromaDB are configured under profiles and **will not** start with `docker compose up -d`, preserving your system's RAM and CPU.

---

### 2. Optional Services (ChromaDB)

ChromaDB is a local vector database used for AI Studio RAG (Retrieval-Augmented Generation) and semantic search:

```bash
# Start ChromaDB
docker compose up -d chromadb

# Check ChromaDB status
docker compose ps chromadb

# Stop ChromaDB
docker compose stop chromadb
```

---

### 3. Local Catalog Connectors

All catalog connectors are configured under the `connectors` profile to avoid unnecessary memory consumption:

```bash
# Start ALL catalog connectors at once
docker compose --profile connectors up -d

# Start individual connectors on demand
docker compose up -d mysql      # MySQL only (Port 3307)
docker compose up -d mongodb    # MongoDB only (Port 27017)
docker compose up -d mssql      # MS SQL Server only (Port 1433)
docker compose up -d presto     # Presto query engine only (Port 8089)
docker compose up -d trino      # Trino query engine only (Port 8082)

# Stop all connectors
docker compose --profile connectors down

# Stop a single connector
docker compose stop mysql
```

---

## Services Matrix

| Service | Container Name | Profile | Image | Host Port | In-Container Port | Volume / Data Dir | Description |
|---|---|---|---|---|---|---|---|
| **keycloak** | `keycloak` | *(default)* | `harbor-registry.dataphion.com/iidrak/keycloak:1.1.4-arm64` | `8080` | `8080` | `./keycloak-data` | Identity & Access Management (SSO) |
| **spark** | `spark` | *(default)* | `apache/spark:4.0.0` | `15002`, `4040` | `15002`, `4040` | `./spark-data`, `/var/folders` | Spark Connect Server & Web UI |
| **redis** | `redis` | *(default)* | `redis:8.8.0` | `6379` | `6379` | `./redis-data` | In-memory key-value store with AOF |
| **registry** | `registry` | *(default)* | `registry:2` | `5001` | `5000` | `./registry-data` | Local private Docker V2 image registry |
| **pgvector** | `pgvector` | *(default)* | `pgvector/pgvector:pg16` | `5432` | `5432` | `./postgres-data`, `./init-scripts/postgres` | PostgreSQL 16 + pgvector + pg_stat_statements |
| **ngrok** | `ngrok` | *(default)* | `ngrok/ngrok:latest` | `4041` | `4040` | `./ngrok-data` | Tunnels host Ollama (:11434) to public URL |
| **chromadb** | `local-chromadb` | `optional` | `chromadb/chroma:1.5.3` | `8000` | `8000` | `./chromadb-data` | Local Vector Database for RAG & Embeddings |
| **mysql** | `local-mysql` | `connectors` | `mysql:8.0` | `3307` | `3306` | `./mysql-data` | MySQL 8.0 Catalog Connector |
| **mongodb** | `local-mongodb` | `connectors` | `mongo:7.0` | `27017` | `27017` | `./mongodb-data` | MongoDB 7.0 Document Store Connector |
| **mssql** | `local-mssql` | `connectors` | `mcr.microsoft.com/azure-sql-edge:latest` | `1433` | `1433` | `./mssql-data` | MS SQL Server (Azure SQL Edge Developer) |
| **presto** | `local-presto` | `connectors` | `prestodb/presto:latest` | `8089` | `8080` | None | PrestoDB Distributed SQL Query Engine |
| **trino** | `local-trino` | `connectors` | `trinodb/trino:latest` | `8082` | `8080` | None | Trino Distributed SQL Query Engine |

---

## Service Details

### Core Services

#### Keycloak (SSO / IAM)
- **URL:** [http://localhost:8080](http://localhost:8080)
- **Admin Credentials:** `admin` / `admin`
- **Purpose:** Manages authentication, user federation, enterprise realms, and OAuth2/OIDC clients for Hermes CMS.
- **Data Persistence:** `./keycloak-data`

#### Spark Connect & Web UI
- **Spark Connect Endpoint:** `sc://localhost:15002`
- **Spark Web UI:** [http://localhost:4040](http://localhost:4040)
- **Purpose:** Executes distributed SQL queries, lakehouse jobs, and DataFrame operations via Spark Connect Client (`SparkSession.builder.remote("sc://localhost:15002").getOrCreate()`).
- **Data Persistence:** `./spark-data` (warehouse, local scratch, Ivy JAR cache) and host `/var/folders` mount for macOS temp file access.

#### Redis (Cache & Queues)
- **Endpoint:** `localhost:6379`
- **Purpose:** Used for caching, background task coordination, and session states.
- **Config:** Append-Only File (AOF) persistence enabled (`--appendonly yes`).
- **Data Persistence:** `./redis-data`

#### Private Docker Registry
- **Endpoint:** [http://localhost:5001](http://localhost:5001) (API: `/v2/`)
- **Purpose:** Local OCI/Docker container image registry for storing custom models, containers, and pipelines.
- **Config:** `REGISTRY_STORAGE_DELETE_ENABLED=true` enables garbage collection and tag deletion.
- **Data Persistence:** `./registry-data`

#### PostgreSQL with pgvector
- **Host / Port:** `localhost:5432`
- **Database:** `postgres`
- **User / Password:** `postgres` / `postgres`
- **Extensions:**
  - `vector`: Enters AI vector embeddings support for AI Studio and Semantic Search.
  - `pg_stat_statements`: Enabled via `command: postgres -c shared_preload_libraries=pg_stat_statements` for query performance monitoring and diagnostics.
- **Init Script:** Automatically loaded from `./init-scripts/postgres/01-create-extensions.sql` on first startup.
- **Data Persistence:** `./postgres-data`

#### ngrok Tunnel (Ollama LLM)
- **Public URL:** `https://micrometrical-patronymically-jarvis.ngrok-free.dev`
- **Inspector Web UI:** [http://localhost:4041](http://localhost:4041)
- **Target:** `host.docker.internal:11434` (Ollama running locally on host)
- **Key Flags:**
  - `--host-header=rewrite`: Rewrites incoming HTTP `Host` header to `host.docker.internal:11434` to prevent Ollama from rejecting requests with `403 Forbidden` / `Invalid Host Header`.
  - `extra_hosts: ["host.docker.internal:host-gateway"]`: Ensures container can reliably resolve host machine networking across Docker Desktop releases.

---

### Optional Services

#### ChromaDB (Vector Database)
- **Endpoint:** [http://localhost:8000](http://localhost:8000)
- **Profile:** `optional` (started via `docker compose up -d chromadb`)
- **Purpose:** Document vector database for Hermes AI Studio RAG pipelines, semantic similarity search, and LLM Agent knowledge grounding.
- **Data Persistence:** `./chromadb-data`

---

### Catalog Connectors

#### MySQL 8.0
- **Container Port:** `3306` ➔ **Host Port:** `3307`
- **Database:** `testdb`
- **User / Password:** `root` / `root`
- **Data Persistence:** `./mysql-data`

#### MongoDB 7.0
- **Container Port:** `27017` ➔ **Host Port:** `27017`
- **Database:** `testdb`
- **User / Password:** `root` / `rootpassword`
- **Data Persistence:** `./mongodb-data`

#### MSSQL (Azure SQL Edge)
- **Container Port:** `1433` ➔ **Host Port:** `1433`
- **Database:** `master`
- **User / Password:** `sa` / `Password@123`
- **Edition:** Developer (`MSSQL_PID: "Developer"`, EULA accepted)
- **Data Persistence:** `./mssql-data`

#### PrestoDB
- **Container Port:** `8080` ➔ **Host Port:** `8089` *(port 8080 is reserved for Keycloak)*
- **User / Password:** `presto` / *(None)*
- **Catalog:** `system` (or `memory`, `tpch`, `tpcds`)
- **Purpose:** Distributed SQL query engine across heterogeneous data sources.

#### Trino
- **Container Port:** `8080` ➔ **Host Port:** `8082` *(ports 8080, 8081, 8089 are reserved)*
- **User / Password:** `admin` / *(None)*
- **Catalog:** `system` (or `tpch`, `tpcds`, `memory`)
- **Purpose:** Fast, distributed SQL query engine for big data and lakehouses.
- **Storage:** Ephemeral in-container storage (no host bind mount needed).

#### SQLite (In-Memory)
- **Mode:** In-Memory (`:memory:`)
- **Host / Port:** `localhost` / `0`
- **Database Name:** `main`
- **Purpose:** Zero-container, zero-file lightweight testing for Hermes Data Catalog.

---

## Hermes Frontend GUI Connector Configuration

When testing or creating connector configurations under **Settings ➔ Connectors Configurations** in the Hermes Frontend (`localhost:3000`), enter these exact values:

| Connector Source | Host | Port | Username | Password | Database / Catalog | Connection Test Result | Notes |
|---|---|---|---|---|---|---|---|
| **Postgres** | `host.docker.internal` | `5432` | `postgres` | `postgres` | `postgres` | ✅ Passed (All Green) | Includes pgvector extension |
| **MySQL** | `host.docker.internal` | `3307` | `root` | `root` | `testdb` | ✅ Passed (All Green) | Host port 3307 |
| **MongoDB** | `host.docker.internal` | `27017` | `root` | `rootpassword` | `testdb` | ✅ Passed (All Green) | Mongo 7.0 standard auth |
| **MSSQL Consumer** | `host.docker.internal` | `1433` | `sa` | `Password@123` | `master` | ✅ Passed (All Green) | Azure SQL Edge Developer edition |
| **Presto** | `host.docker.internal` | `8089` | `presto` | *(leave blank)* | Catalog: `system` | ✅ Passed (All Green) | Default catalog `system` |
| **Trino** | `host.docker.internal` / `localhost` | `8082` | `admin` | *(leave blank)* | Catalog: `system` (or `tpch`) | ✅ Passed (All Green) | Default catalog `system` or `tpch` |
| **SQLite** | `localhost` | `0` | *(leave blank)* | *(leave blank)* | `main` | ✅ Passed (All Green) | In-memory mode (no files required) |
| **ChromaDB** *(AI Studio)* | `host.docker.internal` | `8000` | *(None)* | *(None)* | Default collection | ✅ Active | For RAG & AI Agent vector stores |

> 💡 **Why `host.docker.internal`?**  
> OpenMetadata ingestion runs inside a Docker container (`openmetadata_ingestion`). To reach databases running on your host Mac's mapped ports from inside another container, always use `host.docker.internal` as the host.

---

## Data Persistence & Volumes

All persistent state is stored in bind-mounted directories within `docker-utils/`:

```
docker-utils/
├── keycloak-data/      # Keycloak realm, user, and client state
├── spark-data/         # Spark warehouse, checkpoint, and Ivy cache
├── redis-data/         # Redis appendonly file (AOF)
├── registry-data/      # Docker image blobs and manifests
├── postgres-data/      # PostgreSQL system catalogs and vector tables
├── ngrok-data/         # ngrok logs and session configs
├── chromadb-data/      # ChromaDB collections and vector indices
├── mysql-data/         # MySQL InnoDB tablespaces
├── mongodb-data/       # MongoDB WiredTiger storage engine data
└── mssql-data/         # MS SQL Server MDF/LDF database files
```

- These directories are preserved across `docker compose down` and system reboots.
- All data directories are excluded from Git via `.gitignore`.
- To completely reset any single service to factory defaults, stop the container, delete only that specific `-data` folder, and start the service again.

---

## Maintenance & Troubleshooting

### Useful Commands

```bash
# Check status of all containers
docker compose ps -a

# Check resource consumption (CPU / RAM)
docker stats

# View logs with timestamp
docker compose logs -f -t <service_name>

# Restart a specific service
docker compose restart <service_name>

# Rebuild / re-pull images
docker compose pull
```

### Common Issues

1. **Port conflict on port 8080 / 8081 / 8089:**  
   Keycloak uses port `8080`, OpenMetadata Ingestion uses `8081`, and Presto uses `8089`. Trino's internal port `8080` is therefore mapped to host port **`8082`** to prevent port collisions.
2. **Postgres `pg_stat_statements` error:**  
   PostgreSQL requires `shared_preload_libraries=pg_stat_statements` at launch time. This is handled by the `command` attribute in `docker-compose.yml`.
3. **ngrok Ollama 403 Forbidden:**  
   Ensure `--host-header=rewrite` is present in the `ngrok` command line in `docker-compose.yml` so Ollama's local DNS rebinding protection accepts forwarded requests.
4. **Connection Refused in OpenMetadata Ingestion:**  
   Verify you are using `host.docker.internal` rather than `localhost` in the Hermes GUI connector form.
