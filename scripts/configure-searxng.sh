#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/configure-searxng.sh [service-user]

Optional environment variables:
  SEARXNG_BASE_URL=http://127.0.0.1:8080/
  SEARXNG_CATEGORIES=general,news
  SEARXNG_LANGUAGE=en

What it does:
  - Creates ~/.config/searxng/settings.yml with a generated secret key if missing.
  - Enables SearXNG JSON output format.
  - Adds SEARXNG_BASE_URL to ~/.config/openclaw-gateway/gateway.env.
  - Patches ~/.openclaw/openclaw.json to use SearXNG as web_search provider.
EOF
}

svc_user="${1:-openclaw}"
if [[ "${svc_user}" == "-h" || "${svc_user}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

home_dir="$(getent passwd "${svc_user}" | cut -d: -f6)"
if [[ -z "${home_dir}" ]]; then
  echo "User not found: ${svc_user}" >&2
  exit 1
fi

base_url="${SEARXNG_BASE_URL:-http://127.0.0.1:8080/}"
categories="${SEARXNG_CATEGORIES:-general,news}"
language="${SEARXNG_LANGUAGE:-en}"

searxng_dir="${home_dir}/.config/searxng"
settings_file="${searxng_dir}/settings.yml"
gateway_env_dir="${home_dir}/.config/openclaw-gateway"
gateway_env="${gateway_env_dir}/gateway.env"
openclaw_config="${home_dir}/.openclaw/openclaw.json"

install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${searxng_dir}"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${gateway_env_dir}"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${home_dir}/.openclaw"

if [[ ! -f "${settings_file}" ]]; then
  secret_key="$(openssl rand -hex 32)"
  cat > "${settings_file}" <<EOF
use_default_settings: true

server:
  bind_address: "0.0.0.0"
  port: 8080
  secret_key: "${secret_key}"
  base_url: "${base_url}"
  image_proxy: true
  limiter: false

ui:
  static_use_hash: true
  default_locale: "en"
  query_in_title: false

search:
  safe_search: 1
  autocomplete: ""
  default_lang: "auto"
  formats:
    - html
    - json

outgoing:
  request_timeout: 5.0
  max_request_timeout: 15.0
  useragent_suffix: "openclaw-podman-quickstart"
EOF
  chown "${svc_user}:${svc_user}" "${settings_file}"
  chmod 0600 "${settings_file}"
else
  echo "Existing ${settings_file} found; leaving it unchanged."
fi

# Keep gateway environment file as the place for runtime env vars.
tmp_env="$(mktemp)"
if [[ -f "${gateway_env}" ]]; then
  grep -v '^SEARXNG_BASE_URL=' "${gateway_env}" > "${tmp_env}" || true
fi
printf 'SEARXNG_BASE_URL=%s\n' "${base_url}" >> "${tmp_env}"
install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_env}" "${gateway_env}"
rm -f "${tmp_env}"

if [[ ! -f "${openclaw_config}" ]]; then
  cat > "${openclaw_config}" <<'JSON'
{}
JSON
  chown "${svc_user}:${svc_user}" "${openclaw_config}"
  chmod 0600 "${openclaw_config}"
fi

tmp_config="$(mktemp)"
jq \
  --arg baseUrl "${base_url}" \
  --arg categories "${categories}" \
  --arg language "${language}" '
  .tools.web.search.provider = "searxng" |
  .plugins.entries.searxng.config.webSearch.baseUrl = $baseUrl |
  .plugins.entries.searxng.config.webSearch.categories = $categories |
  .plugins.entries.searxng.config.webSearch.language = $language
' "${openclaw_config}" > "${tmp_config}"
install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_config}" "${openclaw_config}"
rm -f "${tmp_config}"

uid="$(id -u "${svc_user}")"
sudo -u "${svc_user}" \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user daemon-reload || true

echo "SearXNG bootstrap complete."
echo "Settings: ${settings_file}"
echo "Gateway env: ${gateway_env}"
echo "OpenClaw config: ${openclaw_config}"
echo "Base URL: ${base_url}"
