# Uninstall OpenClaw Podman quickstart

This guide removes the services and files created by this quickstart.

There are two levels of cleanup:

1. **Runtime uninstall**: stop services, remove containers/pod, remove user systemd/Quadlet files, but keep OpenClaw/LiteLLM/SearXNG state.
2. **Full purge**: also remove state, secrets, OAuth token caches, images, and optionally the `openclaw` Linux user.

> Review commands before running them. The full purge removes credentials and local state.

## Variables

```bash
svc_user=openclaw
uid="$(id -u "$svc_user")"
home_dir="$(getent passwd "$svc_user" | cut -d: -f6)"
```

## Stop services

From a sudo-capable user:

```bash
sudo -u "$svc_user" env \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user stop \
    openclaw-gateway.service \
    openclaw-browser.service \
    litellm.service \
    searxng.service \
    openclaw-pod.service || true
```

## Remove containers and pod

```bash
sudo -iu "$svc_user" bash -lc '
  podman rm -f openclaw-gateway openclaw-browser openclaw-litellm openclaw-searxng 2>/dev/null || true
  podman pod rm -f openclaw 2>/dev/null || true
'
```

## Remove installed user systemd fallback units

This removes files installed by `scripts/install-openclaw-systemd-fallback.sh`:

```bash
sudo rm -f \
  "${home_dir}/.config/systemd/user/openclaw-pod.service" \
  "${home_dir}/.config/systemd/user/openclaw-browser.service" \
  "${home_dir}/.config/systemd/user/litellm.service" \
  "${home_dir}/.config/systemd/user/searxng.service" \
  "${home_dir}/.config/systemd/user/openclaw-gateway.service"

sudo rm -f \
  "${home_dir}/.local/bin/openclaw-run-browser" \
  "${home_dir}/.local/bin/openclaw-run-litellm" \
  "${home_dir}/.local/bin/openclaw-run-searxng" \
  "${home_dir}/.local/bin/openclaw-run-gateway"
```

## Remove installed Quadlet files

This removes files installed by `scripts/install-openclaw-podman.sh`:

```bash
sudo rm -f \
  "${home_dir}/.config/containers/systemd/openclaw.pod" \
  "${home_dir}/.config/containers/systemd/openclaw-browser.container" \
  "${home_dir}/.config/containers/systemd/litellm.container" \
  "${home_dir}/.config/containers/systemd/searxng.container" \
  "${home_dir}/.config/containers/systemd/openclaw-gateway.container"
```

## Reload user systemd

```bash
sudo -u "$svc_user" env \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user daemon-reload

sudo -u "$svc_user" env \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user reset-failed
```

At this point, the services are uninstalled but state is preserved.

## Optional: remove state and secrets

This removes OpenClaw config/state, LiteLLM config and OAuth token caches, SearXNG settings, browser profile data, gateway environment secrets, and workspace data.

```bash
sudo rm -rf \
  "${home_dir}/.openclaw" \
  "${home_dir}/.config/openclaw-gateway" \
  "${home_dir}/.config/litellm" \
  "${home_dir}/.config/searxng" \
  "${home_dir}/.local/share/litellm" \
  "${home_dir}/.local/share/openclaw-browser"
```

This removes secrets such as:

```text
DISCORD_BOT_TOKEN
LITELLM_API_KEY
LITELLM_MASTER_KEY
SearXNG server.secret_key
GitHub Copilot OAuth token cache
ChatGPT OAuth token cache
```

## Optional: remove images

```bash
sudo -iu "$svc_user" bash -lc '
  podman image rm -f \
    ghcr.io/openclaw/openclaw:latest \
    docker.litellm.ai/berriai/litellm:main-latest \
    docker.io/chromedp/headless-shell:latest \
    docker.io/searxng/searxng:latest 2>/dev/null || true
'
```

You can also prune unused rootless Podman data for the service user:

```bash
sudo -iu "$svc_user" podman system prune -af
```

## Optional: disable linger

If you keep the `openclaw` user but no longer need user services to start at boot:

```bash
sudo loginctl disable-linger "$svc_user"
```

## Optional: delete the service user

Only do this after removing state you care about.

```bash
sudo loginctl disable-linger "$svc_user" || true
sudo userdel -r "$svc_user"
```

## Verify removal

```bash
id "$svc_user" 2>/dev/null || echo "user removed"

sudo -iu "$svc_user" podman ps -a 2>/dev/null || true
sudo -iu "$svc_user" podman pod ps 2>/dev/null || true

sudo -u "$svc_user" env \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user list-unit-files 2>/dev/null | grep -E 'openclaw|litellm|searxng' || true
```

If the service user was deleted, the `sudo -iu "$svc_user"` checks should fail because the user no longer exists.
