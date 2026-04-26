#!/usr/bin/env bash
set -euo pipefail

svc_user="${1:-openclaw}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

apt-get update
apt-get install -y \
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

if ! id "${svc_user}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${svc_user}"
fi

loginctl enable-linger "${svc_user}"

home_dir="$(getent passwd "${svc_user}" | cut -d: -f6)"

sudo -u "${svc_user}" mkdir -p \
  "${home_dir}/.config/containers/systemd" \
  "${home_dir}/.local/share/openclaw-browser" \
  "${home_dir}/.openclaw" \
  "${home_dir}/.openclaw/workspace"

echo "Bootstrap complete for user: ${svc_user}"
echo "Home: ${home_dir}"
