---
name: update-container-image-pins
description: Refresh OpenClaw Podman container image tags and SHA256 digests.
---

# Update Container Image Pins

Use this skill when asked to refresh, verify, or update container image tags and SHA256 digests.

## Goal

Keep all runtime images pinned with immutable tag-plus-digest references. Do not use mutable tags such as `latest`, `main`, `main-latest`, or `stable` in deployment assets.

Pinned references must use this form:

```text
registry.example/repository/image:tag@sha256:digest
```

## Runtime Images

This repo currently pins these images:

```text
openclaw-gateway ghcr.io/openclaw/openclaw
openclaw-browser docker.io/chromedp/headless-shell
litellm docker.litellm.ai/berriai/litellm
searxng docker.io/searxng/searxng
```

## Files To Update

When changing a pin, update every copy of that image reference:

```text
oc.sh
README.md
deploy/openclaw/openclaw-browser.container
deploy/openclaw/openclaw-gateway.container
deploy/openclaw/litellm.container
deploy/openclaw/searxng.container
deploy/openclaw-systemd/bin/openclaw-run-browser
deploy/openclaw-systemd/bin/openclaw-run-gateway
deploy/openclaw-systemd/bin/openclaw-run-litellm
deploy/openclaw-systemd/bin/openclaw-run-searxng
deploy/openclaw-systemd/openclaw-browser.service
```

`oc.sh` is the source for `./oc.sh images` and `./oc.sh images --json`. Keep its image inventory synchronized with the deployment files and README.

## Selecting Tags

Prefer the newest concrete release/version tag that is not mutable:

- OpenClaw: prefer date tags like `2026.4.24`.
- Browser: prefer Chromium version tags like `148.0.7778.56`; avoid `latest` and `stable`.
- LiteLLM: prefer concrete `main-vX.Y.Z` tags; avoid `main`, `latest`, and `main-latest`.
- SearXNG: prefer date/hash tags like `2026.4.24-a7ac696b4`; avoid `latest`.

Use manifest-list or OCI-index digests where available so multi-arch behavior is preserved.

## Querying Registries

Docker Hub tags can be inspected with the Docker Hub API:

```bash
curl -fsSL 'https://registry.hub.docker.com/v2/repositories/chromedp/headless-shell/tags?page_size=20' | jq .
curl -fsSL 'https://registry.hub.docker.com/v2/repositories/searxng/searxng/tags?page_size=20' | jq .
```

Registry manifests can usually be inspected without pulling images:

```bash
docker manifest inspect docker.io/chromedp/headless-shell:148.0.7778.56
docker manifest inspect docker.io/searxng/searxng:2026.4.24-a7ac696b4
docker manifest inspect ghcr.io/openclaw/openclaw:2026.4.24
docker manifest inspect docker.litellm.ai/berriai/litellm:main-v1.82.3
```

If direct registry API calls require bearer tokens, use the registry `WWW-Authenticate` challenge to request an anonymous pull token, then request the manifest with this `Accept` header:

```text
application/vnd.oci.image.index.v1+json,
application/vnd.docker.distribution.manifest.list.v2+json,
application/vnd.oci.image.manifest.v1+json,
application/vnd.docker.distribution.manifest.v2+json
```

Capture both:

- the top-level manifest-list or OCI-index digest from `Docker-Content-Digest`
- the `linux/amd64` and `linux/arm64` child manifest digests for review notes

Only the top-level digest should be used in deployment references unless there is a deliberate single-architecture reason.

## Updating Files

After selecting new pins, update:

- `Image=` lines in Quadlet `.container` files
- image arguments in fallback `openclaw-run-*` scripts
- inline image in `deploy/openclaw-systemd/openclaw-browser.service`
- `image_refs` in `oc.sh`
- README `Pinned Images` section

Then run:

```bash
bash -n ./oc.sh
./oc.sh images
./oc.sh images --json | jq .
git diff --check
```

Confirm no mutable image references remain:

```bash
rg ':latest|main-latest|:stable|:main([^[:alnum:]_.-]|$)' .
```

The command may match documentation that explains forbidden tags. Deployment assets must not match mutable tags.

## Consistency Checks

Before committing, verify:

- Every image shown by `./oc.sh images` appears in the matching deployment assets.
- `./oc.sh images --json` is valid JSON.
- No deployment file uses `latest`, `main`, `main-latest`, or `stable`.
- README pins match `oc.sh` exactly.
- The PR summary includes old and new refs plus verification commands.

## Commit Style

Use a focused commit message such as:

```text
Update pinned container images
```

Do not combine image pin refreshes with unrelated bootstrap or config changes.
