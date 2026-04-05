#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

log "Building and pushing image: $IMAGE_URI"
gcloud builds submit "$REPO_ROOT" --tag "$IMAGE_URI"
