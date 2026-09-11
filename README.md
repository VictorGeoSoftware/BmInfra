# BmInfra

Deployment / orchestration for the **B&M** stack (Docker Compose).
Pairs with the four application repos:

- [BmBackEnd](https://github.com/VictorGeoSoftware/BmBackEnd) → `bm/backend` image
- [DoclingBillReader](https://github.com/VictorGeoSoftware/DoclingBillReader) → `bm/docling` + `bm/n8n` images
- [BmApp](https://github.com/VictorGeoSoftware/BmApp) (Android client)
- [BmWeb](https://github.com/VictorGeoSoftware/BmWeb) (web client)

## ⚠️ Required directory layout

`docker-compose.yml` uses **relative build contexts** (`../BmBackEnd`,
`../DoclingBillReader`). This repo MUST be cloned as a **sibling** of the app
repos, all under one parent folder:

```
parent/
├── BmInfra/            ← this repo (compose lives here)
├── BmBackEnd/
├── DoclingBillReader/
├── BmApp/
└── BmWeb/
```

Clone everything side by side:

```bash
git clone https://github.com/VictorGeoSoftware/BmInfra.git
git clone https://github.com/VictorGeoSoftware/BmBackEnd.git
git clone https://github.com/VictorGeoSoftware/DoclingBillReader.git
# (BmApp / BmWeb optional for server deploys)
```

## Secrets (never committed — recreate on each machine / the VPS)

| File | How to create |
|------|----------------|
| `.env` | `cp .env.example .env` then fill real values |
| `../brielmarnysos-1dc68-firebase-adminsdk-fbsvc-3e2586a86a.json` | Firebase service-account JSON (from secure store). **Must be readable by the container's non-root user**: `chmod 644` (backend containers run as `bmapp`, not root — `600 root:root` causes `/app/firebase-service-account.json (Permission denied)` at login) |
| `../BmBackEnd/certs/` & `../DoclingBillReader/certs/` | Corporate CA bundles — **local dev only**, leave empty on the VPS |

Generate keys:

```bash
openssl rand -base64 32   # BM_ENCRYPTION_KEY (do NOT change once data is encrypted)
```

## Run

```bash
docker compose up -d --build
docker compose ps
```

## Isolated local QA stack

`docker-compose.local-qa.yml` runs the current local source as QA without the
VPS-only PROD checkout, Nginx/TLS, or observability services. It includes:

- PostgreSQL using the `bm_qa` database
- the customer Docling API
- the Gemini-backed price agent
- QA n8n with the project's custom nodes
- the QA backend built from the sibling `BmBackend` checkout

Create the ignored local configuration once:

```bash
cp local-qa.env.example local-qa.env
# Replace every placeholder in local-qa.env.
```

Then start it from `BmInfra`:

```bash
./bm-local-qa up
```

The launcher resolves all paths from its own location. You can therefore call
it while working in another sibling project, for example from `BmBackend`:

```bash
../BmInfra/bm-local-qa up
../BmInfra/bm-local-qa status
../BmInfra/bm-local-qa logs backend-qa
../BmInfra/bm-local-qa down
```

All published ports bind to `127.0.0.1`. Named volumes preserve the QA
database, Docling models, and n8n state across `down`/`up` cycles. The launcher
does not delete volumes. Local QA PostgreSQL uses host port `15433` to avoid
colliding with the backend-only development database on port `5433`.

On a new n8n volume, open `http://localhost:6678` and import/configure the QA
workflows and their external credentials. Workflow and credential provisioning
is not automated yet; n8n being healthy only means its server is ready.

## Services / ports

| Service | Container | Host port |
|---------|-----------|-----------|
| Backend PROD / QA | `backend-prod` / `backend-qa` | 8081 / 9081 |
| Docling PROD / QA | `docling-*` | 5000 / 5001 |
| n8n PROD / QA | `n8n-prod` / `n8n-qa` | 5678 / 6678 |
| Postgres | `postgres` | 5433 |
| nginx | `nginx` | 8090 / 8091 |

> On the VPS, nginx is remapped to `:80` (and later `:443`).
