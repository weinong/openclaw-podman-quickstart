# Bootstrap SearXNG for OpenClaw

This guide runs SearXNG as a rootless Podman sidecar and configures OpenClaw to use it as the `web_search` provider.

## Target architecture

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

## Files installed

The installer copies or creates:

```text
~openclaw/.config/containers/systemd/searxng.container
~openclaw/.config/searxng/settings.yml
~openclaw/.config/openclaw-gateway/gateway.env
~openclaw/.openclaw/openclaw.json
```

`settings.yml` contains a generated `server.secret_key`. Do not commit the generated runtime file.

## OpenClaw config

The bootstrap script patches this search provider block into `~openclaw/.openclaw/openclaw.json`:

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

## SearXNG JSON API

OpenClaw uses SearXNG's JSON search endpoint:

```text
/search?q=<query>&format=json
```

The default `settings.yml` enables:

```yaml
search:
  formats:
    - html
    - json
```

Without `json` in `search.formats`, OpenClaw web search will not work correctly.

## Install or refresh

From the repo checkout:

```bash
sudo ./scripts/install-openclaw-podman.sh openclaw
```

Or run only the SearXNG config bootstrap:

```bash
sudo ./scripts/configure-searxng.sh openclaw
```

Optional overrides:

```bash
SEARXNG_BASE_URL='http://127.0.0.1:8080/' \
SEARXNG_CATEGORIES='general,news' \
SEARXNG_LANGUAGE='en' \
  sudo -E ./scripts/configure-searxng.sh openclaw
```

## Start or restart SearXNG

As the service user:

```bash
sudo -iu openclaw
systemctl --user daemon-reload
systemctl --user restart searxng.service
```

Check logs:

```bash
journalctl --user -u searxng.service -f
```

## Validate SearXNG

As the service user:

```bash
sudo -iu openclaw
curl -fsS http://127.0.0.1:8080/ >/dev/null && echo OK
curl -fsS 'http://127.0.0.1:8080/search?q=openclaw&format=json' | jq '.query, (.results | length)'
```

You can also run the general doctor:

```bash
./openclaw-podman-quickstart/scripts/doctor-openclaw-podman.sh
```

## Restart OpenClaw gateway

After changing SearXNG config or `SEARXNG_BASE_URL`:

```bash
sudo -iu openclaw
systemctl --user restart searxng.service
systemctl --user restart openclaw-gateway.service
```

## Security notes

- Bind SearXNG only to loopback unless you intentionally want to expose it.
- Do not commit generated `~openclaw/.config/searxng/settings.yml`; it contains `server.secret_key`.
- For public SearXNG, use HTTPS and review SearXNG production hardening guidance.
- The default quickstart disables SearXNG limiter because the service is intended to be local-only.
