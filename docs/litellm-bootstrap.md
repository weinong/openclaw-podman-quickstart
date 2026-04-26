# Bootstrap LiteLLM sidecar for OpenClaw

This guide runs LiteLLM as a sidecar in the same rootless Podman pod as OpenClaw and preconfigures OpenClaw to use it as the default model provider.

The default provider in this repo is **GitHub Copilot via LiteLLM**. LiteLLM manages the GitHub Copilot OAuth device-code flow and caches the resulting token under the `openclaw` service user's persistent data directory.

## Target architecture

```text
Podman pod: openclaw
├── openclaw-gateway
│   └── uses LITELLM_API_KEY from ~/.config/openclaw-gateway/gateway.env
├── openclaw-litellm
│   ├── listens on http://127.0.0.1:4000 inside the pod
│   └── manages GitHub Copilot OAuth token cache under ~/.local/share/litellm/github_copilot
└── openclaw-browser
    └── persistent CDP endpoint on http://127.0.0.1:9222
```

The pod publishes LiteLLM on host loopback only:

```text
127.0.0.1:4000:4000
```

## Files installed

The installer copies:

```text
~openclaw/.config/containers/systemd/litellm.container
~openclaw/.config/litellm/config.yaml
~openclaw/.config/litellm/litellm.env
```

It also creates or updates:

```text
~openclaw/.local/share/litellm/github_copilot
~openclaw/.config/openclaw-gateway/gateway.env
~openclaw/.openclaw/openclaw.json
```

## Configure LiteLLM gateway auth

No upstream API key is required for the default GitHub Copilot provider config.

LiteLLM still needs a local master key so OpenClaw can authenticate to the LiteLLM proxy. The installer generates this automatically:

```text
~openclaw/.config/litellm/litellm.env
```

Example:

```bash
LITELLM_MASTER_KEY=sk-litellm-...
```

The installer also writes the same value to the OpenClaw gateway env file as `LITELLM_API_KEY`:

```text
~openclaw/.config/openclaw-gateway/gateway.env
```

OpenClaw uses `LITELLM_API_KEY` to authenticate to LiteLLM.

You can regenerate or set the key explicitly with:

```bash
sudo ./scripts/configure-litellm.sh openclaw
```

or:

```bash
LITELLM_MASTER_KEY='sk-litellm-custom-value' \
  sudo -E bash ./scripts/configure-litellm.sh openclaw
```

## GitHub Copilot OAuth device-code login

Start or restart LiteLLM:

```bash
sudo -iu openclaw
systemctl --user restart litellm.service
```

Then watch logs:

```bash
journalctl --user -u litellm.service -f
```

Trigger the first model request from another terminal:

```bash
sudo -iu openclaw
set -a
source ~/.config/litellm/litellm.env
set +a

curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "github_copilot/gpt-4",
    "messages": [{"role": "user", "content": "Say hello from GitHub Copilot through LiteLLM."}]
  }' | jq .
```

On the first request, LiteLLM should print a GitHub device-code login URL/code in the service logs. Complete the login in a browser. After successful login, LiteLLM caches the Copilot token under:

```text
~openclaw/.local/share/litellm/github_copilot
```

The Quadlet sets:

```bash
GITHUB_COPILOT_TOKEN_DIR=/data/github_copilot
```

and mounts:

```text
~openclaw/.local/share/litellm:/data
```

so the Copilot token cache survives container restarts.

## Default LiteLLM models

The repo's default `config/litellm/config.yaml` exposes these model names:

```text
github_copilot/gpt-4
github_copilot/gpt-5.1-codex
github_copilot/text-embedding-3-small
```

OpenClaw is preconfigured to use:

```text
litellm/github_copilot/gpt-4
```

as the default primary model.

## OpenClaw config

The installer patches this provider block into `~openclaw/.openclaw/openclaw.json`:

```json
{
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
```

## Start or restart services

As the service user:

```bash
sudo -iu openclaw
systemctl --user daemon-reload
systemctl --user restart litellm.service
systemctl --user restart openclaw-gateway.service
```

Check logs:

```bash
journalctl --user -u litellm.service -f
```

## Validate LiteLLM

As the service user:

```bash
sudo -iu openclaw
set -a
source ~/.config/litellm/litellm.env
set +a

curl -fsS http://127.0.0.1:4000/health/liveliness | jq .

curl -fsS http://127.0.0.1:4000/models \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | jq .
```

You can also run:

```bash
./openclaw-podman-quickstart/scripts/doctor-openclaw-podman.sh
```

## Switching to another provider

Edit:

```text
~openclaw/.config/litellm/config.yaml
~openclaw/.config/litellm/litellm.env
```

For example, add `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, then change `model_list` entries to the provider model names you want. Update the OpenClaw model IDs in `~openclaw/.openclaw/openclaw.json` so they match LiteLLM's exposed `model_name` values.

## Security notes

- Do not commit `~openclaw/.config/litellm/litellm.env`.
- Do not commit `~openclaw/.local/share/litellm/github_copilot`; it contains OAuth-derived Copilot credentials.
- Do not expose port `4000` beyond host loopback unless you have explicit authentication, TLS, and network policy.
- Prefer LiteLLM virtual keys with budgets for long-lived OpenClaw deployments.
