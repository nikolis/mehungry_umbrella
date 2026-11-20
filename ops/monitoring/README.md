# Mehungry monitoring stack

Grafana + Prometheus in Docker Compose, running on the LAN box `192.168.1.53`
(deployed copy: `~/monitoring`). Grafana: <http://192.168.1.53:3000> (user `admin`,
password in `~/monitoring/.env`).

| Source | Path into Grafana | Dashboards (folder) |
|---|---|---|
| Backend PromEx metrics | Prometheus scrapes `https://m3hungry.fly.dev/metrics` with `METRICS_API_TOKEN`, one job per Fly machine | Backend |
| Fly platform metrics | `Fly` datasource → `https://api.fly.io/prometheus/personal` with a read-only Fly token | Fly |
| Supabase project metrics | Prometheus scrapes `https://<ref>.supabase.co/customer/v1/privileged/metrics` | Supabase |
| Sentry (mobile app, Android + iOS) | `Sentry` datasource plugin → `https://de.sentry.io` | Mobile |

## Operating it

```sh
# deploy config changes from this repo
rsync -a --exclude .env ops/monitoring/ 192.168.1.53:monitoring/
ssh 192.168.1.53 'cd ~/monitoring && docker compose up -d --force-recreate'

# scrape target health (Prometheus is bound to localhost on the box)
ssh 192.168.1.53 'curl -s localhost:9090/api/v1/targets'
```

Secrets live only in `~/monitoring/.env` on the box (see `.env.example`). After
editing it, run `docker compose up -d --force-recreate`.

## Things that need manual upkeep

- **Fly machine list.** `/metrics` is scraped per machine by pinning each job with
  the `fly-force-instance-id` header (`prometheus/prometheus.yml.tmpl`). When a
  machine is created or destroyed, update the machine IDs there.
- **PromEx dashboards** in `grafana/dashboards/Backend/promex_*.json` are rendered
  from the app (`mix prom_ex.dashboard.export -d <name>.json -m MehungryWeb.PromEx -s`),
  with the datasource set to uid `prometheus` and two variable fixes: Ecto `$repo`
  and Oban `$oban` are sourced from live metrics, because the `*_init_status_info`
  metrics they normally use are never emitted in this umbrella. Re-render after a PromEx upgrade.
- `grafana/dashboards/Supabase/supabase_project.json` is the upstream dashboard
  from <https://github.com/supabase/supabase-grafana> (`grafana/dashboard.json`).
- Dashboards are file-provisioned and read-only in the UI; edit the JSON here.
