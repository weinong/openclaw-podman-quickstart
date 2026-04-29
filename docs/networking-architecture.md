# Networking Architecture

This document describes how the Podman networks and port bindings are arranged for the core OpenClaw pod and the optional observability pod.

## Pods

The core stack runs in the `openclaw` pod:

```text
openclaw
|-- openclaw-browser
|-- openclaw-litellm
|-- openclaw-searxng
`-- openclaw-gateway
```

The observability stack runs in a separate `openclaw-observability` pod:

```text
openclaw-observability
|-- openclaw-grafana
|-- openclaw-prometheus
|-- openclaw-loki
|-- openclaw-alloy
`-- openclaw-podman-exporter
```

The two-pod design keeps observability optional and independently installable while still allowing the OpenClaw gateway to send telemetry to Alloy.

## Networks

Both pods attach to two Podman networks:

```text
podman
openclaw-internal
```

The default `podman` bridge provides normal container networking and outbound access.

The `openclaw-internal` bridge is created with `podman network create --internal openclaw-internal`. It is used for pod-to-pod service discovery and telemetry traffic that should not be exposed on the host or LAN.

The observability pod has this network alias on `openclaw-internal`:

```text
openclaw-alloy
```

That alias lets the OpenClaw gateway reach Alloy at:

```text
http://openclaw-alloy:4318
```

## Port Bindings

Host-facing ports are explicitly bound to loopback.

Core pod:

```text
127.0.0.1:18789 -> gateway
127.0.0.1:18791 -> gateway control service
127.0.0.1:4000  -> LiteLLM
127.0.0.1:8080  -> SearXNG
```

Observability pod:

```text
127.0.0.1:3000  -> Grafana
127.0.0.1:9090  -> Prometheus
127.0.0.1:3100  -> Loki
127.0.0.1:4318  -> Alloy OTLP HTTP
127.0.0.1:14317 -> Alloy OTLP gRPC container port 4317
```

OTLP gRPC uses host port `14317` because port `4317` may already be used by other local OpenTelemetry tooling on the host.

## Traffic Paths

OpenClaw gateway to Alloy:

```text
openclaw-gateway
  -> openclaw-internal DNS alias openclaw-alloy
  -> openclaw-observability pod
  -> openclaw-alloy:4318
```

Host browser to Grafana:

```text
browser or SSH port-forward client
  -> 127.0.0.1:3000
  -> openclaw-observability pod
  -> openclaw-grafana:3000
```

Prometheus scraping inside the observability pod:

```text
openclaw-prometheus
  -> localhost:12345 for Alloy metrics
  -> localhost:3100 for Loki metrics
  -> localhost:9882 for podman-exporter metrics
  -> localhost:9090 for Prometheus self-scrape
```

Because Grafana, Prometheus, Loki, Alloy, and podman-exporter share one pod network namespace, those `localhost` scrape targets refer to services inside the observability pod.

## Fallback Systemd Units

Ubuntu 24.04's Podman 4.9 fallback uses classic user systemd units.

The shared internal network is managed by:

```text
~/.config/systemd/user/openclaw-internal-network.service
```

The installed service ensures the network exists with:

```bash
podman network exists openclaw-internal || podman network create --internal openclaw-internal
```

`oc.sh` also checks and creates the runtime network before starting pods. This handles the stale-active oneshot case where systemd thinks `openclaw-internal-network.service` is active but the Podman network was removed during an uninstall or manual cleanup.

The fallback pod creation commands attach both pods to both networks:

```bash
podman pod create --name openclaw --network podman --network openclaw-internal ...
podman pod create --name openclaw-observability --network podman --network openclaw-internal --network-alias openclaw-alloy ...
```

## Quadlet Units

For hosts with Quadlet `.pod` support, the equivalent assets are installed under:

```text
~/.config/containers/systemd/openclaw-internal.network
~/.config/containers/systemd/openclaw.pod
~/.config/containers/systemd/openclaw-observability.pod
```

The network unit declares:

```ini
[Network]
NetworkName=openclaw-internal
Internal=true
```

The pod units attach to the default `podman` network and the `openclaw-internal.network` Quadlet network. The observability pod also declares `NetworkAlias=openclaw-alloy`.

## Verification

Verify the pods are attached to both networks:

```bash
podman pod inspect openclaw | jq '.InfraConfig.Networks'
podman pod inspect openclaw-observability | jq '.InfraConfig.Networks'
```

On Podman 4.9, `podman pod inspect` returns one JSON object rather than an array. If your Podman returns an array, use `.[0].InfraConfig.Networks` instead.

Expected networks:

```json
[
  "openclaw-internal",
  "podman"
]
```

Verify in-pod DNS and HTTP reachability:

```bash
podman exec openclaw-gateway getent hosts openclaw-alloy
podman exec openclaw-gateway curl -fsS http://openclaw-alloy:4318/v1/logs -o /dev/null -w 'HTTP %{http_code}\n'
```

`HTTP 405` from the curl command is expected because the OTLP logs endpoint expects POST requests. A DNS failure or `curl: (7) Failed to connect` indicates the shared network or alias is not active.

On Podman 4.9, `podman network inspect openclaw-internal` may not show attached containers, so do not rely on `.[0].containers` as a health check.

## Security Boundary

The host-facing endpoints bind to `127.0.0.1` only. Remote access should use SSH port forwarding, Tailscale, or another explicitly configured tunnel/reverse proxy.

The `openclaw-internal` network is internal to Podman and exists only to support pod-to-pod telemetry traffic. It does not replace Gateway auth, Grafana auth, or any other application-layer controls.
