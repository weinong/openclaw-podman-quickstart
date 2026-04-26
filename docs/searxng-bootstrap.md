# Bootstrap SearXNG for OpenClaw

This guide runs SearXNG as a rootless Podman sidecar and configures OpenClaw to use it as the `web_search` provider through the bundled SearXNG plugin.

## Target Architecture

```text
Podman pod: openclaw
├── openclaw-gateway
│   └── uses SEARXNG_BASE_URL from ~/.config/openclaw-gateway/gateway.env
├── openclaw-searxng
│   └── listens on http://127.0.0.1:8080
├── openclaw-litellm
└── openclaw-browser
```

The pod publishes SearXNG on host loopback only:

```text
127.0.0.1:8080:8080
```

The SearXNG container receives only `~/.config/searxng/settings.yml` as a read-only file mount. `oc.sh` owns that host-generated config file; the container consumes it without owning or mutating the host config directory.

## Files Installed

The installer copies or creates:

```text
~/.config/containers/systemd/searxng.container
~/.config/searxng/settings.yml
~/.config/openclaw-gateway/gateway.env
~/.openclaw/openclaw.json
```

`settings.yml` is installed from `config/searxng/settings.yml` when missing. `oc.sh` replaces the template secret with a generated `server.secret_key` and applies the configured base URL. Do not commit the generated runtime file.

## OpenClaw Config

`./oc.sh config searxng` patches this search provider block into `~/.openclaw/openclaw.json`:

```json
{
  "tools": {
    "web": {
      "search": {
        "provider": "searxng"
      }
    }
  },
  "plugins": {
    "entries": {
      "searxng": {
        "enabled": true,
        "config": {
          "webSearch": {
            "baseUrl": "http://127.0.0.1:8080/",
            "categories": "general,news",
            "language": "en"
          }
        }
      }
    }
  }
}
```

It also adds this environment variable to the gateway env file:

```bash
SEARXNG_BASE_URL=http://127.0.0.1:8080/
```

## Install or Refresh

Full install:

```bash
./oc.sh install
```

Only refresh SearXNG config:

```bash
./oc.sh config searxng
```

Optional overrides:

```bash
SEARXNG_BASE_URL='http://127.0.0.1:8080/' \
SEARXNG_CATEGORIES='general,news' \
SEARXNG_LANGUAGE='en' \
  ./oc.sh config searxng
```

## Start or Restart SearXNG

```bash
./oc.sh restart searxng
./oc.sh logs searxng
```

## Validate SearXNG

```bash
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo OK
curl -fsS 'http://127.0.0.1:8080/search?q=openclaw&format=json' | jq '.query, (.results | length)'
./oc.sh doctor
```

## Restart OpenClaw Gateway

After changing SearXNG config or `SEARXNG_BASE_URL`:

```bash
./oc.sh restart searxng
./oc.sh restart gateway
```

## Security Notes

- Bind SearXNG only to loopback unless you intentionally want to expose it.
- Do not commit generated `~/.config/searxng/settings.yml`; it contains `server.secret_key`.
- For public SearXNG, use HTTPS and review SearXNG production hardening guidance.
- The default quickstart disables SearXNG limiter because the service is intended to be local-only.
