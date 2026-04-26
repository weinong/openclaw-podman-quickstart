# OpenClaw Podman Quickstart

Bootstrap a headless Ubuntu host to run OpenClaw-related services with rootless Podman and user-level systemd.

This repo focuses on **bootstrap**, not snapshot/backup. It is meant to reproduce the setup quickly on a fresh VM.

## What this sets up

- A dedicated Linux service user, default: `openclaw`.
- Rootless Podman runtime directories and user-level systemd linger.
- A persistent Chromium CDP browser for OpenClaw browser operations.
- A LiteLLM sidecar for model routing.
- A SearXNG sidecar for local web search.
- An optional OpenClaw gateway container skeleton.
- Optional Discord channel bootstrap.
- Optional Codex/Copilot CLI auth guidance for tool-style usage.

## Important: Ubuntu 24.04 uses the fallback path

Ubuntu 24.04 ships Podman 4.9.3. It includes Quadlet, but its Quadlet support does **not** include `.pod` files. That means this file is ignored by the generator on Ubuntu 24.04:

```text
deploy/openclaw/openclaw.pod
```

If you run the pure Quadlet installer on Ubuntu 24.04, you may see:

```text
Failed to start openclaw-pod.service: Unit openclaw-pod.service not found.
```

For Ubuntu 24.04, use the classic user-systemd fallback installer:

```bash
sudo ./scripts/install-openclaw-systemd-fallback.sh openclaw
```

The fallback preserves the same runtime model:

```text
Podman pod: openclaw
├── openclaw-browser
├── openclaw-litellm
├── openclaw-searxng
└── openclaw-gateway
```

but creates it with normal user systemd services instead of `.pod` Quadlet.

## Recommended fast path for Ubuntu 24.04

From a fresh Ubuntu 24.04 VM:

```bash
sudo apt-get update
sudo apt-get install -y git

git clone https://github.com/weinong/openclaw-podman-quickstart.git
cd openclaw-podman-quickstart

sudo ./scripts/bootstrap-os.sh openclaw
sudo ./scripts/install-openclaw-podman.sh openclaw || true
sudo ./scripts/install-openclaw-systemd-fallback.sh openclaw
```

Why both installers?

- `install-openclaw-podman.sh` creates config files such as `openclaw.json`, LiteLLM config, SearXNG config, and gateway env files.
- `install-openclaw-systemd-fallback.sh` installs Podman-4.9-compatible user systemd services and starts the pod/browser/LiteLLM/SearXNG services.

After install, check status:

```bash
svc_user=openclaw
uid="$(id -u "$svc_user")"

sudo -u "$svc_user" env \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user status \
    openclaw-pod.service \
    openclaw-browser.service \
    litellm.service \
    searxng.service \
    --no-pager
```

Validate endpoints:

```bash
sudo -iu openclaw

podman pod ps
podman ps -a

curl -fsS http://127.0.0.1:9222/json/version | jq .
curl -fsS http://127.0.0.1:4000/health/liveliness | jq .
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG OK"
```

The OpenClaw gateway service is installed but not started automatically. Start it after OpenClaw onboarding/configuration is ready:

```bash
sudo -iu openclaw
systemctl --user start openclaw-gateway.service
journalctl --user -u openclaw-gateway.service -f
```

## Pure Quadlet path for newer Podman

If your Podman supports `.pod` Quadlet units, you can use the pure Quadlet path:

```bash
sudo ./scripts/bootstrap-os.sh openclaw
sudo ./scripts/install-openclaw-podman.sh openclaw
```

Check whether `.pod` Quadlet is supported:

```bash
man podman-systemd.unit | head -40
```

If the synopsis includes `name.pod`, pure Quadlet should work. If it only lists `.container`, `.volume`, `.network`, `.kube`, and `.image`, use the Ubuntu 24.04 fallback path instead.

## Runtime endpoints

All services bind to localhost through the Podman pod:

```text
Chromium CDP: http://127.0.0.1:9222
LiteLLM:      http://127.0.0.1:4000
SearXNG:      http://127.0.0.1:8080
```

OpenClaw is preconfigured to use:

```json
{
  "browser": {
    "enabled": true,
    "defaultProfile": "default",
    "profiles": {
      "default": {
        "driver": "cdp",
        "cdpUrl": "http://127.0.0.1:9222"
      }
    }
  },
  "models": {
    "providers": {
      "litellm": {
        "baseUrl": "http://127.0.0.1:4000",
        "apiKey": "${LITELLM_API_KEY}",
        "api": "openai-completions"
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "litellm/github_copilot/gpt-4"
      }
    }
  }
}
```

## LiteLLM subscription login

The default LiteLLM config uses subscription-backed OAuth/device-code providers:

```text
github_copilot/gpt-4
chatgpt/gpt-5.4
```

Start LiteLLM logs in one terminal:

```bash
sudo -iu openclaw
journalctl --user -u litellm.service -f
```

Trigger the first GitHub Copilot request from another terminal. The first request should print a device-code login URL/code in the LiteLLM logs:

```bash
sudo -iu openclaw
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

To trigger ChatGPT subscription login:

```bash
curl -s http://127.0.0.1:4000/v1/responses \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "chatgpt/gpt-5.4",
    "input": "Say hello from ChatGPT through LiteLLM."
  }' | jq .
```

Token caches are stored under:

```text
~openclaw/.local/share/litellm/github_copilot
~openclaw/.local/share/litellm/chatgpt
```

Treat those directories as secrets.

## SearXNG search

Validate SearXNG:

```bash
sudo -iu openclaw
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG OK"
curl -fsS 'http://127.0.0.1:8080/search?q=openclaw&format=json' | jq '.query, (.results | length)'
```

OpenClaw is configured to use SearXNG as its web search provider through `~openclaw/.openclaw/openclaw.json` and environment values in:

```text
~openclaw/.config/openclaw-gateway/gateway.env
```

## Persistent browser

Validate Chromium CDP:

```bash
sudo -iu openclaw
curl -fsS http://127.0.0.1:9222/json/version | jq .
curl -fsS http://127.0.0.1:9222/json/list | jq .
```

If the OpenClaw CLI is installed:

```bash
openclaw browser --browser-profile default doctor
```

## Discord bootstrap

Create a Discord application and bot in the Discord Developer Portal, copy the bot token, enable the required intents, and invite the bot to your server.

Then run:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  sudo -E bash ./scripts/configure-discord.sh openclaw \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --require-mention false
```

This configures:

```text
DM policy: allowlist
Allowed DM users: values from --dm-user
Guild/server policy: allowlist
Allowed guilds: values from --guild
Mention requirement: false by default in this example
```

The bot token is stored in:

```text
~openclaw/.config/openclaw-gateway/gateway.env
```

The access policy is written to:

```text
~openclaw/.openclaw/openclaw.json
```

Restart the gateway after changing Discord settings:

```bash
sudo -iu openclaw
systemctl --user restart openclaw-gateway.service
```

## Uninstall

See [docs/uninstall.md](docs/uninstall.md) for cleanup instructions.

The uninstall guide covers:

```text
runtime uninstall: stop services, remove containers/pod, remove user units/helpers, keep state
full purge: also remove OpenClaw/LiteLLM/SearXNG state, OAuth caches, images, and optionally the openclaw user
```

Minimal runtime cleanup:

```bash
svc_user=openclaw
uid="$(id -u "$svc_user")"
home_dir="$(getent passwd "$svc_user" | cut -d: -f6)"

sudo -u "$svc_user" env \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user stop \
    openclaw-gateway.service \
    openclaw-browser.service \
    litellm.service \
    searxng.service \
    openclaw-pod.service || true

sudo -iu "$svc_user" bash -lc '
  podman rm -f openclaw-gateway openclaw-browser openclaw-litellm openclaw-searxng 2>/dev/null || true
  podman pod rm -f openclaw 2>/dev/null || true
'
```

Full purge also removes secrets and token caches, so review the dedicated uninstall guide before running it.

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
│   ├── bootstrap.md
│   ├── discord-bootstrap.md
│   ├── litellm-bootstrap.md
│   ├── podman-49-fallback.md
│   ├── searxng-bootstrap.md
│   ├── subscription-cli-auth.md
│   └── uninstall.md
├── scripts/
│   ├── bootstrap-os.sh
│   ├── configure-discord.sh
│   ├── configure-litellm.sh
│   ├── configure-searxng.sh
│   ├── doctor-openclaw-podman.sh
│   ├── install-openclaw-podman.sh
│   └── install-openclaw-systemd-fallback.sh
└── README.md
```

## Security notes

- Do not expose Chrome CDP to the public internet.
- Do not expose LiteLLM port `4000` beyond host loopback unless you have explicit auth, TLS, and network policy.
- Do not expose SearXNG port `8080` beyond host loopback unless you have reviewed production hardening and abuse controls.
- Do not commit real `openclaw.json` files if they contain auth profiles, tokens, API keys, or local machine secrets.
- Do not commit `~openclaw/.config/openclaw-gateway/gateway.env`; it contains runtime secrets such as `DISCORD_BOT_TOKEN`, `LITELLM_API_KEY`, and `SEARXNG_BASE_URL`.
- Do not commit `~openclaw/.config/litellm/litellm.env`; it contains the LiteLLM master key.
- Do not commit `~openclaw/.config/searxng/settings.yml`; it contains the generated SearXNG `server.secret_key`.
- Do not commit `~openclaw/.local/share/litellm/github_copilot`; it contains OAuth-derived Copilot credentials.
- Do not commit `~openclaw/.local/share/litellm/chatgpt`; it contains OAuth-derived ChatGPT credentials.
- This repo intentionally avoids snapshotting runtime state.
- Treat the OpenClaw gateway, LiteLLM, SearXNG, and browser CDP endpoint as sensitive control surfaces.

## Detailed guides

- [Bootstrap OpenClaw with rootless Podman](docs/bootstrap.md)
- [Podman 4.9 systemd fallback](docs/podman-49-fallback.md)
- [Bootstrap LiteLLM sidecar for OpenClaw](docs/litellm-bootstrap.md)
- [Bootstrap SearXNG for OpenClaw](docs/searxng-bootstrap.md)
- [Codex and Copilot CLI auth](docs/subscription-cli-auth.md)
- [Bootstrap Discord for OpenClaw](docs/discord-bootstrap.md)
- [Uninstall OpenClaw Podman quickstart](docs/uninstall.md)
