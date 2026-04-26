#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/configure-litellm.sh openclaw

Optional:
  LITELLM_MASTER_KEY='sk-litellm-...' sudo -E ./scripts/configure-litellm.sh openclaw

Notes:
  - Writes ~/.config/litellm/litellm.env with mode 0600.
  - The default config/litellm/config.yaml uses GitHub Copilot OAuth device flow.
  - No upstream API key is required for the default GitHub Copilot provider config.
  - The first model request prints a device login URL/code in LiteLLM logs.
EOF
}

svc_user="${1:-openclaw}"
shift || true

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
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

litellm_dir="${home_dir}/.config/litellm"
litellm_env="${litellm_dir}/litellm.env"
copilot_token_dir="${home_dir}/.local/share/litellm/github_copilot"
gateway_env_dir="${home_dir}/.config/openclaw-gateway"
gateway_env="${gateway_env_dir}/gateway.env"

install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${litellm_dir}"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${copilot_token_dir}"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${gateway_env_dir}"

existing_master_key=""
if [[ -f "${litellm_env}" ]]; then
  existing_master_key="$(grep '^LITELLM_MASTER_KEY=' "${litellm_env}" | cut -d= -f2- || true)"
fi

master_key="${LITELLM_MASTER_KEY:-${existing_master_key}}"
if [[ -z "${master_key}" ]]; then
  master_key="sk-litellm-$(openssl rand -hex 24)"
fi

tmp_litellm_env="$(mktemp)"
cat > "${tmp_litellm_env}" <<EOF
LITELLM_MASTER_KEY=${master_key}
# GitHub Copilot provider uses OAuth device flow.
# No upstream API key is required for the default config.yaml.
# The first model request prints a device login URL/code in LiteLLM logs.
EOF
install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_litellm_env}" "${litellm_env}"
rm -f "${tmp_litellm_env}"

# OpenClaw reads this value through the gateway EnvironmentFile.
tmp_gateway_env="$(mktemp)"
if [[ -f "${gateway_env}" ]]; then
  grep -v '^LITELLM_API_KEY=' "${gateway_env}" > "${tmp_gateway_env}" || true
fi
printf 'LITELLM_API_KEY=%s\n' "${master_key}" >> "${tmp_gateway_env}"
install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_gateway_env}" "${gateway_env}"
rm -f "${tmp_gateway_env}"

echo "LiteLLM env written to: ${litellm_env}"
echo "Copilot OAuth token cache: ${copilot_token_dir}"
echo "Gateway env updated with LITELLM_API_KEY: ${gateway_env}"
echo "Restart LiteLLM and OpenClaw gateway after changing keys."
echo "Then trigger a model call and watch LiteLLM logs for the GitHub device-code login."
