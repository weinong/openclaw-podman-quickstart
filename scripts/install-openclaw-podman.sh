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
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${home_dir}/.config/openclaw-gateway"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${home_dir}/.config/litellm"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${home_dir}/.local/share/litellm"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${home_dir}/.local/share/litellm/github_copilot"
install -d -o "${svc_user}" -g "${svc_user}" "${home_dir}/.local/share/openclaw-browser"
install -d -o "${svc_user}" -g "${svc_user}" "${home_dir}/.openclaw/workspace"

touch "${home_dir}/.config/openclaw-gateway/gateway.env"
chown "${svc_user}:${svc_user}" "${home_dir}/.config/openclaw-gateway/gateway.env"
chmod 0600 "${home_dir}/.config/openclaw-gateway/gateway.env"

if [[ ! -f "${home_dir}/.config/litellm/litellm.env" ]]; then
  litellm_master_key="sk-litellm-$(openssl rand -hex 24)"
  cat > "${home_dir}/.config/litellm/litellm.env" <<EOF
LITELLM_MASTER_KEY=${litellm_master_key}
# GitHub Copilot provider uses OAuth device flow.
# No upstream API key is required for the default config.yaml.
# The first model request will print a device login URL/code in LiteLLM logs.
EOF
  chown "${svc_user}:${svc_user}" "${home_dir}/.config/litellm/litellm.env"
  chmod 0600 "${home_dir}/.config/litellm/litellm.env"
else
  echo "Existing ${home_dir}/.config/litellm/litellm.env found; leaving it unchanged."
fi

if [[ -f "${repo_root}/config/litellm/config.yaml" ]]; then
  install -o "${svc_user}" -g "${svc_user}" -m 0600 \
    "${repo_root}/config/litellm/config.yaml" \
    "${home_dir}/.config/litellm/config.yaml"
fi

install -o "${svc_user}" -g "${svc_user}" -m 0644 \
  "${repo_root}/deploy/openclaw/openclaw.pod" \
  "${home_dir}/.config/containers/systemd/openclaw.pod"

if [[ -f "${repo_root}/deploy/openclaw/openclaw-browser.container" ]]; then
  install -o "${svc_user}" -g "${svc_user}" -m 0644 \
    "${repo_root}/deploy/openclaw/openclaw-browser.container" \
    "${home_dir}/.config/containers/systemd/openclaw-browser.container"
fi

if [[ -f "${repo_root}/deploy/openclaw/litellm.container" ]]; then
  install -o "${svc_user}" -g "${svc_user}" -m 0644 \
    "${repo_root}/deploy/openclaw/litellm.container" \
    "${home_dir}/.config/containers/systemd/litellm.container"
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
  },
  "models": {
    "providers": {
      "litellm": {
        "baseUrl": "http://127.0.0.1:4000",
        "apiKey": "${LITELLM_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "github_copilot/gpt-4",
            "name": "GitHub Copilot GPT-4 via LiteLLM",
            "reasoning": false,
            "input": ["text"],
            "contextWindow": 128000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "litellm/github_copilot/gpt-4"
      }
    }
  }
}
JSON
  chown "${svc_user}:${svc_user}" "${home_dir}/.openclaw/openclaw.json"
  chmod 0600 "${home_dir}/.openclaw/openclaw.json"
else
  echo "Existing ${home_dir}/.openclaw/openclaw.json found; patching LiteLLM provider while preserving other config."
  tmp_config="$(mktemp)"
  jq '
    .browser.enabled = true |
    .browser.defaultProfile = "default" |
    .browser.profiles.default.driver = "cdp" |
    .browser.profiles.default.cdpUrl = "http://127.0.0.1:9222" |
    .models.providers.litellm = {
      baseUrl: "http://127.0.0.1:4000",
      apiKey: "${LITELLM_API_KEY}",
      api: "openai-completions",
      models: [
        {
          id: "github_copilot/gpt-4",
          name: "GitHub Copilot GPT-4 via LiteLLM",
          reasoning: false,
          input: ["text"],
          contextWindow: 128000,
          maxTokens: 8192
        }
      ]
    } |
    .agents.defaults.model.primary = "litellm/github_copilot/gpt-4"
  ' "${home_dir}/.openclaw/openclaw.json" > "${tmp_config}"
  install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_config}" "${home_dir}/.openclaw/openclaw.json"
  rm -f "${tmp_config}"
fi

# The OpenClaw gateway resolves ${LITELLM_API_KEY} from its environment.
# Use the local LiteLLM master key by default.
litellm_key="$(grep '^LITELLM_MASTER_KEY=' "${home_dir}/.config/litellm/litellm.env" | cut -d= -f2- || true)"
if [[ -n "${litellm_key}" ]]; then
  tmp_gateway_env="$(mktemp)"
  grep -v '^LITELLM_API_KEY=' "${home_dir}/.config/openclaw-gateway/gateway.env" > "${tmp_gateway_env}" || true
  printf 'LITELLM_API_KEY=%s\n' "${litellm_key}" >> "${tmp_gateway_env}"
  install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_gateway_env}" "${home_dir}/.config/openclaw-gateway/gateway.env"
  rm -f "${tmp_gateway_env}"
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

if [[ -f "${home_dir}/.config/containers/systemd/litellm.container" ]]; then
  run_user_systemctl start litellm.service
fi

echo "Install complete for user: ${svc_user}"
echo "LiteLLM env: ${home_dir}/.config/litellm/litellm.env"
echo "LiteLLM Copilot token cache: ${home_dir}/.local/share/litellm/github_copilot"
echo "The first LiteLLM request to github_copilot/gpt-4 will print a device login URL/code in LiteLLM logs."
echo "Gateway unit is installed as a skeleton. Start it after OpenClaw onboarding/configuration is ready."
