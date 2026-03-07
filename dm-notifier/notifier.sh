#!/bin/sh
set -e

echo "=== Docker Manager Notifier ==="
echo "Version: ${NOTIFIER_VERSION:-unknown}"
echo "Server ID: ${SERVER_ID}"
echo "Backend: ${BACKEND_URL}"
echo ""

# Validate required env vars
if [ -z "$PAIRING_TOKEN" ]; then
  echo "ERROR: PAIRING_TOKEN is required"
  exit 1
fi

if [ -z "$BACKEND_URL" ]; then
  echo "ERROR: BACKEND_URL is required"
  exit 1
fi

# Write PID for healthcheck
echo $$ > /tmp/notifier.pid

# Source shared helpers (makes send_system_event, send_container_event available)
. /app/scripts/helpers.sh

# Start background tasks
/app/scripts/update_checker.sh &
echo "✅ Update checker started (PID: $!)"

# Start event watcher (foreground — keeps the container alive)
exec /app/scripts/event_watcher.sh
