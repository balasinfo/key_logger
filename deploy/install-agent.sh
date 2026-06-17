#!/usr/bin/env bash
# Installs a per-user LaunchAgent that runs the tracker at login and keeps it alive.
# Run this once on each laptop AFTER ./build.sh has produced .build-direct/activitytracker.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.activitytracker.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$HOME/.activitytracker"

if [ ! -x "$REPO/.build-direct/activitytracker" ]; then
  echo "Build first:  ./build.sh" >&2; exit 1
fi
mkdir -p "$HOME/Library/LaunchAgents" "$LOGDIR"
chmod +x "$REPO/deploy/run-tracker.sh"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$LABEL</string>
    <key>ProgramArguments</key> <array><string>$REPO/deploy/run-tracker.sh</string></array>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>StandardOutPath</key>  <string>$LOGDIR/agent.log</string>
    <key>StandardErrorPath</key><string>$LOGDIR/agent.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Loaded $LABEL"
echo "Logs:   $LOGDIR/agent.log"
echo "Stop:   launchctl unload $PLIST"
