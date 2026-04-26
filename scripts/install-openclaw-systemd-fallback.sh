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

install -d -o "${svc_user}" -g "${svc_user}" "${home_dir}/.config/systemd/user"
install -d -o "${svc_user}" -g "${svc_user}" "${home_dir}/.local/bin"

for unit in \
  openclaw-pod.service \
  openclaw-browser.service \
  litellm.service \
  searxng.service \
  openclaw-gateway.service; do
  install -o "${svc_user}" -g "${svc_user}" -m 0644 \
    "${repo_root}/deploy/openclaw-systemd/${unit}" \
    "${home_dir}/.config/systemd/user/${unit}"
done

for helper in "${repo_root}"/deploy/openclaw-systemd/bin/*; do
  install -o "${svc_user}" -g "${svc_user}" -m 0755 \
    "${helper}" \
    "${home_dir}/.local/bin/$(basename "${helper}")"
done

loginctl enable-linger "${svc_user}"
systemctl start "user@$(id -u "${svc_user}").service"

uid="$(id -u "${svc_user}")"
run_user_systemctl() {
  sudo -u "${svc_user}" env \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
    systemctl --user "$@"
}

run_user_systemctl daemon-reload
run_user_systemctl start openclaw-pod.service
run_user_systemctl start openclaw-browser.service
run_user_systemctl start litellm.service
run_user_systemctl start searxng.service

echo "Podman 4.9 systemd fallback installed for user: ${svc_user}"
echo "Installed units: ${home_dir}/.config/systemd/user"
echo "Installed helpers: ${home_dir}/.local/bin"
echo "Gateway is installed but not started by default. Start it after OpenClaw onboarding/configuration is ready:"
echo "  systemctl --user start openclaw-gateway.service"
