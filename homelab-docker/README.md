# homelab-docker

A Docker Compose stack that runs a local container registry and an
OpenTelemetry-based observability stack. All persistent data lives in one
folder on a mounted disk.

## What's in the stack

| Service | Image | Host port | Purpose |
|---|---|---|---|
| `registry` | `registry:3` | 5050 | Local Docker/OCI image registry |
| `otel-collector` | `otel/opentelemetry-collector-contrib` | 4317 (gRPC), 4318 (HTTP) | Single OTLP entry point for traces, logs and metrics |
| `loki` | `grafana/loki` | – | Log storage |
| `tempo` | `grafana/tempo` | – | Trace storage |
| `prometheus` | `prom/prometheus` | – | Metrics storage |
| `grafana` | `grafana/grafana` | 3000 | Dashboards and Explore UI |
| `init-storage` | `busybox` | – | One-shot job that creates the data folders and sets their ownership |

Loki, Tempo and Prometheus are not published on the host; they are reachable
only from other containers on the compose network.

### Data flow

```
your apps ──OTLP──▶ otel-collector ──traces──▶ tempo ──span metrics──▶ prometheus
                         │        ──logs────▶ loki
                         │        ──metrics─▶ prometheus
                         └─ scrapes registry:5001/metrics
grafana ──queries──▶ loki, tempo, prometheus
```

- Applications send everything to the collector on `localhost:4317` (gRPC) or
  `localhost:4318` (HTTP).
- Tempo's metrics generator derives service-graph and span metrics from traces
  and remote-writes them to Prometheus.
- Prometheus also scrapes Loki, Tempo, the collector and itself.
- Grafana is provisioned with all three datasources, cross-linked so you can
  jump from a log line to its trace, from a trace to its logs, and from a
  metric exemplar to its trace.

## Layout

```
docker-compose.yml
.env                              settings (data folder, ports, credentials)
config/
  otel-collector.yaml             receivers, pipelines, exporters
  loki.yaml
  tempo.yaml
  prometheus.yaml
  grafana-datasources.yaml        provisioned datasources
```

## Configuration

Settings are in `.env`:

| Variable | Default | Meaning |
|---|---|---|
| `DATA_DIR` | `./data` | Host folder for all persistent data. Set this to an absolute path on your mounted disk. |
| `REGISTRY_PORT` | `5050` | Host port for the registry (5000 is used by AirPlay Receiver on macOS) |
| `GRAFANA_PORT` | `3000` | Host port for Grafana |
| `GRAFANA_ADMIN_USER` | `admin` | Grafana admin login |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Grafana admin password; only applied when Grafana first creates its database |
| `METRICS_RETENTION` | `15d` | Prometheus retention |

Loki and Tempo retention is 7 days (`retention_period` in `config/loki.yaml`,
`block_retention` in `config/tempo.yaml`).

### Storage

`init-storage` creates these subfolders under `DATA_DIR` on every `up`:

| Folder | Used by | Owner (UID) |
|---|---|---|
| `registry/` | registry | root |
| `loki/` | Loki | 10001 |
| `tempo/` | Tempo | 10001 |
| `prometheus/` | Prometheus | 65534 |
| `grafana/` | Grafana | 472 |

Make sure the disk is mounted before starting the stack. If it is not, Docker
will create `DATA_DIR` on the underlying filesystem and the stack will start
with empty data.

## Managing the stack

Run these from this folder.

### Start, stop, status

```bash
docker compose up -d          # start (or apply changes to docker-compose.yml / .env)
docker compose ps             # status
docker compose stop           # stop, keep containers
docker compose down           # stop and remove containers; data in DATA_DIR is kept
```

### Logs

```bash
docker compose logs -f                  # all services
docker compose logs -f otel-collector   # one service
```

### After changing a config file

Files in `config/` are mounted read-only and read at startup, so restart the
service that uses the file:

```bash
docker compose restart otel-collector
```

### Upgrading

Image versions are pinned in `docker-compose.yml`. Edit the tag, then:

```bash
docker compose pull
docker compose up -d
```

### Backup and reset

Everything stateful is under `DATA_DIR`. To back up, stop the stack and copy
that folder. To reset a single component, stop the stack, delete its subfolder
and start again; `init-storage` recreates it.

## Using the registry

```bash
docker tag myimage:latest localhost:5050/myimage:latest
docker push localhost:5050/myimage:latest
docker pull localhost:5050/myimage:latest
```

List repositories and tags:

```bash
curl http://localhost:5050/v2/_catalog
curl http://localhost:5050/v2/myimage/tags/list
```

Deleting a manifest through the API only removes the reference. Reclaim disk
space with the garbage collector:

```bash
docker compose exec registry registry garbage-collect --delete-untagged /etc/distribution/config.yml
```

The registry has no authentication and serves plain HTTP. Docker allows that
for `localhost` only. To push from another machine, either add
`"insecure-registries": ["<host>:5050"]` to that machine's Docker daemon
config, or put a TLS reverse proxy in front of the registry.

## Sending telemetry

Point any OpenTelemetry SDK or agent at the collector:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_SERVICE_NAME=my-service
```

Use `http://localhost:4317` for gRPC exporters. Containers on the same compose
network use `http://otel-collector:4318` instead.

## Grafana

Open http://localhost:3000 and log in with the credentials from `.env`.
Datasources `Prometheus`, `Loki` and `Tempo` are already provisioned; use
**Explore** to query them. Dashboards you create are stored in
`DATA_DIR/grafana`.

## Troubleshooting

- **Port already in use**: change `REGISTRY_PORT` or `GRAFANA_PORT` in `.env`.
  Ports 4317/4318 are set in `docker-compose.yml`.
- **Permission denied in Loki, Tempo, Prometheus or Grafana logs**: the data
  folder ownership is wrong. Run `docker compose up init-storage` and restart
  the service. Some network and exFAT/NTFS mounts do not support `chown`; use
  a filesystem that does.
- **No data in Grafana**: check `docker compose logs otel-collector` for
  export errors, then the logs of the backend for that signal.
- **Grafana password in `.env` is ignored**: it only applies on first start.
  Reset it with `docker compose exec grafana grafana cli admin reset-admin-password <new>`.
