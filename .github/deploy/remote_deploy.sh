#!/usr/bin/env bash
set -euo pipefail

# remote_deploy.sh (runs on remote server)
# expects env:
# APP_REPO_URL, DEPLOYMENTS_DIR, APP_FOLDER, ENV_REPO_URL, ENV_SUBPATH, ENV_FILE_NAME, COMPOSE_FILE

: "${APP_REPO_URL:?}"       # must be SSH form (git@github.com:owner/repo.git)
: "${DEPLOYMENTS_DIR:?}"
: "${APP_FOLDER:?}"
: "${ENV_REPO_URL:?}"      # must be SSH form (git@github.com:owner/envs.git)
: "${ENV_SUBPATH:=}"
: "${ENV_FILE_NAME:=.env}"
: "${COMPOSE_FILE:=dm-backend/docker-compose.yml}"
: "${BRANCH_NAME:=}"      # optional branch name to clone

APP_DIR="${DEPLOYMENTS_DIR%/}/${APP_FOLDER}"
ENV_DIR="${DEPLOYMENTS_DIR%/}/envs"

echo "==> Ensure deployments dir exists: ${DEPLOYMENTS_DIR}"
mkdir -p "${DEPLOYMENTS_DIR}"

# If app dir exists, try graceful down (using sudo docker)
if [ -d "${APP_DIR}" ]; then
  echo "==> App dir exists. Attempting docker compose down in ${APP_DIR}"
  if [ -f "${APP_DIR}/${COMPOSE_FILE}" ]; then
    cd "${APP_DIR}"
    if sudo docker compose version >/dev/null 2>&1; then
      sudo docker compose -f "${COMPOSE_FILE}" down || true
    elif command -v docker-compose >/dev/null 2>&1; then
      sudo docker-compose -f "${COMPOSE_FILE}" down || true
    fi
    cd - >/dev/null || true
  else
    echo "No compose file in existing app dir; continuing."
  fi
fi

echo "==> Removing old app dir: ${APP_DIR}"
rm -rf "${APP_DIR}"

echo "==> Cloning app repo (${APP_REPO_URL}) into ${APP_DIR}"
if [ -n "${BRANCH_NAME}" ]; then
  echo "Cloning branch ${BRANCH_NAME}"
  git clone --depth=1 --branch "${BRANCH_NAME}" "${APP_REPO_URL}" "${APP_DIR}"
else
  git clone --depth=1 "${APP_REPO_URL}" "${APP_DIR}"
fi

echo "==> Removing old envs clone: ${ENV_DIR}"
rm -rf "${ENV_DIR}"

echo "==> Cloning envs repo (${ENV_REPO_URL}) into ${ENV_DIR}"
git clone --depth=1 "${ENV_REPO_URL}" "${ENV_DIR}"

# Determine source directory to copy from inside envs repo.
if [ -n "${ENV_SUBPATH}" ]; then
  SRC_DIR="${ENV_DIR%/}/${ENV_SUBPATH%/}"
else
  SRC_DIR="${ENV_DIR%/}"
fi

PROJECT_ROOT="${APP_DIR%/}"

echo "==> Copying environment files using environment-specific copy script"

if [ ! -d "${SRC_DIR}" ]; then
  echo "ERROR: Source env directory not found: ${SRC_DIR}" >&2
  ls -la "${ENV_DIR}" || true
  exit 1
fi

COPY_SCRIPT="${SRC_DIR}/copy.sh"

if [ -f "${COPY_SCRIPT}" ]; then
  echo "==> Found environment-specific copy script: ${COPY_SCRIPT}"
  chmod +x "${COPY_SCRIPT}"
  "${COPY_SCRIPT}" "${PROJECT_ROOT}"
elif [ -f "${ENV_DIR}/copy_env_files.sh" ]; then
  echo "==> Using generic copy_env_files.sh script"
  chmod +x "${ENV_DIR}/copy_env_files.sh"
  "${ENV_DIR}/copy_env_files.sh" "${ENV_SUBPATH}" "${PROJECT_ROOT}"
else
  echo "==> No copy script found, falling back to copying all contents"
  echo "    Copying from: ${SRC_DIR} -> ${PROJECT_ROOT}"
  cp -a "${SRC_DIR%/}/." "${PROJECT_ROOT%/}/"
fi

# Run docker compose up --build -d in the app dir (using sudo)
cd "${APP_DIR}"
echo "==> Using compose file: ${COMPOSE_FILE}"
if sudo docker compose version >/dev/null 2>&1; then
  sudo docker compose -f "${COMPOSE_FILE}" up --build -d
elif command -v docker-compose >/dev/null 2>&1; then
  sudo docker-compose -f "${COMPOSE_FILE}" up --build -d
else
  echo "ERROR: docker compose not available on remote machine" >&2
  exit 1
fi

echo "==> Waiting 5s and then checking container statuses..."
sleep 5

if sudo docker compose version >/dev/null 2>&1; then
  sudo docker compose -f "${COMPOSE_FILE}" ps --status running || true
else
  sudo docker-compose -f "${COMPOSE_FILE}" ps --filter "status=running" || true
fi

num_running=$(sudo docker ps --filter "status=running" --format '{{.Names}}' | wc -l | tr -d ' ')
if [ "${num_running}" -lt 1 ]; then
  echo "ERROR: No running containers detected after compose up." >&2
  sudo docker ps -a || true
  exit 2
fi

echo "==> Deployment looks healthy (at least one container is running)."
