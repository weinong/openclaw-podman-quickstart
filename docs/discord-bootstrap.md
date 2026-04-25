# Bootstrap Discord for OpenClaw

This guide configures OpenClaw's Discord channel with:

- bot token loaded from a user-only environment file
- DM allowlist
- guild/server allowlist
- optional guild user allowlist
- `requireMention: false` for private servers where the bot should respond without being @mentioned

The token is not stored in `openclaw.json`.

## Discord prerequisites

In the Discord Developer Portal:

1. Create an application.
2. Add a bot.
3. Copy the bot token.
4. Enable the required bot intents:
   - Message Content Intent
   - Server Members Intent, if you plan to use allowlists or name lookups
5. Invite the bot to your server with permission to read and send messages in the channels where you want to use it.

Use Discord numeric IDs for bootstrap:

- your Discord user ID
- the Discord guild/server ID

In Discord, enable Developer Mode, then right-click the user/server and copy the ID.

## Configure Discord

Run from the repo checkout as a sudo-capable user:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  sudo -E bash ./scripts/configure-discord.sh openclaw \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --require-mention false
```

For multiple allowed DM users:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  sudo -E bash ./scripts/configure-discord.sh openclaw \
    --dm-user USER_ID_1 \
    --dm-user USER_ID_2 \
    --guild YOUR_DISCORD_GUILD_ID \
    --require-mention false
```

For a different guild user allowlist than the DM allowlist:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  sudo -E bash ./scripts/configure-discord.sh openclaw \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --guild-user ALLOWED_GUILD_USER_ID \
    --require-mention false
```

## What the script writes

Token location:

```text
~openclaw/.config/openclaw-gateway/gateway.env
```

Example content:

```bash
DISCORD_BOT_TOKEN=...
```

The file is created with mode `0600` and owned by the service user.

OpenClaw config location:

```text
~openclaw/.openclaw/openclaw.json
```

The script patches the Discord channel block into `openclaw.json`:

```json
{
  "channels": {
    "discord": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "allowFrom": ["YOUR_DISCORD_USER_ID"],
      "groupPolicy": "allowlist",
      "guilds": {
        "YOUR_DISCORD_GUILD_ID": {
          "requireMention": false,
          "users": ["YOUR_DISCORD_USER_ID"]
        }
      }
    }
  }
}
```

The script also deletes `channels.discord.token` if present, so the bot token is not stored in JSON.

## Restart the gateway

If the gateway container is already running:

```bash
sudo -iu openclaw
systemctl --user restart openclaw-gateway.service
```

If the gateway has not been started yet:

```bash
sudo -iu openclaw
systemctl --user start openclaw-gateway.service
```

Check logs:

```bash
journalctl --user -u openclaw-gateway.service -f
```

## Validate config

As the service user:

```bash
sudo -iu openclaw
jq '.channels.discord' ~/.openclaw/openclaw.json
cat ~/.config/openclaw-gateway/gateway.env | sed 's/DISCORD_BOT_TOKEN=.*/DISCORD_BOT_TOKEN=<redacted>/'
```

Then run the general doctor:

```bash
bash ./openclaw-podman-quickstart/scripts/doctor-openclaw-podman.sh
```

## Notes

- `dmPolicy: "allowlist"` restricts direct messages to the configured `allowFrom` entries.
- `groupPolicy: "allowlist"` restricts guild/server handling to configured guild IDs.
- `requireMention: false` allows the bot to respond in that guild without being @mentioned. This is best for private servers where the bot is expected to participate freely.
- For shared or busy servers, prefer `requireMention: true` to reduce accidental bot responses.
