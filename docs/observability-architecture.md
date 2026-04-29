# Observability Log And Metric Architecture

This document describes how the optional observability stack collects, stores, and exposes OpenClaw logs, metrics, and traces.

The stack is installed with:

```bash
./oc.sh observability install
```

## Components

- Grafana provides dashboards and Explore.
- Prometheus stores metrics and scrapes local targets.
- Loki stores logs.
- Grafana Alloy collects Podman log files and receives OTLP telemetry.
- podman-exporter exposes Podman runtime metrics from the rootless Podman socket.

## Podman Container Logs

Managed containers run with the Podman `k8s-file` log driver. This produces Kubernetes-style container log files under the rootless Podman storage tree:

```text
~/.local/share/containers/storage/overlay-containers/*/userdata/ctr.log
```

Alloy mounts that directory read-only and scrapes matching `ctr.log` files with this label:

```text
job="podman-container-logs"
```

The flow is:

```text
OpenClaw/sidecar container stdout/stderr
  -> Podman k8s-file ctr.log
  -> Alloy local.file_match + loki.source.file
  -> Loki
  -> Grafana Explore and dashboard log panels
```

Query these logs in Grafana Explore with:

```logql
{job="podman-container-logs"}
```

## OTLP Logs

`./oc.sh observability config` and `./oc.sh observability install` patch `~/.openclaw/openclaw.json` so the OpenClaw gateway exports OTLP to Alloy from inside the shared Podman network:

```json
{
  "diagnostics": {
    "enabled": true,
    "otel": {
      "enabled": true,
      "endpoint": "http://openclaw-alloy:4318",
      "protocol": "http/protobuf",
      "serviceName": "openclaw-gateway",
      "traces": true,
      "metrics": true,
      "logs": true,
      "sampleRate": 0.2,
      "flushIntervalMs": 60000
    }
  },
  "plugins": {
    "entries": {
      "diagnostics-otel": {
        "enabled": true
      }
    }
  }
}
```

The host also exposes a loopback OTLP HTTP endpoint for local test clients:

```text
http://127.0.0.1:4318
```

The flow is:

```text
OpenClaw diagnostics OTLP logs
  -> http://openclaw-alloy:4318/v1/logs
  -> Alloy otelcol.receiver.otlp
  -> Alloy attributes processor adds job="otel-logs"
  -> Alloy Loki exporter
  -> Loki
  -> Grafana Explore and dashboard log panels
```

Query OTLP logs in Grafana Explore with:

```logql
{job="otel-logs"}
```

Service resource labels are promoted into Loki labels where available, including `service_name` and `service_namespace`.

## Metrics

Prometheus scrapes local observability targets inside the `openclaw-observability` pod:

```text
prometheus:     127.0.0.1:9090
loki:           localhost:3100/metrics
alloy:          localhost:12345/metrics
podman-exporter localhost:9882/metrics
```

podman-exporter runs in the observability pod and reads the rootless Podman API socket mounted at:

```text
/run/podman/podman.sock
```

The Podman metrics flow is:

```text
Rootless Podman socket
  -> podman-exporter
  -> Prometheus scrape job "podman"
  -> Prometheus
  -> Grafana dashboard panels
```

Useful Prometheus metrics include:

```promql
podman_container_state
podman_container_cpu_seconds_total
podman_container_mem_usage_bytes
```

OTLP metrics flow through Alloy and are remote-written into local Prometheus:

```text
OpenClaw diagnostics OTLP metrics
  -> http://openclaw-alloy:4318/v1/metrics
  -> Alloy otelcol.receiver.otlp
  -> Alloy batch processor
  -> Alloy Prometheus exporter
  -> Prometheus remote-write receiver at http://127.0.0.1:9090/api/v1/write
  -> Prometheus
  -> Grafana
```

Prometheus is started with `--web.enable-remote-write-receiver` so Alloy can write converted OTLP metrics to it.

## Traces

OpenClaw trace export is enabled because `diagnostics.otel.traces=true`. The local stack accepts traces, but it does not install a trace query backend such as Tempo.

Alloy writes accepted OTLP traces to:

```text
~/.local/share/openclaw-observability/alloy/otel-traces.jsonl
```

That trace file uses Alloy's public-preview `otelcol.exporter.file`, so Alloy is started with:

```text
--stability.level=public-preview
```

The trace flow is:

```text
OpenClaw diagnostics OTLP traces
  -> http://openclaw-alloy:4318/v1/traces
  -> Alloy otelcol.receiver.otlp
  -> Alloy batch processor
  -> /var/lib/alloy/otel-traces.jsonl
```

## Persistence

Generated observability config is stored under:

```text
~/.config/openclaw-observability
```

Observability runtime data is stored under:

```text
~/.local/share/openclaw-observability
```

Grafana, Prometheus, Loki, and Alloy each use subdirectories there for local state. `./oc.sh observability uninstall` keeps these files. `./oc.sh observability uninstall --purge --yes` removes them.

## Health Checks

Run:

```bash
./oc.sh observability doctor
```

Useful manual checks:

```bash
curl -fsS http://127.0.0.1:3000/api/health | jq .
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:3100/ready
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:4318/v1/logs
curl -fsS http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}'
```

For the in-pod OpenClaw to Alloy path, run:

```bash
podman exec openclaw-gateway getent hosts openclaw-alloy
podman exec openclaw-gateway curl -fsS http://openclaw-alloy:4318/v1/logs -o /dev/null -w 'HTTP %{http_code}\n'
```

`HTTP 405` is a successful reachability result for the second command because it performs a GET against an OTLP endpoint that expects POST requests.
