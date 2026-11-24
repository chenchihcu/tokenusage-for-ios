#!/bin/bash
# Runs relay-antigravity-mac.py every 5 minutes while you are logged in to this Mac.
#
#   scripts/install-antigravity-relay-mac.sh              install or update
#   scripts/install-antigravity-relay-mac.sh --uninstall  remove
#
# Optional environment when installing:
#   SYNC_API_URL  upload endpoint (default: the project's Worker)
#   SYNC_TOKEN    Worker write secret; saved to ~/.config/opentokenusage/sync_token (mode 600)
#   INTERVAL      seconds between runs (default 300)
#
# The script is copied to ~/Library/Application Support/OpenTokenUsage because launchd jobs
# cannot read files in ~/Downloads, ~/Documents or ~/Desktop without extra privacy approval.
set -euo pipefail

LABEL="com.opentokenusage.antigravity-relay"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Library/Application Support/OpenTokenUsage"
SCRIPT="$APP_DIR/relay-antigravity-mac.py"
LOG="$HOME/Library/Logs/opentokenusage-antigravity-relay.log"
TOKEN_FILE="$HOME/.config/opentokenusage/sync_token"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$SCRIPT"
  echo "Removed $LABEL. The log stays at $LOG; the token file (if any) at $TOKEN_FILE."
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEXBAR="$(command -v codexbar || true)"
if [[ -z "$CODEXBAR" && -x /Applications/CodexBar.app/Contents/Helpers/CodexBarCLI ]]; then
  CODEXBAR=/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI
fi
if [[ -z "$CODEXBAR" ]]; then
  echo "CodexBar CLI not found. Install CodexBar and enable its command-line tool first." >&2
  exit 1
fi

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp "$HERE/relay-antigravity-mac.py" "$SCRIPT"

if [[ -n "${SYNC_TOKEN:-}" ]]; then
  mkdir -p "$(dirname "$TOKEN_FILE")"
  (umask 077 && printf '%s\n' "$SYNC_TOKEN" > "$TOKEN_FILE")
fi

ENV_ENTRIES="    <key>CODEXBAR_BIN</key><string>$CODEXBAR</string>"
if [[ -n "${SYNC_API_URL:-}" ]]; then
  ENV_ENTRIES+=$'\n'"    <key>SYNC_API_URL</key><string>$SYNC_API_URL</string>"
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>$SCRIPT</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
$ENV_ENTRIES
  </dict>
  <key>StartInterval</key><integer>${INTERVAL:-300}</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $LABEL: every ${INTERVAL:-300} s while you are logged in. Log: $LOG"
