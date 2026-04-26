---
name: update-openclaw-config
description: Add or change oc.sh behavior that writes OpenClaw JSON config.
---

# Update OpenClaw Config

Use this skill when adding or changing code that writes, patches, validates, or documents `~/.openclaw/openclaw.json`.

## Goal

Keep this repo aligned with OpenClaw's native configuration model. `oc.sh` may patch OpenClaw config so deployed host/service resources are usable, but OpenClaw owns the schema and runtime semantics.

## Required References

Before choosing config paths, consult the upstream configuration reference:

```text
https://docs.openclaw.ai/gateway/configuration-reference
```

Use more specific upstream docs when relevant:

```text
https://docs.openclaw.ai/cli/config
https://docs.openclaw.ai/cli/agents
https://docs.openclaw.ai/channels/channel-routing
https://docs.openclaw.ai/channels/discord
https://docs.openclaw.ai/gateway/config-channels
https://docs.openclaw.ai/reference/secretref-credential-surface
```

Fetch current docs during the task when network access is available. Do not assume stale config paths from memory.

## Design Boundary

OpenClaw owns application and runtime semantics. `oc.sh` owns host/service resources and keeps OpenClaw config pointed at them correctly.

Use `oc.sh` for:

- host/service resources
- env files and generated runtime secrets
- systemd/Podman assets
- sidecar service config
- integration-specific OpenClaw config patches

Use OpenClaw-native concepts for config:

- JSON-path config writes
- SecretRefs
- model providers
- channel accounts
- agents
- bindings

Do not invent repo-specific config schemas when OpenClaw has a documented path or runtime concept.

## Secret Handling

Keep raw secrets out of `openclaw.json`.

When OpenClaw supports a SecretRef for a credential path:

- Write the raw value to a user-owned env/config file with restrictive permissions.
- Write a SecretRef into `openclaw.json`.
- Ensure the referenced provider exists, for example `secrets.providers.default.source = "env"`.

Examples:

```text
~/.config/openclaw-gateway/gateway.env
~/.config/litellm/litellm.env
```

## Implementation Rules

Prefer the generic config primitives in `oc.sh` for OpenClaw JSON updates:

```bash
./oc.sh config get <path>
./oc.sh config set <path> <value>
./oc.sh config unset <path>
```

Inside `oc.sh`, prefer helpers such as:

```bash
config_set_path
config_set_json
config_unset_path
```

Use focused `jq` only when generic path writes are not expressive enough, such as upserting entries in `agents.list[]` or `bindings[]`.

When adding or changing a config-related subcommand:

- Support both `-h` and `--help` without requiring the `openclaw` user, user systemd, Podman, or runtime services.
- Update README/docs when user-visible behavior changes.
- Include examples for SecretRefs, accounts, agents, or bindings when those concepts are involved.

## Validation

At minimum, run:

```bash
bash -n ./oc.sh
./oc.sh config -h
git diff --check
```

Use temporary-home smoke tests for config writes so real user state is not touched:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" ./oc.sh config set browser.enabled true --strict-json --allow-current-user
jq . "${tmp_home}/.openclaw/openclaw.json"
```

For feature wrappers, verify:

- expected config paths exist
- raw secrets are absent from `openclaw.json`
- raw secrets are present only in the intended env/config file
- SecretRefs point to the intended env var/provider
- account, agent, and binding entries match upstream docs

If OpenClaw CLI or the pinned OpenClaw image is available, prefer validating generated config with OpenClaw's own schema/doctor commands.

## Commit Style

Use a focused commit message such as:

```text
Align Discord config with OpenClaw accounts
```

Do not combine config schema changes with unrelated image pin updates or service lifecycle refactors.
