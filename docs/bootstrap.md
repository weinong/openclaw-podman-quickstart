# Bootstrap OpenClaw with rootless Podman

This guide bootstraps a fresh Ubuntu host to run OpenClaw-related containers with rootless Podman and user-level systemd services.

The VM admin only prepares the OS and creates the `openclaw` user. The OpenClaw bootstrap itself is run by the `openclaw` user with `./oc.sh`.

## Target Architecture

```text
Ubuntu host
└── user: openclaw
    └── systemd --user
        └── Podman pod: openclaw
            ├── openclaw-browser
            │   └── persistent Chromium CDP endpoint on :9222
            ├── openclaw-litellm
            ├── openclaw-searxng
            └── openclaw-gateway
```

The persistent browser is the important part. OpenClaw expects a long-lived CDP endpoint for operations like `tabs` and `snapshot`.

## Phase 1: Admin Prep

Run as a sudo-capable VM admin user:

```bash
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl dbus-user-session fuse-overlayfs git gnupg \
  iproute2 jq lsof openssl podman slirp4netns systemd-container uidmap

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

`oc.sh` exports the user-systemd environment itself, but the `.profile` snippet makes manual `systemctl --user` commands work in headless `sudo -iu openclaw` shells.

## Phase 2: One-Shot Install

Switch to the service user and run the repo entrypoint:

```bash
sudo -iu openclaw
git clone https://github.com/weinong/openclaw-podman-quickstart.git
cd openclaw-podman-quickstart

./oc.sh install
```

`./oc.sh install` creates config, installs user systemd units, and starts the core services. It automatically uses the Podman 4.9 fallback when Quadlet `.pod` support is unavailable.

Force a specific install mode if needed:

```bash
./oc.sh install fallback
./oc.sh install quadlet
```

## Config Management

OpenClaw config can be refreshed independently:

```bash
./oc.sh config openclaw
```

Sidecar config can also be managed independently:

```bash
./oc.sh config litellm
./oc.sh config searxng
```

## Service Operations

Common commands:

```bash
./oc.sh status
./oc.sh restart browser
./oc.sh restart litellm
./oc.sh restart searxng
./oc.sh start gateway
./oc.sh logs gateway
```

The gateway unit is installed but not started by default. Start it after OpenClaw onboarding/configuration is ready.

## Uninstall

Remove installed services and unit files while preserving generated config and data:

```bash
./oc.sh uninstall
```

Also remove generated config, credentials, browser data, and LiteLLM token caches:

```bash
./oc.sh uninstall --purge --yes
```

## Validate the Browser CDP Endpoint

As `openclaw`:

```bash
curl -s http://127.0.0.1:9222/json/version | jq .
curl -s http://127.0.0.1:9222/json/list | jq .
```

Run the general doctor:

```bash
./oc.sh doctor
```

If the OpenClaw CLI is installed in the service user's `PATH`, the doctor also runs:

```bash
openclaw browser --browser-profile default doctor
```

## Why Not Browserless?

Browserless is useful for on-demand browser automation jobs. This setup needs a persistent CDP browser. Browserless session mode can create a browser for one WebSocket connection and close it when the client disconnects.

This quickstart uses `chromedp/headless-shell` as a long-lived Chromium process with a stable CDP endpoint.

## Security Model

The browser CDP port is powerful. This setup binds it to host loopback through the Podman pod. Never expose CDP on `0.0.0.0` to an untrusted network.

## Troubleshooting

If `curl http://127.0.0.1:9222/json/version` fails, check:

```bash
./oc.sh status browser
./oc.sh logs browser
podman ps -a
podman logs --tail=100 openclaw-browser
```

If OpenClaw cannot see browser tabs, refresh the reusable OpenClaw config:

```bash
./oc.sh config openclaw
```
