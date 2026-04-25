#!/usr/bin/env bash
set -euo pipefail

echo "== user systemd services =="
systemctl --user status openclaw-pod.service --no-pager || true
systemctl --user status openclaw-browser.service --no-pager || true
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
echo "== OpenClaw browser doctor =="
if command -v openclaw >/dev/null 2>&1; then
  openclaw browser --browser-profile default doctor || true
else
  echo "openclaw CLI is not installed or not in PATH."
fi
