# Agent Instructions

This repo uses a single user-run bootstrap entrypoint, `oc.sh`. Prefer small, focused changes and keep README/docs synchronized with command behavior.

## `oc.sh` Subcommands

When adding or changing an `oc.sh` subcommand, make sure the subcommand supports both `-h` and `--help`. Help output must work without requiring the `openclaw` user, user systemd, Podman, or other runtime services.

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
