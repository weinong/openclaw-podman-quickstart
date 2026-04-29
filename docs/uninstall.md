# Uninstall OpenClaw Podman Quickstart

This guide removes services and files created by this quickstart.

There are two levels of cleanup:

1. Runtime uninstall: stop services, remove containers/pods, remove installed user systemd/Quadlet files and helpers, but keep generated state.
2. Full purge: also remove state, secrets, OAuth token caches, browser profile data, and optional observability data when purging observability separately.

Review commands before running them. The full purge removes credentials and local state.

## Runtime Uninstall

Run from the repo checkout as the `openclaw` user:

```bash
./oc.sh uninstall
```

This removes:

```text
~/.config/systemd/user/openclaw-pod.service
~/.config/systemd/user/openclaw-browser.service
~/.config/systemd/user/openclaw-gateway.service
~/.config/systemd/user/litellm.service
~/.config/systemd/user/searxng.service
~/.config/containers/systemd/openclaw.pod
~/.config/containers/systemd/openclaw-browser.container
~/.config/containers/systemd/openclaw-gateway.container
~/.config/containers/systemd/litellm.container
~/.config/containers/systemd/searxng.container
~/.local/bin/openclaw-run-browser
~/.local/bin/openclaw-run-gateway
~/.local/bin/openclaw-run-litellm
~/.local/bin/openclaw-run-searxng
```

It also stops/removes the `openclaw` Podman pod and managed containers when Podman is available. Shared `openclaw-internal` network assets are removed only when the observability stack is not installed.

Generated config and state are kept.

## Observability Uninstall

The optional Grafana, Prometheus, Loki, Alloy, and podman-exporter stack is managed separately from the core OpenClaw runtime:

```bash
./oc.sh observability uninstall
```

This removes:

```text
~/.config/systemd/user/openclaw-observability-pod.service
~/.config/systemd/user/grafana.service
~/.config/systemd/user/prometheus.service
~/.config/systemd/user/loki.service
~/.config/systemd/user/alloy.service
~/.config/systemd/user/podman-exporter.service
~/.config/containers/systemd/openclaw-observability.pod
~/.config/containers/systemd/grafana.container
~/.config/containers/systemd/prometheus.container
~/.config/containers/systemd/loki.container
~/.config/containers/systemd/alloy.container
~/.config/containers/systemd/podman-exporter.container
~/.local/bin/openclaw-run-grafana
~/.local/bin/openclaw-run-prometheus
~/.local/bin/openclaw-run-loki
~/.local/bin/openclaw-run-alloy
~/.local/bin/openclaw-run-podman-exporter
```

It also stops/removes the `openclaw-observability` Podman pod and managed observability containers when Podman is available. Shared `openclaw-internal` network assets are removed only when the core stack is not installed, and the runtime network is removed only if the core `openclaw` pod is not present.

## Full Purge

Run from the repo checkout as the `openclaw` user:

```bash
./oc.sh uninstall --purge --yes
```

This also removes:

```text
~/.openclaw
~/openclaw-workspace
~/.config/openclaw-gateway
~/.config/litellm
~/.config/searxng
~/.local/share/openclaw-browser
~/.local/share/litellm
```

This removes secrets and state such as:

```text
DISCORD_BOT_TOKEN*
LITELLM_API_KEY
LITELLM_MASTER_KEY
SearXNG server.secret_key
GitHub Copilot OAuth token cache
ChatGPT OAuth token cache
OpenClaw config, default workspace, agents, and sessions
```

Observability config and data use a separate purge command:

```bash
./oc.sh observability uninstall --purge --yes
```

This removes:

```text
~/.config/openclaw-observability
~/.local/share/openclaw-observability
```

This removes the Grafana admin password plus local Grafana, Prometheus, Loki, and Alloy state.

## Optional: Remove Images

`./oc.sh uninstall` does not remove images. Inspect pinned images:

```bash
./oc.sh images
```

Remove pinned images manually if desired:

```bash
podman image rm -f \
  ghcr.io/openclaw/openclaw:2026.4.24@sha256:7c4370ff8777555d4c9fe5ab821aaaad7c87188d389a6cf761270725d96ec3e9 \
  docker.io/chromedp/headless-shell:148.0.7778.56@sha256:8b36bc4bca3f394103db8a2e60f0053969a277b3918abc39acfee819168c4f79 \
  docker.litellm.ai/berriai/litellm:main-v1.82.3@sha256:067aee932b8770ed42955ee802a04abdcd369d0995b5e696bb07d6520a231b1c \
  docker.io/searxng/searxng:2026.4.24-a7ac696b4@sha256:c9100c29c14a77d5289263a671580226c3b8a396a1a0130d2f500f57076a0119 \
  docker.io/grafana/grafana-oss:12.4.3@sha256:2e986801428cd689c2358605289c90ab37d2b39e24808874971f54c99bcdc412 \
  docker.io/prom/prometheus:v3.11.3@sha256:e4254400b85610324913f0dc4acf92603d9984e7519414c5a12811aa6146acc3 \
  docker.io/grafana/loki:3.5.8@sha256:00981fd9455db8589c3aa6d06744af3138c4b2c32fdec62101e92c7a704b2642 \
  docker.io/grafana/alloy:v1.16.0@sha256:6e00cf7c5a692ff5f24844529416ed017d76fce922f8199004e73d5eca46b6b8 \
  quay.io/navidys/prometheus-podman-exporter:v1.21.0@sha256:2ebb9e09101d8cc1e28e3f306b56a722450918e628208435201ed39bd62403cb
```

You can also prune unused rootless Podman data for the service user:

```bash
podman system prune -af
```

## Optional: Disable Linger

If you keep the `openclaw` user but no longer need user services to start at boot, run as a sudo-capable VM admin user:

```bash
sudo loginctl disable-linger openclaw
```

## Optional: Delete The Service User

Only do this after removing state you care about. Run as a sudo-capable VM admin user:

```bash
sudo loginctl disable-linger openclaw || true
sudo userdel -r openclaw
```

## Verify Removal

As the `openclaw` user:

```bash
podman ps -a
podman pod ps
systemctl --user list-unit-files | grep -E 'openclaw|litellm|searxng|grafana|prometheus|loki|alloy|podman-exporter' || true
```

If the service user was deleted, verify from a sudo-capable VM admin user:

```bash
id openclaw 2>/dev/null || echo "user removed"
```
