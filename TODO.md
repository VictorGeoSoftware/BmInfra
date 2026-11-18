# BmInfra — Pending Tasks

Open infrastructure / VPS work. Backend *code* debt lives in
`BmBackEnd/docs/TECH_DEBT.md`; everything about the VPS, Compose, nginx, n8n
hosting and deploy pipelines lives here. Done items are kept below as history.

## Open

### Disk

- [ ] **Docker build cache: 96 GB reclaimable** (`docker system df`, 2026-11-18),
  plus ~11.5 GB of unused images. `docker builder prune` (optionally with
  `--filter until=168h`) frees it; the next image builds are slower once.

### Reliability

- [ ] **Automated off-box Postgres backups**: nightly
  `pg_dumpall -U bm_app | gzip` cron with retention, copied off the VPS
  (e.g. IONOS object storage). Test a restore once. Manual one today:
  `docker compose exec -T postgres pg_dumpall -U bm_app | gzip > /root/backup-$(date +%F).sql.gz`
  (user is `bm_app`, not `postgres`).
- [ ] **The VPS-only `docker-compose.override.yml` is load-bearing** (moved from
  BmBackEnd TECH_DEBT #2). Compose auto-loads it; it is the only place that
  publishes **80/443** and wires `BM_AUTH_EMAIL_ALLOWLIST`. If the VPS is
  rebuilt it is gone and public traffic stops. Current content (2026-11-16):
  ```yaml
  services:
    nginx:
      ports: ["80:80", "443:443"]
    backend-prod:
      environment: [BM_AUTH_EMAIL_ALLOWLIST=${BM_AUTH_EMAIL_ALLOWLIST}]
    backend-qa:
      environment: [BM_AUTH_EMAIL_ALLOWLIST=${BM_AUTH_EMAIL_ALLOWLIST}]
  ```
  Fix: commit it as `docker-compose.vps.yml` and pass `-f` explicitly in the
  BmInfra, BmBackEnd and DoclingBillReader deploy workflows (can't commit it
  under the auto-loaded name: it would bind privileged ports on dev machines).
- [ ] **One missing `.env` variable breaks every deploy pipeline** (moved from
  BmBackEnd TECH_DEBT #8). Compose parses the whole file, so any `${VAR:?}`
  that is unset (e.g. `GRAFANA_ADMIN_PASSWORD`) fails BmBackEnd PROD/QA and
  DoclingBillReader deploys with an error naming an unrelated service. Keep `:?`
  only for security-critical values (`DB_PASSWORD`, `BM_ENCRYPTION_KEY`,
  `INTERNAL_API_TOKEN`, n8n passwords); use `:-default` elsewhere, and keep an
  `env.example` listing every variable.

### Upgrades

- [ ] **Docker upgrade** (held with `apt-mark hold` on 2026-11-16): engine
  29.0 → 29.9, containerd 2.1 → 2.4, compose plugin 2.40 → 5.7. Read the
  Compose 5 release notes first, `apt-mark unhold` the 7 docker packages,
  upgrade in a quiet window (dockerd restart = all containers restart), then
  run a no-op BmInfra deploy (`workflow_dispatch`) to prove CI still works.
  Engine/containerd can go first with compose still held.
- [ ] **n8n deprecation warnings**: set `N8N_RUNNERS_ENABLED=true`,
  `DB_SQLITE_POOL_SIZE` > 0 and `N8N_GIT_NODE_DISABLE_BARE_REPOS=true`. Try on
  `n8n-qa` first (task runners change how Code nodes execute) and run both
  workflows before applying to PROD.

### Someday / only if needed

- [ ] Build/push images to a registry instead of building on the VPS.
- [ ] If LLM-based extraction is reintroduced, decide where the LLM runs
  (container vs. host with `extra_hosts: host.docker.internal`) and re-add `LLM_*` env
  vars to the compose service accordingly.

---

# History (done)

## VPS cleanup (2026-11-18)

- [x] **Rogue n8n removed.** `n8n-compose.service` (Nov 2025) ran
  `/root/docker-compose.yaml` at boot; since the 2026-11-16 reboot it started an
  empty stock n8n (`root-n8n-1`) configured for public `0.0.0.0:5678` (it only
  lost the port race to `n8n-prod`). Verified empty (no workflows/credentials),
  then unit disabled + deleted, stack and volume removed.
- [x] Old host PostgreSQL (`postgresql@16-main`) stopped and disabled.
- [x] Pre-Docker leftovers deleted: `/root/BmBackEnd`, `/root/DoclingBillReader`
  (7.6 GB venv), `/opt/DoclingBillReader`, `/opt/docling*`, old systemd units
  (`bm-backend`, `docling-api`, `docling-price-tables`, `n8n*`, `ollama` drop-in),
  orphan `docling-api` image. ~8 GB freed.
- [x] Archive kept in `/root/pre-docker-archive-2026-11-18/` (root-only):
  `leftover-configs.tgz` (configs, `.env` files, unit files; no venv/node_modules)
  and `old-host-postgres-pg_dumpall.sql.gz`.


Post-migration follow-ups after the VPS Docker cutover (2026-08-03).

## n8n

- [x] Re-import workflows on the VPS — DONE 2026-08-03 (done manually by user via n8n UI).
- [x] Re-add the **Total.es Account** credential (`totalEsCredentials`) — DONE 2026-08-03 (user).
- [x] Fix internal URLs in the workflows — DONE 2026-08-03 (user).
- [x] Update n8n version — DONE 2026-08-03: upgraded `1.117.3` → `1.123.20`
  (newest 1.x whose base image still ships `apk`; from ~1.123.30 n8n uses
  Docker Hardened Images with no package manager, so `apk add chromium` fails).
  Also bumped `playwright` `1.48.2` → `^1.54` (old headless mode removed from
  Chromium ≥ ~131; launch verified against Chromium 142). To go beyond
  1.123.20 / to 2.x later, the Chromium install must be reworked
  (multi-stage copy from alpine, or a Playwright-based base image).

## Cleanup

- [x] Stray `docling-api` container on port 5010 removed (image still there,
  see Open → Cleanup). Old host Postgres and leftovers: see Open.

## CI/CD

- [x] Rewrite `BmBackEnd/.github/workflows/deploy.yml` for Docker-based deploys — DONE 2026-08-03:
  pulls `/opt/bm/BmBackEnd`, syncs `BM_AUTH_EMAIL_ALLOWLIST` from the GitHub secret into
  `/opt/bm/BmInfra/.env`, rebuilds `backend-prod`, recreates both backend containers.
- [x] Rewrite `DoclingBillReader/.github/workflows/deploy.yml` — DONE 2026-08-03:
  pulls `/opt/bm/DoclingBillReader`, rebuilds `docling-api` + `n8n-prod`, recreates the
  four containers. All host-level steps (venv, Ollama install, systemd, host Playwright)
  removed.
- [x] Ollama cleanup — DONE 2026-08-03: Ollama + `qwen2.5:7b` (~4.4GB) removed from the VPS,
  all `LLM_*`/Ollama references stripped from DoclingBillReader (they were vestigial — no
  Python code consumed them; the `/extract-conditions` and `/extract-all-v2` endpoints
  documented in the old README don't exist in the code).
- Registry builds and LLM placement: see Open → Someday.

## QA environment

- [x] `bm_qa` database — already exists (created by `init-databases.sql` on first
  Postgres container start); QA backend healthy on `localhost:9081`.
- [x] Backend image split (2026-08-07): `backend-prod` → `bm/backend:prod`
  (build context `../BmBackEnd`, main branch), `backend-qa` → `bm/backend:qa`
  (build context `../BmBackEnd-qa`, qa branch). Deploys are decoupled —
  BmBackEnd `deploy.yml` deploys PROD on `main` pushes and QA on `qa` pushes.
- [x] nginx vhost for `api.qa.poweredbyadvisors.com` → `backend-qa` (port 80,
  ACME webroot at `/var/www/certbot` for certbot). Port-based QA on :81 kept.
- [x] **On the VPS** (2026-08-07): `/var/www/certbot` created, nginx recreated.
- [x] **DNS (IONOS)** (2026-08-07): A record `api.qa.poweredbyadvisors.com` →
  217.154.181.175; CNAME `app.qa.poweredbyadvisors.com` → Vercel (qa branch).
- [x] **SSL** (2026-08-07): certbot webroot cert issued for `api.qa.*` (expires
  2026-11-05, auto-renew via systemd timer + deploy hook
  `/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh`). nginx serves
  `443 ssl`, HTTP→HTTPS redirect, override maps `443:443`, ufw allows 443.
- [x] ~~Expose QA externally (ufw 9081/6678)~~ — dropped 2026-11-16: QA is
  reached via `https://api.qa.*` and `https://n8n.qa.*`; raw ports are loopback.
- [x] Seed n8n-qa: workflows + Total.es credential present (verified 2026-11-16).

## Infra hardening (optional)

- [x] Domain + Let's Encrypt SSL (nginx :443).
  - [x] PROD (2026-11-16): IONOS A record `api.poweredbyadvisors.com` →
    217.154.181.175; certbot webroot cert issued (expires 2027-02-14, same
    auto-renew as QA); nginx `443 ssl` vhost → `backend-prod`, HTTP→HTTPS
    redirect for the domain. Raw-IP HTTP catch-all kept for installed apps.
  - [x] Deploy fix: workflow restarts nginx instead of `nginx -s reload`
    (single-file bind mount kept the pre-reset nginx.conf; PROD vhost needed
    a manual `docker compose restart nginx` on 2026-11-16).
  - [x] Switch clients: Vercel `BM_BACKEND_URL` (PowerAppWeb + BmWeb PROD) →
    `https://api.poweredbyadvisors.com`. BmApp PR #66 merged to `qa` (app being retired, no release planned).
- [x] Clean up nginx port mapping (2026-11-16): base `8090/8091/8443` now bind to
  127.0.0.1, so the override only adds the public `80` and `443`.
- Automated Postgres backups: see Open → Reliability.

## VPS security plan (started 2026-11-16)

Context: Docker publishes ports past ufw, so every `"N:N"` mapping was open to
the internet, including Postgres and both backends (which bypassed nginx and
exposed the unauthenticated n8n-only endpoints).

- [x] Phase 0: port audit + DB backup (`/root/backup-2026-11-16-0950.sql.gz`).
- [x] Phase 1 (2026-11-16): lock down (BmInfra #7 + BmBackEnd #82).
  - Internal ports (5000, 5001, 5002, 5433, 8081, 9081, 8090/8091/8443) →
    `127.0.0.1`. Reach them with `ssh -L <port>:127.0.0.1:<port> root@<vps>`.
  - nginx: exact-match deny `= /api/v1/consumption-report` in every proxying
    block; raw-IP `:80` catch-all serves ACME only (444 otherwise).
  - VPS override: `81:81` removed (QA reached via `api.qa.*` only).
  - CI health checks use `https://api.poweredbyadvisors.com/health`.
  - Breaks installed BmApp builds that call `http://<ip>:8081` (app retired).
- [x] Phase 2 (2026-11-16, BmInfra #8, BmBackEnd #84, DoclingBillReader #60): shared-secret header on `consumption-report` and
  `batch-process-price-tables` (BmBackEnd).
  - `INTERNAL_API_TOKEN` in VPS `.env` (added 2026-11-16), passed to both
    backends and both n8n instances.
  - n8n "Fetch prices from Total" → "Storing prices" sends
    `X-Internal-Token: {{ $env.INTERNAL_API_TOKEN }}` (PROD + QA).
  - `consumption-report` had 0 calls in 30 days (the live consumption workflow
    answers via webhook response); it is gated anyway.
- [x] Phase 3 (2026-11-16, BmInfra #10): n8n on HTTPS.
  - [x] IONOS A records `n8n` / `n8n.qa` → 217.154.181.175; certbot webroot
    certs issued 2026-11-16 (expire 2027-02-14, same auto-renew).
  - nginx vhosts (websocket push, public `/webhook*/` denied), n8n HTTPS
    settings with `N8N_SECURE_COOKIE=true`, 5678/6678 bound to 127.0.0.1.
- [x] Phase 4: cleanup.
  - [x] ufw (2026-11-16): removed moot 5678/5000/8081 allows and 5010 deny
    (backup `/root/ufw-backup-2026-11-16`). Public: 22, 80, 443 only.
  - [x] Stale docs: TECH_DEBT reload claim, raw-IP URLs (BmBackEnd, BmInfra,
    DoclingBillReader `docs/vps-security-cleanup` PRs).
  - [x] VPS OS updates + reboot (2026-11-16): 91 packages, kernel
    6.8.0-149, ~1 min downtime, all containers back healthy. Pre-reboot DB
    backup `/root/backup-2026-11-16-1258-prereboot.sql.gz`.
  - [x] BmApp PR #66: already merged to `qa`; app retired, nothing to do.

Follow-ups from the security plan are in **Open** at the top.

---

## n8n upgrade notes

- n8n runs from the custom `bm/n8n:latest` image (built from `DoclingBillReader/Dockerfile.n8n`,
  Playwright base + Node 22 + custom `n8n-nodes-web-automation` nodes).
- Data lives in the `n8n-prod-data` / `n8n-qa-data` volumes (SQLite).
- Before upgrading: back up the SQLite DB + encryption key from `/home/node/.n8n` inside the
  container (`n8n export:workflow --all` as extra safety). n8n DB migrations are forward-only.
- Verify `n8n-nodes-web-automation` compatibility with the target n8n version.
