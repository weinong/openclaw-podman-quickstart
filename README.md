# OpenClaw Podman Quickstart

Bootstrap a headless Ubuntu host to run OpenClaw with rootless Podman, user-level systemd services, a persistent Chromium CDP browser container, a LiteLLM sidecar, a SearXNG search sidecar, and optional Discord gateway configuration.

This repo focuses on **bootstrap**, not snapshot/backup. It is meant to help you reproduce the setup quickly on a fresh VM.

## What this installs

- OS packages needed for the workflow: `podman`, `jq`, `curl`, `git`, `uidmap`, `slirp4netns`, `fuse-overlayfs`, `dbus-user-session`, and related utilities.
- A dedicated Linux user, default: `openclaw`.
- Rootless Podman runtime directories.
- User-level systemd linger for the service user.
- Quadlet units for:
  - an OpenClaw pod
  - a persistent Chromium CDP browser container
  - a LiteLLM proxy sidecar
  - a SearXNG search sidecar
  - an optional OpenClaw gateway container skeleton
- A minimal OpenClaw browser profile config pointing to the persistent CDP endpoint.
- A LiteLLM provider config for OpenClaw, with the default OpenClaw model set to `litellm/github_copilot/gpt-4` and ChatGPT subscription models also available.
- A SearXNG `web_search` provider config for OpenClaw, with SearXNG bound to `127.0.0.1:8080`.
- Optional Discord bot bootstrap with token stored in a user-only env file and access policy stored in OpenClaw config.
- Optional Codex/Copilot CLI auth guidance for tool-style usage.

## Assumptions

- Target OS: Ubuntu 22.04 or 24.04 server.
- You want to run services as a non-root user.
- You want a persistent browser endpoint for OpenClaw, not short-lived Browserless sessions.
- Chrome CDP should stay local to the pod/host and should not be exposed publicly.
- LiteLLM should run locally as the OpenClaw model gateway on `127.0.0.1:4000`.
- SearXNG should run locally as the OpenClaw web search provider on `127.0.0.1:8080`.
- LiteLLM should manage GitHub Copilot and ChatGPT OAuth device-code login for subscription-backed models.
- Discord access should be explicit: allowed DM users, allowed server/guild IDs, and private-server mention behavior.

## Prerequisite packages

On a fresh Ubuntu VM, install `git` first so you can clone this repo:

```bash
sudo apt-get update
sudo apt-get install -y git
```

After cloning the repo, run the OS bootstrap script to install the rest of the packages required by the Podman/systemd workflow:

```bash
sudo ./scripts/bootstrap-os.sh openclaw
```

The bootstrap script installs:

```text
ca-certificates
curl
dbus-user-session
fuse-overlayfs
git
gnupg
iproute2
jq
lsof
openssl
podman
slirp4netns
systemd-container
uidmap
```

If you prefer to install prerequisites manually instead of using the script, run:

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
```

Then create the service user and enable linger manually:

```bash
sudo useradd --create-home --shell /bin/bash openclaw 2>/dev/null || true
sudo loginctl enable-linger openclaw
```

## Fast path

From a fresh Ubuntu VM:

```bash
sudo apt-get update
sudo apt-get install -y git

git clone https://github.com/weinong/openclaw-podman-quickstart.git
cd openclaw-podman-quickstart

sudo ./scripts/bootstrap-os.sh openclaw
sudo ./scripts/install-openclaw-podman.sh openclaw
```

The installer copies these Quadlet files into `~openclaw/.config/containers/systemd/` and starts the pod, browser, LiteLLM, and SearXNG services when their unit files are present:

```text
deploy/openclaw/openclaw.pod
deploy/openclaw/openclaw-browser.container
deploy/openclaw/litellm.container
deploy/openclaw/searxng.container
deploy/openclaw/openclaw-gateway.container
```

Then start LiteLLM and trigger the first GitHub Copilot model request. The first request prints a GitHub device-code login URL/code in the LiteLLM logs:

```bash
sudo -iu openclaw
systemctl --user restart litellm.service
journalctl --user -u litellm.service -f
```

From another terminal:

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

To trigger ChatGPT subscription login too:

```bash
curl -s http://127.0.0.1:4000/v1/responses \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "chatgpt/gpt-5.4",
    "input": "Say hello from ChatGPT through LiteLLM."
  }' | jq .
```

Verify SearXNG search:

```bash
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG OK"
curl -fsS 'http://127.0.0.1:8080/search?q=openclaw&format=json' | jq '.query, (.results | length)'
```

Complete any device-code login in a browser. Then run the doctor:

```bash
./openclaw-podman-quickstart/scripts/doctor-openclaw-podman.sh
```

## Persistent browser service

`deploy/openclaw/openclaw-browser.container` defines the persistent Chromium CDP browser service. The install script copies it to:

```text
~openclaw/.config/containers/systemd/openclaw-browser.container
```

and starts the generated user service:

```text
openclaw-browser.service
```

To install or refresh just the deployed unit files, run from the repo checkout:

```bash
sudo ./scripts/install-openclaw-podman.sh openclaw
```

To manually reload and restart the browser service:

```bash
sudo -iu openclaw
systemctl --user daemon-reload
systemctl --user restart openclaw-pod.service
systemctl --user restart openclaw-browser.service
```

Check status and logs:

```bash
systemctl --user status openclaw-browser.service --no-pager
journalctl --user -u openclaw-browser.service -f
podman logs -f openclaw-browser
```

Verify the CDP endpoint:

```bash
curl -fsS http://127.0.0.1:9222/json/version | jq .
curl -fsS http://127.0.0.1:9222/json/list | jq .
```

OpenClaw is preconfigured to use this endpoint:

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
  }
}
```

Run OpenClaw's browser doctor if the CLI is available:

```bash
openclaw browser --browser-profile default doctor
```

## LiteLLM sidecar

The default setup runs LiteLLM in the same Podman pod as OpenClaw:

```text
OpenClaw gateway -> http://127.0.0.1:4000 -> LiteLLM -> GitHub Copilot / ChatGPT OAuth device-code providers
```

The installer creates:

```text
~openclaw/.config/litellm/config.yaml
~openclaw/.config/litellm/litellm.env
~openclaw/.local/share/litellm/github_copilot
~openclaw/.local/share/litellm/chatgpt
~openclaw/.config/openclaw-gateway/gateway.env
```

The OpenClaw config uses:

```json
{
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

The default LiteLLM config uses GitHub Copilot and ChatGPT OAuth device-code login. To use another provider, edit `~openclaw/.config/litellm/config.yaml` and `~openclaw/.config/litellm/litellm.env`, then update the OpenClaw model IDs to match the LiteLLM `model_name` values.

See [docs/litellm-bootstrap.md](docs/litellm-bootstrap.md) for details.

## SearXNG search sidecar

The default setup runs SearXNG in the same Podman pod as OpenClaw:

```text
OpenClaw gateway -> http://127.0.0.1:8080 -> SearXNG -> upstream search engines
```

The installer creates:

```text
~openclaw/.config/containers/systemd/searxng.container
~openclaw/.config/searxng/settings.yml
~openclaw/.config/openclaw-gateway/gateway.env
```

The generated `settings.yml` enables the SearXNG JSON API:

```yaml
search:
  formats:
    - html
    - json
```

OpenClaw is preconfigured to use SearXNG:

```json
{
  "tools": {
    "web": {
      "search": {
        "provider": "searxng"
      }
    }
  },
  "plugins": {
    "entries": {
      "searxng": {
        "config": {
          "webSearch": {
            "baseUrl": "http://127.0.0.1:8080/",
            "categories": "general,news",
            "language": "en"
          }
        }
      }
    }
  }
}
```

Restart and validate SearXNG:

```bash
sudo -iu openclaw
systemctl --user restart searxng.service
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo OK
curl -fsS 'http://127.0.0.1:8080/search?q=openclaw&format=json' | jq '.query, (.results | length)'
```

See [docs/searxng-bootstrap.md](docs/searxng-bootstrap.md) for details.

## Optional: Codex and Copilot CLI auth

Codex and Copilot CLI login is useful when OpenClaw invokes those CLIs as tools. Copilot and ChatGPT model routing through LiteLLM is handled separately by LiteLLM providers.

```text
LiteLLM: model gateway with GitHub Copilot / ChatGPT OAuth device-code providers
Codex/Copilot CLI: tool credentials for invoking those CLIs directly
```

Run CLI login as the same service user that runs OpenClaw only if you need the CLIs themselves:

```bash
sudo -iu openclaw
codex login
copilot login
```

See [docs/subscription-cli-auth.md](docs/subscription-cli-auth.md) for details.

## Optional: bootstrap Discord

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

The bot token is stored here with mode `0600`:

```text
~openclaw/.config/openclaw-gateway/gateway.env
```

The access policy is written to:

```text
~openclaw/.openclaw/openclaw.json
```

Start or restart the gateway after configuring Discord:

```bash
sudo -iu openclaw
systemctl --user restart openclaw-gateway.service
```

See [docs/discord-bootstrap.md](docs/discord-bootstrap.md) for the full Discord flow.

## Layout

```text
.
├── config/litellm/
│   ├── config.yaml
│   └── litellm.env.example
├── config/searxng/
│   └── settings.yml
├── deploy/openclaw/
│   ├── litellm.container
│   ├── openclaw.pod
│   ├── openclaw-browser.container
│   ├── openclaw-gateway.container
│   └── searxng.container
├── docs/
│   ├── bootstrap.md
│   ├── discord-bootstrap.md
│   ├── litellm-bootstrap.md
│   ├── searxng-bootstrap.md
│   └── subscription-cli-auth.md
├── scripts/
│   ├── bootstrap-os.sh
│   ├── configure-discord.sh
│   ├── configure-litellm.sh
│   ├── configure-searxng.sh
│   ├── install-openclaw-podman.sh
│   └── doctor-openclaw-podman.sh
└── README.md
```

## Persistent browser model

OpenClaw browser commands such as `tabs` and `snapshot` work best against a persistent Chrome/Chromium CDP endpoint.

This repo uses:

```text
http://127.0.0.1:9222
```

When OpenClaw and the browser run in the same Podman pod, that address resolves inside the shared pod network namespace.

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
- Treat Codex/Copilot CLI credential directories as secrets; do not bake them into container images.
- This repo intentionally avoids snapshotting runtime state.
- Treat the OpenClaw gateway, LiteLLM, SearXNG, and browser CDP endpoint as sensitive control surfaces.

## Detailed guides

- [Bootstrap OpenClaw with rootless Podman](docs/bootstrap.md)
- [Bootstrap LiteLLM sidecar for OpenClaw](docs/litellm-bootstrap.md)
- [Bootstrap SearXNG for OpenClaw](docs/searxng-bootstrap.md)
- [Codex and Copilot CLI auth](docs/subscription-cli-auth.md)
- [Bootstrap Discord for OpenClaw](docs/discord-bootstrap.md)
