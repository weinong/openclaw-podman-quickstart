# OpenClaw Podman Quickstart

Bootstrap a headless Ubuntu host to run OpenClaw-related services with rootless Podman and user-level systemd.

This repo focuses on reproducible bootstrap. Runtime state, credentials, and generated config live in the `openclaw` user's home directory and should not be committed.

## What this sets up

- A dedicated Linux service user, default: `openclaw`.
- Rootless Podman runtime directories and user-level systemd linger.
- A persistent Chromium CDP browser for OpenClaw browser operations.
- A LiteLLM sidecar for model routing.
- A SearXNG sidecar for local web search.
- An optional OpenClaw gateway container skeleton.
- Optional Discord channel bootstrap.

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
- Configures LiteLLM and writes `~/.config/litellm/litellm.env`.
- Configures SearXNG and writes `~/.config/searxng/settings.yml`.
- Installs user systemd units.
- Starts the pod, browser, LiteLLM, and SearXNG services.
- Leaves `openclaw-gateway.service` installed but stopped by default.

Start the gateway after OpenClaw onboarding/configuration is ready:

```bash
./oc.sh start gateway
./oc.sh logs gateway
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

OpenClaw configuration is managed as its own reusable subcommand:

```bash
./oc.sh config openclaw
```

That command creates or patches `~/.openclaw/openclaw.json` with:

- A persistent CDP browser profile at `http://127.0.0.1:9222`.
- A LiteLLM model provider at `http://127.0.0.1:4000`.
- The default primary model `litellm/github_copilot/gpt-4`.

Other config subcommands can be run independently:

```bash
./oc.sh config litellm
./oc.sh config searxng
```

## LiteLLM Subscription Login

The default LiteLLM config uses subscription-backed OAuth/device-code providers:

```text
github_copilot/gpt-4
chatgpt/gpt-5.4
```

Watch LiteLLM logs:

```bash
./oc.sh logs litellm
```

Trigger the first GitHub Copilot request from another terminal:

```bash
set -a
source ~/.config/litellm/litellm.env
set +a

curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "github_copilot/gpt-4",
    "messages": [{"role": "user", "content": "Say hello from GitHub Copilot through LiteLLM."}]
  }' | jq .
```

Token caches are stored under:

```text
~/.local/share/litellm/github_copilot
~/.local/share/litellm/chatgpt
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

Create a Discord application and bot in the Discord Developer Portal, copy the bot token, enable required intents, and invite the bot to your server.

Then run as `openclaw` from the repo checkout:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  ./oc.sh config discord \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --require-mention false
```

Restart the gateway after changing Discord settings:

```bash
./oc.sh restart gateway
```

The bot token is stored in `~/.config/openclaw-gateway/gateway.env`. The access policy is written to `~/.openclaw/openclaw.json`.

## `oc.sh` Commands

```bash
./oc.sh install
./oc.sh install fallback
./oc.sh install quadlet
./oc.sh install --start-gateway
./oc.sh uninstall
./oc.sh uninstall --purge --yes
./oc.sh init
./oc.sh config openclaw
./oc.sh config litellm
./oc.sh config searxng
./oc.sh config discord --dm-user ID --guild ID
./oc.sh start browser|litellm|searxng|gateway|pod|all
./oc.sh stop browser|litellm|searxng|gateway|pod|all
./oc.sh restart browser|litellm|searxng|gateway|pod|all
./oc.sh status browser|litellm|searxng|gateway|pod|all
./oc.sh logs gateway
./oc.sh doctor
```

For development or testing under a non-`openclaw` user, pass `--allow-current-user` to commands that normally enforce the service username.

## Uninstall

Remove installed services, Quadlet files, fallback systemd units, and copied helper scripts while keeping generated config and data:

```bash
./oc.sh uninstall
```

Also remove generated config, credentials, browser data, and LiteLLM token caches:

```bash
./oc.sh uninstall --purge --yes
```

`--purge` deletes `~/.openclaw`, `~/.config/openclaw-gateway`, `~/.config/litellm`, `~/.config/searxng`, `~/.local/share/openclaw-browser`, and `~/.local/share/litellm`.

## Layout

```text
.
├── config/
│   ├── litellm/
│   │   ├── config.yaml
│   │   └── litellm.env.example
│   └── searxng/
│       └── settings.yml
├── deploy/
│   ├── openclaw/
│   │   ├── litellm.container
│   │   ├── openclaw.pod
│   │   ├── openclaw-browser.container
│   │   ├── openclaw-gateway.container
│   │   └── searxng.container
│   └── openclaw-systemd/
│       ├── openclaw-pod.service
│       ├── openclaw-browser.service
│       ├── litellm.service
│       ├── searxng.service
│       ├── openclaw-gateway.service
│       └── bin/
├── docs/
├── oc.sh
└── README.md
```

## Security Notes

- Do not expose Chrome CDP to the public internet.
- Do not expose LiteLLM port `4000` beyond host loopback unless you have explicit auth, TLS, and network policy.
- Do not expose SearXNG port `8080` beyond host loopback unless you have reviewed production hardening and abuse controls.
- Do not commit real `openclaw.json` files if they contain auth profiles, tokens, API keys, or local machine secrets.
- Do not commit `~/.config/openclaw-gateway/gateway.env`; it contains runtime secrets such as `DISCORD_BOT_TOKEN`, `LITELLM_API_KEY`, and `SEARXNG_BASE_URL`.
- Do not commit `~/.config/litellm/litellm.env`; it contains the LiteLLM master key.
- Do not commit `~/.config/searxng/settings.yml`; it contains the generated SearXNG `server.secret_key`.
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
