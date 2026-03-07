#!/bin/sh
# Checks GHCR for newer dm-notifier images by comparing image digests.
# Runs as a background loop — started by notifier.sh.
# Requires: curl, jq, docker socket access

. /app/scripts/helpers.sh

GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/thesobersobber/dm-notifier}"
CHECK_INTERVAL="${UPDATE_CHECK_INTERVAL:-21600}"  # 6 hours
NOTIFIED_DIGEST=""

# Get our running container's image digest via docker socket
get_current_digest() {
  # hostname inside a container = container ID
  _container_id=$(hostname)

  # Get the image repo digest (sha256:...) that was pulled
  _image=$(docker inspect --format='{{.Config.Image}}' "$_container_id" 2>/dev/null)
  if [ -z "$_image" ]; then
    return 1
  fi

  # Get the repo digest for this image
  docker inspect --format='{{index .RepoDigests 0}}' "$_image" 2>/dev/null | cut -d@ -f2
}

# Get the latest image digest from GHCR registry API
get_latest_digest() {
  # Step 1: Get anonymous auth token for the repo
  _token=$(curl -s "https://ghcr.io/token?scope=repository:thesobersobber/dm-notifier:pull" \
    2>/dev/null | jq -r '.token // empty' 2>/dev/null)

  if [ -z "$_token" ]; then
    echo ""
    return 1
  fi

  # Step 2: Get the manifest digest for :latest (HEAD request)
  curl -sI "https://ghcr.io/v2/thesobersobber/dm-notifier/manifests/latest" \
    -H "Authorization: Bearer $_token" \
    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
    2>/dev/null | grep -i "docker-content-digest" | awk '{print $2}' | tr -d '\r\n'
}

# Wait for things to settle before first check
sleep 30

echo "[update-checker] Starting (interval: ${CHECK_INTERVAL}s)"
echo "[update-checker] Image: ${GHCR_IMAGE}"
echo "[update-checker] Version: ${NOTIFIER_VERSION:-unknown}"

while true; do
  CURRENT=$(get_current_digest)
  LATEST=$(get_latest_digest)

  if [ -n "$LATEST" ] && [ -n "$CURRENT" ] && [ "$LATEST" != "$CURRENT" ] && [ "$LATEST" != "$NOTIFIED_DIGEST" ]; then
    echo "[update-checker] 🆕 Update available!"
    echo "[update-checker]   Current: ${CURRENT}"
    echo "[update-checker]   Latest:  ${LATEST}"

    send_system_event "update_available" \
      "\"current_version\":\"${NOTIFIER_VERSION:-unknown}\",\"changelog_url\":\"https://github.com/theSoberSobber/Docker-Manager/releases\""

    NOTIFIED_DIGEST="$LATEST"
  elif [ -z "$CURRENT" ]; then
    echo "[update-checker] ⚠️  Could not determine current image digest"
  elif [ -z "$LATEST" ]; then
    echo "[update-checker] ⚠️  Could not reach GHCR API"
  fi

  sleep "$CHECK_INTERVAL"
done
