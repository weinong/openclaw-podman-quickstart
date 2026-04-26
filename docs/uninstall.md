# Uninstall OpenClaw Podman Quickstart

This guide removes services and files created by this quickstart.

There are two levels of cleanup:

1. Runtime uninstall: stop services, remove containers/pod, remove installed user systemd/Quadlet files and helpers, but keep OpenClaw/LiteLLM/SearXNG state.
2. Full purge: also remove state, secrets, OAuth token caches, and browser profile data.

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

It also stops/removes the `openclaw` Podman pod and managed containers when Podman is available.

Generated config and state are kept.

## Full Purge

Run from the repo checkout as the `openclaw` user:

```bash
./oc.sh uninstall --purge --yes
```

This also removes:

```text
~/.openclaw
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
OpenClaw config, workspace, agents, and sessions
```

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
  docker.io/searxng/searxng:2026.4.24-a7ac696b4@sha256:c9100c29c14a77d5289263a671580226c3b8a396a1a0130d2f500f57076a0119
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
systemctl --user list-unit-files | grep -E 'openclaw|litellm|searxng' || true
```

If the service user was deleted, verify from a sudo-capable VM admin user:

```bash
id openclaw 2>/dev/null || echo "user removed"
```
