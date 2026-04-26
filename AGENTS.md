# Agent Instructions

This repo uses a single user-run bootstrap entrypoint, `oc.sh`. Prefer small, focused changes and keep README/docs synchronized with command behavior.

## Design Principle

`oc.sh` is the repository's control plane for a Podman-based OpenClaw host. It installs and manages supporting services, writes their runtime secrets/config, and patches OpenClaw config with the SecretRefs, providers, accounts, and bindings needed to use those services.

OpenClaw owns application and runtime semantics. `oc.sh` owns host/service resources and keeps OpenClaw config pointed at them correctly.

When adding features, keep this boundary clear:

- Use `oc.sh` for host/service resources, env files, systemd/Podman assets, image pins, and integration-specific config patches.
- Align config changes with OpenClaw-native concepts such as JSON-path config writes, SecretRefs, channel accounts, agents, and bindings.
- Do not invent repo-specific config schemas when an OpenClaw config path or runtime concept exists.
- Keep raw secrets out of `openclaw.json`; use SecretRefs where OpenClaw supports them and store actual values in user-owned env/config files with restrictive permissions.

## OpenClaw Config Changes

When adding or changing code that writes `~/.openclaw/openclaw.json`, follow the skill in:

```text
.agents/skills/update-openclaw-config/SKILL.md
```

Always consult the upstream configuration reference before choosing config paths:

```text
https://docs.openclaw.ai/gateway/configuration-reference
```

Use channel-specific upstream docs when relevant, such as `https://docs.openclaw.ai/channels/discord` for Discord accounts, SecretRefs, and routing.

## `oc.sh` Subcommands

When adding or changing an `oc.sh` subcommand, make sure the subcommand supports both `-h` and `--help`. When adding, removing, renaming, or aliasing command flags, update the relevant help text in the same change so `-h`/`--help` reflects the parser exactly. Help output must work without requiring the `openclaw` user, user systemd, Podman, or other runtime services.

## Container Image Pins

When updating container image tags or SHA256 digests, follow the skill in:

```text
.agents/skills/update-container-image-pins/SKILL.md
```

Key requirements:

- Use immutable `tag@sha256:digest` references.
- Do not use mutable deployment tags such as `latest`, `main`, `main-latest`, or `stable`.
- Keep `oc.sh images`, deployment files, and README pinned-image documentation synchronized.
- Verify with `bash -n ./oc.sh`, `./oc.sh images`, `./oc.sh images --json | jq .`, and `git diff --check`.
