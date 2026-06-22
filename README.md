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
| `../BmBackEnd/brielmarnysos-1dc68-22e522af0a00.json` | Firebase service-account JSON (from secure store) |
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

## Services / ports

| Service | Container | Host port |
|---------|-----------|-----------|
| Backend PROD / QA | `backend-prod` / `backend-qa` | 8081 / 9081 |
| Docling PROD / QA | `docling-*` | 5000 / 5001 |
| n8n PROD / QA | `n8n-prod` / `n8n-qa` | 5678 / 6678 |
| Postgres | `postgres` | 5433 |
| nginx | `nginx` | 8090 / 8091 |

> On the VPS, nginx is remapped to `:80` (and later `:443`).
