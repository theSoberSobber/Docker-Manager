#!/bin/sh
# Watches Docker events and forwards relevant container actions to the backend.
# Runs as the main foreground process — started by notifier.sh.
# Requires: docker socket access, curl, jq

. /app/scripts/helpers.sh

echo "[event-watcher] Watching Docker events..."
echo "---"

docker events --format '{{json .}}' | while read -r event; do
  EVENT_TYPE=$(echo "$event" | jq -r '.Type // empty' 2>/dev/null)
  EVENT_ACTION=$(echo "$event" | jq -r '.Action // empty' 2>/dev/null)
  EVENT_NAME=$(echo "$event" | jq -r '.Actor.Attributes.name // empty' 2>/dev/null)
  EVENT_IMAGE=$(echo "$event" | jq -r '.Actor.Attributes.image // empty' 2>/dev/null)
  EVENT_TIME=$(echo "$event" | jq -r '.time // empty' 2>/dev/null)

  # Only forward meaningful container events
  if [ "$EVENT_TYPE" = "container" ]; then
    case "$EVENT_ACTION" in
      start|stop|die|restart|oom|kill|pause|unpause)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🐳 ${EVENT_NAME} — ${EVENT_ACTION}"
        send_container_event "$EVENT_ACTION" "$EVENT_NAME" "$EVENT_IMAGE" "$EVENT_TIME"
        ;;
    esac
  fi
done
