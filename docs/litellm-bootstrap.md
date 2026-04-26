# Bootstrap LiteLLM Sidecar for OpenClaw

This guide runs LiteLLM as a sidecar in the same rootless Podman pod as OpenClaw and preconfigures OpenClaw to use it as the default model provider.

The default model in this repo is **GitHub Copilot via LiteLLM**, and the same LiteLLM sidecar also exposes **ChatGPT subscription models**. LiteLLM manages OAuth device-code flows for both providers and caches the resulting tokens under the `openclaw` user's persistent data directory.

## Target Architecture

```text
Podman pod: openclaw
├── openclaw-gateway
│   └── uses LITELLM_API_KEY from ~/.config/openclaw-gateway/gateway.env
├── openclaw-litellm
│   ├── listens on http://127.0.0.1:4000 inside the pod
│   ├── manages GitHub Copilot OAuth token cache under ~/.local/share/litellm/github_copilot
│   └── manages ChatGPT OAuth token cache under ~/.local/share/litellm/chatgpt
└── openclaw-browser
    └── persistent CDP endpoint on http://127.0.0.1:9222
```

The pod publishes LiteLLM on host loopback only:

```text
127.0.0.1:4000:4000
```

## Files Installed

The installer copies or creates:

```text
~/.config/containers/systemd/litellm.container
~/.config/litellm/config.yaml
~/.config/litellm/litellm.env
~/.local/share/litellm/github_copilot
~/.local/share/litellm/chatgpt
~/.config/openclaw-gateway/gateway.env
~/.openclaw/openclaw.json
```

## Configure LiteLLM Gateway Auth

No upstream API key is required for the default GitHub Copilot and ChatGPT provider config.

LiteLLM still needs a local master key so OpenClaw can authenticate to the LiteLLM proxy. The one-shot installer generates this automatically:

```bash
./oc.sh install
```

You can regenerate or set the key explicitly with:

```bash
./oc.sh config litellm
```

or:

```bash
LITELLM_MASTER_KEY='sk-litellm-custom-value' ./oc.sh config litellm
```

OpenClaw uses `LITELLM_API_KEY` from `~/.config/openclaw-gateway/gateway.env` to authenticate to LiteLLM.

## GitHub Copilot OAuth Device-Code Login

Start or restart LiteLLM:

```bash
./oc.sh restart litellm
```

Watch logs:

```bash
./oc.sh logs litellm
```

Trigger the first Copilot model request from another terminal:

```bash
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
~/.local/share/litellm/github_copilot
```

## ChatGPT OAuth Device-Code Login

Trigger the first ChatGPT model request:

```bash
set -a
source ~/.config/litellm/litellm.env
set +a

curl -s http://127.0.0.1:4000/v1/responses \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "chatgpt/gpt-5.4",
    "input": "Say hello from ChatGPT through LiteLLM."
  }' | jq .
```

On the first request, LiteLLM should print a ChatGPT device-code login URL/code in the service logs. Complete the login in a browser. After successful login, LiteLLM caches the ChatGPT token under:

```text
~/.local/share/litellm/chatgpt
```

## Default LiteLLM Models

The repo's default `config/litellm/config.yaml` exposes these model names:

```text
github_copilot/gpt-4
github_copilot/gpt-5.1-codex
github_copilot/text-embedding-3-small
chatgpt/gpt-5.4
chatgpt/gpt-5.4-pro
chatgpt/gpt-5.3-codex
chatgpt/gpt-5.3-codex-spark
chatgpt/gpt-5.3-instant
chatgpt/gpt-5.3-chat-latest
```

OpenClaw is preconfigured to use `litellm/github_copilot/gpt-4` as the default primary model. ChatGPT models are available through the same `litellm` provider and can be selected explicitly by model ID.

## OpenClaw Config

OpenClaw model config is managed independently:

```bash
./oc.sh config openclaw
```

That patches the LiteLLM provider block and default model into `~/.openclaw/openclaw.json`.

## Validate LiteLLM

```bash
set -a
source ~/.config/litellm/litellm.env
set +a

curl -fsS http://127.0.0.1:4000/health/liveliness | jq .
curl -fsS http://127.0.0.1:4000/models \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | jq .

./oc.sh doctor
```

## Switching to Another Provider

Edit:

```text
~/.config/litellm/config.yaml
~/.config/litellm/litellm.env
```

For example, add `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, then change `model_list` entries to the provider model names you want. Update the OpenClaw model IDs in `~/.openclaw/openclaw.json` so they match LiteLLM's exposed `model_name` values.

## Security Notes

- Do not commit `~/.config/litellm/litellm.env`.
- Do not commit `~/.local/share/litellm/github_copilot`; it contains OAuth-derived Copilot credentials.
- Do not commit `~/.local/share/litellm/chatgpt`; it contains OAuth-derived ChatGPT credentials.
- Do not expose port `4000` beyond host loopback unless you have explicit authentication, TLS, and network policy.
- Prefer LiteLLM virtual keys with budgets for long-lived OpenClaw deployments.
