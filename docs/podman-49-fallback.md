# Podman 4.9 systemd fallback

Ubuntu 24.04 ships Podman 4.9.3. That package includes Quadlet, but its Quadlet support does not include `.pod` units.

You can confirm this with:

```bash
man podman-systemd.unit | head -40
```

If the synopsis lists `.container`, `.volume`, `.network`, `.kube`, and `.image`, but not `.pod`, then `deploy/openclaw/openclaw.pod` will be ignored by the generator and `openclaw-pod.service` will not be created.

This repo includes a classic user-systemd fallback under:

```text
deploy/openclaw-systemd/
```

It creates the pod with a normal systemd unit and runs the containers with helper scripts.

## Install fallback units

From the repo checkout:

```bash
sudo ./scripts/install-openclaw-systemd-fallback.sh openclaw
```

The fallback installer copies services to:

```text
~openclaw/.config/systemd/user/
```

and helper scripts to:

```text
~openclaw/.local/bin/
```

It starts these services:

```text
openclaw-pod.service
openclaw-browser.service
litellm.service
searxng.service
```

The gateway service is installed but not started automatically.

## Check status

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

As the service user:

```bash
sudo -iu openclaw
podman pod ps
podman ps -a
```

## Start gateway

After OpenClaw onboarding/configuration is ready:

```bash
sudo -iu openclaw
systemctl --user start openclaw-gateway.service
journalctl --user -u openclaw-gateway.service -f
```

## Validate endpoints

```bash
sudo -iu openclaw

curl -fsS http://127.0.0.1:9222/json/version | jq .
curl -fsS http://127.0.0.1:4000/health/liveliness | jq .
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG OK"
```

## Why this fallback exists

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
