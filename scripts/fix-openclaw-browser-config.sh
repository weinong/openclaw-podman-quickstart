#!/usr/bin/env bash
set -euo pipefail

svc_user="${1:-openclaw}"
home_dir="$(getent passwd "${svc_user}" | cut -d: -f6)"

if [[ -z "${home_dir}" ]]; then
  echo "User not found: ${svc_user}" >&2
  exit 1
fi

config="${home_dir}/.openclaw/openclaw.json"
if [[ ! -f "${config}" ]]; then
  echo "OpenClaw config not found: ${config}" >&2
  exit 1
fi

tmp="$(mktemp)"
jq '
  .browser.enabled = true |
  .browser.defaultProfile = "default" |
  .browser.profiles.default.cdpUrl = "http://127.0.0.1:9222" |
  .browser.profiles.default.color = "#FF4500" |
  del(.browser.profiles.default.driver)
' "${config}" > "${tmp}"

install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp}" "${config}"
rm -f "${tmp}"

echo "Updated browser profile in ${config} for current OpenClaw schema."
echo "Profile default now uses remote CDP via cdpUrl and color, without legacy driver=cdp."
