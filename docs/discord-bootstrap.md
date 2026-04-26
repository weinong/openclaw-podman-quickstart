# Bootstrap Discord for OpenClaw

This guide configures OpenClaw's Discord channel with:

- bot token loaded from a user-only environment file through an OpenClaw SecretRef
- DM allowlist
- guild/server allowlist
- optional guild channel allowlist
- optional guild user allowlist
- `requireMention: false` for private servers where the bot should respond without being @mentioned

The raw token is not stored in `openclaw.json`; only a SecretRef to `DISCORD_BOT_TOKEN` is stored there.

## Discord Prerequisites

In the Discord Developer Portal:

1. Create an application.
2. Add a bot.
3. Copy the bot token.
4. Enable the required bot intents: Message Content Intent and, if using allowlists or name lookups, Server Members Intent.
5. Invite the bot to your server with permission to read and send messages in the channels where you want to use it.

Use Discord numeric IDs for bootstrap:

- your Discord user ID
- the Discord guild/server ID
- optional Discord channel IDs

In Discord, enable Developer Mode, then right-click the user, server, or channel and copy the ID.

## Configure Discord

Run from the repo checkout as the `openclaw` user:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  ./oc.sh config discord \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --require-mention false
```

For multiple allowed DM users:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  ./oc.sh config discord \
    --dm-user USER_ID_1 \
    --dm-user USER_ID_2 \
    --guild YOUR_DISCORD_GUILD_ID \
    --require-mention false
```

For a different guild user allowlist than the DM allowlist:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  ./oc.sh config discord \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --guild-user ALLOWED_GUILD_USER_ID \
    --require-mention false
```

To restrict the bot to one or more guild channels, add `--channel-id` values:

```bash
DISCORD_BOT_TOKEN='YOUR_BOT_TOKEN' \
  ./oc.sh config discord \
    --dm-user YOUR_DISCORD_USER_ID \
    --guild YOUR_DISCORD_GUILD_ID \
    --channel-id YOUR_DISCORD_CHANNEL_ID \
    --require-mention false
```

If `--channel-id` is omitted, the script allowlists the guild without adding a channel restriction. If one or more `--channel-id` values are set, OpenClaw restricts that guild to those channels.

## What `oc.sh` Writes

Token location:

```text
~/.config/openclaw-gateway/gateway.env
```

OpenClaw config location:

```text
~/.openclaw/openclaw.json
```

The script patches the Discord channel block into `openclaw.json`:

```json
{
  "channels": {
    "discord": {
      "enabled": true,
      "token": {
        "source": "env",
        "provider": "default",
        "id": "DISCORD_BOT_TOKEN"
      },
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

With channel restrictions, the guild entry includes a `channels` map. The script also ensures this secret provider exists:

```json
{
  "secrets": {
    "providers": {
      "default": {
        "source": "env"
      }
    }
  }
}
```

The raw token value stays in `~/.config/openclaw-gateway/gateway.env`; `openclaw.json` stores only the SecretRef.

## Restart the Gateway

If the gateway container is already running:

```bash
./oc.sh restart gateway
```

If the gateway has not been started yet:

```bash
./oc.sh start gateway
```

Check logs:

```bash
./oc.sh logs gateway
```

## Validate Config

```bash
jq '.channels.discord' ~/.openclaw/openclaw.json
sed 's/DISCORD_BOT_TOKEN=.*/DISCORD_BOT_TOKEN=<redacted>/' ~/.config/openclaw-gateway/gateway.env
./oc.sh doctor
```

## Notes

- `dmPolicy: "allowlist"` restricts direct messages to the configured `allowFrom` entries.
- `groupPolicy: "allowlist"` restricts guild/server handling to configured guild IDs.
- If a guild has no `channels` block, messages from the allowlisted users are allowed anywhere in that guild where the bot has Discord permissions.
- If a guild has a `channels` block, only listed channels are allowed.
- `requireMention: false` allows the bot to respond in that guild or channel without being @mentioned. This is best for private servers where the bot is expected to participate freely.
- For shared or busy servers, prefer `requireMention: true` to reduce accidental bot responses.
