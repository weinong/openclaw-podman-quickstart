# OpenClaw Podman Quickstart

Bootstrap a headless Ubuntu host to run OpenClaw with rootless Podman, user-level systemd services, a persistent Chromium CDP browser container, a LiteLLM sidecar, and optional Discord gateway configuration.

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
  - an optional OpenClaw gateway container skeleton
- A minimal OpenClaw browser profile config pointing to the persistent CDP endpoint.
- A LiteLLM provider config for OpenClaw, with the default OpenClaw model set to `litellm/openai/gpt-4.1-mini`.
- Optional Discord bot bootstrap with token stored in a user-only env file and access policy stored in OpenClaw config.

## Assumptions

- Target OS: Ubuntu 22.04 or 24.04 server.
- You want to run services as a non-root user.
- You want a persistent browser endpoint for OpenClaw, not short-lived Browserless sessions.
- Chrome CDP should stay local to the pod/host and should not be exposed publicly.
- LiteLLM should run locally as the OpenClaw model gateway on `127.0.0.1:4000`.
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

Then add a real provider API key for the default LiteLLM config:

```bash
OPENAI_API_KEY='YOUR_OPENAI_API_KEY' \
  sudo -E bash ./scripts/configure-litellm.sh openclaw
```

Restart LiteLLM after setting the key:

```bash
sudo -iu openclaw
systemctl --user restart litellm.service
```

Run the doctor:

```bash
./openclaw-podman-quickstart/scripts/doctor-openclaw-podman.sh
```

## LiteLLM sidecar

The default setup runs LiteLLM in the same Podman pod as OpenClaw:

```text
OpenClaw gateway -> http://127.0.0.1:4000 -> LiteLLM -> upstream model provider
```

The installer creates:

```text
~openclaw/.config/litellm/config.yaml
~openclaw/.config/litellm/litellm.env
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
        "primary": "litellm/openai/gpt-4.1-mini"
      }
    }
  }
}
```

The default LiteLLM config expects `OPENAI_API_KEY`. To use another provider, edit `~openclaw/.config/litellm/config.yaml` and `~openclaw/.config/litellm/litellm.env`, then update the OpenClaw model IDs to match the LiteLLM `model_name` values.

See [docs/litellm-bootstrap.md](docs/litellm-bootstrap.md) for details.

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
├── deploy/openclaw/
│   ├── litellm.container
│   ├── openclaw.pod
│   ├── openclaw-browser.container
│   └── openclaw-gateway.container
├── docs/
│   ├── bootstrap.md
│   ├── discord-bootstrap.md
│   └── litellm-bootstrap.md
├── scripts/
│   ├── bootstrap-os.sh
│   ├── configure-discord.sh
│   ├── configure-litellm.sh
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
- Do not commit real `openclaw.json` files if they contain auth profiles, tokens, API keys, or local machine secrets.
- Do not commit `~openclaw/.config/openclaw-gateway/gateway.env`; it contains runtime secrets such as `DISCORD_BOT_TOKEN` and `LITELLM_API_KEY`.
- Do not commit `~openclaw/.config/litellm/litellm.env`; it contains upstream provider keys such as `OPENAI_API_KEY`.
- This repo intentionally avoids snapshotting runtime state.
- Treat the OpenClaw gateway, LiteLLM, and browser CDP endpoint as sensitive control surfaces.

## Detailed guides

- [Bootstrap OpenClaw with rootless Podman](docs/bootstrap.md)
- [Bootstrap LiteLLM sidecar for OpenClaw](docs/litellm-bootstrap.md)
- [Bootstrap Discord for OpenClaw](docs/discord-bootstrap.md)
