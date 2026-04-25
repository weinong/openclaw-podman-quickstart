# Bootstrap OpenClaw with rootless Podman

This guide bootstraps a fresh Ubuntu host to run OpenClaw-related containers with rootless Podman and user-level systemd services.

It focuses on reproducible bootstrap only. It does not cover runtime snapshots, VM snapshots, or backing up OpenClaw state.

## Target architecture

```text
Ubuntu host
└── user: openclaw
    └── systemd --user
        └── Podman pod: openclaw
            ├── openclaw-browser
            │   └── persistent Chromium CDP endpoint on :9222
            └── openclaw-gateway
                └── OpenClaw gateway, optional containerized form
```

The persistent browser is the important part. OpenClaw expects a long-lived CDP endpoint for operations like `tabs` and `snapshot`. Short-lived Browserless-style sessions can connect successfully but then disappear after the WebSocket session closes.

## Phase 1: bootstrap the OS

Run as a sudo-capable user on the VM:

```bash
sudo ./scripts/bootstrap-os.sh openclaw
```

The script does the following:

1. Installs required OS packages.
2. Creates the `openclaw` user if missing.
3. Ensures rootless Podman helper packages are present.
4. Enables systemd linger for the service user.
5. Creates initial config directories.

Installed packages include:

- `podman`
- `uidmap`
- `slirp4netns`
- `fuse-overlayfs`
- `dbus-user-session`
- `systemd-container`
- `jq`
- `curl`
- `git`
- `ca-certificates`
- `gnupg`
- `openssl`
- `lsof`
- `iproute2`

## Phase 2: install Quadlet units and config

Run:

```bash
sudo ./scripts/install-openclaw-podman.sh openclaw
```

This copies these files into the service user's Quadlet directory:

```text
~openclaw/.config/containers/systemd/openclaw.pod
~openclaw/.config/containers/systemd/openclaw-browser.container
~openclaw/.config/containers/systemd/openclaw-gateway.container
```

It also creates a minimal OpenClaw config if one does not already exist:

```text
~openclaw/.openclaw/openclaw.json
```

The default browser profile points to:

```text
http://127.0.0.1:9222
```

## Phase 3: start services

The install script starts:

```text
openclaw-pod.service
openclaw-browser.service
```

The gateway unit is installed but may require OpenClaw-specific onboarding or environment values before it is useful. You can start it manually after adjusting the unit and config:

```bash
sudo -iu openclaw
systemctl --user start openclaw-gateway.service
```

## Validate the browser CDP endpoint

As the service user:

```bash
sudo -iu openclaw
curl -s http://127.0.0.1:9222/json/version | jq .
curl -s http://127.0.0.1:9222/json/list | jq .
```

Run the helper:

```bash
./openclaw-podman-quickstart/scripts/doctor-openclaw-podman.sh
```

If the OpenClaw CLI is installed in the service user's `PATH`, the doctor script also runs:

```bash
openclaw browser --browser-profile default doctor
```

## User systemd command pattern

When running from outside the service user's login shell, use the user bus explicitly:

```bash
svc_user=openclaw
uid="$(id -u "$svc_user")"

sudo -u "$svc_user" \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user status openclaw-browser.service --no-pager
```

When logged in as the service user, normal user-systemd commands are enough:

```bash
systemctl --user status openclaw-browser.service --no-pager
journalctl --user -u openclaw-browser.service -f
```

## Why not Browserless for this profile?

Browserless is useful for on-demand browser automation jobs. However, in this setup OpenClaw needs a persistent CDP browser. Browserless session mode can create a browser for one WebSocket connection and close it when the client disconnects. That causes later `tabs` or `snapshot` operations to fail because the browser instance is already gone.

This quickstart uses `chromedp/headless-shell` as a long-lived Chromium process with a stable CDP endpoint.

## Security model

The browser CDP port is powerful. This setup avoids publishing `9222` outside the pod in the containerized OpenClaw model. If you temporarily publish it to the host for debugging, bind only to loopback:

```text
127.0.0.1:9222:9222
```

Never expose CDP on `0.0.0.0` to an untrusted network.

## Common operations

Restart browser:

```bash
systemctl --user restart openclaw-browser.service
```

Logs:

```bash
journalctl --user -u openclaw-browser.service -f
podman logs -f openclaw-browser
```

Show generated Quadlet service:

```bash
systemctl --user cat openclaw-browser.service
```

List containers:

```bash
podman ps -a
```

## Troubleshooting

### `Failed to enable unit: transient or generated`

Quadlet-generated `.service` files are generated under the user systemd generator path. Start them directly instead of enabling them:

```bash
systemctl --user daemon-reload
systemctl --user start openclaw-browser.service
```

The `[Install]` section in the `.container` or `.pod` file is what wires it into the user target.

### `curl http://127.0.0.1:9222/json/version` fails

Check:

```bash
systemctl --user status openclaw-browser.service --no-pager
journalctl --user -u openclaw-browser.service -n 100 --no-pager
podman ps -a
podman logs --tail=100 openclaw-browser
```

### OpenClaw cannot see browser tabs

Make sure the configured browser profile uses the persistent CDP endpoint:

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

If OpenClaw itself runs inside the same Podman pod as the browser, `127.0.0.1:9222` is the shared pod network namespace.
