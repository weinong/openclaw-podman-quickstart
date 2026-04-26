#!/usr/bin/env bash
set -euo pipefail

echo "== user systemd services =="
systemctl --user status openclaw-pod.service --no-pager || true
systemctl --user status openclaw-browser.service --no-pager || true
systemctl --user status litellm.service --no-pager || true
systemctl --user status openclaw-gateway.service --no-pager || true

echo
echo "== podman containers =="
podman ps -a || true

echo
echo "== Chromium CDP endpoint =="
if command -v curl >/dev/null 2>&1; then
  curl -fsS http://127.0.0.1:9222/json/version | jq . || true
  curl -fsS http://127.0.0.1:9222/json/list | jq . || true
else
  echo "curl is not installed."
fi

echo
echo "== LiteLLM endpoint =="
if command -v curl >/dev/null 2>&1; then
  if [[ -f "${HOME}/.config/litellm/litellm.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source "${HOME}/.config/litellm/litellm.env"
    set +a
  fi

  curl -fsS http://127.0.0.1:4000/health/liveliness | jq . || true

  if [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
    curl -fsS http://127.0.0.1:4000/models \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | jq . || true
  else
    echo "LITELLM_MASTER_KEY is not set; skipping authenticated /models check."
  fi
else
  echo "curl is not installed."
fi

echo
echo "== OpenClaw browser doctor =="
if command -v openclaw >/dev/null 2>&1; then
  openclaw browser --browser-profile default doctor || true
else
  echo "openclaw CLI is not installed or not in PATH."
fi
