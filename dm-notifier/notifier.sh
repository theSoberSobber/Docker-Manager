#!/bin/sh
set -e

echo "=== Docker Manager Notifier ==="
echo "Server ID: ${SERVER_ID}"
echo "Backend: ${BACKEND_URL}"
echo "Event types: ${EVENT_TYPES}"
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

echo ""
echo "Watching Docker events..."
echo "---"

# Create a PID file so the healthcheck knows we're alive
echo $$ > /tmp/notifier.pid

# Watch docker events and forward them to the backend
# --format outputs JSON, we filter for relevant events
docker events --format '{{json .}}' | while read -r event; do
  # Parse event type
  EVENT_TYPE=$(echo "$event" | jq -r '.Type // empty' 2>/dev/null)
  EVENT_ACTION=$(echo "$event" | jq -r '.Action // empty' 2>/dev/null)
  EVENT_ACTOR_NAME=$(echo "$event" | jq -r '.Actor.Attributes.name // empty' 2>/dev/null)
  EVENT_ACTOR_IMAGE=$(echo "$event" | jq -r '.Actor.Attributes.image // empty' 2>/dev/null)
  EVENT_TIME=$(echo "$event" | jq -r '.time // empty' 2>/dev/null)

  # Filter: only forward container events that matter
  if [ "$EVENT_TYPE" = "container" ]; then
    case "$EVENT_ACTION" in
      start|stop|die|restart|oom|kill|pause|unpause)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Container '$EVENT_ACTOR_NAME' — $EVENT_ACTION"

        # Forward to backend
        curl -s -o /dev/null -X POST "${BACKEND_URL}/events" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer ${PAIRING_TOKEN}" \
          -d "{
            \"server_id\": \"${SERVER_ID}\",
            \"event_type\": \"${EVENT_TYPE}\",
            \"action\": \"${EVENT_ACTION}\",
            \"container_name\": \"${EVENT_ACTOR_NAME}\",
            \"image\": \"${EVENT_ACTOR_IMAGE}\",
            \"timestamp\": ${EVENT_TIME}
          }" 2>/dev/null || echo "  ⚠️  Failed to forward event (backend unreachable)"
        ;;
      *)
        # Skip less important events like create, attach, detach, exec, etc.
        ;;
    esac
  fi
done
