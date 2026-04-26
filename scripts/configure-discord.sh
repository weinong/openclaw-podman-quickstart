#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  DISCORD_BOT_TOKEN='...' sudo -E ./scripts/configure-discord.sh openclaw \
    --dm-user DISCORD_USER_ID \
    --guild DISCORD_GUILD_ID \
    [--channel-id DISCORD_CHANNEL_ID] \
    [--guild-user DISCORD_USER_ID] \
    [--require-mention true|false]

Examples:
  DISCORD_BOT_TOKEN='...' sudo -E ./scripts/configure-discord.sh openclaw \
    --dm-user 123456789012345678 \
    --guild 987654321098765432 \
    --require-mention false

  DISCORD_BOT_TOKEN='...' sudo -E ./scripts/configure-discord.sh openclaw \
    --dm-user 123456789012345678 \
    --guild 987654321098765432 \
    --channel-id 111122223333444455 \
    --require-mention false

Notes:
  - The token is written to ~/.config/openclaw-gateway/gateway.env with mode 0600.
  - The token is not written to openclaw.json.
  - Use Discord numeric user IDs, guild/server IDs, and channel IDs.
  - If --channel-id is omitted, the allowlisted guild is allowed without channel restriction.
  - If one or more --channel-id values are set, OpenClaw restricts that guild to those channels.
EOF
}

svc_user="${1:-openclaw}"
shift || true

require_mention="false"
dm_users=()
guild_users=()
guild_ids=()
channel_ids=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dm-user)
      dm_users+=("$2")
      shift 2
      ;;
    --guild-user)
      guild_users+=("$2")
      shift 2
      ;;
    --guild|--server)
      guild_ids+=("$2")
      shift 2
      ;;
    --channel|--channel-id)
      channel_ids+=("$2")
      shift 2
      ;;
    --require-mention)
      require_mention="$2"
      shift 2
      ;;
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
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
  echo "DISCORD_BOT_TOKEN is required in the environment." >&2
  echo "Example: DISCORD_BOT_TOKEN='...' sudo -E $0 ${svc_user} --dm-user USER_ID --guild GUILD_ID" >&2
  exit 1
fi

if [[ "${#dm_users[@]}" -eq 0 ]]; then
  echo "At least one --dm-user DISCORD_USER_ID is required." >&2
  exit 1
fi

if [[ "${#guild_ids[@]}" -eq 0 ]]; then
  echo "At least one --guild DISCORD_GUILD_ID is required." >&2
  exit 1
fi

case "${require_mention}" in
  true|false) ;;
  *)
    echo "--require-mention must be true or false." >&2
    exit 1
    ;;
esac

home_dir="$(getent passwd "${svc_user}" | cut -d: -f6)"
if [[ -z "${home_dir}" ]]; then
  echo "User not found: ${svc_user}" >&2
  exit 1
fi

config_file="${home_dir}/.openclaw/openclaw.json"
gateway_env_dir="${home_dir}/.config/openclaw-gateway"
gateway_env="${gateway_env_dir}/gateway.env"

install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${gateway_env_dir}"
install -d -o "${svc_user}" -g "${svc_user}" -m 0700 "${home_dir}/.openclaw"

# Preserve existing non-Discord values in gateway.env while replacing DISCORD_BOT_TOKEN.
tmp_env="$(mktemp)"
if [[ -f "${gateway_env}" ]]; then
  grep -v '^DISCORD_BOT_TOKEN=' "${gateway_env}" > "${tmp_env}" || true
fi
printf 'DISCORD_BOT_TOKEN=%s\n' "${DISCORD_BOT_TOKEN}" >> "${tmp_env}"
install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_env}" "${gateway_env}"
rm -f "${tmp_env}"

if [[ ! -f "${config_file}" ]]; then
  cat > "${config_file}" <<'JSON'
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
  chown "${svc_user}:${svc_user}" "${config_file}"
  chmod 0600 "${config_file}"
fi

dm_json="$(printf '%s\n' "${dm_users[@]}" | jq -R . | jq -s .)"
if [[ "${#guild_users[@]}" -eq 0 ]]; then
  guild_users=("${dm_users[@]}")
fi
guild_users_json="$(printf '%s\n' "${guild_users[@]}" | jq -R . | jq -s .)"
guild_ids_json="$(printf '%s\n' "${guild_ids[@]}" | jq -R . | jq -s .)"
channel_ids_json="$(printf '%s\n' "${channel_ids[@]}" | jq -R . | jq -s .)"

tmp_config="$(mktemp)"
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
' "${config_file}" > "${tmp_config}"

install -o "${svc_user}" -g "${svc_user}" -m 0600 "${tmp_config}" "${config_file}"
rm -f "${tmp_config}"

uid="$(id -u "${svc_user}")"
sudo -u "${svc_user}" \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
  systemctl --user daemon-reload || true

echo "Discord bootstrap complete."
echo "Token: ${gateway_env}"
echo "Config: ${config_file}"
echo "Restart the gateway after reviewing config: systemctl --user restart openclaw-gateway.service"
