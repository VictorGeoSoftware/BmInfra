# Runbook — deploying the observability stack to the VPS

First-time deployment of Phase 0 + Phase 1 (structured logs, request-ID
correlation, log rotation, Loki + Promtail + Grafana).

**Read §1 before running anything.** The order of these steps is not cosmetic:
one step out of sequence breaks all three deployment pipelines.

- **VPS:** `root@217.154.181.175`
- **Compose project:** `/opt/bm/BmInfra` (manually maintained — no CI updates it)
- **Est. time:** 30–40 min, most of it waiting on image builds

---

## 1. Why the order matters

Two facts that drive everything below.

**a) A missing variable breaks every deploy, not just Grafana.**
`docker-compose.yml` declares:

```yaml
- GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD must be set}
```

The `:?` means *fail if unset*, and Compose parses the **whole file** before it
does anything. So with the variable missing, even an unrelated command fails:

```
$ docker compose build backend-prod
error while interpolating services.grafana.environment.[]:
required variable GRAFANA_ADMIN_PASSWORD is missing a value
```

Three pipelines run `docker compose` against this file — BmBackEnd PROD,
BmBackEnd QA, and DoclingBillReader. **Pull BmInfra before adding the variable
and you break all three.** Step 2 exists solely to prevent this.

**b) Backend code must be JSON-capable before Promtail starts.**
`logback.xml` lives in the BmBackEnd monitoring branch. If Compose sets
`LOG_FORMAT=json` while an older backend image is running, that image has no
`logback.xml`, ignores the variable and keeps logging plain text. Promtail's
backend job would then try to JSON-parse plain text, and its `output` stage
would have no `message` field to emit. Deploying BmBackEnd (steps 3–4) *before*
starting Promtail (step 7) avoids the situation entirely.

---

## 2. Set the Grafana credentials — do this FIRST

Nothing to sign up for. Grafana is self-hosted; these values *create* its admin
login on first startup. Generate a strong one:

```bash
ssh root@217.154.181.175
openssl rand -base64 24        # copy the output; save it in your password manager
```

Append to the VPS env file — note `>>`, not `>`:

```bash
cd /opt/bm/BmInfra
cp .env .env.bak-$(date +%F)   # cheap insurance
cat >> .env <<'EOF'

# ─── Observability (Grafana) ───
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=PASTE_THE_GENERATED_VALUE_HERE
EOF
```

Replace the placeholder, then **verify**:

```bash
grep GRAFANA .env
docker compose config >/dev/null && echo "OK: compose parses"
```

> ⚠️ `GF_SECURITY_ADMIN_PASSWORD` is only read when Grafana initialises its
> database on first boot. Changing it later has no effect unless you reset it
> with `grafana-cli` or wipe the `grafana-data` volume. Pick the real value now.

Expected: the `echo` prints `OK: compose parses`. If it errors, **stop** — a
variable is still missing, and continuing will break deployments.

---

## 3. Deploy the backend to QA

Merge the monitoring branch into `qa`. This triggers `deploy.yml`, which
rebuilds and recreates `backend-qa`.

```bash
# on your laptop
cd BmBackEnd
git checkout qa && git pull
git merge feature/implemeting-monitorization-phase0
git push origin qa
```

Watch the run in GitHub Actions until it goes green, then **verify**:

```bash
ssh root@217.154.181.175 "cd /opt/bm/BmInfra && docker compose ps backend-qa"
curl -s -o /dev/null -w '%{http_code}\n' http://217.154.181.175:8091/health
```

Expected: container `Up (healthy)`, HTTP `200`. Logs are still plain text at
this point — correct, because Compose has not yet been updated. Exercise QA
briefly through the app before continuing.

---

## 4. Deploy the backend to PROD

```bash
cd BmBackEnd
git checkout main && git pull
git merge qa
git push origin main
```

**Verify:**

```bash
ssh root@217.154.181.175 "cd /opt/bm/BmInfra && docker compose ps backend-prod"
```

Expected: `Up (healthy)`. Both backends now contain `logback.xml`, so they can
emit JSON as soon as Compose asks them to.

---

## 5. Update the infrastructure on the VPS

BmInfra has no CI, so this is manual. Merging is safe — nothing auto-deploys.

```bash
# on your laptop
cd BmInfra
git checkout master && git pull
git merge feature/implementing-obesrvability-phase0
git push origin master
```

Then on the VPS:

```bash
ssh root@217.154.181.175
cd /opt/bm/BmInfra
git status          # expect a clean tree; if not, STOP and inspect
git pull
docker compose config >/dev/null && echo "OK: compose still parses"
```

Expected: `OK: compose still parses`. If this fails, step 2 was skipped or
incomplete — fix `.env` before going further; deployments are broken until you do.

---

## 6. Apply the new config to the running services

This turns on JSON logging, log rotation and the new Nginx config. Recreate the
backends and Nginx — Nginx matters because `nginx.conf` gained the correlation
header and the `/metrics` deny.

```bash
cd /opt/bm/BmInfra
docker compose up -d backend-prod backend-qa nginx
```

**Verify JSON logging is actually on:**

```bash
docker compose logs --tail=5 backend-prod
```

Expected: lines beginning `{"timestamp":"…` and containing `"env":"prod"`. If
they are still plain text, the running image predates step 4 — re-check that the
merge to `main` actually deployed.

**Verify Nginx is healthy and the metrics endpoint is closed:**

```bash
docker compose ps nginx
curl -s -o /dev/null -w '%{http_code}\n' http://217.154.181.175:8090/metrics
```

Expected: `Up`, and HTTP `403`.

> If Nginx fails to start, check `docker compose logs nginx` for a certificate
> error. The TLS vhost needs the Let's Encrypt files under `/etc/letsencrypt`,
> which already exist on the VPS.

---

## 7. Start the monitoring stack

```bash
cd /opt/bm/BmInfra
docker compose up -d loki promtail grafana
docker compose ps loki promtail grafana
```

Expected: Loki and Grafana `Up (healthy)`, Promtail `Up`. Give Loki ~45 s to
pass its healthcheck.

**Verify Loki is receiving from all three jobs:**

```bash
curl -s http://127.0.0.1:3100/loki/api/v1/label/job/values
```

Expected: `bm-backend`, `bm-infra`, `bm-nginx`. If a job is missing, check
`docker compose logs promtail`.

---

## 8. Acceptance test — trace one request end to end

Generate a request and capture the id Nginx assigns:

```bash
RID=$(curl -s -i http://217.154.181.175:8090/api/v1/price-table-results \
      | awk 'tolower($1)=="x-request-id:"{print $2}' | tr -d '\r')
echo "request id: $RID"
sleep 10
```

Query Loki for that id across every service:

```bash
curl -s -G http://127.0.0.1:3100/loki/api/v1/query_range \
  --data-urlencode "query={job=~\"bm-.+\"} | requestId=\`$RID\`" \
  --data-urlencode "start=$(( ($(date +%s) - 900) * 1000000000 ))"
```

**Pass criteria:** results from **two** streams — `job="bm-nginx"` and
`job="bm-backend"` — sharing that one id. That is the Phase 1 deliverable: one
request, one story, across hops.

---

## 9. Open Grafana

Grafana binds to `127.0.0.1` only and is deliberately unreachable from the
internet. Tunnel in from your laptop:

```bash
ssh -L 3000:127.0.0.1:3000 root@217.154.181.175
```

Leave that running, then open <http://localhost:3000> and log in with the
credentials from step 2. The Loki datasource and both dashboards are
provisioned automatically — no manual setup.

---

## 10. Day-2 checks

After ~24 h, confirm rotation is capping disk as intended:

```bash
ssh root@217.154.181.175 \
  "du -sh /var/lib/docker/containers/*/*-json.log | sort -h | tail -5"
df -h /
```

Expected: no container log above ~30 MB (`max-size: 10m` × `max-file: 3`).

---

## Rollback

Nothing here migrates data, so rollback is just reverting config.

**Monitoring stack only** (leaves the backends running):

```bash
cd /opt/bm/BmInfra
docker compose stop loki promtail grafana
```

**Back to plain-text logs** without redeploying the backends. `LOG_FORMAT` is
declared as `${PROD_LOG_FORMAT:-json}` / `${QA_LOG_FORMAT:-json}`, so `.env`
overrides it:

```bash
cd /opt/bm/BmInfra
echo 'PROD_LOG_FORMAT=text' >> .env
echo 'QA_LOG_FORMAT=text'   >> .env
docker compose up -d backend-prod backend-qa
```

Verify with `docker compose logs --tail=3 backend-prod` — lines should no longer
start with `{`. The same levers raise verbosity temporarily:
`PROD_LOG_LEVEL=DEBUG`. Remove the lines from `.env` and recreate to go back.

**Full infrastructure revert:**

```bash
cd /opt/bm/BmInfra
git log --oneline -5          # find the commit before the observability merge
git checkout <that-commit> -- docker-compose.yml nginx/nginx.conf
docker compose up -d backend-prod backend-qa nginx
```

The backend application rollback is the normal one: revert the merge on `main`
and let `deploy.yml` redeploy.

---

## Known issues

- **BmInfra has no CI.** `deploy.yml` does `cd /opt/bm/BmInfra` but never pulls
  it, so every infra change needs steps 5–7 by hand. Worth automating next.
- **`./gradlew build` is red on `qa`** — two pre-existing
  `GrantedUsersServiceTest` failures (`Please call Database.connect()`),
  unrelated to observability. Until fixed, a green build cannot be used as a
  merge gate.
- **Prometheus is not deployed yet** (Phase 2). `/metrics` is served by the
  backends and denied at the proxy, but nothing scrapes it.
