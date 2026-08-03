# BmInfra — Pending Tasks

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

## Cleanup (after a confidence period, ~1 week stable)

- [ ] Disable + stop the old system PostgreSQL (kept running as rollback):
  `systemctl disable --now postgresql@16-main`
- [ ] Remove the stray 5-month-old `docling-api` container on port 5010:
  `docker rm -f docling-api && docker rmi docling-api`
- [ ] Remove old deployment leftovers once unneeded: `/root/BmBackEnd`, `/root/DoclingBillReader`,
  `/opt/DoclingBillReader`, `/opt/docling*`, old systemd unit files.
- [ ] Keep `/root/bm_backup_2026-08-03_0842.dump` (pre-migration DB backup) — do not delete.

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
- [ ] **Future**: if LLM-based extraction is reintroduced, decide where the LLM runs
  (container vs. host with `extra_hosts: host.docker.internal`) and re-add `LLM_*` env
  vars to the compose service accordingly.
- [ ] Consider building/pushing images to a registry instead of building on the VPS.

## QA environment

- [x] `bm_qa` database — already exists (created by `init-databases.sql` on first
  Postgres container start); QA backend healthy on `localhost:9081`.
- [ ] **Expose QA externally** when needed: open ufw ports `9081` (backend) and
  `6678` (n8n QA) — currently blocked, so the GitHub Actions QA health check is
  non-blocking. Command: `ufw allow 9081/tcp && ufw allow 6678/tcp`.
  Consider restricting to specific source IPs rather than `Anywhere`.

## Infra hardening (optional)

- [ ] Domain + Let's Encrypt SSL (nginx :443).
- [ ] Clean up nginx port mapping: the override appends to base `8090/8091` instead of
  replacing — use `ports: !reset` in `docker-compose.override.yml` if the extra ports are unwanted.
- [ ] Automated Postgres backups (pg_dump cron → off-box copy).

---

## n8n upgrade notes

- n8n runs from the custom `bm/n8n:latest` image (built from `DoclingBillReader/Dockerfile.n8n`,
  Playwright base + Node 22 + custom `n8n-nodes-web-automation` nodes).
- Data lives in the `n8n-prod-data` / `n8n-qa-data` volumes (SQLite).
- Before upgrading: back up the SQLite DB + encryption key from `/home/node/.n8n` inside the
  container (`n8n export:workflow --all` as extra safety). n8n DB migrations are forward-only.
- Verify `n8n-nodes-web-automation` compatibility with the target n8n version.
