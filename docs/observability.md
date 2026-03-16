# Observability

The Towlion platform provides a complete observability stack: structured logging, dashboards, and alerting. All apps inherit this automatically from the app-template.

## Structured JSON Logging

Every Towlion app uses `python-json-logger` to emit structured JSON logs to stdout. Docker captures these, Promtail scrapes them, and Loki stores them for querying in Grafana.

### What Gets Logged

The FastAPI middleware logs every HTTP request as a JSON object:

```json
{
  "timestamp": "2026-03-16T12:00:00",
  "level": "INFO",
  "message": "request",
  "method": "GET",
  "path": "/health",
  "status_code": 200,
  "duration_ms": 1.23,
  "client_ip": "172.18.0.1"
}
```

### How It Works

In `app/main.py`, the app-template configures:

1. **Root logger** with `StreamHandler(stdout)` and `JsonFormatter`
2. **Request middleware** that logs method, path, status_code, duration_ms, and client_ip

The Dockerfile uses `--no-access-log` to suppress uvicorn's default access log, since the structured middleware replaces it with richer data.

### Adding Custom Log Lines

Use the standard Python `logging` module — it inherits the JSON formatter:

```python
import logging
logger = logging.getLogger(__name__)
logger.info("task completed", extra={"task_id": 42, "result": "success"})
```

## Dashboards

### Platform Overview

**UID:** `towlion-platform-overview`

Shows all container logs, error rate by container, and a filterable log viewer. Available by default.

### App Dashboard

**UID:** `towlion-app-dashboard`

Per-app observability with a `$app` dropdown:

- **Request Rate** — `count_over_time` by HTTP method (LogQL)
- **Error Rate (5xx)** — Count of responses with status_code >= 500 (LogQL)
- **Response Time p95** — `quantile_over_time` on `duration_ms` field (LogQL, requires Loki 3.0+)
- **Container CPU/Memory** — PromQL panels (requires metrics profile)
- **Recent Logs** — Filterable log stream

### Resource Metrics

**UID:** `towlion-resource-metrics`

Host and container resource usage. Requires the metrics profile (`COMPOSE_PROFILES=metrics`). See [Server Contract](server-contract.md#resource-metrics-optional).

## Alerting Rules

Three Grafana native alert rules are provisioned automatically:

| Rule | Source | Condition | Severity |
|---|---|---|---|
| Error Rate Spike | LogQL | >10 HTTP 5xx errors in 5 minutes | Warning |
| Container Down | PromQL | Container stops reporting metrics | Critical |
| Disk Usage >85% | PromQL | Root filesystem above 85% | Warning |

The Container Down and Disk Usage rules require the metrics profile to be enabled.

These rules supplement the existing `check-alerts.sh` cron job, which runs every 5 minutes and checks containers, disk, memory, TLS, restarts, backups, and HTTP health.

### Viewing Alerts

Navigate to **Alerting > Alert rules** in Grafana (ops.anulectra.com) to see rule status, silences, and history.

## LogQL Query Examples

**All requests to a specific app:**
```
{container=~"todo-app.*"} | json
```

**Slow requests (>500ms):**
```
{container=~"todo-app.*"} | json | duration_ms > 500
```

**Error responses only:**
```
{container=~"todo-app.*"} | json | status_code >= 400
```

**Request count by path (last hour):**
```
sum by (path) (count_over_time({container=~"todo-app.*"} | json | __error__=`` [1h]))
```

**p99 response time:**
```
quantile_over_time(0.99, {container=~"todo-app.*"} | json | unwrap duration_ms [5m]) by ()
```

## Enabling Metrics

The CPU/Memory panels in the App Dashboard and two of the three alert rules require Prometheus, cAdvisor, and node-exporter. To enable:

```bash
# Add to /opt/platform/.env
echo "COMPOSE_PROFILES=metrics" >> /opt/platform/.env

# Restart services
cd /opt/platform && docker compose up -d
```

Or bootstrap with `sudo ENABLE_METRICS=true bash bootstrap-server.sh`.
