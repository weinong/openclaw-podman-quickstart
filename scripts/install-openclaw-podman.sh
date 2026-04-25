#!/usr/bin/env bash
set -euo pipefail

svc_user="${1:-openclaw}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

home_dir="$(getent passwd "${svc_user}" | cut -d: -f6)"
if [[ -z "${home_dir}" ]]; then
  echo "User not found: ${svc_user}" >&2
  exit 1
fi

install -d -o "${svc_user}" -g "${svc_user}" "${home_dir}/.config/containers/systemd"
install -d -o "${svc_user}" -g "${svc_user}" "${home_dir}/.local/share/openclaw-browser"
install -d -o "${svc_user}" -g "${svc_user}" "${home_dir}/.openclaw/workspace"

install -o "${svc_user}" -g "${svc_user}" -m 0644 \
  "${repo_root}/deploy/openclaw/openclaw.pod" \
  "${home_dir}/.config/containers/systemd/openclaw.pod"

if [[ -f "${repo_root}/deploy/openclaw/openclaw-browser.container" ]]; then
  install -o "${svc_user}" -g "${svc_user}" -m 0644 \
    "${repo_root}/deploy/openclaw/openclaw-browser.container" \
    "${home_dir}/.config/containers/systemd/openclaw-browser.container"
fi

if [[ -f "${repo_root}/deploy/openclaw/openclaw-gateway.container" ]]; then
  install -o "${svc_user}" -g "${svc_user}" -m 0644 \
    "${repo_root}/deploy/openclaw/openclaw-gateway.container" \
    "${home_dir}/.config/containers/systemd/openclaw-gateway.container"
fi

if [[ ! -f "${home_dir}/.openclaw/openclaw.json" ]]; then
  cat > "${home_dir}/.openclaw/openclaw.json" <<'JSON'
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
JSON
  chown "${svc_user}:${svc_user}" "${home_dir}/.openclaw/openclaw.json"
  chmod 0600 "${home_dir}/.openclaw/openclaw.json"
else
  echo "Existing ${home_dir}/.openclaw/openclaw.json found; leaving it unchanged."
fi

loginctl enable-linger "${svc_user}"
uid="$(id -u "${svc_user}")"

run_user_systemctl() {
  sudo -u "${svc_user}" \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
    systemctl --user "$@"
}

run_user_systemctl daemon-reload
run_user_systemctl start openclaw-pod.service

if [[ -f "${home_dir}/.config/containers/systemd/openclaw-browser.container" ]]; then
  run_user_systemctl start openclaw-browser.service
else
  echo "openclaw-browser.container is missing; install it before starting the browser service."
fi

echo "Install complete for user: ${svc_user}"
echo "Gateway unit is installed as a skeleton. Start it after OpenClaw onboarding/configuration is ready."
