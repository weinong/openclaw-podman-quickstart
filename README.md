# OpenClaw Podman Quickstart

Bootstrap a headless Ubuntu host to run OpenClaw-related services with rootless Podman and user-level systemd.

This repo focuses on reproducible bootstrap and host/service integration. Runtime state, credentials, and generated config live in the `openclaw` user's home directory and should not be committed.

## Goals

This repo is meant to make a prepared VM become a working, rootless OpenClaw host with one repeatable command. It should give operators a small control surface for installing, configuring, updating, inspecting, and removing the Podman-based services that support OpenClaw.

The goals are:

- Run OpenClaw and its sidecars as the dedicated `openclaw` user, not as root or the VM admin user.
- Keep host resources, service config, generated secrets, and OpenClaw config synchronized.
- Store raw runtime secrets in user-owned env/config files with restrictive permissions.
- Store references to those secrets in `openclaw.json` using OpenClaw SecretRefs where supported.
- Configure OpenClaw using its native concepts: JSON-path config writes, providers, channel accounts, agents, and bindings.
- Support both newer Quadlet deployments and Ubuntu 24.04's Podman 4.9-compatible user-systemd fallback.
- Keep deployed container images auditable with immutable tag-plus-digest pins.
- Make install, doctor, service management, config patching, image inventory, and uninstall available through `oc.sh`.

## What this sets up

- A dedicated Linux service user, default: `openclaw`.
- Rootless Podman runtime directories and user-level systemd linger.
- A persistent Chromium CDP browser for OpenClaw browser operations.
- A LiteLLM sidecar for model routing.
- A SearXNG sidecar for local web search.
- An optional OpenClaw gateway container skeleton.
- Optional Discord channel bootstrap.
- Optional Grafana, Prometheus, Loki, Alloy, podman-exporter, and OTLP observability stack.

## Admin prep

Run this once as a sudo-capable VM admin user:

```bash
sudo apt-get update
sudo apt-get install -y \
  ca-certificates \
  curl \
  dbus-user-session \
  fuse-overlayfs \
  git \
  gnupg \
  iproute2 \
  jq \
  lsof \
  openssl \
  podman \
  slirp4netns \
  systemd-container \
  uidmap

sudo useradd --create-home --shell /bin/bash openclaw || true
sudo loginctl enable-linger openclaw
sudo systemctl start "user@$(id -u openclaw).service"

cat <<'EOF' | sudo -u openclaw tee -a /home/openclaw/.profile >/dev/null

# Make systemctl --user work in headless sudo/su login shells.
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "${XDG_RUNTIME_DIR:-}/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi
EOF
```

Everything else is run as the `openclaw` user. `oc.sh` also exports the user-systemd environment itself, but the `.profile` snippet makes manual `systemctl --user` commands work in headless `sudo -iu openclaw` shells.

## One-Shot Install

From the `openclaw` user:

```bash
sudo -iu openclaw
git clone https://github.com/weinong/openclaw-podman-quickstart.git
cd openclaw-podman-quickstart

./oc.sh install
./oc.sh doctor
```

`./oc.sh install` does the full user-owned bootstrap:

- Creates directories under `~/.config`, `~/.local/share`, and `~/.openclaw`.
- Creates or patches `~/.openclaw/openclaw.json`.
- Generates `OPENCLAW_GATEWAY_TOKEN` in `~/.config/openclaw-gateway/gateway.env` and stores a SecretRef in `openclaw.json`.
- Configures local Gateway mode, token auth, Control UI origins, coding tool profile plus browser access, per-channel-peer DM sessions, and the browser plugin.
- Configures LiteLLM and writes `~/.config/litellm/litellm.env`.
- Configures SearXNG and installs `~/.config/searxng/settings.yml` from the bundled template with a generated secret.
- Installs user systemd units.
- Starts the pod, browser, LiteLLM, and SearXNG services.
- Leaves `openclaw-gateway.service` installed but stopped by default.

Start the gateway after OpenClaw onboarding/configuration is ready:

```bash
./oc.sh start gateway
./oc.sh logs gateway
```

Set `OPENCLAW_CONTROL_UI_ORIGIN` before `./oc.sh config openclaw` or `./oc.sh install` to allow a tailnet Control UI origin. Both full origins and hostnames are accepted:

```bash
OPENCLAW_CONTROL_UI_ORIGIN=https://ubuntu-ts-01.example.ts.net ./oc.sh config openclaw
OPENCLAW_CONTROL_UI_ORIGIN=ubuntu-ts-01.example.ts.net ./oc.sh config openclaw
```

## Ubuntu 24.04 Fallback

Ubuntu 24.04 ships Podman 4.9.3. It includes Quadlet, but its Quadlet support does not include `.pod` files. `./oc.sh install` detects that and uses the classic user-systemd fallback automatically.

You can force a path explicitly:

```bash
./oc.sh install fallback
./oc.sh install quadlet
```

The fallback preserves this runtime model:

```text
Podman pod: openclaw
├── openclaw-browser
├── openclaw-litellm
├── openclaw-searxng
└── openclaw-gateway
```

## Runtime Endpoints

All services bind to localhost through the Podman pod:

```text
Chromium CDP: http://127.0.0.1:9222
LiteLLM:      http://127.0.0.1:4000
SearXNG:      http://127.0.0.1:8080
```

Validate endpoints:

```bash
podman pod ps
podman ps -a

curl -fsS http://127.0.0.1:9222/json/version | jq .
curl -fsS http://127.0.0.1:4000/health/liveliness | jq .
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG OK"
```

## OpenClaw Config

OpenClaw JSON configuration is managed through reusable JSON-path subcommands:

```bash
./oc.sh config file
./oc.sh config get browser.profiles.default.cdpUrl
./oc.sh config set browser.enabled true --strict-json
./oc.sh config unset browser.profiles.default.driver
```

`config set` creates `~/.openclaw/openclaw.json` as `{}` if it does not already exist. Paths use dot and array-index notation like `agents.list[0].tools.exec.node`. Values are parsed as JSON when possible; otherwise they are written as strings. Use `--strict-json` to require JSON parsing.

Feature-specific config commands remain available and use `config set`/`unset` internally:

```bash
./oc.sh config openclaw
```

That command creates or patches `~/.openclaw/openclaw.json` with:

- Gateway bind mode `lan`, for container bridge networking behind host-loopback Podman port publishing.
- A persistent CDP browser profile at `http://127.0.0.1:9222`.
- A LiteLLM model provider at `http://127.0.0.1:4000`.
- The default primary model `litellm/github_copilot/gpt-5.4`.

Other config subcommands can be run independently:

```bash
./oc.sh config litellm
./oc.sh config searxng
```

## LiteLLM Subscription Login

The default LiteLLM config uses GitHub Copilot OAuth/device-code models:

```text
github_copilot/gpt-5.4
github_copilot/gpt-5.5
github_copilot/claude-opus-4.6
```

ChatGPT subscription models in `config/litellm/config.yaml` are commented out by default. Uncomment only the models available to your subscription, or replace/add API-key-backed LiteLLM providers and put the required env vars in `~/.config/litellm/litellm.env`. If you change exposed `model_name` values, update the matching OpenClaw LiteLLM model IDs and `agents.defaults.model.primary` in `~/.openclaw/openclaw.json`.

Watch LiteLLM logs:

```bash
./oc.sh logs litellm
```

Trigger the first GitHub Copilot request from another terminal:

```bash
set -a
source ~/.config/litellm/litellm.env
set +a

curl -s http://127.0.0.1:4000/v1/responses \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "github_copilot/gpt-5.4",
    "input": "Say hello from GitHub Copilot through LiteLLM."
  }' | jq .
```

Token caches are stored under:

```text
~/.local/share/litellm/github_copilot
~/.local/share/litellm/chatgpt     # only used if ChatGPT models are enabled
```

Treat those directories as secrets.

## SearXNG Search

Validate SearXNG:

```bash
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG OK"
curl -fsS 'http://127.0.0.1:8080/search?q=openclaw&format=json' | jq '.query, (.results | length)'
```

Refresh SearXNG config:

```bash
./oc.sh config searxng
./oc.sh restart searxng
```

`./oc.sh config searxng` installs the bundled SearXNG settings template when missing, enables OpenClaw's bundled SearXNG plugin, and points it at the local sidecar.

## Observability Stack

Install the optional local observability stack when you want dashboards, metrics, and container logs:

```bash
./oc.sh observability install
```

This installs and starts:

- Grafana for dashboards.
- Prometheus for metrics storage and scraping.
- Loki for log storage and queries.
- Grafana Alloy for collecting Podman container logs and local OTLP logs/metrics.
- podman-exporter for Podman pod/container/image/volume/network metrics.

It also patches OpenClaw diagnostics to export OTLP to Alloy from inside the shared Podman network:

```text
diagnostics.otel.endpoint: http://openclaw-alloy:4318
diagnostics.otel.protocol: http/protobuf
plugins.entries.diagnostics-otel.enabled: true
```

Runtime endpoints bind to localhost only:

```text
Grafana:    http://127.0.0.1:3000
Prometheus: http://127.0.0.1:9090
Loki:       http://127.0.0.1:3100
OTLP gRPC:  127.0.0.1:14317
OTLP HTTP:  http://127.0.0.1:4318
```

Containers in the OpenClaw pod use the internal endpoint `http://openclaw-alloy:4318`, provided by the shared `openclaw-internal` Podman network. Host processes can continue to use `http://127.0.0.1:4318`.

Grafana credentials are written to `~/.config/openclaw-observability/grafana.env`. Set `GRAFANA_ADMIN_PASSWORD` before install or config refresh to choose the password yourself:

```bash
GRAFANA_ADMIN_PASSWORD='CHANGE_ME' ./oc.sh observability install
```

The generated Grafana dashboard includes Podman container state, CPU, memory, container logs, and OTLP logs. Prometheus also scrapes Grafana Alloy, Loki, Prometheus, and podman-exporter metrics. OTLP metrics sent to Alloy are converted to Prometheus samples and remote-written into local Prometheus. OTLP traces are accepted and written to `~/.local/share/openclaw-observability/alloy/otel-traces.jsonl`; this uses Alloy's public-preview file exporter and does not install a trace query backend like Tempo.

Point OpenTelemetry clients at the local Alloy receiver:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

For gRPC clients, use `http://127.0.0.1:14317`. OTLP logs are available in Grafana Explore with `{job="otel-logs"}`. See [docs/observability-architecture.md](docs/observability-architecture.md) for log and metric data flow, and [docs/networking-architecture.md](docs/networking-architecture.md) for Podman network and port layout.

If you installed an earlier version of this branch and Grafana shows `Failed to fetch` or empty panels, refresh the installed units/config and restart the managed containers so the fixed podman-exporter options and file logging are applied:

```bash
./oc.sh config openclaw
./oc.sh observability config
./oc.sh install fallback --start-gateway
./oc.sh observability install fallback
```

Use `quadlet` instead of `fallback` if this host is using Quadlet `.pod` support.

Manage the stack independently from the core OpenClaw services:

```bash
./oc.sh start observability
./oc.sh observability status
./oc.sh observability logs
./oc.sh observability doctor
./oc.sh observability restart
```

Refresh bundled observability config without reinstalling units:

```bash
./oc.sh observability config
./oc.sh observability restart
```

## Persistent Browser

Validate Chromium CDP:

```bash
curl -fsS http://127.0.0.1:9222/json/version | jq .
curl -fsS http://127.0.0.1:9222/json/list | jq .
```

If the OpenClaw CLI is installed:

```bash
openclaw browser --browser-profile default doctor
```

## Discord Bootstrap

Create a Discord application and bot in the Discord Developer Portal, copy the bot token, enable required intents, and invite the bot to your server. The upstream setup guide is: https://docs.openclaw.ai/channels/discord

Then run as `openclaw` from the repo checkout:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  ./oc.sh config discord \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID
```

Restart the gateway after changing Discord settings:

```bash
./oc.sh restart gateway
```

The raw bot token is stored in `~/.config/openclaw-gateway/gateway.env`. `~/.openclaw/openclaw.json` stores a SecretRef to `DISCORD_BOT_TOKEN` plus the Discord access policy. Discord thread bindings are enabled when Discord config is applied.

Guild messages require a bot mention by default. Add `--require-mention false` without `--channel-id` to disable mention gating for the whole guild, or with `--channel-id` to disable it only for the listed channels.

For multiple Discord bots in one gateway, configure each bot as a separate Discord account and optionally bind it to a separate agent:

```bash
DISCORD_BOT_TOKEN_CODING='YOUR_CODING_BOT_TOKEN' \
  ./oc.sh config discord \
    --account coding \
    --token-env DISCORD_BOT_TOKEN_CODING \
    --agent coding \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --channel-id YOUR_DISCORD_CHANNEL_ID \
    --require-mention false
```

## `oc.sh` Commands

```bash
./oc.sh install
./oc.sh install fallback
./oc.sh install quadlet
./oc.sh install --start-gateway
./oc.sh uninstall
./oc.sh uninstall --purge --yes
./oc.sh init
./oc.sh config file
./oc.sh config get browser.enabled --json
./oc.sh config set browser.enabled true --strict-json
./oc.sh config unset browser.profiles.default.driver
./oc.sh config openclaw
./oc.sh config litellm
./oc.sh config searxng
./oc.sh config discord --dm-user ID --guild ID
./oc.sh observability install
./oc.sh observability status
./oc.sh observability doctor
./oc.sh observability uninstall
./oc.sh start observability
./oc.sh start browser|litellm|searxng|gateway|pod|all
./oc.sh stop browser|litellm|searxng|gateway|pod|all
./oc.sh restart browser|litellm|searxng|gateway|pod|all
./oc.sh status browser|litellm|searxng|gateway|pod|all
./oc.sh logs gateway
./oc.sh images
./oc.sh images --json
./oc.sh doctor
```

For development or testing under a non-`openclaw` user, pass `--allow-current-user` to commands that normally enforce the service username.

## Pinned Images

`oc.sh` owns the tag-plus-digest image references and renders them into the installed Quadlet and fallback systemd assets. Print the pinned image inventory with:

```bash
./oc.sh images
./oc.sh images --json
```

Current pins:

```text
openclaw-gateway ghcr.io/openclaw/openclaw 2026.4.24 sha256:7c4370ff8777555d4c9fe5ab821aaaad7c87188d389a6cf761270725d96ec3e9
openclaw-browser docker.io/chromedp/headless-shell 148.0.7778.56 sha256:8b36bc4bca3f394103db8a2e60f0053969a277b3918abc39acfee819168c4f79
litellm docker.litellm.ai/berriai/litellm main-v1.82.3 sha256:067aee932b8770ed42955ee802a04abdcd369d0995b5e696bb07d6520a231b1c
searxng docker.io/searxng/searxng 2026.4.24-a7ac696b4 sha256:c9100c29c14a77d5289263a671580226c3b8a396a1a0130d2f500f57076a0119
grafana docker.io/grafana/grafana-oss 12.4.3 sha256:2e986801428cd689c2358605289c90ab37d2b39e24808874971f54c99bcdc412
prometheus docker.io/prom/prometheus v3.11.3 sha256:e4254400b85610324913f0dc4acf92603d9984e7519414c5a12811aa6146acc3
loki docker.io/grafana/loki 3.5.8 sha256:00981fd9455db8589c3aa6d06744af3138c4b2c32fdec62101e92c7a704b2642
alloy docker.io/grafana/alloy v1.16.0 sha256:6e00cf7c5a692ff5f24844529416ed017d76fce922f8199004e73d5eca46b6b8
podman-exporter quay.io/navidys/prometheus-podman-exporter v1.21.0 sha256:2ebb9e09101d8cc1e28e3f306b56a722450918e628208435201ed39bd62403cb
```

## Uninstall

See [docs/uninstall.md](docs/uninstall.md) for cleanup details.

Remove installed services, Quadlet files, fallback systemd units, copied helper scripts, containers, and the pod while keeping generated config and data:

```bash
./oc.sh uninstall
```

Also remove generated config, credentials, browser data, and LiteLLM token caches:

```bash
./oc.sh uninstall --purge --yes
```

`--purge` deletes `~/.openclaw`, `~/.config/openclaw-gateway`, `~/.config/litellm`, `~/.config/searxng`, `~/.local/share/openclaw-browser`, and `~/.local/share/litellm`.

Observability has a separate uninstall path:

```bash
./oc.sh observability uninstall
./oc.sh observability uninstall --purge --yes
```

The observability purge deletes `~/.config/openclaw-observability` and `~/.local/share/openclaw-observability`.

## Layout

```text
.
├── config/
│   ├── litellm/
│   │   ├── config.yaml
│   │   └── litellm.env.example
│   ├── observability/
│   │   ├── alloy.alloy
│   │   ├── grafana/
│   │   ├── loki.yml
│   │   └── prometheus.yml
│   └── searxng/
│       └── settings.yml
├── deploy/
│   ├── openclaw/
│   │   ├── alloy.container
│   │   ├── grafana.container
│   │   ├── litellm.container
│   │   ├── loki.container
│   │   ├── openclaw.pod
│   │   ├── openclaw-observability.pod
│   │   ├── openclaw-browser.container
│   │   ├── openclaw-gateway.container
│   │   ├── podman-exporter.container
│   │   ├── prometheus.container
│   │   └── searxng.container
│   └── openclaw-systemd/
│       ├── openclaw-pod.service
│       ├── openclaw-browser.service
│       ├── litellm.service
│       ├── searxng.service
│       ├── openclaw-gateway.service
│       ├── openclaw-observability-pod.service
│       └── bin/
├── docs/
│   ├── bootstrap.md
│   ├── discord-bootstrap.md
│   ├── litellm-bootstrap.md
│   ├── podman-49-fallback.md
│   ├── searxng-bootstrap.md
│   ├── subscription-cli-auth.md
│   └── uninstall.md
├── oc.sh
└── README.md
```

## Security Notes

- Do not expose Chrome CDP to the public internet.
- Do not expose LiteLLM port `4000` beyond host loopback unless you have explicit auth, TLS, and network policy.
- Do not expose SearXNG port `8080` beyond host loopback unless you have reviewed production hardening and abuse controls.
- Do not expose Grafana, Prometheus, Loki, Alloy, OTLP, or podman-exporter ports beyond host loopback without explicit auth, TLS, and network policy.
- Do not commit real `openclaw.json` files if they contain auth profiles, tokens, API keys, or local machine secrets.
- Do not commit `~/.config/openclaw-gateway/gateway.env`; it contains runtime secrets such as `OPENCLAW_GATEWAY_TOKEN`, `DISCORD_BOT_TOKEN`, `LITELLM_API_KEY`, and `SEARXNG_BASE_URL`.
- Do not commit `~/.config/litellm/litellm.env`; it contains the LiteLLM master key.
- Do not commit `~/.config/openclaw-observability/grafana.env`; it contains the Grafana admin password.
- Do not commit `~/.config/searxng/settings.yml`; it contains the generated SearXNG `server.secret_key`.
- Do not commit `~/.local/share/openclaw-observability`; it contains local metrics, logs, and Grafana state.
- Do not commit `~/.local/share/litellm/github_copilot`; it contains OAuth-derived Copilot credentials.
- Do not commit `~/.local/share/litellm/chatgpt`; it contains OAuth-derived ChatGPT credentials.
- This repo intentionally avoids snapshotting runtime state.

## Detailed Guides

- [Bootstrap OpenClaw with rootless Podman](docs/bootstrap.md)
- [Podman 4.9 systemd fallback](docs/podman-49-fallback.md)
- [Bootstrap LiteLLM sidecar for OpenClaw](docs/litellm-bootstrap.md)
- [Bootstrap SearXNG for OpenClaw](docs/searxng-bootstrap.md)
- [Bootstrap Discord for OpenClaw](docs/discord-bootstrap.md)
- [Codex and Copilot CLI auth](docs/subscription-cli-auth.md)
- [Uninstall OpenClaw Podman quickstart](docs/uninstall.md)
