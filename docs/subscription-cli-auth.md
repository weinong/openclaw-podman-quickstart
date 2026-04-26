# Codex and Copilot subscription CLI auth

This guide covers a different authentication path from LiteLLM.

LiteLLM is an OpenAI-compatible model gateway. It works best with API keys, bearer tokens, or provider credentials.

Codex CLI and GitHub Copilot CLI subscription access use their own OAuth/device-code flows. These are useful for coding-agent tools, ACP-style integrations, or shell commands that invoke `codex` or `copilot`, but they are not the same thing as a LiteLLM model provider.

## Mental model

```text
OpenClaw model calls
└── LiteLLM sidecar
    └── API key / provider credential / LiteLLM virtual key

OpenClaw tool or shell calls
├── codex CLI
│   └── Sign in with ChatGPT / Codex CLI auth
└── copilot CLI
    └── GitHub Copilot OAuth device flow
```

Use LiteLLM when OpenClaw needs a normal model provider.

Use Codex/Copilot CLI auth when OpenClaw or a human shell invokes those CLIs as tools.

## Why not route subscriptions through LiteLLM?

Codex and Copilot subscription logins do not expose a stable OpenAI-compatible API endpoint that LiteLLM can use as an upstream provider.

The subscription login creates CLI-specific credentials for the CLI product. Treat those credentials as tool credentials, not model-provider credentials.

## Codex CLI

Codex CLI can be installed with npm:

```bash
npm install -g @openai/codex
```

Log in as the service user so credentials are stored under the same home directory OpenClaw will use:

```bash
sudo -iu openclaw
codex login
```

Follow the browser/device sign-in flow. For ChatGPT plan access, use **Sign in with ChatGPT** when prompted.

After login, verify:

```bash
codex --version
codex --help
```

If you previously used an API key and want subscription-based access, log out and log back in:

```bash
codex logout
codex login
```

## GitHub Copilot CLI

GitHub Copilot CLI can be installed with npm if Node.js 22+ is available:

```bash
npm install -g @github/copilot
```

Log in as the service user:

```bash
sudo -iu openclaw
copilot login
```

The CLI will show a one-time code and ask you to visit the GitHub device login URL.

After login, verify:

```bash
copilot --version
copilot --help
```

## Headless VM notes

On a headless VM, the CLI may try to open a browser and fail. That is okay. Copy the displayed device code and verification URL into a browser on your workstation.

Make sure you run the login as the same Linux user that will run OpenClaw:

```bash
sudo -iu openclaw
```

That keeps CLI credentials in the right home directory.

## Containerized OpenClaw note

If OpenClaw runs inside a container and you want it to invoke `codex` or `copilot`, the CLIs and their credential directories must be available inside that container.

The simpler approach is:

1. Run OpenClaw gateway on the host as the `openclaw` user when using subscription CLIs as tools.
2. Or build a custom OpenClaw container image that includes Node.js, Codex CLI, and Copilot CLI.
3. Mount the service user's credential directories into the container carefully.

Do not bake personal OAuth credentials into an image.

## Security notes

- Treat CLI credential directories as secrets.
- Do not commit CLI auth files.
- Do not share a single personal subscription login across a team deployment.
- For team or production deployments, prefer service identities, API keys, or provider-managed keys where available.
- Subscription CLI auth is best for a personal assistant/dev box setup, not a multi-user shared gateway.
