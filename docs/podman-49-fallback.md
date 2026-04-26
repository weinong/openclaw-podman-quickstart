# Podman 4.9 Systemd Fallback

Ubuntu 24.04 ships Podman 4.9.3. That package includes Quadlet, but its Quadlet support does not include `.pod` units.

`./oc.sh install` detects this and installs the classic user-systemd fallback automatically.

## Install Fallback Units

Run from the repo checkout as the `openclaw` user:

```bash
./oc.sh install fallback
```

The fallback installer copies services to:

```text
~/.config/systemd/user/
```

and helper scripts to:

```text
~/.local/bin/
```

It starts these services:

```text
openclaw-pod.service
openclaw-browser.service
litellm.service
searxng.service
```

The gateway service is installed but not started automatically.

## Check Status

```bash
./oc.sh status core
podman pod ps
podman ps -a
```

## Start Gateway

After OpenClaw onboarding/configuration is ready:

```bash
./oc.sh start gateway
./oc.sh logs gateway
```

## Validate Endpoints

```bash
curl -fsS http://127.0.0.1:9222/json/version | jq .
curl -fsS http://127.0.0.1:4000/health/liveliness | jq .
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG OK"
```

## Why This Fallback Exists

The Quadlet path is cleaner on newer Podman releases that support `.pod` units. Ubuntu 24.04's stock Podman 4.9.3 has Quadlet support, but does not support `.pod` files, so it cannot generate `openclaw-pod.service` from `openclaw.pod`.

The fallback preserves the same runtime model:

```text
Podman pod: openclaw
├── openclaw-browser
├── openclaw-litellm
├── openclaw-searxng
└── openclaw-gateway
```

but creates it with classic user systemd services instead of `.pod` Quadlet.
