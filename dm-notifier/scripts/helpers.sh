#!/bin/sh
# Shared helpers for dm-notifier scripts.
# Sourced by other scripts — do not run directly.

# --- System Event Helper ---
# Sends a system event to the backend.
# Usage: send_system_event <action> [extra_json_fields]
#
# Examples:
#   send_system_event "update_available"
#   send_system_event "update_available" '"latest_version":"1.1.0","changelog_url":"https://..."'
send_system_event() {
  _action="$1"
  _extra="${2:-}"

  _payload="{\"server_id\":\"${SERVER_ID}\",\"event_type\":\"system\",\"action\":\"${_action}\"${_extra:+,$_extra}}"

  curl -s -o /dev/null -X POST "${BACKEND_URL}/events" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${PAIRING_TOKEN}" \
    -d "$_payload" 2>/dev/null || echo "  ⚠️  Failed to send system event: ${_action}"
}

# --- Docker Event Helper ---
# Sends a container event to the backend.
# Usage: send_container_event <action> <container_name> <image> <timestamp>
send_container_event() {
  _action="$1"
  _container="$2"
  _image="$3"
  _timestamp="$4"

  curl -s -o /dev/null -X POST "${BACKEND_URL}/events" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${PAIRING_TOKEN}" \
    -d "{
      \"server_id\": \"${SERVER_ID}\",
      \"event_type\": \"container\",
      \"action\": \"${_action}\",
      \"container_name\": \"${_container}\",
      \"image\": \"${_image}\",
      \"timestamp\": ${_timestamp}
    }" 2>/dev/null || echo "  ⚠️  Failed to forward event (backend unreachable)"
}
