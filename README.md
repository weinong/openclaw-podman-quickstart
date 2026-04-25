# OpenClaw Podman Quickstart

Bootstrap a headless Ubuntu host to run OpenClaw with rootless Podman, user-level systemd services, and a persistent Chromium CDP browser container.

This repo focuses on **bootstrap**, not snapshot/backup. It is meant to help you reproduce the setup quickly on a fresh VM.

## What this installs

- OS packages needed for the workflow: `podman`, `jq`, `curl`, `git`, `uidmap`, `slirp4netns`, `fuse-overlayfs`, `dbus-user-session`, and related utilities.
- A dedicated Linux user, default: `openclaw`.
- Rootless Podman runtime directories.
- User-level systemd linger for the service user.
- Quadlet units for:
  - an OpenClaw pod
  - a persistent Chromium CDP browser container
  - an optional OpenClaw gateway container skeleton
- A minimal OpenClaw browser profile config pointing to the persistent CDP endpoint.

## Assumptions

- Target OS: Ubuntu 22.04 or 24.04 server.
- You want to run services as a non-root user.
- You want a persistent browser endpoint for OpenClaw, not short-lived Browserless sessions.
- Chrome CDP should stay local to the pod/host and should not be exposed publicly.

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

Then switch to the service user:

```bash
sudo -iu openclaw
./openclaw-podman-quickstart/scripts/doctor-openclaw-podman.sh
```

## Layout

```text
.
├── deploy/openclaw/
│   ├── openclaw.pod
│   ├── openclaw-browser.container
│   └── openclaw-gateway.container
├── docs/
│   └── bootstrap.md
├── scripts/
│   ├── bootstrap-os.sh
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
- Do not commit real `openclaw.json` files if they contain auth profiles, tokens, API keys, or local machine secrets.
- This repo intentionally avoids snapshotting runtime state.
- Treat the OpenClaw gateway and browser CDP endpoint as sensitive control surfaces.

## Detailed guide

See [docs/bootstrap.md](docs/bootstrap.md).
