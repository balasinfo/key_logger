#!/usr/bin/env bash
# Wrapper launched by the LaunchAgent. Loads secrets (Resend key) from a 600-permission file,
# then runs the tracker. Keeps the API key out of the plist and out of the repo.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$HOME/.activitytracker/secrets.env"

if [ -f "$SECRETS" ]; then
  set -a; . "$SECRETS"; set +a
fi

exec "$REPO/.build-direct/activitytracker" track
