#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

services=(
  openclaw-pod.service
  openclaw-browser.service
  litellm.service
  searxng.service
  openclaw-gateway.service
)

core_services=(
  openclaw-pod.service
  openclaw-browser.service
  litellm.service
  searxng.service
)

image_names=(
  openclaw-gateway
  openclaw-browser
  litellm
  searxng
)

image_refs=(
  "ghcr.io/openclaw/openclaw:2026.4.24@sha256:7c4370ff8777555d4c9fe5ab821aaaad7c87188d389a6cf761270725d96ec3e9"
  "docker.io/chromedp/headless-shell:148.0.7778.56@sha256:8b36bc4bca3f394103db8a2e60f0053969a277b3918abc39acfee819168c4f79"
  "docker.litellm.ai/berriai/litellm:main-v1.82.3@sha256:067aee932b8770ed42955ee802a04abdcd369d0995b5e696bb07d6520a231b1c"
  "docker.io/searxng/searxng:2026.4.24-a7ac696b4@sha256:c9100c29c14a77d5289263a671580226c3b8a396a1a0130d2f500f57076a0119"
)

usage() {
  cat <<'EOF'
Usage:
  ./oc.sh install [fallback|quadlet] [--start-gateway] [--allow-current-user]
  ./oc.sh uninstall [--purge --yes] [--allow-current-user]
  ./oc.sh init [--allow-current-user]
  ./oc.sh config openclaw|litellm|searxng [--allow-current-user]
  DISCORD_BOT_TOKEN='...' ./oc.sh config discord [options]
  ./oc.sh start|stop|restart|status [service]
  ./oc.sh logs [service]
  ./oc.sh images [--json]
  ./oc.sh doctor

Install:
  install                 One-shot install. Auto-detects Quadlet .pod support.
  install fallback        Install classic user-systemd units for Podman 4.9.
  install quadlet         Install Quadlet units for newer Podman.

Uninstall:
  uninstall               Stop services and remove installed units/helpers only.
  uninstall --purge --yes Also remove generated config, credentials, and data.

Images:
  images                  Print pinned image tags and sha256 manifest digests.
  images --json           Print pinned images as JSON.

Services:
  browser                 openclaw-browser.service
  litellm                 litellm.service
  searxng                 searxng.service
  gateway                 openclaw-gateway.service
  pod                     openclaw-pod.service
  core                    pod, browser, LiteLLM, and SearXNG services
  all                     all OpenClaw services

Discord config options:
  --dm-user ID            Allowed Discord DM user. Repeatable.
  --guild ID              Allowed Discord guild/server. Repeatable.
  --guild-user ID         Allowed guild user. Defaults to --dm-user values.
  --channel-id ID         Allowed guild channel. Repeatable.
  --require-mention bool  true or false. Default: false.

Environment:
  LITELLM_MASTER_KEY      Optional LiteLLM master key.
  SEARXNG_BASE_URL        Default: http://127.0.0.1:8080/
  SEARXNG_CATEGORIES      Default: general,news
  SEARXNG_LANGUAGE        Default: en

This script is designed to run as the openclaw user after the VM admin has
created that user and enabled linger. Root execution is refused.
EOF
}

usage_init() {
  cat <<'EOF'
Usage:
  ./oc.sh init [--allow-current-user]

Create OpenClaw runtime directories under the current user's home.
EOF
}

usage_config() {
  cat <<'EOF'
Usage:
  ./oc.sh config openclaw [--allow-current-user]
  ./oc.sh config litellm [--allow-current-user]
  ./oc.sh config searxng [--allow-current-user]
  DISCORD_BOT_TOKEN='...' ./oc.sh config discord [options] [--allow-current-user]

Targets:
  openclaw
    Creates ~/.openclaw/openclaw.json if missing.
    Enables the default persistent browser profile at http://127.0.0.1:9222.
    Adds the LiteLLM provider at http://127.0.0.1:4000.
    Sets the default primary model to litellm/github_copilot/gpt-4.

  litellm
    Creates ~/.config/litellm/litellm.env with LITELLM_MASTER_KEY.
    Copies config/litellm/config.yaml to ~/.config/litellm/config.yaml.
    Writes LITELLM_API_KEY into ~/.config/openclaw-gateway/gateway.env.
    Creates LiteLLM token-cache directories under ~/.local/share/litellm.

  searxng
    Creates ~/.config/searxng/settings.yml if missing, with a generated secret.
    Leaves existing SearXNG settings unchanged.
    Writes SEARXNG_BASE_URL into ~/.config/openclaw-gateway/gateway.env.
    Patches ~/.openclaw/openclaw.json to use SearXNG for web search.

  discord
    Requires DISCORD_BOT_TOKEN in the environment.
    Writes DISCORD_BOT_TOKEN into ~/.config/openclaw-gateway/gateway.env.
    Patches ~/.openclaw/openclaw.json with Discord DM/guild allowlists.

Notes:
  Config commands do not install systemd units or start containers.
  Without --allow-current-user, config commands must run as user openclaw.
  --allow-current-user writes to the current user's HOME, not /home/openclaw.

Discord options:
  --dm-user ID            Allowed Discord DM user. Repeatable.
  --guild ID              Allowed Discord guild/server. Repeatable.
  --guild-user ID         Allowed guild user. Defaults to --dm-user values.
  --channel-id ID         Allowed guild channel. Repeatable.
  --require-mention bool  true or false. Default: false.
EOF
}

usage_install() {
  cat <<'EOF'
Usage:
  ./oc.sh install [fallback|quadlet] [--start-gateway] [--allow-current-user]

One-shot user-owned install. Creates config, installs user systemd units,
and starts core services. With no mode, automatically selects Quadlet when
.pod support exists, otherwise uses the Podman 4.9-compatible fallback.

Options:
  fallback                Force classic user-systemd fallback units.
  quadlet                 Force Quadlet units.
  --start-gateway         Start openclaw-gateway.service after install.
  --allow-current-user    Allow running as a non-openclaw, non-root user.
EOF
}

usage_uninstall() {
  cat <<'EOF'
Usage:
  ./oc.sh uninstall [--purge --yes] [--allow-current-user]

Stop OpenClaw services and remove installed units/helpers. Generated config,
credentials, browser data, and token caches are kept unless --purge --yes is set.

Options:
  --purge                 Also delete generated config, credentials, and data.
  --yes, -y               Required confirmation for --purge.
  --allow-current-user    Allow running as a non-openclaw, non-root user.
EOF
}

usage_service() {
  local action="${1:-start}"
  cat <<EOF
Usage:
  ./oc.sh ${action} [browser|litellm|searxng|gateway|pod|core|all] [--allow-current-user]

Run systemctl --user ${action} for one OpenClaw service group. Defaults to all.
EOF
}

usage_logs() {
  cat <<'EOF'
Usage:
  ./oc.sh logs [browser|litellm|searxng|gateway|pod|core|all] [--allow-current-user]

Follow user journal logs for one OpenClaw service group. Defaults to gateway.
EOF
}

usage_images() {
  cat <<'EOF'
Usage:
  ./oc.sh images [--json]

Print pinned container image repositories, tags, and sha256 manifest digests.

Options:
  --json                  Print image inventory as JSON.
EOF
}

usage_doctor() {
  cat <<'EOF'
Usage:
  ./oc.sh doctor [--allow-current-user]

Print service, Podman, browser, LiteLLM, SearXNG, and OpenClaw browser checks.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

split_image_ref() {
  local ref="$1"
  image_without_digest="${ref%@sha256:*}"
  image_digest="sha256:${ref##*@sha256:}"
  image_repository="${image_without_digest%:*}"
  image_tag="${image_without_digest##*:}"
}

print_images() {
  local format="${1:-text}"
  local i

  case "${format}" in
    text)
      for i in "${!image_names[@]}"; do
        split_image_ref "${image_refs[$i]}"
        printf '%s %s %s %s\n' "${image_names[$i]}" "${image_repository}" "${image_tag}" "${image_digest}"
      done
      ;;
    json)
      printf '[\n'
      for i in "${!image_names[@]}"; do
        split_image_ref "${image_refs[$i]}"
        printf '  {"name":"%s","repository":"%s","tag":"%s","digest":"%s","ref":"%s"}' \
          "${image_names[$i]}" \
          "${image_repository}" \
          "${image_tag}" \
          "${image_digest}" \
          "${image_refs[$i]}"
        if [[ "${i}" -lt "$((${#image_names[@]} - 1))" ]]; then
          printf ','
        fi
        printf '\n'
      done
      printf ']\n'
      ;;
    *)
      die "unknown images format: ${format}"
      ;;
  esac
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

assert_not_root() {
  [[ "${EUID}" -ne 0 ]] || die "run this as the openclaw user, not root"
}

assert_openclaw_user() {
  local allow_current_user="$1"
  assert_not_root
  if [[ "${allow_current_user}" != "true" && "$(id -un)" != "openclaw" ]]; then
    die "run this as user 'openclaw' or pass --allow-current-user"
  fi
}

parse_common_flags() {
  allow_current_user="false"
  remaining_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --allow-current-user)
        allow_current_user="true"
        shift
        ;;
      *)
        remaining_args+=("$1")
        shift
        ;;
    esac
  done
}

openclaw_config="${HOME}/.openclaw/openclaw.json"
gateway_env="${HOME}/.config/openclaw-gateway/gateway.env"
litellm_env="${HOME}/.config/litellm/litellm.env"

ensure_user_dirs() {
  mkdir -p \
    "${HOME}/.config/containers/systemd" \
    "${HOME}/.config/openclaw-gateway" \
    "${HOME}/.config/litellm" \
    "${HOME}/.config/searxng" \
    "${HOME}/.config/systemd/user" \
    "${HOME}/.local/bin" \
    "${HOME}/.local/share/litellm/github_copilot" \
    "${HOME}/.local/share/litellm/chatgpt" \
    "${HOME}/.local/share/openclaw-browser" \
    "${HOME}/.openclaw/workspace"

  chmod 0700 \
    "${HOME}/.config/openclaw-gateway" \
    "${HOME}/.config/litellm" \
    "${HOME}/.config/searxng" \
    "${HOME}/.local/share/litellm" \
    "${HOME}/.local/share/litellm/github_copilot" \
    "${HOME}/.local/share/litellm/chatgpt" \
    "${HOME}/.openclaw" 2>/dev/null || true

  if [[ ! -f "${gateway_env}" ]]; then
    : > "${gateway_env}"
    chmod 0600 "${gateway_env}"
  fi
}

replace_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${file}" ]]; then
    grep -v "^${key}=" "${file}" > "${tmp}" || true
  fi
  printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
  install -m 0600 "${tmp}" "${file}"
  rm -f "${tmp}"
}

ensure_openclaw_config_file() {
  ensure_user_dirs
  if [[ ! -f "${openclaw_config}" ]]; then
    printf '{}\n' > "${openclaw_config}"
    chmod 0600 "${openclaw_config}"
  fi
}

config_openclaw() {
  need_cmd jq
  ensure_openclaw_config_file

  local tmp
  tmp="$(mktemp)"
  jq '
    .browser.enabled = true |
    .browser.defaultProfile = "default" |
    .browser.profiles.default.cdpUrl = "http://127.0.0.1:9222" |
    .browser.profiles.default.color = "#FF4500" |
    del(.browser.profiles.default.driver) |
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
        },
        {
          id: "chatgpt/gpt-5.4",
          name: "ChatGPT GPT-5.4 via LiteLLM",
          reasoning: true,
          input: ["text", "image"],
          contextWindow: 128000,
          maxTokens: 32768
        }
      ]
    } |
    .agents.defaults.model.primary = "litellm/github_copilot/gpt-4"
  ' "${openclaw_config}" > "${tmp}"
  install -m 0600 "${tmp}" "${openclaw_config}"
  rm -f "${tmp}"

  echo "OpenClaw config updated: ${openclaw_config}"
}

config_litellm() {
  need_cmd openssl
  ensure_user_dirs

  local existing_master_key=""
  if [[ -f "${litellm_env}" ]]; then
    existing_master_key="$(grep '^LITELLM_MASTER_KEY=' "${litellm_env}" | cut -d= -f2- || true)"
  fi

  local master_key="${LITELLM_MASTER_KEY:-${existing_master_key}}"
  if [[ -z "${master_key}" ]]; then
    master_key="sk-litellm-$(openssl rand -hex 24)"
  fi

  local tmp
  tmp="$(mktemp)"
  cat > "${tmp}" <<EOF
LITELLM_MASTER_KEY=${master_key}
# GitHub Copilot and ChatGPT providers use OAuth device flow.
# No upstream API key is required for the default config.yaml.
# The first model request for each provider prints a device login URL/code in LiteLLM logs.
EOF
  install -m 0600 "${tmp}" "${litellm_env}"
  rm -f "${tmp}"

  if [[ -f "${repo_root}/config/litellm/config.yaml" ]]; then
    install -m 0600 "${repo_root}/config/litellm/config.yaml" "${HOME}/.config/litellm/config.yaml"
  fi

  replace_env_value "${gateway_env}" "LITELLM_API_KEY" "${master_key}"

  echo "LiteLLM env updated: ${litellm_env}"
  echo "Gateway env updated with LITELLM_API_KEY: ${gateway_env}"
}

config_searxng() {
  need_cmd jq
  need_cmd openssl
  ensure_user_dirs
  ensure_openclaw_config_file

  local base_url="${SEARXNG_BASE_URL:-http://127.0.0.1:8080/}"
  local categories="${SEARXNG_CATEGORIES:-general,news}"
  local language="${SEARXNG_LANGUAGE:-en}"
  local settings_file="${HOME}/.config/searxng/settings.yml"

  if [[ ! -f "${settings_file}" ]]; then
    local secret_key
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
    chmod 0600 "${settings_file}"
  else
    echo "Existing ${settings_file} found; leaving it unchanged."
  fi

  replace_env_value "${gateway_env}" "SEARXNG_BASE_URL" "${base_url}"

  local tmp
  tmp="$(mktemp)"
  jq \
    --arg baseUrl "${base_url}" \
    --arg categories "${categories}" \
    --arg language "${language}" '
    .tools.web.search.provider = "searxng" |
    .plugins.entries.searxng.config.webSearch.baseUrl = $baseUrl |
    .plugins.entries.searxng.config.webSearch.categories = $categories |
    .plugins.entries.searxng.config.webSearch.language = $language
  ' "${openclaw_config}" > "${tmp}"
  install -m 0600 "${tmp}" "${openclaw_config}"
  rm -f "${tmp}"

  echo "SearXNG settings: ${settings_file}"
  echo "SearXNG URL: ${base_url}"
}

config_discord() {
  need_cmd jq
  ensure_user_dirs
  ensure_openclaw_config_file

  local require_mention="false"
  local dm_users=()
  local guild_users=()
  local guild_ids=()
  local channel_ids=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dm-user)
        [[ $# -ge 2 ]] || die "--dm-user requires a value"
        dm_users+=("$2")
        shift 2
        ;;
      --guild-user)
        [[ $# -ge 2 ]] || die "--guild-user requires a value"
        guild_users+=("$2")
        shift 2
        ;;
      --guild|--server)
        [[ $# -ge 2 ]] || die "--guild requires a value"
        guild_ids+=("$2")
        shift 2
        ;;
      --channel|--channel-id)
        [[ $# -ge 2 ]] || die "--channel-id requires a value"
        channel_ids+=("$2")
        shift 2
        ;;
      --require-mention)
        [[ $# -ge 2 ]] || die "--require-mention requires true or false"
        require_mention="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown Discord option: $1"
        ;;
    esac
  done

  [[ -n "${DISCORD_BOT_TOKEN:-}" ]] || die "DISCORD_BOT_TOKEN is required in the environment"
  [[ "${#dm_users[@]}" -gt 0 ]] || die "at least one --dm-user is required"
  [[ "${#guild_ids[@]}" -gt 0 ]] || die "at least one --guild is required"
  case "${require_mention}" in
    true|false) ;;
    *) die "--require-mention must be true or false" ;;
  esac

  replace_env_value "${gateway_env}" "DISCORD_BOT_TOKEN" "${DISCORD_BOT_TOKEN}"

  if [[ "${#guild_users[@]}" -eq 0 ]]; then
    guild_users=("${dm_users[@]}")
  fi

  local dm_json guild_users_json guild_ids_json channel_ids_json tmp
  dm_json="$(printf '%s\n' "${dm_users[@]}" | jq -R . | jq -s .)"
  guild_users_json="$(printf '%s\n' "${guild_users[@]}" | jq -R . | jq -s .)"
  guild_ids_json="$(printf '%s\n' "${guild_ids[@]}" | jq -R . | jq -s .)"
  channel_ids_json="$(printf '%s\n' "${channel_ids[@]}" | jq -R . | jq -s .)"

  tmp="$(mktemp)"
  jq \
    --argjson dmUsers "${dm_json}" \
    --argjson guildUsers "${guild_users_json}" \
    --argjson guildIds "${guild_ids_json}" \
    --argjson channelIds "${channel_ids_json}" \
    --argjson requireMention "${require_mention}" '
    .channels.discord.enabled = true |
    .channels.discord.dmPolicy = "allowlist" |
    .channels.discord.allowFrom = $dmUsers |
    .channels.discord.groupPolicy = "allowlist" |
    .channels.discord.guilds = (.channels.discord.guilds // {}) |
    reduce $guildIds[] as $gid (
      .;
      .channels.discord.guilds[$gid] = (
        (.channels.discord.guilds[$gid] // {}) as $existing |
        (
          $existing + {
            requireMention: $requireMention,
            users: $guildUsers
          }
          | if ($channelIds | length) > 0 then
              .channels = (
                ($existing.channels // {}) |
                reduce $channelIds[] as $cid (
                  .;
                  .[$cid] = ((.[$cid] // {}) + {
                    allow: true,
                    requireMention: $requireMention
                  })
                )
              )
            else
              .
            end
        )
      )
    ) |
    del(.channels.discord.token)
  ' "${openclaw_config}" > "${tmp}"
  install -m 0600 "${tmp}" "${openclaw_config}"
  rm -f "${tmp}"

  echo "Discord config updated: ${openclaw_config}"
  echo "Discord token stored in: ${gateway_env}"
}

ensure_user_systemd_env() {
  local uid
  uid="$(id -u)"

  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"

  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi
}

require_user_systemd_bus() {
  ensure_user_systemd_env

  if [[ ! -d "${XDG_RUNTIME_DIR}" || ! -S "${XDG_RUNTIME_DIR}/bus" ]]; then
    cat >&2 <<EOF
error: user systemd bus is not available at ${XDG_RUNTIME_DIR}/bus

Ask the VM admin to run:
  sudo loginctl enable-linger $(id -un)
  sudo systemctl start user@$(id -u).service

Then start a new shell as $(id -un) and retry.
EOF
    exit 1
  fi
}

systemctl_user() {
  require_user_systemd_bus
  systemctl --user "$@"
}

service_name() {
  case "${1:-all}" in
    pod|openclaw-pod|openclaw-pod.service) echo "openclaw-pod.service" ;;
    browser|openclaw-browser|openclaw-browser.service) echo "openclaw-browser.service" ;;
    litellm|litellm.service) echo "litellm.service" ;;
    searxng|searxng.service) echo "searxng.service" ;;
    gateway|openclaw-gateway|openclaw-gateway.service) echo "openclaw-gateway.service" ;;
    all) printf '%s\n' "${services[@]}" ;;
    core) printf '%s\n' "${core_services[@]}" ;;
    *) die "unknown service: $1" ;;
  esac
}

copy_quadlet_units() {
  ensure_user_dirs
  install -m 0644 "${repo_root}/deploy/openclaw/openclaw.pod" "${HOME}/.config/containers/systemd/openclaw.pod"
  install -m 0644 "${repo_root}/deploy/openclaw/openclaw-browser.container" "${HOME}/.config/containers/systemd/openclaw-browser.container"
  install -m 0644 "${repo_root}/deploy/openclaw/litellm.container" "${HOME}/.config/containers/systemd/litellm.container"
  install -m 0644 "${repo_root}/deploy/openclaw/searxng.container" "${HOME}/.config/containers/systemd/searxng.container"
  install -m 0644 "${repo_root}/deploy/openclaw/openclaw-gateway.container" "${HOME}/.config/containers/systemd/openclaw-gateway.container"
}

copy_fallback_units() {
  ensure_user_dirs
  local unit helper
  for unit in "${repo_root}"/deploy/openclaw-systemd/*.service; do
    install -m 0644 "${unit}" "${HOME}/.config/systemd/user/$(basename "${unit}")"
  done
  for helper in "${repo_root}"/deploy/openclaw-systemd/bin/*; do
    install -m 0755 "${helper}" "${HOME}/.local/bin/$(basename "${helper}")"
  done
}

configure_core() {
  config_openclaw
  config_litellm
  config_searxng
}

start_core_services() {
  systemctl_user daemon-reload
  systemctl_user start "${core_services[@]}"
}

quadlet_pod_supported() {
  if ! command -v man >/dev/null 2>&1; then
    return 1
  fi
  man podman-systemd.unit 2>/dev/null | grep -Eq '(^|[[:space:]])name\.pod([[:space:]]|$)|\.pod'
}

install_fallback() {
  configure_core
  copy_fallback_units
  start_core_services
  echo "Installed Podman 4.9-compatible user-systemd fallback units."
}

install_quadlet() {
  configure_core
  copy_quadlet_units
  start_core_services
  echo "Installed Quadlet units."
}

install_auto() {
  if quadlet_pod_supported; then
    echo "Detected Quadlet .pod support; using quadlet installer."
    install_quadlet
  else
    echo "Quadlet .pod support not detected; using fallback installer."
    install_fallback
  fi
}

stop_openclaw_runtime() {
  systemctl_user stop "${services[@]}" >/dev/null 2>&1 || true

  if command -v podman >/dev/null 2>&1; then
    podman rm -f \
      openclaw-gateway \
      openclaw-searxng \
      openclaw-litellm \
      openclaw-browser >/dev/null 2>&1 || true
    podman pod rm -f openclaw >/dev/null 2>&1 || true
  fi
}

uninstall_openclaw() {
  local purge="$1"
  local yes="$2"

  if [[ "${purge}" == "true" && "${yes}" != "true" ]]; then
    die "--purge deletes generated config, credentials, and data; rerun with --purge --yes"
  fi

  stop_openclaw_runtime

  rm -f \
    "${HOME}/.config/systemd/user/openclaw-pod.service" \
    "${HOME}/.config/systemd/user/openclaw-browser.service" \
    "${HOME}/.config/systemd/user/openclaw-gateway.service" \
    "${HOME}/.config/systemd/user/litellm.service" \
    "${HOME}/.config/systemd/user/searxng.service" \
    "${HOME}/.config/containers/systemd/openclaw.pod" \
    "${HOME}/.config/containers/systemd/openclaw-browser.container" \
    "${HOME}/.config/containers/systemd/openclaw-gateway.container" \
    "${HOME}/.config/containers/systemd/litellm.container" \
    "${HOME}/.config/containers/systemd/searxng.container" \
    "${HOME}/.local/bin/openclaw-run-browser" \
    "${HOME}/.local/bin/openclaw-run-gateway" \
    "${HOME}/.local/bin/openclaw-run-litellm" \
    "${HOME}/.local/bin/openclaw-run-searxng"

  systemctl_user daemon-reload >/dev/null 2>&1 || true
  systemctl_user reset-failed "${services[@]}" >/dev/null 2>&1 || true

  if [[ "${purge}" == "true" ]]; then
    rm -rf \
      "${HOME}/.openclaw" \
      "${HOME}/.config/openclaw-gateway" \
      "${HOME}/.config/litellm" \
      "${HOME}/.config/searxng" \
      "${HOME}/.local/share/openclaw-browser" \
      "${HOME}/.local/share/litellm"
    echo "Uninstalled OpenClaw services and purged generated config, credentials, and data."
  else
    echo "Uninstalled OpenClaw services, units, and helper scripts."
    echo "Generated config and data were kept. To remove them: ./oc.sh uninstall --purge --yes"
  fi
}

doctor() {
  echo "== user systemd services =="
  systemctl_user status "${services[@]}" --no-pager || true

  echo
  echo "== podman containers =="
  podman ps -a || true

  echo
  echo "== Chromium CDP endpoint =="
  if command -v curl >/dev/null 2>&1; then
    curl -fsS http://127.0.0.1:9222/json/version | jq . || true
    curl -fsS http://127.0.0.1:9222/json/list | jq . || true
  else
    echo "curl is not installed."
  fi

  echo
  echo "== LiteLLM endpoint =="
  if command -v curl >/dev/null 2>&1; then
    if [[ -f "${litellm_env}" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "${litellm_env}"
      set +a
    fi

    curl -fsS http://127.0.0.1:4000/health/liveliness | jq . || true
    if [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
      curl -fsS http://127.0.0.1:4000/models \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | jq . || true
    else
      echo "LITELLM_MASTER_KEY is not set; skipping authenticated /models check."
    fi
  else
    echo "curl is not installed."
  fi

  echo
  echo "== SearXNG endpoint =="
  if command -v curl >/dev/null 2>&1; then
    curl -fsS http://127.0.0.1:8080/ >/dev/null && echo "SearXNG HTML endpoint OK" || true
    curl -fsS 'http://127.0.0.1:8080/search?q=openclaw&format=json' | jq '.query, (.results | length)' || true
  else
    echo "curl is not installed."
  fi

  echo
  echo "== OpenClaw browser doctor =="
  if command -v openclaw >/dev/null 2>&1; then
    openclaw browser --browser-profile default doctor || true
  else
    echo "openclaw CLI is not installed or not in PATH."
  fi
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    -h|--help|help|"")
      usage
      ;;
    init)
      shift
      case "${1:-}" in -h|--help) usage_init; exit 0 ;; esac
      parse_common_flags "$@"
      assert_openclaw_user "${allow_current_user}"
      ensure_user_dirs
      echo "Initialized OpenClaw directories under ${HOME}."
      ;;
    config)
      shift
      case "${1:-}" in -h|--help|"") usage_config; exit 0 ;; esac
      local config_target="${1:-}"
      shift
      case "${1:-}" in -h|--help) usage_config; exit 0 ;; esac
      parse_common_flags "$@"
      assert_openclaw_user "${allow_current_user}"
      set -- "${remaining_args[@]}"
      case "${config_target}" in
        openclaw) [[ $# -eq 0 ]] || die "config openclaw does not accept extra arguments"; config_openclaw ;;
        litellm) [[ $# -eq 0 ]] || die "config litellm does not accept extra arguments"; config_litellm ;;
        searxng) [[ $# -eq 0 ]] || die "config searxng does not accept extra arguments"; config_searxng ;;
        discord) config_discord "$@" ;;
        *) die "unknown config target: ${config_target}" ;;
      esac
      ;;
    install)
      shift
      case "${1:-}" in -h|--help) usage_install; exit 0 ;; esac
      local mode="auto"
      local start_gateway="false"
      local args=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          fallback|quadlet)
            mode="$1"
            shift
            ;;
          --start-gateway)
            start_gateway="true"
            shift
            ;;
          *)
            args+=("$1")
            shift
            ;;
        esac
      done
      parse_common_flags "${args[@]}"
      assert_openclaw_user "${allow_current_user}"
      need_cmd jq
      need_cmd podman
      need_cmd systemctl
      case "${mode}" in
        auto) install_auto ;;
        fallback) install_fallback ;;
        quadlet) install_quadlet ;;
      esac
      if [[ "${start_gateway}" == "true" ]]; then
        systemctl_user start openclaw-gateway.service
        echo "Started openclaw-gateway.service."
      else
        echo "Gateway is installed but not started. Start it with: ./oc.sh start gateway"
      fi
      ;;
    uninstall)
      shift
      case "${1:-}" in -h|--help) usage_uninstall; exit 0 ;; esac
      local purge="false"
      local yes="false"
      local args=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --purge)
            purge="true"
            shift
            ;;
          --yes|-y)
            yes="true"
            shift
            ;;
          *)
            args+=("$1")
            shift
            ;;
        esac
      done
      parse_common_flags "${args[@]}"
      assert_openclaw_user "${allow_current_user}"
      uninstall_openclaw "${purge}" "${yes}"
      ;;
    images)
      shift
      case "${1:-}" in
        "") print_images text ;;
        --json) print_images json ;;
        -h|--help) usage_images ;;
        *) die "unknown images option: $1" ;;
      esac
      ;;
    start|stop|restart|status)
      local action="${cmd}"
      shift
      case "${1:-}" in -h|--help) usage_service "${action}"; exit 0 ;; esac
      parse_common_flags "$@"
      assert_openclaw_user "${allow_current_user}"
      set -- "${remaining_args[@]}"
      mapfile -t selected_services < <(service_name "${1:-all}")
      if [[ "${action}" == "status" ]]; then
        systemctl_user status "${selected_services[@]}" --no-pager
      else
        systemctl_user "${action}" "${selected_services[@]}"
      fi
      ;;
    logs)
      shift
      case "${1:-}" in -h|--help) usage_logs; exit 0 ;; esac
      parse_common_flags "$@"
      assert_openclaw_user "${allow_current_user}"
      set -- "${remaining_args[@]}"
      mapfile -t selected_services < <(service_name "${1:-gateway}")
      require_user_systemd_bus
      journalctl --user -u "${selected_services[@]}" -f
      ;;
    doctor)
      shift
      case "${1:-}" in -h|--help) usage_doctor; exit 0 ;; esac
      parse_common_flags "$@"
      assert_openclaw_user "${allow_current_user}"
      doctor
      ;;
    *)
      die "unknown command: ${cmd}"
      ;;
  esac
}

main "$@"
