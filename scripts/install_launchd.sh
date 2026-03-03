#!/usr/bin/env bash
set -euo pipefail

REPO="${OPENCLAW_REPO:-}"
if [[ -z "${REPO}" ]]; then
  echo "OPENCLAW_REPO is required (example: langgexyz/openclaw-7x24-lab)" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_PATH="${HOME}/Library/LaunchAgents/ai.openclaw.7x24.dispatcher.plist"
LOG_DIR="${ROOT_DIR}/.state"
mkdir -p "${LOG_DIR}"

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ai.openclaw.7x24.dispatcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT_DIR}/scripts/agent_daemon.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OPENCLAW_REPO</key>
    <string>${REPO}</string>
    <key>OPENCLAW_POLL_SECONDS</key>
    <string>120</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/dispatcher.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/dispatcher.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "${PLIST_PATH}" >/dev/null 2>&1 || true
launchctl load "${PLIST_PATH}"

echo "installed: ${PLIST_PATH}"
echo "logs: ${LOG_DIR}/dispatcher.out.log ${LOG_DIR}/dispatcher.err.log"
